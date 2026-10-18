"""Verify every S2 record through actual B/ProDOS reads and buffer canaries."""

import argparse

from . import test_mode

from .common import BUILD,DOCS,ROOT,read_json,sha256,write_json
from .library import assemble
from .synthetic_test import launch


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--session',required=True)
    test_mode.argument(parser)
    options=parser.parse_args();directory=test_mode.directory(options.mode)/'city-probe';directory.mkdir(parents=True,exist_ok=True)
    manifest=read_json(test_mode.directory(options.mode)/'manifest.json')
    data=(test_mode.directory(options.mode)/'text/S2.bin').read_bytes()
    probes=[]
    for city in range(30):
        start=int.from_bytes(data[city*3:city*3+3],'little');end=int.from_bytes(data[city*3+3:city*3+6],'little')
        raw=data[start:end];boundary=int.from_bytes(raw[:2],'little');text,picture=raw[2:boundary],raw[boundary:]
        if len(text)>1792 or len(picture)+1>0xC00:raise ValueError('City exceeds verified B buffers')
        for mode,entry in (('record',0x9809),('text',0x980C)):
            name=f'{city:02d}-{mode}'
            code=f'.setcpu "6502"\n.segment "CODE"\nPROBE_ENTRY: sei\n        cld\n        lda #${city:02X}\n        jsr ${entry:04X}\nPROBE_DONE: jmp PROBE_DONE\n'
            (directory/(name+'.s')).write_text(code)
            binary,symbols=assemble(directory/(name+'.s'),directory,name,0x9100,0x100)
            (directory/(name+'-text.bin')).write_bytes(text)
            (directory/(name+'-picture.bin')).write_bytes(picture)
            probes.append({'name':name,'city':city,'mode':mode,'symbols':symbols,'probe_sha256':sha256(binary),
                'text_bytes':len(text),'text_sha256':sha256(text),'picture_bytes':len(picture),'picture_sha256':sha256(picture),
                'record_start':start,'boundary':boundary})
    write_json(directory/'manifest.json',{'probes':probes})
    process,session=launch(options.session,ROOT/manifest['image'],options.mode)
    try:
        point=session.bp(0x601C);session.call('go');session.stopped(0x601C);session.clear(point)
        test_mode.bootstrap(session);session.guard('synthetic-cities-before')
        session.lua("return dofile('tools/korean/city_test.lua')")
        results=[]
        for index,p in enumerate(probes,1):
            started=session.call('korean_city_start',index);session.call('go');session.stopped(started['done'])
            result=session.call('korean_city_finish')
            if result['cpu']['P']&1 or not result['text_matches'] or not result['text_tail_unchanged']:
                raise ValueError('Native S2 text read differs: '+p['name'])
            if p['mode']=='record':
                if not result['picture_matches'] or result['picture_terminator']!=0 or not result['picture_tail_unchanged']:
                    raise ValueError('Native S2 image read/boundary differs: '+p['name'])
            elif not result['picture_buffer_unchanged']:raise ValueError('Text-only read touched picture buffer')
            for name in ('A','X','Y','SP','P','PC'):
                if result['restored_cpu'][name]!=result['saved_cpu'][name]:raise ValueError('City caller not restored')
            results.append(result)
            print(p['name']+': text, image/terminator and buffer boundaries match',flush=True)
        session.guard('synthetic-cities-after');session.exit();process.wait(timeout=10)
        if process.returncode!=0 or sha256((session.directory/'carmen-world.hdv').read_bytes())!=manifest['image_sha256']:
            raise ValueError('S2 reads changed media or failed normal owned exit')
        write_json(test_mode.runtime(options.mode)/'native-cities.json',{'format':1,'status':'pass','session':options.session,
            **test_mode.identity(options.mode),'probes':probes,'results':results,
            'checks':['All 30 city records through B_LOAD_S2_RECORD and B_LOAD_S2_TEXT',
                'Every native text/picture byte matches the rebuilt S2 record, including offsets above 64KiB',
                'Picture NUL and text/image tail canaries match; text-only calls leave picture buffer unchanged',
                'Native MLI success, main/auxiliary zero page/stack and loader buffers restored; disk unchanged'],
            'scope':'60 actual ProDOS data-load calls; selected clue/description and rendering gates have separate evidence'})
        print('All 30 native city record/text reads passed; owned MAME exited',flush=True)
    finally:
        if process.poll() is None:
            process.terminate()
            try:process.wait(timeout=5)
            except Exception:process.kill();process.wait(timeout=5)


if __name__=='__main__':main()
