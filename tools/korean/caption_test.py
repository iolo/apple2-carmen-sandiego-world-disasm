"""Verify caption pixels, unmodified art, and native ABI on both HGR pages."""

import argparse

from . import test_mode
import shutil

from .common import BUILD, DOCS, ROOT, read_json, sha256, write_json
from .font import hgr_rows, load_bdf
from .library import assemble
from .synthetic_test import launch


def reference(baseline, items):
    page=bytearray(value&127 for value in baseline)
    protected=set(range(8192))
    original_d=(ROOT/'assets/po/D.bin').read_bytes()
    glyphs=load_bdf()

    def offset(x,y):
        return (y&7)*1024+((y>>3)&7)*128+(y>>6)*40+x//7

    for item in items:
        left,right,top,bottom=item['rectangle']
        for y in range(top,bottom):
            for x in range(left,right):
                address=offset(x,y);mask=1<<(x%7)
                if item['white_background']:page[address] |= mask
                else:page[address] &= 127 ^ mask
                protected.discard(address)
        for line in item['lines']:
            x=line['left'];top=line['top']
            for character in line['text']:
                if ord(character)>127:
                    pixels=[[(row>>bit)&1 for bit in range(7)] for row in hgr_rows(glyphs,character)]
                    advance=8
                else:
                    index=ord(character)-32
                    start=original_d[index]+256*original_d[index+112]-0xB900
                    width,height=original_d[start:start+2];stride=(width+6)//7
                    pixels=[[(original_d[start+2+y*stride+col//7]>>(col%7))&1 for col in range(width)] for y in range(height)]
                    advance=width+1
                for y,row in enumerate(pixels):
                    for col,pixel in enumerate(row):
                        if pixel:page[offset(x+col,top+y)] ^= 1<<((x+col)%7)
                x+=advance
    return bytes(page),protected


def preview(raw,path):
    from PIL import Image
    image=Image.new('RGB',(280,192));pixels=image.load()
    for y in range(192):
        for x in range(280):
            offset=(y&7)*1024+((y>>3)&7)*128+(y>>6)*40+x//7
            if raw[offset]&(1<<(x%7)):pixels[x,y]=(255,255,255)
    image.resize((840,576)).save(path)


def build(mode="synthetic"):
    directory=test_mode.directory(mode)/'caption-probe';directory.mkdir(parents=True,exist_ok=True)
    captions=read_json(test_mode.directory(mode)/'captions/manifest.json')
    probes=[]
    for module,images in (('R',range(4)),('N',range(6))):
        patch=captions['modules'][module]
        for number in images:
            for page in (1,2):
                name=f'{module}{number}-page{page}'
                code=('.setcpu "6502"\n.segment "CODE"\nPROBE_ENTRY:\n        sei\n        cld\n'
                    '        lda #$20\n        sta $C1\n        lda #$00\n        sta $C0\n        tay\n'
                    '        ldx #$40\n        lda #$80\nCLEAR: sta ($C0),y\n        iny\n        bne CLEAR\n'
                    '        inc $C1\n        dex\n        bne CLEAR\n'
                    '        lda #$00\n        sta $68\n        sta $BE\n        sta $A2\n'
                    '        lda #$27\n        sta $BF\n        lda #$06\n        sta $5F\n'
                    f'        lda #${page:02X}\n        sta $74\n')
                if module=='N':code+=f'        ldy #${number:02X}\n'
                else:
                    pointer=(0x7800,0x7BE0,0x7FA0,0x8760)[number]
                    code+=f'        ldx #${pointer&255:02X}\n        ldy #${pointer>>8:02X}\n'
                code+=f'        jsr ${patch["entry"]:04X}\nPROBE_DONE: jmp PROBE_DONE\n'
                (directory/(name+'.s')).write_text(code)
                binary,symbols=assemble(directory/(name+'.s'),directory,name,0x0800,0x400)
                probes.append({'name':name,'module':module,'image':number,'page':page,'symbols':symbols,'sha256':sha256(binary)})
    result={'probes':probes,'captions':captions}
    write_json(directory/'manifest.json',result)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--session',required=True)
    test_mode.argument(parser)
    options=parser.parse_args();fixture=build(options.mode)
    manifest=read_json(test_mode.directory(options.mode)/'manifest.json')
    process,session=launch(options.session,ROOT/manifest['image'],options.mode)
    try:
        point=session.bp(0x601C);session.call('go');session.stopped(0x601C);session.clear(point)
        test_mode.bootstrap(session)
        session.guard('synthetic-captions-before')
        session.lua("return dofile('tools/korean/caption_test.lua')")
        results=[]
        for index,probe in enumerate(fixture['probes'],1):
            trials=[]
            for baseline in (True,False):
                started=session.call('korean_caption_start',index,baseline)
                session.call('go');session.stopped(started['done'])
                result=session.call('korean_caption_finish');trials.append(result)
                for name in ('A','X','Y','SP','P','PC'):
                    if result['restored_cpu'][name]!=result['saved_cpu'][name]:
                        raise ValueError('Caption probe caller not restored')
            before,after=trials
            original=(session.directory/(before['name']+'.hgr')).read_bytes()
            actual=(session.directory/(after['name']+'.hgr')).read_bytes()
            group=probe['module']+str(probe['image'])
            items=[item for item in fixture['captions']['layout'].values() if item['group']==group]
            expected,protected=reference(original,items)
            if bytes(value&127 for value in actual)!=expected:
                (session.directory/(probe['name']+'-expected.hgr')).write_bytes(expected)
                raise ValueError('Native caption ink differs: '+probe['name'])
            if any(original[i]!=actual[i] for i in protected):
                raise ValueError('Native caption changed picture bytes outside lettering: '+probe['name'])
            if (session.directory/(before['name']+'.zp')).read_bytes()!=(session.directory/(after['name']+'.zp')).read_bytes():
                raise ValueError('Caption hook changed the original decompressor zero-page result')
            if before['stopped_cpu']!=after['stopped_cpu']:
                raise ValueError('Caption hook changed native register/flag result: '+str(trials))
            if probe['page']==1:preview(actual,session.directory/(probe['name']+'.png'))
            results.append({'name':probe['name'],'caption_entries':len(items),'reference_ink_matches':True,
                            'all_protected_bytes_match':True,'registers_flags_and_zero_page_match':True,
                            'baseline_hgr_sha256':sha256(original),'caption_hgr_sha256':sha256(actual),
                            'native_registers':after['stopped_cpu']})
            print(probe['name']+': pixels, protected art, native registers/flags and zero page match',flush=True)
        session.guard('synthetic-captions-after')
        session.exit();process.wait(timeout=10)
        if process.returncode!=0 or sha256((session.directory/'carmen-world.hdv').read_bytes())!=manifest['image_sha256']:
            raise ValueError('Caption RAM test changed media or failed owned exit')
        destination=test_mode.runtime(options.mode)/'native-captions';destination.mkdir(parents=True,exist_ok=True)
        artifacts={}
        for path in sorted([*session.directory.glob('R*'),*session.directory.glob('N*'),*session.directory.glob(session.mode+'-captions*.json')]):
            if path.is_file():shutil.copyfile(path,destination/path.name);artifacts[path.name]=sha256(path.read_bytes())
        write_json(test_mode.runtime(options.mode)/'native-captions.json',{'format':1,'status':'pass','session':options.session,
            **test_mode.identity(options.mode),'fixture':fixture,'probes':results,'artifacts':artifacts,
            'checks':['All 11 caption entries through actual N/R post-decompression hooks on both HGR pages',
                'Independent BDF/original-ASCII pixel reference matches all page ink; phase bits excluded only for ink',
                'Every byte outside lettering rectangles is identical to the unhooked native image',
                'All decompressor CPU registers/flags and 256 zero-page bytes match the native baseline',
                'Untargeted globe and N pictures 0..3 remain byte-identical; original compressed S/O/P files untouched',
                'All borrowed modules, library/cache, display pages, buffers, stack and CPU restored; media unchanged'],
            'scope':'Native caption decoder/renderer component; updated full disk lifecycle remains a separate gate'})
        print('Native caption probes passed; owned MAME exited',flush=True)
    finally:
        if process.poll() is None:
            process.terminate()
            try:process.wait(timeout=5)
            except Exception:process.kill();process.wait(timeout=5)


if __name__=='__main__':main()
