"""Freeze a human-review bundle after complete synthetic feasibility checks.

The real draft is used only for UTF-8 documents and offline font previews.
This command neither approves translations nor creates translated game media.
"""

from copy import deepcopy
import csv
import html
import json
import shutil

from .catalog import CATALOG, CONTROL_RE
from .common import ASSETS, BUILD, DOCS, ROOT, original_inputs, read_json, sha256, write_json
from .draft import audit
from .encoding import GameEncoding
from .font import hgr_rows, load_bdf
from .evidence import read as read_evidence
from .measure_draft import units


RETAINED_UI = {
    'c.ui.006': 'Side A fragment retained for the floppy disk prompt; not selected by the 800K prompt.',
    'c.ui.007': 'Side B fragment retained for the floppy disk prompt; not selected by the 800K prompt.',
    'c.ui.041': 'Original UI save help retained; the 800K game draws the separately catalogued n.save_dialog.',
    'c.ui.047': 'Original retained UI text; no UI call for index 47 in either N source. Not a live-branch claim.',
    'c.ui.048': 'Original retained UI text; no UI call for index 48 in either N source. Not a live-branch claim.',
    'c.ui.097': 'Write-protection prompt prefix used by the floppy branch, absent from the 800K prompt.',
    'c.ui.117': 'Write-protection prompt suffix used by the floppy branch, absent from the 800K prompt.',
}
NATIVE = ('synthetic-text', 'native-readers', 'native-clock', 'native-captions', 'native-messages', 'native-cities')


