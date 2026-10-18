"""Exhaustive draft message domains and fixed HGR layout preflight.

This is a source-derived static analysis and offline draft preview. It never
loads real translations into an emulator or writes a game image. Native tests
of the selected synthetic extrema are a separate required evidence source.
"""

import itertools
import sys

from .catalog import CATALOG, CONTROL_RE
from .common import BUILD, DOCS, ROOT, read_json, sha256, write_json
from .draft import audit
from .encoding import GameEncoding
from .measure_draft import units, wrap
from .captions import half_width

sys.path.insert(0,str(ROOT/'tools'))
from d_font import decode_d


def native_typewriter_layout(text,widths):
    result=wrap(text,widths,24,24,126,skip_line_marker_80=True)
    # Native N scrolls after its terminal NUL as well as after an explicit
    # separator. If only skipped spaces/$80 remain, that final run is empty.
    if result['final_empty_line']:
        result['lines'].append('')
        result['line_count']+=1
    first=next((i for i,line in enumerate(result['lines']) if line.strip()),None)
    span=0 if first is None else result['line_count']-first
    result['completed_lines_from_first_text']=span
    result['first_text_final_row']=None if first is None else 153-10*span
    result['all_text_remains_visible']=first is None or result['first_text_final_row']>=42
    return result


def legal_names(widths):
    """Exact original gates: <=15 ASCII bytes, glyph start byte column <16."""
    states={(0,24):''}
    candidates=[]
    for count in range(15):
        for (n,x),prefix in list(states.items()):
            if n!=count or x//7>=16:continue
            for code in range(33,127):  # unspaced worst word, no leading space
                value=prefix+chr(code);end=x+widths[code]
                candidates.append((end-24,value))
                states.setdefault((count+1,end),value)
    widest=max(candidates,key=lambda pair:(pair[0],-len(pair[1])))
    fifteen=next(value for _,value in candidates if len(value)==15)
    return {'widest':widest[1],'widest_advance':widest[0],'max_byte_name':fifteen,
            'maximum_characters':15,'glyph_start_byte_column_exclusive':16}


