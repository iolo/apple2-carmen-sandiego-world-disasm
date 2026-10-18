-- Borrow and restore RAM for native clock geometry/pixel checks.
local json=require('json')
local k=assert(_G.carmen_korean_runtime)
local mode=_G.carmen_korean_mode or 'synthetic'
assert(mode=='synthetic' or mode=='approved','unknown runtime mode')
local function file(path) local f=assert(io.open(path,'rb'));local b=f:read('a');f:close();return b end
local dir=k.root..'/build/korean/'..mode..'/clock-probe/'
local fixture=json.parse(file(dir..'manifest.json'))
local state={}
local function space() return manager.machine.devices[':maincpu'].spaces.program end
local function read(address,count)
    local b={};for i=0,count-1 do b[#b+1]=string.char(space():read_u8(address+i)) end;return table.concat(b)
end
local function write(address,b)
    for i=1,#b do space():write_u8(address+i-1,b:byte(i)) end
    assert(read(address,#b)==b,'clock borrowed RAM restore differs')
end
function a2.korean_clock_start(day,hour)
    assert(not state.saved and a2.status().debugger=='stop')
    assert(day>=0 and day<7 and day==math.floor(day) and hour>=0 and hour<24 and hour==math.floor(hour))
    local saved={cpu=a2.registers(),day=day,hour=hour,
        page2=(space():read_u8(0xC01C)&0x80)~=0,regions={}}
    for _,r in ipairs({{0,512},{0x0800,1024},{0x2000,8192},{0x6000,0x3200}}) do
        saved.regions[#saved.regions+1]={address=r[1],bytes=read(r[1],r[2])}
    end
    state.saved=saved
    write(0x0800,file(dir..'clock.bin'))
    space():write_u8(fixture.symbols.CLOCK_INITIAL,state.last and 0 or 1)
    if state.last then write(0x2000,state.last) end
    space():write_u8(fixture.symbols.CLOCK_DAY,day);space():write_u8(fixture.symbols.CLOCK_HOUR,hour)
    saved.point=a2.breakpoint(fixture.symbols.PROBE_DONE).id
    a2.set_register('PC',fixture.symbols.PROBE_ENTRY)
    return {done=fixture.symbols.PROBE_DONE}
end
function a2.korean_clock_finish()
    local saved=assert(state.saved)
    assert(a2.status().debugger=='stop' and a2.registers().PC==fixture.symbols.PROBE_DONE)
    local name=string.format('clock-%d-%02d',saved.day,saved.hour)
    state.last=read(0x2000,8192)
    local f=assert(io.open(k.work..'/'..name..'.hgr','wb'));f:write(state.last);f:close()
    for _,r in ipairs(saved.regions) do write(r.address,r.bytes) end
    space():read_u8(saved.page2 and 0xC055 or 0xC054)
    a2.clear_breakpoint(saved.point)
    for _,n in ipairs({'A','X','Y','SP','P','PC'}) do a2.set_register(n,saved.cpu[n]) end
    local result={name=name,day=saved.day,hour=saved.hour,saved_cpu=saved.cpu,restored_cpu=a2.registers()}
    state.saved=nil;return result
end
return {loaded=true}