def feasibility():
    catalog = read_json(CATALOG)
    status = audit(catalog, complete=True)
    identity = original_inputs()
    disk = read_json(BUILD / 'synthetic/manifest.json')
    city = read_json(DOCS / 'draft-capacity.json')
    messages = read_json(DOCS / 'message-layouts.json')
    text = read_json(DOCS / 'synthetic-text-assets.json')
    encoding = read_json(DOCS / 'encoding-roundtrip.json')
    if any(report['catalog_sha256'] != status['catalog_sha256'] for report in (disk, city, messages, text, encoding)):
        raise ValueError('Rebuild stale draft evidence before requesting review')
    if disk['mode'] != 'synthetic' or sha256((ROOT / disk['image']).read_bytes()) != disk['image_sha256']:
        raise ValueError('Synthetic media identity differs')
    if disk['original_inputs'] != identity or disk['repeated_build_identical'] is not True:
        raise ValueError('Original inputs or repeated-build evidence differ')
    for name, digest in disk['build_inputs']['sources'].items():
        if sha256((ROOT / name).read_bytes()) != digest:
            raise ValueError('Synthetic build source changed: ' + name)
    if text['remaining_display_entries'] or messages['status'] != 'pass' or messages['errors']:
        raise ValueError('Unresolved integration/layout entries')
    if not all(bound['fits'] for bound in city['bounds'].values()):
        raise ValueError('STOP: measured draft capacity failure; user decision required')
    if disk['disk']['free_blocks'] <= 0 or disk['disk']['total_blocks'] != 1600:
        raise ValueError('STOP: synthetic disk capacity differs')
    for name, record in text['files'].items():
        if sha256((ROOT / record['path']).read_bytes()) != record['sha256']:
            raise ValueError('Compiled asset changed: ' + name)
    reports = {}
    for name in NATIVE:
        path = DOCS / f'runtime/{name}.json'
        report = read_json(path)
        if report['status'] != 'pass' or report['synthetic_image_sha256'] != disk['image_sha256']:
            raise ValueError('Native evidence is stale: ' + name)
        if name == 'synthetic-text':
            if report['catalog_sha256'] != status['catalog_sha256']:
                raise ValueError('Lifecycle catalog changed')
            for session in report['sessions']:
                for filename, digest in session['artifacts'].items():
                    artifact = DOCS / 'runtime/synthetic-text' / session['session'] / filename
                    if sha256(read_evidence(artifact)) != digest:
                        raise ValueError('Lifecycle artifact changed: ' + str(artifact))
        else:
            for filename, digest in report.get('artifacts', {}).items():
                artifact = DOCS / 'runtime' / name / filename
                if sha256(read_evidence(artifact)) != digest:
                    raise ValueError('Native artifact changed: ' + str(artifact))
        reports[name] = {'path': str(path.relative_to(ROOT)), 'sha256': sha256(path.read_bytes()),
                         'scope': report['scope']}
    caption = read_json(DOCS / 'runtime/native-captions.json')
    if caption['fixture']['captions'] != text['captions']:
        raise ValueError('Native caption layout is stale')
    # Recompute the message extrema and compare complete payload/layout fixtures,
    # without rerunning an already passing emulator test.
    from .message_test import build as message_fixtures
    if message_fixtures() != read_json(DOCS / 'runtime/native-messages.json')['fixture']:
        raise ValueError('Native message extrema are stale')
    if len(read_json(DOCS / 'runtime/native-cities.json')['results']) != 60:
        raise ValueError('Native city coverage is incomplete')

    contexts = {}
    def cover(ids, reason):
        for identifier in ids:
            contexts.setdefault(identifier, []).append(reason)
    cover(city['covered_catalog_ids'], 'All native city selectors, subject/pronoun/trait expansions, or explicitly retained S2 tail previews')
    cover(messages['covered_context_ids'], 'Source-derived fixed field, assembled report, warrant sequence, or normal-field layout')
    cover(text['captions']['covered_entries'], 'Native post-decompression caption pixels on both HGR pages')
    cover(('bitmap.d.am', 'bitmap.d.pm'), 'All native clock hours/weekdays and redraw transitions')
    cover(('i.090',), 'Original intentional empty treasure terminator; not selected by the 0..89 treasure domain')
    cover(('n.plural_suffix',), 'Intentionally empty; complete nine-byte English plural append/cursor-increment span removed')
    for identifier, reason in RETAINED_UI.items():
        cover((identifier,), reason + ' Isolated font/layout preview only.')
    cover(('s2.city21.line24.disk2',), 'Floppy-only original wording variant; draft round-trip/offline preview, outside the first 800K build')
    targets = [entry for entry in catalog['entries'] if entry['translatable']]
    missing = [entry['id'] for entry in targets if entry['id'] not in contexts]
    if missing:
        raise ValueError('Unaccounted translation layouts: ' + ', '.join(missing))
    ids = {entry['id'] for entry in targets if any(ref['variant'] == 'po' for ref in entry['references'])}
    if not ids <= set(disk['covered_entries']):
        raise ValueError('Some 800K translations are absent from the full-size synthetic image')
    report = {'format': 1, 'status': 'pass', 'catalog_sha256': status['catalog_sha256'],
              'synthetic_image_sha256': disk['image_sha256'], 'translation_targets': len(targets),
              'po_targets': len(ids), 'unaccounted_ids': missing, 'contexts': contexts,
              'retained_ui_without_po_call': RETAINED_UI, 'native_evidence': reports,
              'glyphs': encoding['non_ascii_glyphs'], 'font_bytes': encoding['font_bytes'],
              'capacity_bounds': city['bounds'], 'disk_free_blocks': disk['disk']['free_blocks'],
              'dynamic_combinations': messages['dynamic_combinations'],
              'warrant_subsets': messages['warrant_sequences_measured'],
              'original_inputs': identity, 'repeated_build_identical': True,
              'scope': 'K2 technical feasibility and complete draft coverage. Human linguistic approval and K5/K6 actual-translation execution remain open.'}
    write_json(DOCS / 'review-readiness.json', report)
    return report, catalog, city, messages, text


