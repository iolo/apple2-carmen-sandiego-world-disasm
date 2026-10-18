-- Native before/after comparison of the caption hook at both HGR pages.
-- Baseline removes only its four-byte entry patch. Each trial starts from
-- identical borrowed RAM, and all caller/module/display state is restored.
local json=require('json')
local k=assert(_G.carmen_korean_runtime)
local mode=_G.carmen_korean_mode or 'synthetic'
assert(mode=='synthetic' or mode=='approved','unknown runtime mode')
local dir=k.root..'/build/korean/'..mode..'/caption-probe/'
local function file(path) local f=assert(io.open(path,'rb'));local b=f:read('a');f:close();return b end
local fixture=json.parse(file(dir..'manifest.json'))
local captions=json.parse(file(k.root..'/build/korean/'..mode..'/captions/manifest.json'))
local state={}
local function space() return manager.machine.devices[':maincpu'].spaces.program end
local function read(address,count)
    local b={};for i=0,count-1 do b[#b+1]=string.char(space():read_u8(address+i)) end;return table.concat(b)
end
local function write(address,b)
    for i=1,#b do space():write_u8(address+i-1,b:byte(i)) end
    assert(read(address,#b)==b,'caption trial setup/restore differs')
end
local function normal()
    space():write_u8(0xC002,0);space():write_u8(0xC004,0)
    space():read_u8(0xC083);space():read_u8(0xC083)
end
local function unhex(value)
    return value:gsub('..',function(b)return string.char(tonumber(b,16))end)
end
function a2.korean_caption_start(index,baseline)
    assert(not state.saved and a2.status().debugger=='stop')
    local probe=assert(fixture.probes[index])
    local saved={probe=probe,baseline=baseline,cpu=a2.registers(),
        page2=(space():read_u8(0xC01C)&0x80)~=0,regions={}}
    normal()
    for _,r in ipairs({{0,512},{0x0800,1024},{0x1100,0xD00},{0x2000,0x7800},{0xA700,0xB00}}) do
        saved.regions[#saved.regions+1]={address=r[1],bytes=read(r[1],r[2])}
    end
    state.saved=saved
    write(0x6000,file(k.root..'/build/korean/'..mode..'/text/'..probe.module..'.bin'))
    if probe.module=='R' then write(0x7800,file(k.root..'/assets/po/S.bin')) end
    write(0xA700,file(k.root..'/assets/po/O.bin'))
    write(0x1100,file(k.root..'/assets/po/P.bin'))
    if baseline then
        local patch=captions.modules[probe.module]
        write(patch.entry,unhex(patch.original_hex))
    end
    write(0x0800,file(dir..probe.name..'.bin'))
    saved.point=a2.breakpoint(probe.symbols.PROBE_DONE).id
    a2.set_register('PC',probe.symbols.PROBE_ENTRY)
    return {done=probe.symbols.PROBE_DONE}
end
function a2.korean_caption_finish()
    local saved=assert(state.saved);local p=saved.probe
    assert(a2.status().debugger=='stop' and a2.registers().PC==p.symbols.PROBE_DONE)
    normal()
    local name=p.name..(saved.baseline and '-baseline' or '-caption')
    local page=read(p.page==1 and 0x2000 or 0x4000,8192)
    local zp=read(0,256)
    for suffix,b in pairs({hgr=page,zp=zp}) do
        local f=assert(io.open(k.work..'/'..name..'.'..suffix,'wb'));f:write(b);f:close()
    end
    local result={name=name,module=p.module,image=p.image,page=p.page,
        baseline=saved.baseline,stopped_cpu=a2.registers(),saved_cpu=saved.cpu}
    for _,r in ipairs(saved.regions) do write(r.address,r.bytes) end
    space():read_u8(saved.page2 and 0xC055 or 0xC054)
    a2.clear_breakpoint(saved.point)
    for _,n in ipairs({'A','X','Y','SP','P','PC'}) do a2.set_register(n,saved.cpu[n]) end
    result.restored_cpu=a2.registers();state.saved=nil
    return result
end
return {loaded=true,probes=#fixture.probes}
