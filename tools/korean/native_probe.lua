-- Instruction-boundary RAM tests of the actual 6502 decoder/font library.
-- All borrowed English-game RAM, banks and CPU registers are restored.
local json=require('json')
local k=assert(_G.carmen_korean_runtime,'load start.lua first')
local state=_G.carmen_native_probe or {}
_G.carmen_native_probe=state
local function space() return manager.machine.devices[':maincpu'].spaces.program end
local function read(address,length)
    local result={}
    for i=0,length-1 do result[#result+1]=string.char(space():read_u8(address+i)) end
    return table.concat(result)
end
local function write(address,bytes)
    for i=1,#bytes do space():write_u8(address+i-1,bytes:byte(i)) end
    assert(read(address,#bytes)==bytes,'RAM write/read-back mismatch')
end
local function file(path)
    local f=assert(io.open(path,'rb')); local data=f:read('a'); f:close(); return data
end
local function normal_map()
    space():write_u8(0xC002,0);space():write_u8(0xC004,0)
    space():read_u8(0xC083);space():read_u8(0xC083)
end
local function select(bank)
    normal_map()
    if bank=='aux' then space():write_u8(0xC003,0);space():write_u8(0xC005,0)
    elseif bank=='lc1' then space():read_u8(0xC08B);space():read_u8(0xC08B) end
end
local function save(bank,address,length)
    select(bank)
    return {bank=bank,address=address,bytes=read(address,length)}
end

function a2.korean_native_start(mode)
    assert(mode=='C2' or mode=='C6')
    assert(not state.saved,'finish the previous native probe')
    assert(a2.status().debugger=='stop','debugger instruction boundary required')
    assert((space():read_u8(0xC016)&0x80)~=0,'auxiliary zero page required')
    normal_map()
    local directory=k.root..'/build/korean/library/'
    local manifest=assert(json.parse(file(directory..'manifest.json')))
    local font=file(k.root..'/build/korean/draft-fixtures/KF.bin')
    assert(#font==manifest.font_bytes and #font>4096 and #font<10497)
    local saved={cpu=a2.registers(),mode=mode,manifest=manifest,font=font,regions={}}
    state.saved=saved
    saved.regions={save('main',0,256),save('main',0x6000,0x3800),
        save('main',0x1100,#font),save('main',0xA000,0x700),
        save('lc2',0xD900,0x1E0),save('lc2',0xD100,80),
        save('lc1',0xD000,4096),save('aux',0xA700,#font-4096+16)}
    select('lc2');saved.original_c=read(0xD200,10105)
    -- Poison every allocated font byte before the native installer runs.
    -- Bit seven is set in the poison and clear in all real seven-bit rows.
    select('lc1');write(0xD000,string.rep(string.char(0xA5),4096))
    select('aux');write(0xA700,string.rep(string.char(0xA5),#font-4096))
    select('lc2');write(0xD100,string.rep(string.char(0xA5),64))
    for name,table in pairs(manifest.lookup_tables) do write(table.address,file(directory..name..'.bin')) end
    select('main')
    write(0x6000,font)
    write(0x9200,file(directory..'KL.bin'))
    write(0xA000,file(directory..'all-glyphs.bin'))
    write(0x8F00,file(directory..'probe-'..mode..'.bin'))
    local probe=manifest.probes[mode]
    saved.breakpoint=a2.breakpoint(probe.symbols.PROBE_DONE).id
    a2.set_register('PC',probe.symbols.PROBE_ENTRY)
    return {mode=mode,entry=probe.symbols.PROBE_ENTRY,done=probe.symbols.PROBE_DONE,
        breakpoint=saved.breakpoint,font_bytes=#font}
end

function a2.korean_native_finish()
    local saved=assert(state.saved,'no native probe')
    local probe=saved.manifest.probes[saved.mode]
    assert(a2.status().debugger=='stop' and a2.registers().PC==probe.symbols.PROBE_DONE,'probe completion breakpoint required')
    normal_map()
    local pixels=read(0x1100,#saved.font)
    local source=saved.mode=='C2' and 0xC2 or 0xC6
    local pointer=space():read_u8(source)+256*space():read_u8(source+1)
    local result={mode=saved.mode,cpu=a2.registers(),font_bytes=#saved.font,
        probe_error=space():read_u8(probe.symbols.PROBE_ERROR),
        decoder_error=space():read_u8(saved.manifest.symbols.K_ERROR),
        all_font_pixels_match=pixels==saved.font,source_after_nul=pointer,
        expected_source_after_nul=0xA001+2*(#saved.font/8)}
    local f=assert(io.open(k.work..'/native-'..saved.mode..'-pixels.bin','wb'));f:write(pixels);f:close()
    select('lc1');result.native_lc_font_matches=read(0xD000,4096)==saved.font:sub(1,4096)
    select('aux');result.native_aux_font_matches=read(0xA700,#saved.font-4096)==saved.font:sub(4097)
    local tail=saved.regions[8].bytes:sub(-16)
    result.aux_tail_unchanged=read(0xA700+#saved.font-4096,16)==tail
    -- Restore all borrowed bytes before restoring the paused caller's PC.
    for _,region in ipairs(saved.regions) do select(region.bank);write(region.address,region.bytes) end
    normal_map();result.original_c_restored=read(0xD200,10105)==saved.original_c
    a2.clear_breakpoint(saved.breakpoint)
    for _,name in ipairs({'A','X','Y','SP','P','PC'}) do a2.set_register(name,saved.cpu[name]) end
    result.cpu_restored=a2.registers()
    result.saved_cpu=saved.cpu
    state.saved=nil
    local f=assert(io.open(k.work..'/native-'..saved.mode..'.json','wb'));f:write(json.stringify(result));f:write('\n');f:close()
    assert(result.probe_error==0 and result.decoder_error==0,'native ABI/control check failed')
    assert(result.all_font_pixels_match and result.native_lc_font_matches and result.native_aux_font_matches,'native font pixels differ')
    assert(result.aux_tail_unchanged and result.original_c_restored,'native probe wrote outside its data ownership')
    assert(pointer==result.expected_source_after_nul,'source pointer/terminator consumption mismatch')
    return result
end

function a2.korean_renderer_start(tag)
    assert(tag=='N' or tag=='R' or tag=='TW')
    local module=tag=='TW' and 'N' or tag
    assert(not state.saved,'finish the previous native probe')
    assert(a2.status().debugger=='stop','instruction boundary required')
    normal_map()
    local directory=k.root..'/build/korean/'
    local manifest=assert(json.parse(file(directory..'library/manifest.json')))
    local fixture=assert(json.parse(file(directory..'render-probe/manifest.json')))
    local font=file(directory..'draft-fixtures/KF.bin')
    local saved={renderer=module,tag=tag,manifest=manifest,fixture=fixture,font=font,cpu=a2.registers(),
        page2=(space():read_u8(0xC01C)&0x80)~=0}
    state.saved=saved
    saved.regions={save('main',0,256),save('main',0x6000,0x3800),
        save('main',0x2000,16384),save('main',0xA000,0x700),
        save('lc2',0xD900,0x1E0),save('lc2',0xD100,80),
        save('lc1',0xD000,4096),save('aux',0xA700,#font-4096+16)}
    select('lc2');saved.original_c=read(0xD200,10105)
    select('lc1');write(0xD000,string.rep(string.char(0xA5),4096))
    select('aux');write(0xA700,string.rep(string.char(0xA5),#font-4096))
    select('lc2');write(0xD100,string.rep(string.char(0xA5),64))
    for name,table in pairs(manifest.lookup_tables) do write(table.address,file(directory..'library/'..name..'.bin')) end
    select('main');write(0x6000,font);write(0x9200,file(directory..'library/KL.bin'))
    write(0xA000,file(directory..'render-probe/strings.bin'))
    local probe=fixture.probes[tag]
    write(probe.address,file(directory..'render-probe/'..tag..'.bin'))
    saved.breakpoint=a2.breakpoint(probe.symbols.PROBE_INITIALIZED).id
    a2.set_register('PC',probe.symbols.PROBE_ENTRY)
    return {entry=probe.symbols.PROBE_ENTRY,initialized=probe.symbols.PROBE_INITIALIZED,breakpoint=saved.breakpoint}
end

function a2.korean_renderer_install()
    local saved=assert(state.saved)
    local probe=assert(saved.fixture.probes[saved.tag])
    assert(a2.status().debugger=='stop' and a2.registers().PC==probe.symbols.PROBE_INITIALIZED,'native font installation stop required')
    a2.clear_breakpoint(saved.breakpoint)
    normal_map()
    local bytes=file(k.root..'/build/korean/renderers/'..saved.renderer..'/'..saved.renderer..'.bin')
    assert(0x6000+#bytes<=probe.address,'module overlaps probe')
    write(0x6000,bytes)
    if saved.tag=='TW' then
        local renderers=assert(json.parse(file(k.root..'/build/korean/renderers/manifest.json')))
        local return_address=renderers.modules.N.hooks.HOOK_DRAW+2
        local address=saved.manifest.symbols.K_PENDING
        saved.trace={}
        -- 6502 opcode fetches can bypass program read taps. Observe the
        -- decoder's data write and identify its drawing caller on the stack.
        -- Measurement calls have a different return address and are excluded.
        saved.tap=space():install_write_tap(address,address,'typewriter-glyph-trace',function(offset,data)
            if data~=0 or manager.machine:side_effects_disabled() then return end
            local cpu=manager.machine.devices[':maincpu']
            local sp=cpu.state.SP.value&0xFF
            local caller=space():read_u8(0x100+((sp+2)&0xFF))+256*space():read_u8(0x100+((sp+3)&0xFF))
            if caller~=return_address then return end
            local source=space():read_u8(0xC2)+256*space():read_u8(0xC3)
            local first=space():read_u8(source)
            local record
            if first>=0x90 and first<0xFF then
                local trail=space():read_u8(source+1)
                record={kind='glyph',id=(first-0x90)*90+space():read_u8(0xD900+trail)}
            else record={kind='native',code=first} end
            saved.trace[#saved.trace+1]=record
        end)
    end
    saved.breakpoint=a2.breakpoint(probe.symbols.PROBE_DONE).id
    a2.set_register('PC',probe.symbols.PROBE_RENDER)
    return {entry=probe.symbols.PROBE_RENDER,done=probe.symbols.PROBE_DONE,breakpoint=saved.breakpoint}
end

function a2.korean_renderer_present()
    local saved=assert(state.saved)
    local probe=assert(saved.fixture.probes[saved.tag])
    assert(a2.status().debugger=='stop' and a2.registers().PC==probe.symbols.PROBE_DONE,'renderer not complete')
    a2.clear_breakpoint(saved.breakpoint);saved.breakpoint=nil
    local before=a2.status().time
    return {time_before=before,scheduled=a2.go()}
end

function a2.korean_renderer_stop()
    local saved=assert(state.saved)
    local probe=assert(saved.fixture.probes[saved.tag])
    assert(not saved.breakpoint,'completion breakpoint already armed')
    saved.breakpoint=a2.breakpoint(probe.symbols.PROBE_DONE).id
    return {done=probe.symbols.PROBE_DONE,scheduled=a2.go()}
end

function a2.korean_renderer_finish()
    local saved=assert(state.saved)
    local module=saved.tag
    local probe=assert(saved.fixture.probes[module])
    assert(a2.status().debugger=='stop' and a2.registers().PC==probe.symbols.PROBE_DONE,'instruction boundary required')
    normal_map()
    local body=probe.symbols.PROBE_BODY_COLUMN
    local result={module=module,cpu=a2.registers(),
        body_cursor={column=space():read_u8(body),bit=space():read_u8(body+1),row=space():read_u8(body+2)},
        body_pointer=space():read_u8(body+3)+256*space():read_u8(body+4),
        decoder_error=space():read_u8(saved.manifest.symbols.K_ERROR),
        hard_break_flag=space():read_u8(saved.manifest.symbols.K_HARD_BREAK)}
    if saved.tap then saved.tap:remove();result.glyph_trace=saved.trace end
    local page=read(0x2000,8192)
    local f=assert(io.open(k.work..'/renderer-'..module..'.hgr','wb'));f:write(page);f:close()
    a2.screenshot(k.work..'/renderer-'..module..'.png')
    if module~='TW' then result.reference_pixels_match=page==file(k.root..'/build/korean/render-probe/expected.hgr') end
    if module=='TW' then
        local f=assert(io.open(k.work..'/renderer-TW-page2.hgr','wb'));f:write(read(0x4000,8192));f:close()
    end
    for _,region in ipairs(saved.regions) do select(region.bank);write(region.address,region.bytes) end
    normal_map();result.original_c_restored=read(0xD200,10105)==saved.original_c
    space():read_u8(saved.page2 and 0xC055 or 0xC054)
    a2.clear_breakpoint(saved.breakpoint)
    for _,name in ipairs({'A','X','Y','SP','P','PC'}) do a2.set_register(name,saved.cpu[name]) end
    result.cpu_restored=a2.registers();result.saved_cpu=saved.cpu
    state.saved=nil
    local f=assert(io.open(k.work..'/renderer-'..module..'.json','wb'));f:write(json.stringify(result));f:write('\n');f:close()
    assert(result.decoder_error==0 and result.hard_break_flag==0,'renderer left an invalid decoder/break state')
    assert(result.original_c_restored,'C services/data not restored')
    return result
end