class Raster:
    def __init__(self):
        from PIL import Image
        self.Image = Image
        self.bdf = load_bdf()
        self.d = (ROOT / 'assets/po/D.bin').read_bytes()

    def image(self):
        return self.Image.new('RGB', (280, 192))

    def line(self, image, value, x, y):
        for token in units(value):
            control = CONTROL_RE.fullmatch(token)
            code = int(control[1], 16) if control else ord(token)
            if code > 127 and not control:
                rows = hgr_rows(self.bdf, token)
                pixels = [[bool(row & 1 << bit) for bit in range(7)] for row in rows]
                advance = 8
            else:
                if not 32 <= code < 0x8B:
                    raise ValueError('Non-drawing control survived layout')
                index = code - 32
                start = self.d[index] + 256 * self.d[index + 112] - 0xB900
                width, height = self.d[start:start + 2]
                stride = (width + 6) // 7
                pixels = [[bool(self.d[start + 2 + row * stride + col // 7] & 1 << (col % 7))
                           for col in range(width)] for row in range(height)]
                advance = width + 1
            for row, values in enumerate(pixels):
                for col, pixel in enumerate(values):
                    if pixel:
                        if not (0 <= x + col < 280 and 0 <= y + row < 192):
                            raise ValueError('Offline preview ink is outside HGR')
                        image.putpixel((x + col, y + row), (255, 255, 255))
            x += advance

    def layout(self, lines, first, next_x, top):
        image = self.image()
        for row, line in enumerate(lines):
            self.line(image, line, first if row == 0 else next_x, top + row * 10)
        return image

    def hgr(self, raw):
        image = self.image()
        for y in range(192):
            for x in range(280):
                offset = (y & 7) * 1024 + ((y >> 3) & 7) * 128 + (y >> 6) * 40 + x // 7
                if raw[offset] & 1 << (x % 7):
                    image.putpixel((x, y), (255, 255, 255))
        return image


def previews(directory, catalog, city, messages, text):
    raster = Raster()
    enc = GameEncoding.from_catalog(catalog)
    entries = {entry['id']: entry for entry in catalog['entries']}
    items = []
    destination = directory / 'previews'
    destination.mkdir(exist_ok=True)
    def save(name, image, caption, ids):
        filename = 'previews/' + name + '.png'
        image.save(directory / filename)
        items.append({'file': filename, 'caption': caption, 'ids': ids,
                      'kind': 'offline real-draft raster; not translated gameplay evidence'})

    # Actual unmodified native bitmap backgrounds plus host-side draft ink.
    from .caption_test import reference
    inverse = {enc.characters[(i + 1) % len(enc.characters)]: c for i, c in enumerate(enc.characters)}
    for group in ('R0', 'R2', 'R3', 'N4', 'N5'):
        selected = {identifier: deepcopy(item) for identifier, item in text['captions']['layout'].items() if item['group'] == group}
        for item in selected.values():
            for line in item['lines']:
                line['text'] = ''.join(inverse.get(c, c) for c in line['text'])
        raw = read_evidence(DOCS / f'runtime/native-captions/{group}-page1-baseline.hgr')
        page, _ = reference(raw, selected.values())
        save('caption-' + group, raster.hgr(page), 'Draft caption on original bitmap: ' + group, list(selected))

    for number in range(30):
        desc = max((item for item in city['descriptions'] if any(ref.get('record') == number and ref['variant'] == 'po'
                    for ref in entries[item['id']]['references'])), key=lambda item: item['last_pixel_row_exclusive'])
        save(f'city-{number:02d}-description', raster.layout(desc['lines'], 156, 148, 6),
             f'City {number:02d}: deepest description', [desc['id']])
        clue = city['investigations'][number]
        save(f'city-{number:02d}-investigation', raster.layout(clue['lines'], 148, 148, 26),
             f'City {number:02d}: deepest combined investigation', [clue['route_id'], clue['trait_id']])
    for group, state in messages['message_groups'].items():
        item = state['max_lines']; lines = item['layout']['lines']
        save('report-' + group, raster.layout(lines, 24, 24, 153 - 10 * len(lines)),
             'Report extent: ' + group, item['ids'])
    sequence = messages['worst_warrant_sequence']
    save('complete-warrant-list', raster.layout(sequence['lines'], 24, 24, 153 - 10 * len(sequence['lines'])),
         'Complete ten-suspect list after native terminal scrolls', [f'c.suspects.{i:02d}' for i in sequence['suspects']])
    for item in messages['normal_fields']:
        if item['id'] == 'n.save_dialog':
            save('save-dialog', raster.layout(item['layout']['lines'], item['first_x'], item['next_x'], item['top']),
                 'Save dialog field at its actual coordinates', [item['id']])
    # A distinct offline view makes the single floppy-only draft reviewable.
    identifier = 's2.city21.line24.disk2'
    value = (entries['c.ui.059']['translation'] +
             entries[identifier]['translation'].replace('#', entries['c.ui.067']['translation']) + '.')
    from .measure_draft import wrap
    from d_font import decode_d
    widths = {glyph['code']: glyph['width_byte'] + 1 for glyph in decode_d(raster.d)['glyphs']}
    layout = wrap(value, widths, 148, 148, 273)
    save('floppy-only-variant', raster.layout(layout['lines'], 148, 148, 26),
         'Floppy-only variant; outside 800K image', [identifier])
    write_json(directory / 'previews.json', items)
    return items


def publish_current(directory, manifest):
    """Publish approval state outside the immutable reviewed snapshot."""
    from .approval import require
    receipt = None
    if (ASSETS / 'approval.json').exists():
        try:
            candidate = require(workspace=ROOT)
            if candidate['catalog_sha256'] == manifest['catalog_sha256']:
                receipt = candidate
        except ValueError:
            pass  # An old receipt cannot approve a changed draft.
    current = DOCS / 'review'
    record = {'catalog_sha256': manifest['catalog_sha256'],
              'bundle_sha256': manifest['bundle_sha256'], 'directory': directory.name,
              'index': directory.name + '/index.html',
              'status': 'approved' if receipt else 'awaiting_human_review'}
    if receipt:
        record.update(approval='assets/korean/approval.json',
                      approval_sha256=sha256((ASSETS/'approval.json').read_bytes()))
    write_json(current / 'current.json', record)
    title = '승인된 한국어 번역' if receipt else '현재 한국어 번역 검수'
    status = ("<p>사용자가 전체 번역을 승인했습니다. 아래 검수 묶음은 승인 전 상태를 보존한 기록입니다. "
              "현재 승인 상태는 <a href='../../../assets/korean/approval.json'>별도 승인 기록</a>에 있습니다.</p>"
              "<p><a href='../release-checks.md'>한국어판 실행 검증</a> · "
              "<a href='../../../build/korean/approved/carmen-world-ko.po'>800K 한국어 디스크</a></p>" if receipt else
              "<p>항목 ID로 수정 의견을 보내거나, 검수한 전체 카탈로그 버전을 명시하여 승인해 주세요.</p>")
    (current / 'index.html').write_text(
        "<!doctype html><html lang='ko'><meta charset='utf-8'><meta name='viewport' content='width=device-width'>"
        f"<title>{title}</title><style>body{{font:16px/1.6 system-ui,sans-serif;max-width:60rem;margin:3rem auto;padding:1rem}}"
        f"code{{overflow-wrap:anywhere}}</style><h1>{title}</h1>{status}"
        f"<p><a href='{directory.name}/index.html'>검수 묶음 — {manifest['translation_targets']:,}개 번역</a></p>"
        f"<p>Catalog SHA-256: <code>{manifest['catalog_sha256']}</code></p>"
        f"<p>Bundle SHA-256: <code>{manifest['bundle_sha256']}</code></p></html>", encoding='utf-8')


def build():
    readiness, catalog, city, messages, text = feasibility()
    directory = DOCS / 'review' / readiness['catalog_sha256'][:12]
    if (directory/'manifest.json').exists():
        from .approval import bundle
        manifest, _ = bundle(directory/'manifest.json', workspace=ROOT)
        publish_current(directory, manifest)
        print('Preserved immutable review bundle:', directory.relative_to(ROOT))
        return manifest
    directory.mkdir(parents=True, exist_ok=True)
    for source, name in ((CATALOG, 'catalog.json'), (ASSETS / 'glossary.json', 'glossary.json'),
                         (ASSETS / 'review-notes.json', 'review-notes.json'),
                         (ASSETS / 'font/source.json', 'font-source.json'),
                         (ASSETS / 'font/LICENSE.txt', 'FONT-LICENSE.txt'),
                         (DOCS / 'draft-capacity.json', 'city-layouts.json'),
                         (DOCS / 'message-layouts.json', 'message-layouts.json'),
                         (DOCS / 'review-readiness.json', 'readiness.json')):
        shutil.copyfile(source, directory / name)
    images = previews(directory, catalog, city, messages, text)
    esc = lambda value: html.escape(str(value), quote=True)
    rows = []
    with (directory / 'translations.tsv').open('w', encoding='utf-8', newline='') as stream:
        writer = csv.writer(stream, delimiter='\t')
        writer.writerow(('id', 'status', 'translation_target', 'original', 'draft', 'context', 'protected_tokens', 'input_tokens', 'references', 'layout_evidence'))
        for entry in catalog['entries']:
            refs = json.dumps(entry['references'], ensure_ascii=False)
            evidence = readiness['contexts'].get(entry['id'], [entry.get('exclusion_reason', '')])
            writer.writerow((entry['id'], entry['status'], entry['translatable'], entry['original'], entry['translation'], entry['context'],
                             json.dumps(entry['protected_tokens'], ensure_ascii=False), json.dumps(entry.get('input_tokens', []), ensure_ascii=False), refs, '; '.join(evidence)))
            sources = '; '.join(f"{ref['variant']}/{ref['file']}: {ref['locator']} (offset {ref.get('offset', 'bitmap')})" for ref in entry['references'])
            tokens = json.dumps({'protected': entry['protected_tokens'], 'input': entry.get('input_tokens', [])}, ensure_ascii=False)
            rows.append(f"<tr id='{esc(entry['id'])}' data-target='{int(entry['translatable'])}'><td><a href='#{esc(entry['id'])}'>{esc(entry['id'])}</a><br>{esc(entry['status'])}</td>"
                        f"<td class='text'>{esc(entry['original'])}</td><td class='text' lang='ko'>{esc(entry['translation'] if entry['translation'] is not None else '[excluded]')}</td>"
                        f"<td>{esc(entry['context'])}<p>{esc('; '.join(evidence))}</p><details><summary>Tokens and source references</summary><pre>{esc(tokens)}</pre>{esc(sources)}</details></td></tr>")
    gallery = ''.join(f"<figure><a href='{esc(item['file'])}'><img loading='lazy' width='280' height='192' src='{esc(item['file'])}'></a><figcaption>{esc(item['caption'])}<br>{esc(', '.join(item['ids']))}</figcaption></figure>" for item in images)
    style = "body{font:16px/1.5 system-ui,sans-serif;margin:2rem;color:#20242a}a{color:#2458a4}table{border-collapse:collapse;width:100%;table-layout:fixed}td,th{border:1px solid #ccd1d7;padding:.6rem;vertical-align:top;overflow-wrap:anywhere}th{background:#edf0f3}td:first-child{width:13%}.text{white-space:pre-wrap}pre{white-space:pre-wrap;font-size:13px}input{font:inherit;padding:.5rem;width:min(42rem,90%)}figure{margin:0}img{image-rendering:pixelated;max-width:100%;height:auto;background:#000}figcaption{font-size:13px;max-width:280px}.gallery{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:2rem}nav{margin:1rem 0}p{max-width:90ch}"
    intro = f"""<h1>한국어 번역 초안 검수</h1>
<p>대상 전체 <b>{readiness['translation_targets']:,}개</b> · 800K판 {readiness['po_targets']:,}개 · 한글 710자 · 아직 사람 승인 없음.</p>
<p>Catalog SHA-256: <code>{readiness['catalog_sha256']}</code></p>
<p>원문과 초안의 정확성·자연스러움·용어 일관성·단서 난이도를 검수해 주세요. 수정할 때 항목 ID를 적어 주세요.
전체 승인 시 이 카탈로그 해시를 명시해 주세요. 답이 없거나 일부만 승인한 경우 전체 승인으로 처리하지 않습니다.</p>
<p>이 묶음의 한국어 PNG는 원래 7×8 한글 및 영문 글꼴로 만든 <b>오프라인 초안 미리보기</b>입니다.
한국어 번역을 실행한 게임 화면이 아닙니다. 합성 디스크는 같은 문자 집합·크기·제어 구조를 가진 글자 순환 치환으로 검증했습니다.
원래 그림을 쓴 5개 미리보기 외의 검은 배경은 글자 위치만 보여 줍니다.</p>
<p>영문 입력은 그대로입니다. 탐정 이름은 ASCII 최대 15자이며 원래 문자폭 제한 때문에 더 일찍 멈출 수 있습니다.
Y/N, Return, Escape, Control-D를 바꾸지 않습니다. TEXT MODE 안내 12개는 영어 유지 대상입니다.
의도된 빈 문자열·반복·미사용 원본 항목도 삭제하지 않았습니다. 140K 플로피 이식은 이번 800K 빌드 범위 밖입니다.</p>
<nav><a href='previews.html'>대표 글꼴/레이아웃 미리보기 {len(images)}개</a> · <a href='translations.tsv'>전체 검수 TSV</a> ·
<a href='catalog.json'>전체 카탈로그와 원본 참조</a> · <a href='glossary.json'>용어집</a> · <a href='review-notes.json'>검수 주의 사항</a> ·
<a href='readiness.json'>용량·합성 실행 검증</a> · <a href='font-source.json'>글꼴 출처</a> · <a href='FONT-LICENSE.txt'>라이선스</a></nav>
<p>주요 검수 사항: 영어 말장난의 손실, 시대 지명·국경·통화, 원문 사실을 보존한 부분, 저작권 기호의 문자 대체,
자신/자신의 치환과 반복, 도시 선택 범위 밖에 보존된 14개 단서, 플로피에만 있는 문장 1개. 자세한 ID와 결정은 검수 주의 사항에 있습니다.</p>"""
    script = """<script>const search=document.querySelector('#search'),toggle=document.querySelector('#excluded'),rows=[...document.querySelectorAll('tbody tr')];function filter(){let n=0;const q=search.value.toLocaleLowerCase();for(const row of rows){row.hidden=(!toggle.checked&&row.dataset.target==='0')||!row.textContent.toLocaleLowerCase().includes(q);if(!row.hidden)n++;}document.querySelector('#count').textContent=n;}search.addEventListener('input',filter);toggle.addEventListener('change',filter);filter();if(location.hash){toggle.checked=true;filter();document.getElementById(decodeURIComponent(location.hash.slice(1)))?.scrollIntoView();}</script>"""
    (directory / 'index.html').write_text(f"<!doctype html><html lang='ko'><meta charset='utf-8'><meta name='viewport' content='width=device-width'><title>한국어 번역 검수</title><style>{style}</style>{intro}<label>검색 <input id='search' type='search' placeholder='ID, 원문, 번역, 문맥'></label><p><label><input id='excluded' type='checkbox' style='width:auto'> 번역 제외 항목도 표시</label> · 표시 <span id='count'></span>개</p><table><thead><tr><th>ID / 상태</th><th>원문</th><th>한국어 초안</th><th>문맥과 근거</th></tr></thead><tbody>{''.join(rows)}</tbody></table>{script}</html>", encoding='utf-8')
    (directory / 'previews.html').write_text(f"<!doctype html><html lang='ko'><meta charset='utf-8'><meta name='viewport' content='width=device-width'><title>오프라인 초안 미리보기</title><style>{style}</style><h1>오프라인 초안 미리보기</h1><p><a href='index.html'>검수표로 돌아가기</a> · 원래 280×192 좌표와 실제 글꼴 픽셀. 클릭하면 PNG가 열립니다. 실제 번역판 게임 실행 화면이 아닙니다.</p><div class='gallery'>{gallery}</div></html>", encoding='utf-8')
    files = {str(path.relative_to(directory)): sha256(path.read_bytes()) for path in sorted(directory.rglob('*')) if path.is_file() and path.name != 'manifest.json'}
    manifest = {'format': 1, 'status': 'awaiting explicit human review; no approval created',
                'catalog_sha256': readiness['catalog_sha256'], 'files': files,
                'bundle_sha256': sha256(json.dumps(files, sort_keys=True, separators=(',', ':')).encode()),
                'translation_targets': readiness['translation_targets'], 'offline_preview_images': len(images),
                'approval_requirement': 'PLAN-korean.md K3: explicit human approval of the whole exact catalog version before actual-translation media integration'}
    write_json(directory / 'manifest.json', manifest)
    publish_current(directory, manifest)
    print('Review bundle:', directory.relative_to(ROOT))
    print('Bundle SHA-256:', manifest['bundle_sha256'])
    return manifest


if __name__ == '__main__':
    build()
