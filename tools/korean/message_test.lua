-- Render synthetic message extrema through the actual narrow typewriter.
local json=require('json')
local k=assert(_G.carmen_korean_runtime)
local mode=_G.carmen_korean_mode or 'synthetic'
assert(mode=='synthetic' or mode=='approved','unknown runtime mode')
local function file(path)local f=assert(io.open(path,'rb'));local b=f:read('a');f:close();return b end
local dir=k.root..'/build/korean/'..mode..'/message-probe/'
local fixture=json.parse(file(dir..'manifest.json'))
local library=json.parse(file(k.root..'/build/korean/library/manifest.json'))
local renderers=json.parse(file(k.root..'/build/korean/renderers/manifest.json'))
local state={}
local function space()return manager.machine.devices[':maincpu'].spaces.program end
local function read(a,n)local b={};for i=0,n-1 do b[#b+1]=string.char(space():read_u8(a+i)) end;return table.concat(b)end
local function write(a,b)for i=1,#b do space():write_u8(a+i-1,b:byte(i)) end;assert(read(a,#b)==b)end
local function normal()
    space():write_u8(0xC002,0);space():write_u8(0xC004,0)
    space():read_u8(0xC083);space():read_u8(0xC083)
end
function a2.korean_message_start(index)
    assert(not state.saved and a2.status().debugger=='stop')
    normal();local p=assert(fixture.probes[index])
    local saved={probe=p,cpu=a2.registers(),regions={},trace={},scrolls=0,last_page=1,
        page2=(space():read_u8(0xC01C)&0x80)~=0}
    for _,r in ipairs({{0,512},{0x0800,1024},{0x2000,0x7800},{0xA000,0x710}}) do
        saved.regions[#saved.regions+1]={address=r[1],bytes=read(r[1],r[2])}
    end
    state.saved=saved
    write(0x6000,file(k.root..'/build/korean/'..mode..'/text/N.bin'))
    write(0xA000,string.rep(string.char(0xA5),0x710))
    write(0xA0FD,file(dir..p.name..'.bin'))
    write(0x0800,file(dir..'probe.bin'))
    space():write_u8(0x74,1);space():read_u8(0xC010)
    local address=library.symbols.K_PENDING
    local return_address=renderers.modules.N.hooks.HOOK_DRAW+2
    saved.tap=space():install_write_tap(address,address,'message-glyphs',function(offset,data)
        if data~=0 or manager.machine:side_effects_disabled() then return end
        local cpu=manager.machine.devices[':maincpu'];local sp=cpu.state.SP.value&255
        local caller=space():read_u8(0x100+((sp+2)&255))+256*space():read_u8(0x100+((sp+3)&255))
        if caller~=return_address then return end
        local source=space():read_u8(0xC2)+256*space():read_u8(0xC3)
        local first=space():read_u8(source);local item
        if first>=0x90 and first<0xFF then
            item={kind='glyph',id=(first-0x90)*90+space():read_u8(0xD900+space():read_u8(source+1))}
        else item={kind='native',code=first} end
        saved.trace[#saved.trace+1]=item
    end)
    saved.scrolltap=space():install_write_tap(0x74,0x74,'message-scrolls',function(address,data)
        if manager.machine:side_effects_disabled() or data==saved.last_page then return end
        saved.scrolls=saved.scrolls+1;saved.last_page=data
    end)
    saved.point=a2.breakpoint(fixture.symbols.PROBE_DONE).id
    a2.set_register('PC',fixture.symbols.PROBE_ENTRY)
    return {done=fixture.symbols.PROBE_DONE}
end
function a2.korean_message_finish()
    local saved=assert(state.saved);local p=saved.probe
    assert(a2.status().debugger=='stop' and a2.registers().PC==fixture.symbols.PROBE_DONE)
    saved.tap:remove();saved.scrolltap:remove();normal()
    local result={name=p.name,scrolls=saved.scrolls,glyph_trace=saved.trace,cpu=a2.registers(),
        source_at_nul=space():read_u8(0xC2)+256*space():read_u8(0xC3),
        decoder_error=space():read_u8(library.symbols.K_ERROR),
        break_flag=space():read_u8(library.symbols.K_HARD_BREAK),
        cursor={column=space():read_u8(0x70),bit=space():read_u8(0x71),row=space():read_u8(0x72)}}
    local payload=file(dir..p.name..'.bin')
    result.source_unchanged=read(0xA0FD,#payload)==payload
    result.buffer_tail_unchanged=read(0xA0FD+#payload,0xA710-0xA0FD-#payload)==string.rep(string.char(0xA5),0xA710-0xA0FD-#payload)
    for _,page in ipairs({1,2}) do
        local f=assert(io.open(k.work..'/message-'..p.name..'-page'..page..'.hgr','wb'))
        f:write(read(page==1 and 0x2000 or 0x4000,8192));f:close()
    end
    for _,r in ipairs(saved.regions) do write(r.address,r.bytes) end
    space():read_u8(saved.page2 and 0xC055 or 0xC054)
    a2.clear_breakpoint(saved.point)
    for _,name in ipairs({'A','X','Y','SP','P','PC'}) do a2.set_register(name,saved.cpu[name]) end
    result.saved_cpu=saved.cpu;result.restored_cpu=a2.registers();state.saved=nil
    local f=assert(io.open(k.work..'/message-'..p.name..'.json','wb'));f:write(json.stringify(result));f:write('\n');f:close()
    return result
end
return {loaded=true,probes=#fixture.probes}
