"""Native full-screen witness for the longest approved city description."""

import argparse

from . import test_mode
from .catalog import CATALOG
from .common import BUILD, DOCS, ROOT, read_json, sha256, write_json
from .encoding import GameEncoding
from .gameplay_test import archive, fixture, launch, stop


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--tag',required=True)
    options=parser.parse_args()
    if not options.tag.replace('-','').isalnum():parser.error('Safe tag required')
    pins=test_mode.identity('approved')
    directory=BUILD/(options.tag+'-visual');directory.mkdir(exist_ok=False)
    catalog=read_json(CATALOG);enc=GameEncoding.from_catalog(catalog)
    layouts=read_json(DOCS/'draft-capacity.json')['descriptions']
    item=max(layouts,key=lambda x:x['encoded_with_nul'])
    entry=next(e for e in catalog['entries'] if e['id']==item['id'])
    city=int(item['id'].split('.')[1][4:])
    state=read_json(test_mode.runtime('approved')/'synthetic-text.json')['save']['case_state'].copy()
    state[17]=city;state[22]=0;state[27:33]=[255]*6;state[23]=255
    source={'name':'VISUAL','rank':0,'solved':0}
    base=ROOT/read_json(BUILD/'approved/manifest.json')['image']
    media=fixture(base,directory/'long-description.po',source,state)
    process,session=launch('mame-'+options.tag+'-visual',media,'korean')
    try:
        session.boot_game('VISUAL',prompt=True,expected=state)
        # A valid selection from this city's first three raw-NUL strings.
        # Pin the selected-data fixture, then redraw via ordinary menus.
        data=enc.entry(entry)+b'\0'
        session.call('write',0x0E00,list(data))
        session.row(1);session.enter_menu('N_SHOW_COMPUTER_SAVE_MENU');session.enter_menu('N_OPEN_COMPUTER')
        session.guard('computer-full-screen')
        session.drain_menu_input()
        result=session.advance_to('N_WAIT_CITY_INPUT','\x1b','longest-city-description')
        if session.call('read',0x0E00,len(data))['bytes']!=list(data):raise ValueError('Native redraw replaced selected description')
        stop(process,session)
        write_json(test_mode.runtime('approved')/'visual.json',{'format':1,'status':'pass',**pins,
            'selected_description_id':entry['id'],'selected_encoded_sha256':sha256(data),
            'selected_data_fixture':True,'native_menu_redraw':True,'layout':item,'session':archive(session),
            'scope':'Longest encoded description selected within its native city, displayed through normal computer exit/redraw; visual inspection recorded in release-checks.md. Exhaustive static layouts and native message extrema are separate evidence.'})
    finally:
        if process.poll() is None:session.call('exit');process.wait(timeout=10)


if __name__=='__main__':main()
