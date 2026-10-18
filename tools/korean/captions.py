"""Overlay synthetic lettering after native RLE while preserving picture files.

The publisher's original proper-name logo is kept as bitmap art; its translated
presentation credit is drawn separately. All other catalog content is present
in bounded overlay-owned NUL-separated lines with explicit layout metadata.
"""

from .common import BUILD, ROOT, read_json, sha256, write_json
from .library import assemble
from .renderers import word, branch


def half_width(width):
    columns, remainder = divmod(width, 7)
    return (columns//2)*7 + remainder//2 + (4 if columns%2 else 0)


def build(nbytes, rbytes, encoding, entries, *, synthetic=True):
    directory = BUILD / ("synthetic" if synthetic else "approved") / "captions"
    directory.mkdir(parents=True, exist_ok=True)
    display = encoding.synthetic if synthetic else lambda value: value
    native = {module: read_json(BUILD / f"maps/{module}-symbols.json") for module in ("N","R")}
    values = {"N_CLEAR": native["N"]["HGR_CLEAR_RECT"], "N_FILL": native["N"]["HGR_FILL_RECT"],
              "N_CENTER": native["N"]["N_MEASURE_CENTERED_NEXT_CHAR"],
              "R_CLEAR": native["R"]["R_HGR_CLEAR_RECT"], "R_FILL": native["R"]["R_HGR_FILL_RECT"],
              "R_CENTER": native["R"]["R_MEASURE_CENTERED_STRING"]}
    (directory / "caption-engine-config.inc").write_text("".join(f"{key} = ${value:04X}\n" for key,value in values.items()))
    base_library = (BUILD / "library/KL.bin").read_bytes()
    start = 0x9200+len(base_library)
    engine, symbols = assemble(ROOT / "src/korean/caption_engine.s", directory, "engine", start, 0x9700-start)

    # rect=(left, right-exclusive, top, bottom-exclusive), even horizontal edges.
    # Native clear/fill use inclusive endpoints in two-pixel units.
    groups = {
        "R0": [{"id":"bitmap.s.presents", "rect":(96,170,126,137), "white":False,
                "lines":[("suffix",140,128)], "prefix":"Broderbund SOFTWARE "}],
        "R2": [{"id":"bitmap.s.title", "rect":(0,280,8,117), "white":False,
                "lines":[(i,140,y) for i,y in enumerate((20,36,58,70,82,100))]}],
        "R3": [{"id":"bitmap.s.agency", "rect":(152,218,44,78), "white":True,
                "lines":[(0,186,49),(1,186,65)], "wrap_first_space":True}],
        "N4": [{"id":"bitmap.o."+name,"rect":(152,190,row,row+8),"white":i!=0,
                "lines":[(0,170,row)]} for i,(name,row) in enumerate(zip(
                    ("sex","hobby","hair","feature","auto","food"),(18,29,40,51,62,73)))],
        "N5": [{"id":"bitmap.p.jail","rect":(174,232,10,26),"white":True,"lines":[(0,202,14)]}]
    }
    groups["N4"].append({"id":"bitmap.o.computer","rect":(166,250,104,112),"white":True,"lines":[(0,208,104)]})
    original_d = (ROOT / "assets/po/D.bin").read_bytes()
    widths, heights = {}, {}
    for code in range(32,127):
        index=code-32;offset=original_d[index]+256*original_d[index+112]-0xB900
        widths[code]=original_d[offset]+1
        heights[code]=original_d[offset+1]
    outputs, layout, covered = {}, {}, []
    for module, base, limit in (("N",nbytes,0x9200),("R",rbytes,0x7800)):
        work = directory / module
        work.mkdir(exist_ok=True)
        mode_groups={key:items for key,items in groups.items() if key.startswith(module)}
        source, text_sources, text_lines, expected_lengths = [], [], {}, {}
        for key,items in mode_groups.items():
            source.append(f"CAP_{key}:\n")
            for item in items:
                identifier=item["id"];entry=entries[identifier]
                if entry["codec"]!="bitmap" or "<CTRL:" in entry["translation"]:
                    raise ValueError("Caption input must contain plain Unicode lines")
                text=entry["translation"]
                if item.get("wrap_first_space"):
                    if "\n" in text or not text.startswith("ACME "):
                        raise ValueError("Recheck agency layout for changed proper name/line structure")
                    lines=text.split(" ",1)
                else:
                    lines=text.split("\n")
                tag="CAP_T_"+identifier.replace(".","_")
                payload=b"".join(encoding.encode(display(line))+b"\0" for line in lines)
                if len(payload)!=len(encoding.entry(entry,synthetic=synthetic)):
                    raise ValueError("Caption line layout changed the complete encoded byte count")
                expected_lengths[identifier]=len(payload)
                text_sources.append(tag+":\n"+"".join("        .byte "+",".join(f"${b:02X}" for b in payload[i:i+16])+"\n" for i in range(0,len(payload),16)))
                left,right,top,bottom=item["rect"]
                if left%2 or right%2 or not(0<=left<right<=280 and 0<=top<bottom<=192):
                    raise ValueError("Caption rectangle outside even native coordinates")
                source.append(f"        .byte {int(item['white'])},{left//2},{(right-2)//2},{top},{bottom-1}\n")
                measured=[]
                for selected,center,row in item["lines"]:
                    if selected=="suffix":
                        prefix=item["prefix"]
                        if not text.startswith(prefix):
                            raise ValueError("Recheck preserved publisher-logo prefix before changing it")
                        value=text[len(prefix):];offset=len(prefix.encode("ascii"))
                    else:
                        if len(lines)!=len(item["lines"]):
                            raise ValueError("Caption line count differs from measured layout")
                        value=lines[selected]
                        offset=sum(len(encoding.encode(display(line)))+1 for line in lines[:selected])
                    if center%2:
                        raise ValueError("Caption center must use native two-pixel units")
                    width=sum(widths[ord(c)] if ord(c)<128 else 8 for c in value)
                    height=max((heights[ord(c)] if ord(c)<128 else 8 for c in value),default=0)
                    x=center-half_width(width)
                    if not(left<=x and x+width-1<right and top<=row and row+height<=bottom and x+width<273):
                        raise ValueError(f"Caption {identifier} exceeds its verified rectangle: {x=},{width=},{row=}")
                    pointer=tag+f"+{offset}"
                    source.append(f"        .byte 2,{center//2},{row},<({pointer}),>({pointer})\n")
                    measured.append({"text":display(value),"left":x,"top":row,"advance_width":width,"height":height,"pointer_offset":offset})
                layout[identifier]={"group":key,"rectangle":list(item["rect"]),"white_background":item["white"],
                                    "lines":measured,"preserved_bitmap_prefix":item.get("prefix"),"stored_bytes":len(payload)}
                text_lines[identifier]=[display(line) for line in lines]
                covered.append(identifier)
            source.append("        .byte $FF\n")
        (work / "caption-data.inc").write_text("".join(source+text_sources))
        config={"MODE_N":int(module=="N"),"K_CAPTION_DRAW":symbols["K_CAPTION_DRAW"],
                "IMAGE_ENTRY":native[module]["HGR_RLE_DRAW_N" if module=="N" else "HGR_RLE_DRAW"]}
        if module=="N":config["N_TABLE_STRIDE"]=native["N"]["N_RLE_USE_TABLE_STRIDE"]
        (work / "caption-hooks-config.inc").write_text("".join(f"{key} = ${value:04X}\n" for key,value in config.items()))
        extension, hook_symbols = assemble(ROOT / "src/korean/caption_hooks.s",work,"hooks",0x6000+len(base),limit-0x6000-len(base))
        patched=bytearray(base+extension)
        site=config["IMAGE_ENTRY"]-0x6000
        expected=(b"\xC0\x00"+branch(0xD0,config["IMAGE_ENTRY"]+2,config["N_TABLE_STRIDE"])) if module=="N" else b"\x86\xCC\x84\xCD"
        if patched[site:site+4]!=expected:
            raise ValueError("Caption entry patch overlaps an unexpected instruction span")
        patched[site:site+4]=b"\x4C"+word(hook_symbols["K_IMAGE_HOOK"])+b"\xEA"
        outputs[module]=bytes(patched)
        outputs[module+"_metadata"]={"extension_bytes":len(extension),"hook":hook_symbols["K_IMAGE_HOOK"],
            "entry":config["IMAGE_ENTRY"],"original_hex":expected.hex(),"patched_hex":patched[site:site+4].hex(),
            "command_pointers":{key:hook_symbols["CAP_"+key] for key in mode_groups},
            "mutable_addresses":[hook_symbols[name] for name in ("K_IMAGE_INDEX",) if name in hook_symbols] +
                [hook_symbols[name] for name in ("K_IMAGE_LO","K_IMAGE_HI") if name in hook_symbols],
            "strings":text_lines,"stored_entry_bytes":expected_lengths}
    mutable=[]
    for label in ("K_CAPTION_READ","K_CAPTION_CLEAR_CALL","K_CAPTION_FILL_CALL","K_CAPTION_CENTER_CALL"):
        mutable.extend((symbols[label]+1,symbols[label]+2))
    manifest={"address":start,"bytes":len(engine),"sha256":sha256(engine),
              "entry":symbols["K_CAPTION_DRAW"],"end_exclusive":start+len(engine),
              "base_library_bytes":len(base_library),"base_library_sha256":sha256(base_library),
              "symbols":{key:value for key,value in symbols.items() if key.startswith("K_CAPTION_")},
              "mutable_operands":mutable,"mutable_data_start":symbols["K_CAPTION_MUTABLE"],
              "layout":layout,"covered_entries":covered,"modules":{key:outputs[key+"_metadata"] for key in ("N","R")},
              "format":"commands: 0/1,left/2,(right-exclusive-2)/2,top,bottom-inclusive; 2,center/2,row,ptrlo,ptrhi; FF end",
              "status":("synthetic caption compiler; native image/ABI and lifecycle verification required" if synthetic else
                        "approved caption compiler; actual-translation runtime verification required")}
    outputs["KL"]=base_library+engine
    outputs["manifest"]=manifest
    write_json(directory / "manifest.json",manifest)
    return outputs
