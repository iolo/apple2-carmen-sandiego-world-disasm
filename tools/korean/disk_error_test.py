"""Recover real missing-file failures by mounting owned good media and retrying."""

import argparse
import shutil

from . import test_mode
from .common import BUILD, ROOT, read_json, sha256, write_json
from .gameplay_test import archive, launch, replace_files, roster, stop
from .verify_save import extract
from .synthetic_test import launch as start


def mount(session, media):
    images = [image for image in session.call('devices')['images'] if image.get('filename')]
    if len(images) != 1:
        raise ValueError('Expected one owned hard-disk image')
    result = session.call('mount', images[0]['tag'], str(media))
    if result['filename'] != str(media):
        raise ValueError('Good replacement media was not mounted')
    return images[0]['tag']


def main():
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--tag', required=True)
    options = parser.parse_args()
    if not options.tag.replace('-', '').isalnum(): parser.error('Safe tag required')
    pins = test_mode.identity('approved')
    manifest = read_json(BUILD / 'approved/manifest.json'); base = ROOT / manifest['image']
    directory = BUILD / (options.tag + '-disk-errors'); directory.mkdir(exist_ok=False)
    b = manifest['loader_symbols']['B']
    from reconstruct import run
    bad = directory / 'missing-R.po'; shutil.copyfile(base, bad); run('a2kit','delete','-d',str(bad),'-f','R')
    good = directory / 'text-recovery.hdv'; shutil.copyfile(base, good)
    process, session = start('mame-' + options.tag + '-text-error', bad, 'approved')
    try:
        point = session.bp(b['B_WAIT_FOR_DISK_KEY']); session.call('go'); session.stopped(b['B_WAIT_FOR_DISK_KEY']); session.clear(point)
        raw = bytes(session.call('read', 0x400, 1024)['bytes'])
        lines = [''.join(chr(raw[(row&7)*128+(row>>3)*40+col]&127) for col in range(40)).strip() for row in range(24)]
        text = '\n'.join(line for line in lines if line)
        for phrase in ('CARMEN', 'SANDIEGO', 'RETURN'):
            if phrase not in text.upper(): raise ValueError('Original English TEXT prompt missing: ' + text)
        session.call('screenshot', str(session.directory / 'text-disk-error.png'))
        write_json(session.directory / 'text-disk-error.json', {'text':text, 'text_page_sha256':sha256(raw)})
        tag = mount(session, good)
        point = session.bp(0x601C); session.call('go'); session.call('keys','\r'); session.stopped(0x601C); session.clear(point)
        test_mode.bootstrap(session)
        session.guard('approved-text-error-recovered')
        stop(process, session)
        text_result = {'missing_file':'R', 'text':text, 'image_tag':tag, 'font_and_resident_code_intact_after_retry':True,
            'artifacts':{p.name:sha256(p.read_bytes()) for p in session.directory.glob('text-disk-error.*')}}
        destination = test_mode.runtime('approved') / 'disk-errors'; destination.mkdir(exist_ok=True)
        for p in session.directory.glob('text-disk-error.*'): shutil.copyfile(p, destination / p.name)
    finally:
        if process.poll() is None:
            session.call('exit'); process.wait(timeout=10)
    life = read_json(test_mode.runtime('approved') / 'synthetic-text.json')
    source = BUILD / life['sessions'][0]['session'] / 'carmen-world.hdv'
    payloads = {name:extract(source,name) for name in ('F','G','H')}
    good = replace_files(base, directory / 'hgr-recovery.hdv', payloads)
    bad = directory / 'missing-H.po'; shutil.copyfile(good,bad); run('a2kit','delete','-d',str(bad),'-f','H')
    process, session = launch('mame-' + options.tag + '-hgr-error', bad, 'korean')
    try:
        point=session.bp(0x601C);session.call('go');session.stopped(0x601C);session.clear(point);test_mode.bootstrap(session)
        point=session.bp(0x6000);session.call('go');session.call('keys','\r');session.stopped(0x6000);session.clear(point)
        point=session.bp('N_READ_NAME_KEY');session.call('go');session.stopped('N_READ_NAME_KEY');session.clear(point)
        session.call('korean_fast_text',True)
        point=session.bp('N_READ_YES_NO_RESPONSE');session.call('go');session.call('keys',life['save']['detective']+'\r');session.stopped('N_READ_YES_NO_RESPONSE');session.clear(point)
        point=session.bp('N_POLL_KEY_OR_BUTTON');session.call('go');session.call('keys','Y\r');session.stopped('N_POLL_KEY_OR_BUTTON');session.clear(point)
        session.guard('hgr-disk-error')
        tag=mount(session,good)
        point=session.bp('N_WAIT_CITY_INPUT');session.call('go');session.call('keys','\r');session.stopped('N_WAIT_CITY_INPUT');session.clear(point)
        session.call('korean_fast_text',False)
        restored=session.guard('hgr-disk-error-recovered')['case_state']
        expected=life['save']['case_state'].copy();expected[26]=2;expected[22]=0
        if restored!=expected:raise ValueError('Retry did not restore the saved case')
        stop(process,session)
        hgr_result={'missing_file':'H','image_tag':tag,'restored_case':restored,'font_and_resident_code_intact_at_prompt_and_after_retry':True,'session':archive(session)}
    finally:
        if process.poll() is None:
            session.call('exit');process.wait(timeout=10)
    write_json(test_mode.runtime('approved')/'disk-errors.json',{'format':1,'status':'pass',**pins,
        'text_mode':text_result,'hgr_mode':hgr_result,
        'scope':'Actual ProDOS missing R and H errors, English TEXT prompt and Korean HGR prompt, owned replacement-media mount and native retry. No low-level host I/O failure injection.'})


if __name__=='__main__':main()
