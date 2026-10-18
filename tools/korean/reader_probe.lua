-- Native C/N byte-copy tests inside the disk-booted synthetic game.
local json=require('json')
local k=assert(_G.carmen_korean_runtime)
local mode=_G.carmen_korean_mode or 'synthetic'
assert(mode=='synthetic' or mode=='approved','unknown runtime mode')
local state={}
local function file(path)
    local f=assert(io.open(path,'rb'));local b=f:read('a');f:close();return b
end
local directory=k.root..'/build/korean/'..mode..'/reader-probe/'
local manifest=json.parse(file(directory..'manifest.json'))
local function space() return manager.machine.devices[':maincpu'].spaces.program end
local function normal()
    local s=space();s:write_u8(0xC002,0);s:write_u8(0xC004,0)
    s:read_u8(0xC083);s:read_u8(0xC083)
end
local function select(bank)
    normal()
    if bank=='aux' then space():write_u8(0xC003,0);space():write_u8(0xC005,0) end
end
local function read(address,count)
    local b={};for i=0,count-1 do b[#b+1]=string.char(space():read_u8(address+i)) end
    return table.concat(b)
end
local function write(address,bytes)
    for i=1,#bytes do space():write_u8(address+i-1,bytes:byte(i)) end
    assert(read(address,#bytes)==bytes,'native reader setup/restore failed')
end
local function save(bank,address,count)
    select(bank);return {bank=bank,address=address,bytes=read(address,count)}
end
function a2.korean_reader_start(index)
    assert(not state.saved,'finish the active reader probe')
    assert(a2.status().debugger=='stop','instruction boundary required')
    local probe=assert(manifest.probes[index])
    local saved={probe=probe,cpu=a2.registers(),regions={save('main',0,512),save('main',0x0800,1024),
        save('main',0x0E00,0x1200),save('main',0xA000,0x710),save('aux',0x5000,4096)}}
    state.saved=saved
    select('main');write(0xA000,string.rep(string.char(0xA5),0x710))
    write(0xA000,string.rep('P',probe.prefix))
    select(probe.mode=='C' and 'aux' or 'main')
    write(probe.source_address,file(directory..probe.name..'-source.bin'))
    select('main');write(0x0800,file(directory..probe.name..'.bin'))
    saved.breakpoint=a2.breakpoint(probe.symbols.PROBE_DONE).id
    a2.set_register('PC',probe.symbols.PROBE_ENTRY)
    return {name=probe.name,done=probe.symbols.PROBE_DONE}
end
function a2.korean_reader_finish()
    local saved=assert(state.saved);local p=saved.probe
    assert(a2.status().debugger=='stop' and a2.registers().PC==p.symbols.PROBE_DONE,'reader completion breakpoint required')
    normal()
    local expected=file(directory..p.name..'-expected.bin')
    local actual=read(0xA000,#expected)
    local pointer=p.mode=='N' and 0xC4 or 0xCE
    local source=space():read_u8(pointer)+256*space():read_u8(pointer+1)
    local cursor=space():read_u8(0xAC)+256*space():read_u8(0xDB)
    local result={name=p.name,output_matches=actual==expected,output_bytes=#actual,
        source_at_nul=source,expected_source_at_nul=p.source_pointer_at_nul,
        cursor_at_nul=cursor,expected_cursor_at_nul=0xA000+#expected-1,
        tail_canary_unchanged=read(0xA000+#expected,0x710-#expected)==string.rep(string.char(0xA5),0x710-#expected),
        saved_cpu=saved.cpu,stopped_cpu=a2.registers()}
    local f=assert(io.open(k.work..'/reader-'..p.name..'-output.bin','wb'));f:write(actual);f:close()
    for _,region in ipairs(saved.regions) do select(region.bank);write(region.address,region.bytes) end
    normal();a2.clear_breakpoint(saved.breakpoint)
    for _,name in ipairs({'A','X','Y','SP','P','PC'}) do a2.set_register(name,saved.cpu[name]) end
    result.restored_cpu=a2.registers();state.saved=nil
    local f=assert(io.open(k.work..'/reader-'..p.name..'.json','wb'));f:write(json.stringify(result));f:write('\n');f:close()
    assert(result.output_matches and result.tail_canary_unchanged,'native reader lost/changed bytes or exceeded its output')
    assert(source==result.expected_source_at_nul and cursor==result.expected_cursor_at_nul,'native reader source/cursor differs')
    return result
end
return {loaded=true,probes=#manifest.probes}
