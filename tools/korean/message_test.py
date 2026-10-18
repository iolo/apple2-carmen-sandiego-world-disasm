"""Native synthetic witnesses for every assembled-message size/layout extremum."""

import argparse

from . import test_mode
import shutil

from .catalog import CATALOG, CONTROL_RE
from .common import BUILD, DOCS, ROOT, read_json, sha256, write_json
from .encoding import GameEncoding
from .library import assemble
from .measure_draft import units
from .message_layouts import measure, native_typewriter_layout
from .synthetic_test import launch


def build(mode="synthetic"):
    report=measure();enc=GameEncoding.from_catalog(read_json(CATALOG))
    directory=test_mode.directory(mode)/'message-probe';directory.mkdir(parents=True,exist_ok=True)
    candidates={}
    for group,state in report['message_groups'].items():
        for kind in ('max_bytes','max_lines'):
            item=state[kind]
            candidates.setdefault(item['text'],{'groups':[],'layout':item['layout']})['groups'].append(group+'/'+kind)
    sequence=report['worst_warrant_sequence']
    text='<CTRL:8D>'.join(sequence['native_calls'])
    # Every native call terminates with a scroll; an explicit separator in
    # this single witness preserves those transitions and the same glyphs.
    from d_font import decode_d
    widths={g['code']:g['width_byte']+1 for g in decode_d((ROOT/'assets/po/D.bin').read_bytes())['glyphs']}
    candidates[text]={'groups':['complete-warrant-list'],'layout':native_typewriter_layout(text,widths)}
    for text in ('','<CTRL:8D>','<CTRL:8D><CTRL:80>','<CTRL:8D>  '):
        candidates.setdefault(text,{'groups':['terminal-empty-run'],'layout':native_typewriter_layout(text,widths)})
    probes=[]
    for i,(value,item) in enumerate(candidates.items()):
        name=f'{i:02d}';synthetic=test_mode.text(value,enc,mode)
        data=enc.encode(synthetic)+b'\0'
        if len(data)>512:raise ValueError('Native message fixture exceeds its verified source reservation')
        trace=[]
        for line in item['layout']['lines']:
            for token in units(test_mode.text(line,enc,mode)):
                ctrl=CONTROL_RE.fullmatch(token)
                trace.append({'kind':'native','code':int(ctrl[1],16) if ctrl else ord(token)} if ctrl or ord(token)<128 else
                             {'kind':'glyph','id':enc.ids[token]})
        (directory/(name+'.bin')).write_bytes(data)
        probes.append({'name':name,'groups':item['groups'],'bytes':len(data),'sha256':sha256(data),
            **({'synthetic_text':synthetic} if mode=='synthetic' else {'text':synthetic}),'expected_trace':trace,'expected_scrolls':item['layout']['line_count'],
            'source_nul':0xA0FD+len(data)-1,'first_text_final_row':item['layout']['first_text_final_row']})
    n=read_json(BUILD/'maps/N-symbols.json')
    code=('.setcpu "6502"\n.segment "CODE"\nPROBE_ENTRY:\n        sei\n        cld\n'
        '        lda #$20\n        sta $C1\n        lda #$00\n        sta $C0\n        tay\n'
        '        ldx #$40\n        lda #$80\nCLEAR: sta ($C0),y\n        iny\n        bne CLEAR\n'
        '        inc $C1\n        dex\n        bne CLEAR\n'
        '        lda #$00\n        sta $68\n        sta $BE\n        sta $A2\n        lda #$27\n        sta $BF\n'
        '        lda #$06\n        sta $5F\n        lda #$01\n        sta $74\n'
        '        lda #$03\n        sta $70\n        sta $71\n        ldx #$FD\n        ldy #$A0\n'
        f'        jsr ${n["N_DRAW_TEXT_XY"]:04X}\nPROBE_DONE: jmp PROBE_DONE\n')
    (directory/'probe.s').write_text(code)
    binary,symbols=assemble(directory/'probe.s',directory,'probe',0x0800,0x400)
    fixture={'format':1,'catalog_sha256':report['catalog_sha256'],'probes':probes,'symbols':symbols,
        'probe_sha256':sha256(binary),'message_groups_measured':len(report['message_groups']),
        'dynamic_combinations':report['dynamic_combinations'],'warrant_subsets':report['warrant_sequences_measured']}
    write_json(directory/'manifest.json',fixture)
    return fixture


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--session',required=True)
    test_mode.argument(parser)
    options=parser.parse_args();fixture=build(options.mode);manifest=read_json(test_mode.directory(options.mode)/'manifest.json')
    if fixture['catalog_sha256']!=manifest['catalog_sha256']:raise ValueError('Rebuild the synthetic disk for the current draft')
    process,session=launch(options.session,ROOT/manifest['image'],options.mode)
    try:
        point=session.bp(0x601C);session.call('go');session.stopped(0x601C);session.clear(point)
        point=session.bp(0x6000);session.call('go');session.call('keys','\r');session.stopped(0x6000);session.clear(point)
        test_mode.bootstrap(session);session.guard('synthetic-messages-before','N')
        session.lua("return dofile('tools/korean/message_test.lua')")
        results=[]
        for i,probe in enumerate(fixture['probes'],1):
            start=session.call('korean_message_start',i);session.call('korean_fast_text',True)
            session.call('go');session.stopped(start['done']);session.call('korean_fast_text',False)
            result=session.call('korean_message_finish')
            if result['glyph_trace']!=probe['expected_trace']:raise ValueError('Native message lost/repeated a glyph: '+probe['name'])
            if result['scrolls']!=probe['expected_scrolls']:raise ValueError(f"Native terminal/line scroll mismatch: {probe['name']} ({result['scrolls']} != {probe['expected_scrolls']})")
            if result['source_at_nul']!=probe['source_nul'] or not result['source_unchanged'] or not result['buffer_tail_unchanged']:
                raise ValueError('Native message source/NUL/buffer boundary differs')
            if result['decoder_error'] or result['break_flag'] or result['cursor']!={'column':3,'bit':3,'row':153}:
                raise ValueError('Native typewriter status/cursor differs')
            for name in ('A','X','Y','SP','P','PC'):
                if result['restored_cpu'][name]!=result['saved_cpu'][name]:raise ValueError('Message caller was not restored')
            results.append({'name':probe['name'],'groups':probe['groups'],'glyphs':len(result['glyph_trace']),
                'scrolls':result['scrolls'],'source_nul':result['source_at_nul'],'all_expected_glyphs_and_scrolls_match':True})
            print(probe['name']+': complete glyph stream, scroll count, source/cursor and buffer canary match',flush=True)
        session.guard('synthetic-messages-after','N');session.exit();process.wait(timeout=10)
        if process.returncode!=0 or sha256((session.directory/'carmen-world.hdv').read_bytes())!=manifest['image_sha256']:
            raise ValueError('Message test changed media or failed normal exit')
        destination=test_mode.runtime(options.mode)/'native-messages';destination.mkdir(parents=True,exist_ok=True);artifacts={}
        for path in sorted([*session.directory.glob('message-*'),*session.directory.glob(session.mode+'-messages*.json')]):
            shutil.copyfile(path,destination/path.name);artifacts[path.name]=sha256(path.read_bytes())
        write_json(test_mode.runtime(options.mode)/'native-messages.json',{'format':1,'status':'pass','session':options.session,
            **test_mode.identity(options.mode),'fixture':fixture,'probes':results,'artifacts':artifacts,
            'checks':['Native witnesses for every assembled-message byte/line extremum and the complete ten-suspect list',
                'Every actual drawing-call glyph matches independent layout; measurement calls excluded by return address',
                'Actual report-page changes count every line and terminal-NUL scroll, including final empty runs',
                'Source terminators, buffer tail, decoder status and final cursor match; caller/RAM restored; media unchanged'],
            'scope':f'{options.mode} output witnesses for source-derived message extrema; not execution of every originating gameplay branch'})
        print('Native message extrema passed; owned MAME exited',flush=True)
    finally:
        if process.poll() is None:
            process.terminate()
            try:process.wait(timeout=5)
            except Exception:process.kill();process.wait(timeout=5)


if __name__=='__main__':main()