def measure():
    catalog=read_json(CATALOG);coverage=audit(catalog,complete=True)
    enc=GameEncoding.from_catalog(catalog)
    entries={entry['id']:entry for entry in catalog['entries']}
    text=lambda identifier:entries[identifier]['translation']
    ui=lambda number:text(f'c.ui.{number:03d}')
    original_glyphs=decode_d((ROOT/'assets/po/D.bin').read_bytes())['glyphs']
    widths={g['code']:g['width_byte']+1 for g in original_glyphs}
    heights={g['code']:g['height'] for g in original_glyphs}
    names=legal_names(widths)
    player_names=list(dict.fromkeys((names['widest'],names['max_byte_name'])))
    cities=[text(f'c.cities.{i:02d}') for i in range(30)]
    suspects=[text(f'c.suspects.{i:02d}') for i in range(10)]
    ranks=[text(f'c.detective_ranks.{i:02d}') for i in range(6)]
    treasures=[text(f'i.{i:03d}') for i in range(90)]  # Three per city; I[90] is structural empty.
    weekdays=[text(f'c.weekdays.{i:02d}')+text(f'c.weekday_suffixes.{i:02d}') for i in range(7)]
    cases={};fixed=[];covered=set();errors=[]

    def height(value):
        return max((heights[int(CONTROL_RE.fullmatch(token)[1],16)] if CONTROL_RE.fullmatch(token) else
                    heights[ord(token)] if ord(token)<128 else 8 for token in units(value)),default=0)

    def sentence(value):return value if value.endswith('"') else value+'.'

    def add(group,value,ids,consumer,parameters=None,buffer_limit=256):
        covered.update(ids)
        data=enc.encode(value)+b'\0'
        if len(data)>buffer_limit:errors.append(f'{group}: {len(data)} bytes exceed cursor-reset contract {buffer_limit}')
        layout=native_typewriter_layout(value,widths)
        if not layout['all_text_remains_visible']:errors.append(group+': first text scrolls beyond the report window before the wait')
        for line in layout['lines']:
            advance=sum(widths[int(CONTROL_RE.fullmatch(token)[1],16)] if CONTROL_RE.fullmatch(token) else
                        widths[ord(token)] if ord(token)<128 else 8 for token in units(line))
            if 24+advance>=126:errors.append(f'{group}: line exceeds native strict right edge')
        candidate={'text':value,'encoded_with_nul':len(data),'layout':layout,'ids':ids,
                   'consumer':consumer,'parameters':parameters or {}}
        state=cases.setdefault(group,{'combinations':0,'max_bytes':None,'max_lines':None})
        state['combinations']+=1
        if state['max_bytes'] is None or len(data)>state['max_bytes']['encoded_with_nul']:state['max_bytes']=candidate
        if state['max_lines'] is None or (layout['line_count'],len(data))>(state['max_lines']['layout']['line_count'],state['max_lines']['encoded_with_nul']):state['max_lines']=candidate

    def centered(identifier,center,row,bounds,consumer):
        value=text(identifier);covered.add(identifier)
        if any(CONTROL_RE.fullmatch(token) and int(CONTROL_RE.fullmatch(token)[1],16)>=0x8D for token in units(value)):
            raise ValueError('Forced-break text cannot be a single centered field')
        advance=sum(widths[int(CONTROL_RE.fullmatch(token)[1],16)] if CONTROL_RE.fullmatch(token) else
                    widths[ord(token)] if ord(token)<128 else 8 for token in units(value))
        left=center-half_width(advance)
        clip_left,clip_right,clip_top,clip_bottom=bounds
        actual_height=height(value)
        fits=clip_left<=left and left+advance-1<clip_right and clip_top<=row and row+actual_height<=clip_bottom
        if not fits:errors.append(f'{identifier}: centered field exceeds {bounds}')
        fixed.append({'id':identifier,'text':value,'center':center,'left':left,'top':row,
                      'advance_width':advance,'height':actual_height,'bounds':bounds,'fits':fits,'consumer':consumer})

    # All fixed centered UI call domains from N; numeric IDs are native C indexes.
    fixed_specs=[(0,138,69,[80,198,63,81],'N_DRAW_VERSION_DIALOG'),
        (1,56,14,[8,102,8,34],'N_BEGIN_OVERNIGHT_SKIP'),
        (2,56,14,[8,102,8,34],'N_PREPARE_REPORT_SCREEN'),
        (40,138,57,[36,234,48,104],'N_DRAW_SAVE_CASE_PROMPT'),
        (14,138,10,[4,276,4,24],'N_DRAW_HALL_OF_FAME'),
        (15,140,7,[4,276,4,24],'N_DRAW_DETECTIVE_ROSTER'),
        (12,140,177,[4,276,169,188],'N_SHOW_DETECTIVE_ROSTER'),
        (13,140,177,[4,276,169,188],'N_DELETE_DETECTIVE')]
    fixed_specs += [(number,136,52+10*i,[64,208,48,94],'N_DRAW_DISK_PROMPT') for i,number in enumerate((3,4,5,8))]
    fixed_specs += [(number,208,151+10*i,[148,273,145,188],'N_SHOW_WARRANT_FOLLOWUP') for i,number in enumerate((9,10,11))]
    fixed_specs += [(number,208,144+11*i,[148,273,138,188],'N_DRAW_MAIN_CITY_MENU') for i,number in enumerate((49,50,51,52))]
    fixed_specs += [(53,208,144,[148,273,138,188],'N_DRAW_CONNECTION_TOGGLE_OPTION'),
                    (54,208,155,[148,273,149,178],'N_SHOW_COMPUTER_SAVE_MENU'),
                    (55,208,166,[148,273,149,178],'N_SHOW_COMPUTER_SAVE_MENU')]
    fixed_specs += [(number,208,row,[148,273,58,105],'N_FINISH_ROUTE_CITY_EVENT / N_RESOLVE_ARREST')
                    for number,row in ((42,64),(43,74),(44,84),(45,80),(46,90))]
    for number in range(118,130):
        for row in (116,127,138):fixed_specs.append((number,84,row,[22,138,110,148],'N_DRAW_INVESTIGATION_CHOICES'))
    for number,center,row,bounds,consumer in fixed_specs:centered(f'c.ui.{number:03d}',center,row,bounds,consumer)
    for i in range(30):
        centered(f'c.cities.{i:02d}',56,14,[8,102,8,34],'N_DRAW_CURRENT_CITY_NAME')
        centered(f'c.cities.{i:02d}',74,44,[22,134,38,108],'N_DRAW_NEXT_TRAVEL_DESTINATION')
    for i in range(7):centered(f'c.weekdays.{i:02d}',110,9,[106,116,9,18],'N_DRAW_CLOCK_WEEKDAY')

    # Assembled reports follow N's append/show boundaries, not an invented
    # concatenation of separate buffers. Every combination in each domain is
    # measured; extrema retain IDs/parameters for native synthetic tests.
    for player in player_names:
        add('welcome',ui(24)+player+ui(25),['c.ui.024','c.ui.025'],'N_SHOW_CASE_WELCOME',{'name':player})
        add('failed-header',sentence(ui(76)+player)+ui(56),['c.ui.076','c.ui.056'],'N_BEGIN_FAILED_CASE_REPORT',{'name':player})
        add('next-case',ui(93)+player+ui(94),['c.ui.093','c.ui.094'],'N_ASK_FOR_NEXT_CASE',{'name':player})
    for rank,value in enumerate(ranks):
        add('rank',value+ui(99),[f'c.detective_ranks.{rank:02d}','c.ui.099'],'N_SHOW_CASE_WELCOME',{'rank':rank})
        add('promotion',ui(96)+value+ui(58),['c.ui.096',f'c.detective_ranks.{rank:02d}','c.ui.058'],'N_CHECK_PROMOTION_REPORT',{'rank':rank})
    for city,value in enumerate(cities):
        add('news',sentence(ui(27)+value),['c.ui.027',f'c.cities.{city:02d}'],'N_ANNOUNCE_NEWS_FLASH',{'city':city})
        for female in (False,True):
            sex=30 if female else 29;poss=100 if female else 101;obj=70 if female else 69
            add('suspect-sex',ui(sex)+ui(31),[f'c.ui.{sex:03d}','c.ui.031'],'N_ANNOUNCE_SUSPECT',{'female':female})
            add('mission',ui(32)+value+' '+ui(33)+ui(poss)+ui(34)+ui(obj)+'<CTRL:8D>',
                ['c.ui.032',f'c.cities.{city:02d}','c.ui.033',f'c.ui.{poss:03d}','c.ui.034',f'c.ui.{obj:03d}'],
                'N_APPEND_ARREST_OBJECT',{'city':city,'female':female})
        for suspect,person in enumerate(suspects):
            add('successful-police',sentence(ui(77)+value+ui(78)+person),
                ['c.ui.077',f'c.cities.{city:02d}','c.ui.078',f'c.suspects.{suspect:02d}'],
                'N_REPORT_SOLVED_CASE',{'city':city,'suspect':suspect})
    for treasure,value in enumerate(treasures):
        add('treasure',sentence(ui(28)+value),['c.ui.028',f'i.{treasure:03d}'],'N_ANNOUNCE_NEWS_FLASH',{'treasure':treasure})
        for city in (treasure//3,):  # N chooses 3*origin_city + random(3).
            origin=cities[city]
            for suspect,person in enumerate(suspects):
                add('successful-loot',sentence(ui(102)+person+ui(79)+value+ui(80)+origin),
                    ['c.ui.102',f'c.suspects.{suspect:02d}','c.ui.079',f'i.{treasure:03d}','c.ui.080',f'c.cities.{city:02d}'],
                    'N_REPORT_SOLVED_CASE',{'treasure':treasure,'city':city,'suspect':suspect})
    original_c=(ROOT/'assets/po/C.bin').read_bytes()
    for day,weekday in enumerate(weekdays):
        for hour in range(8,18):  # Native case initialization: random(10)+8.
            digits=''
            if hour>=10 and not(13<=hour<22):digits+=chr(original_c[0xD780-0xD200+hour]+32)
            digits+=chr(original_c[0xD798-0xD200+hour]+32)
            for player in player_names:
                add('deadline',ui(35)+weekday+ui(71)+digits+ui(72 if hour<12 else 73)+ui(36)+player+ui(37),
                    ['c.ui.035',f'c.weekdays.{day:02d}',f'c.weekday_suffixes.{day:02d}','c.ui.071',
                     f'c.ui.{72 if hour<12 else 73:03d}','c.ui.036','c.ui.037'],
                    'N_APPEND_DEADLINE_MERIDIEM',{'day':day,'hour':hour,'name':player})
    for i,person in enumerate(suspects):
        add('timeout',ui(83)+ui(91)+person+ui(92),['c.ui.083','c.ui.091',f'c.suspects.{i:02d}','c.ui.092'],
            'N_REPORT_CASE_TIMEOUT',{'suspect':i})
        add('warrant-name',person+ui(58),[f'c.suspects.{i:02d}','c.ui.058'],'N_APPEND_NEXT_MATCHED_SUSPECT',{'suspect':i})
        for player in player_names:
            header=sentence(ui(76)+player)+ui(56)
            add('no-warrant',sentence(header+ui(88)+person)+ui(89),
                ['c.ui.076','c.ui.056','c.ui.088',f'c.suspects.{i:02d}','c.ui.089'],'N_SHOW_ARREST_RESULT',{'suspect':i,'name':player})
            add('wrong-trail',header+ui(84)+person+ui(85),
                ['c.ui.076','c.ui.056','c.ui.084',f'c.suspects.{i:02d}','c.ui.085'],'N_REPORT_WRONG_WARRANT',{'suspect':i,'name':player})
        add('wrong-warrant',sentence(ui(86)+person),['c.ui.086',f'c.suspects.{i:02d}'],'N_REPORT_WRONG_WARRANT',{'warrant':i})
    for number in range(1,11):
        add('promotion-progress',ui(102)+ui(106+number)+ui(106)+ui(95),
            ['c.ui.102',f'c.ui.{106+number:03d}','c.ui.106','c.ui.095'],'N_REPORT_CASES_UNTIL_PROMOTION',{'remaining':number})
    for number in (19,20,21,22,23,26,38,39,61,62,63,64,74,75,81,82,87,90,98):
        add('direct-report-'+str(number),ui(number),[f'c.ui.{number:03d}'],'N_DRAW_UI_TEXT / N_DRAW_UI_TEXT_AT_LEFT_MARGIN')

    # Suspect lists are separate native calls, each with its own terminal
    # scroll. Preserve their order and changing comma/final-period rule.
    sequences=[]
    for mask in range(1,1<<10):
        chosen=[i for i in range(10) if mask&(1<<i)]
        first=62 if len(chosen)==1 else 63
        calls=[ui(first)] + [suspects[i]+ui(58 if j==len(chosen)-1 else 57) for j,i in enumerate(chosen)]
        lines=[]
        for value in calls:lines.extend(native_typewriter_layout(value,widths)['lines'])
        first_text=next(i for i,line in enumerate(lines) if line.strip())
        final_row=153-10*(len(lines)-first_text)
        if final_row<42:errors.append('warrant list scrolls information outside its viewport')
        sequences.append({'suspects':chosen,'native_calls':calls,'lines':lines,
                          'first_text_final_row':final_row,'all_text_remains_visible':final_row>=42,
                          'largest_individual_buffer':max(len(enc.encode(value))+1 for value in calls)})
    worst_sequence=min(sequences,key=lambda value:value['first_text_final_row'])
    covered.add('c.ui.057')

    # Raw fragments not normally shown alone still get a complete review view
    # and typewriter regression layout. This is not a live-context claim.
    standalone=[]
    for number in range(130):
        identifier=f'c.ui.{number:03d}'
        standalone.append({'id':identifier,'text':ui(number),'layout':native_typewriter_layout(ui(number),widths),
                           'context':'isolated catalog preview; concrete fixed/assembly contexts are recorded separately'})
    normal=[]
    def normal_field(identifier,first,next_x,right,row,bottom,consumer):
        value=text(identifier);covered.add(identifier)
        layout=wrap(value,widths,first,next_x,right)
        last=row+max(0,layout['line_count']-1)*10+(height(layout['lines'][-1]) if layout['lines'] else 0)
        if last>bottom:errors.append(identifier+': normal text exceeds panel bottom')
        normal.append({'id':identifier,'text':value,'first_x':first,'next_x':next_x,'right':right,
                       'top':row,'bottom':bottom,'last_row_exclusive':last,'consumer':consumer,'layout':layout})
    normal_field('n.save_dialog',46,46,232,72,102,'N_DRAW_SAVE_CASE_PROMPT')
    for i in range(4):
        value=text(f'r.intro.{i:02d}');covered.add(f'r.intro.{i:02d}')
        if i<2:normal_field(f'r.intro.{i:02d}',10 if i==0 else 12,10 if i==0 else 12,273,13 if i==0 else 160,149 if i==0 else 188,'R_DRAW_INTRO_STRING')
        else:centered(f'r.intro.{i:02d}',140,128 if i==2 else 116,[4,276,112,140],'R_CENTER_INTRO_STRING')
    # Computer values use normal wrapping inside the right monitor; each row
    # has an eleven-pixel pitch, so every value must remain a single line.
    for identifier in sorted(e for e in entries if e.startswith('c.clue.')):
        value=text(identifier);covered.add(identifier)
        layout=wrap(value,widths,196,196,273)
        if layout['line_count']>1:errors.append(identifier+': trait value exceeds its row')
        normal.append({'id':identifier,'text':value,'first_x':196,'right':273,'layout':layout,'consumer':'N_DRAW_TRAIT_VALUE'})
    for number in (65,66):
        normal_field(f'c.ui.{number:03d}',196,196,273,18,29,'N_DRAW_TRAIT_VALUE / sex selector')
    for number,left,right in ((16,24,110),(17,120,208),(18,208,273)):
        normal_field(f'c.ui.{number:03d}',left,left,right,19,27,'N_DRAW_DETECTIVE_ROSTER column header')
    for rank in range(6):
        normal_field(f'c.detective_ranks.{rank:02d}',110,110,239,32,43,'N_NEXT_ROSTER_RECORD rank field')
    for i in range(8):
        for female in (False,True):
            identifier=f'k.{i:03d}';covered.add(identifier)
            value=sentence(text(identifier).replace('#',text('c.service.she' if female else 'c.service.he')))
            layout=wrap(value,widths,148,148,273)
            last=26+max(0,layout['line_count']-1)*10+8
            if last>136:errors.append(identifier+': standalone investigation exceeds panel')
            normal.append({'id':identifier,'female':female,'text':value,'first_x':148,'right':273,
                           'last_row_exclusive':last,'layout':layout,'consumer':'C_APPEND_5000_TEXT / N_SHOW_INVESTIGATION_RESULT'})
    name_fields={'roster_name':{'left':12,'max_advance':names['widest_advance'],'right_exclusive':12+names['widest_advance'],'next_column_left':110},
                 'roster_rows':{'first':32,'last':32+12*11,'height':9,'footer_top':177},
                 'hall_names':{'left':84,'max_advance':names['widest_advance'],'right_exclusive':84+names['widest_advance']},
                 'hall_rows':{'first':22,'last':22+15*10,'height':9,'bottom_exclusive':188},
                 'case_count':{'left':239,'max_digits':3,'max_advance':3*max(widths[i] for i in range(48,58)),'right_limit':273}}
    if name_fields['roster_name']['right_exclusive']>110:errors.append('Legal ASCII name overlaps roster rank')
    if name_fields['roster_rows']['last']+9>177 or name_fields['hall_rows']['last']+9>188:errors.append('Roster/hall final row clips')
    if 239+name_fields['case_count']['max_advance']>=273:errors.append('Native decimal case count clips')
    report={'format':1,'catalog_sha256':coverage['catalog_sha256'],'status':'pass' if not errors else 'fail',
            'input_names':names,'fixed_fields':fixed,'normal_fields':normal,'message_groups':cases,
            'dynamic_combinations':sum(group['combinations'] for group in cases.values()),
            'maximum_assembled_bytes':max(group['max_bytes']['encoded_with_nul'] for group in cases.values()),
            'standalone_ui_previews':standalone,'covered_context_ids':sorted(covered),'errors':errors,
            'warrant_sequences_measured':len(sequences),'worst_warrant_sequence':worst_sequence,'ascii_name_and_numeric_fields':name_fields,
            'structural_empty_treasure_id':'i.090',
            'font_contract':{'hangul_advance':8,'hangul_height':8,'ascii_max_height':max(heights[i] for i in range(32,127)),
                             'line_pitch':10,'completed_report_rows':[42,153]},
            'scope':'Static finite dynamic choices with source-coupled treasure/city and valid deadline hours; name byte/advance envelopes are representative stress profiles. S2/captions have separate exhaustive reports; native extrema must be verified before K3.'}
    write_json(DOCS/'message-layouts.json',report)
    write_json(BUILD/'synthetic/message-layouts.json',report)
    if errors:raise ValueError('Draft message layout failed: '+'; '.join(errors[:10]))
    print(f"Measured {report['dynamic_combinations']} dynamic combinations; max {report['maximum_assembled_bytes']} bytes; {len(fixed)} fixed fields fit")
    return report


if __name__=='__main__':measure()
