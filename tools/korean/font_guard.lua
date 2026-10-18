-- Full-size font residency experiment on an owned disposable English machine.
-- This does not install a renderer or any draft translation strings.
local json = require('json')
local k = assert(_G.carmen_korean_runtime, 'load start.lua first')
local function space() return manager.machine.devices[':maincpu'].spaces.program end
local function high(address) return (space():read_u8(address) & 0x80) ~= 0 end
local function restore_map()
    local s=space()
    s:write_u8(0xC002,0); s:write_u8(0xC004,0)
    s:read_u8(0xC083); s:read_u8(0xC083)
end
local function select_region(region)
    local s=space()
    restore_map()
    if region.bank == 'aux-lc1' then
        s:read_u8(0xC08B); s:read_u8(0xC08B)
    elseif region.bank == 'aux' then
        s:write_u8(0xC003,0); s:write_u8(0xC005,0)
    end
end
local function read_region(region)
    select_region(region)
    local bytes={}
    for i=0,#region.expected-1 do bytes[#bytes+1]=string.char(space():read_u8(region.address+i)) end
    return table.concat(bytes)
end
local function write_region(region, bytes)
    select_region(region)
    for i=1,#bytes do space():write_u8(region.address+i-1,bytes:byte(i)) end
end
local function mapped(region, operation)
    if region.bank == 'main' then
        return not high(operation=='read' and 0xC013 or 0xC014)
    elseif region.bank == 'aux' then
        return high(operation=='read' and 0xC013 or 0xC014)
    else
        return high(0xC016) and high(0xC011)==(region.bank=='aux-lc2')
            and (operation=='write' or high(0xC012))
    end
end
local function record(region,operation,address,data)
    local guard=k.font_guard
    if guard.suspended or not mapped(region,operation) then return end
    if manager.machine:side_effects_disabled() then
        guard.debugger_accesses=guard.debugger_accesses+1
        if #guard.debugger_examples<8 then
            guard.debugger_examples[#guard.debugger_examples+1]={region=region.name,operation=operation,
                address=address,pc=manager.machine.devices[':maincpu'].state.PC.value}
        end
        return
    end
    guard.hits=guard.hits+1
    if #guard.examples<24 then
        guard.examples[#guard.examples+1]={region=region.name,operation=operation,address=address,data=data,
            pc=manager.machine.devices[':maincpu'].state.PC.value}
    end
end

function a2.korean_font_guard_start()
    assert(not k.font_guard, 'font guard already active')
    assert(a2.status().debugger=='stop', 'instruction-boundary stop required')
    assert(not high(0xC013) and not high(0xC014) and high(0xC016)
        and high(0xC011) and high(0xC012) and not high(0xC018), 'unexpected game mapping')
    local f=assert(io.open(k.root..'/build/korean/draft-fixtures/KF.bin','rb'))
    local font=f:read('a'); f:close()
    assert(#font>4096 and #font<=10496, 'font size outside proposed split')
    local pattern={}
    for i=0,1535 do pattern[#pattern+1]=string.char((i*73+41)%256) end
    local guard={suspended=true,hits=0,examples={},debugger_accesses=0,debugger_examples={},taps={},font_bytes=#font,
        regions={
            {name='font-first-512',bank='aux-lc1',address=0xD000,expected=font:sub(1,4096)},
            {name='font-remainder',bank='aux',address=0xA700,expected=font:sub(4097)},
            {name='lc-copy-helper',bank='aux-lc2',address=0xD100,expected=table.concat(pattern):sub(1,64)},
            {name='common-code-and-cache',bank='main',address=0x9200,expected=table.concat(pattern)}
        }}
    k.font_guard=guard
    for _,region in ipairs(guard.regions) do
        region.original=read_region(region)
        write_region(region,region.expected)
        assert(read_region(region)==region.expected, 'bank write/read-back failed: '..region.name)
    end
    restore_map()
    for _,region in ipairs(guard.regions) do
        for _,operation in ipairs({'read','write'}) do
            local callback=function(address,data) record(region,operation,address,data) end
            local tap
            if operation=='read' then
                tap=space():install_read_tap(region.address,region.address+#region.expected-1,region.name..'-read',callback)
            else
                tap=space():install_write_tap(region.address,region.address+#region.expected-1,region.name..'-write',callback)
            end
            guard.taps[#guard.taps+1]=tap
        end
    end
    -- Prove each tap sees its selected bank, rather than interpreting silence
    -- as success. Restore the original value immediately after each write.
    guard.suspended=false
    for _,region in ipairs(guard.regions) do
        select_region(region)
        local before=guard.hits
        local value=space():read_u8(region.address)
        space():write_u8(region.address,value)
        assert(guard.hits==before+2, 'read/write taps are not live: '..region.name)
    end
    restore_map()
    guard.self_test_hits=guard.hits
    guard.hits=0; guard.examples={}
    return a2.korean_font_guard_check('font-installed')
end

function a2.korean_font_guard_check(name)
    assert(name:match('^[a-z0-9_-]+$'))
    a2.registers()
    local guard=assert(k.font_guard,'no font guard')
    guard.suspended=true
    local results={}
    for _,region in ipairs(guard.regions) do
        local bytes=read_region(region)
        local f=assert(io.open(k.work..'/'..name..'-'..region.name..'.bin','wb'))
        f:write(bytes); f:close()
        results[#results+1]={name=region.name,bank=region.bank,address=region.address,
            bytes=#region.expected,identical=bytes==region.expected}
    end
    -- Recheck tap liveness after bank switches and lifecycle transitions.
    -- These intentional host accesses are counted separately from game use.
    local old_hits, old_examples=guard.hits,guard.examples
    guard.examples={}
    guard.suspended=false
    for _,region in ipairs(guard.regions) do
        select_region(region)
        local before=guard.hits
        local value=space():read_u8(region.address)
        space():write_u8(region.address,value)
        assert(guard.hits==before+2,'tap no longer live: '..region.name)
    end
    local recent_self_test_hits=guard.hits-old_hits
    guard.hits,guard.examples=old_hits,old_examples
    guard.suspended=true
    restore_map()
    guard.suspended=false
    local result={name=name,regions=results,font_bytes=guard.font_bytes,
        unexpected_accesses=guard.hits,examples=guard.examples,self_test_hits=guard.self_test_hits,
        recent_self_test_hits=recent_self_test_hits,
        debugger_accesses=guard.debugger_accesses,debugger_examples=guard.debugger_examples,
        cpu=a2.registers(),status=a2.status(),
        scope='English lifecycle with full font and helper canaries; renderer not installed'}
    local f=assert(io.open(k.work..'/'..name..'-font-guard.json','wb'))
    f:write(json.stringify(result)); f:write('\n'); f:close()
    return result
end

function a2.korean_font_guard_survey(name)
    local guard=assert(k.font_guard,'no font guard')
    guard.suspended=true
    local ok,result=pcall(a2.korean_memory_survey,name)
    guard.suspended=false
    assert(ok,result)
    return result
end

function a2.korean_font_guard_remove()
    a2.registers()
    local guard=assert(k.font_guard,'no font guard')
    guard.suspended=true
    for _,tap in ipairs(guard.taps) do tap:remove() end
    for _,region in ipairs(guard.regions) do write_region(region,region.original) end
    restore_map()
    k.font_guard=nil
    return {restored=true}
end
