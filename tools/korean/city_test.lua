-- Exercise the actual ProDOS B/S2 reader for all rebuilt city records.
local json=require('json')
local k=assert(_G.carmen_korean_runtime)
local mode=_G.carmen_korean_mode or 'synthetic'
assert(mode=='synthetic' or mode=='approved','unknown runtime mode')
local dir=k.root..'/build/korean/'..mode..'/city-probe/'
local function file(path)local f=assert(io.open(path,'rb'));local b=f:read('a');f:close();return b end
local fixture=json.parse(file(dir..'manifest.json'))
local state={}
local function space()return manager.machine.devices[':maincpu'].spaces.program end
local function read(a,n)local b={};for i=0,n-1 do b[#b+1]=string.char(space():read_u8(a+i)) end;return table.concat(b)end
local function write(a,b)for i=1,#b do space():write_u8(a+i-1,b:byte(i)) end;assert(read(a,#b)==b)end
local function normal()
    space():write_u8(0xC002,0);space():write_u8(0xC004,0);space():write_u8(0xC009,0)
    space():read_u8(0xC083);space():read_u8(0xC083)
end
function a2.korean_city_start(index)
    assert(not state.saved and a2.status().debugger=='stop')
    normal();local p=assert(fixture.probes[index])
    local saved={probe=p,cpu=a2.registers(),regions={}}
    for _,r in ipairs({{0,512},{0x0800,1024},{0x1100,0xD00},{0x9100,0x100},{0x9800,0x600},{0xA000,0x710}}) do
        saved.regions[#saved.regions+1]={address=r[1],bytes=read(r[1],r[2])}
    end
    space():write_u8(0xC008,0);saved.main_zp=read(0,512);normal()
    state.saved=saved
    write(0xA000,string.rep(string.char(0xA5),0x710))
    write(0x1100,string.rep(string.char(0xA5),0xC00))
    write(0x9100,file(dir..p.name..'.bin'))
    saved.point=a2.breakpoint(p.symbols.PROBE_DONE).id
    a2.set_register('PC',p.symbols.PROBE_ENTRY)
    return {done=p.symbols.PROBE_DONE}
end
function a2.korean_city_finish()
    local saved=assert(state.saved);local p=saved.probe
    assert(a2.status().debugger=='stop' and a2.registers().PC==p.symbols.PROBE_DONE)
    local result={name=p.name,city=p.city,mode=p.mode,cpu=a2.registers(),saved_cpu=saved.cpu}
    normal()
    local text=file(dir..p.name..'-text.bin')
    result.text_matches=read(0xA000,#text)==text
    result.text_tail_unchanged=read(0xA000+#text,0x710-#text)==string.rep(string.char(0xA5),0x710-#text)
    if p.mode=='record' then
        local picture=file(dir..p.name..'-picture.bin')
        result.picture_matches=read(0x1100,#picture)==picture
        result.picture_terminator=space():read_u8(0x1100+#picture)
        result.picture_tail_unchanged=read(0x1101+#picture,0xC00-#picture-1)==string.rep(string.char(0xA5),0xC00-#picture-1)
    else result.picture_buffer_unchanged=read(0x1100,0xC00)==string.rep(string.char(0xA5),0xC00) end
    for _,r in ipairs(saved.regions) do write(r.address,r.bytes) end
    space():write_u8(0xC008,0);write(0,saved.main_zp);normal()
    a2.clear_breakpoint(saved.point)
    for _,n in ipairs({'A','X','Y','SP','P','PC'}) do a2.set_register(n,saved.cpu[n]) end
    result.restored_cpu=a2.registers();state.saved=nil
    return result
end
return {loaded=true,probes=#fixture.probes}
