-- Owned MAME session helpers for K0. Load after a2-mame/control.lua.
-- Calls are synchronous while paused except a2.go, which schedules execution.
local json = require('json')
local k0 = _G.carmen_korean_runtime or {saved=nil}
_G.carmen_korean_runtime = k0
local function read_json(path)
    local f = assert(io.open(path, 'rb')); local data = f:read('a'); f:close()
    return assert(json.parse(data))
end
local function write_json(path, data)
    local f = assert(io.open(path, 'wb')); f:write(json.stringify(data)); f:write('\n'); f:close()
end
local function equal(a, b)
    if #a ~= #b then return false end
    for i=1,#a do if a[i] ~= b[i] then return false end end
    return true
end

function a2.korean_attach(root, work)
    assert(a2.status().driver == 'apple2e', '128K apple2e profile required')
    if root == '.' then root = assert(os.getenv('PWD')) end
    if work:sub(1,1) ~= '/' then work = root .. '/' .. work end
    k0.root, k0.work = root, work
    -- The historical K0 proxy fixture is optional for normal mailbox and
    -- synthetic-disk sessions. A clean synthetic build need not create it.
    local probe_path=root .. '/build/korean/probe/manifest.json'
    local probe_file=io.open(probe_path,'rb')
    if probe_file then probe_file:close();k0.manifest=read_json(probe_path)
    else k0.manifest=nil end
    k0.symbols = {N=read_json(root .. '/build/korean/maps/N-symbols.json'),
                  R=read_json(root .. '/build/korean/maps/R-symbols.json')}
    return {root=root, work=work, status=a2.status()}
end

function a2.korean_checkpoint(name)
    assert(name:match('^[a-z0-9_-]+$'), 'safe checkpoint name required')
    local cpu = a2.registers()
    local space = manager.machine.devices[':maincpu'].spaces.program
    -- Read-only IIe soft-switch status addresses, not their write triggers.
    local switches = {}
    for name,address in pairs({LCBANK2=0xC011,LCRAM=0xC012,RAMRD=0xC013,
          RAMWRT=0xC014,ALTZP=0xC016,STORE80=0xC018,PAGE2=0xC01C,HIRES=0xC01D}) do
        switches[name] = (space:read_u8(address) & 0x80) ~= 0
    end
    local record = {name=name, status=a2.status(), cpu=cpu, mapping=switches,
                    case_state=a2.read(0,33).bytes, menu_state=a2.read(0x64,16).bytes,
                    last_key=a2.read(0x76,1).bytes[1], source='CPU-visible memory with mapping recorded'}
    write_json(k0.work .. '/' .. name .. '.json', record)
    a2.screenshot(k0.work .. '/' .. name .. '.png')
    return record
end

function a2.korean_probe_start(module)
    assert(module == 'N' or module == 'R', 'choose N or R')
    assert(not k0.saved, 'previous probe must be finished first')
    assert(a2.status().debugger == 'stop', 'register edits require a debugger instruction-boundary stop')
    local manifest=assert(k0.manifest,'run make korean-probe before using the historical K0 RAM fixture')
    local probe = assert(manifest.probes[module])
    k0.saved = {module=module, cpu=a2.registers(), zp=a2.read(0,256).bytes,
        pointers={a2.read(0xB95E,2).bytes,a2.read(0xB9CE,2).bytes},
        scratch=a2.read(0x9200,1536).bytes}
    a2.load_binary(k0.root .. '/' .. probe.path, k0.manifest.load_address)
    k0.saved.breakpoint = a2.breakpoint(probe.done).id
    a2.set_register('PC', k0.manifest.load_address)
    return {module=module, bytes=probe.bytes, entry=k0.manifest.load_address,
             done=probe.done, breakpoint=k0.saved.breakpoint, cpu=a2.registers()}
end

function a2.korean_probe_finish()
    local saved = assert(k0.saved, 'no active probe')
    local probe = k0.manifest.probes[saved.module]
    assert(a2.status().debugger == 'stop', 'arm probe stop and go before restoring CPU registers')
    assert(a2.registers().PC == probe.done, 'probe has not reached its completion breakpoint')
    assert(equal(a2.read(0xB95E,2).bytes, saved.pointers[1]), 'font low pointers not restored')
    assert(equal(a2.read(0xB9CE,2).bytes, saved.pointers[2]), 'font high pointers not restored')
    local result = {module=saved.module, probe=probe, stopped=a2.registers(), font_pointers_restored=true,
                    cursor={column=a2.read(0x70,1).bytes[1], bit=a2.read(0x71,1).bytes[1],
                            row=a2.read(0x72,1).bytes[1]}}
    a2.screenshot(k0.work .. '/probe-' .. saved.module .. '.png')
    -- Also archive exact HGR bytes; a paused screen may precede the last frame.
    local f = assert(io.open(k0.work .. '/probe-' .. saved.module .. '.hgr', 'wb'))
    for start=0x2000,0x3FFF,1024 do
        local bytes = a2.read(start,1024).bytes
        for _,value in ipairs(bytes) do f:write(string.char(value)) end
    end
    f:close()
    if saved.breakpoint then a2.clear_breakpoint(saved.breakpoint) end
    a2.write(0, saved.zp)
    a2.write(0x9200, saved.scratch)
    for _,name in ipairs({'A','X','Y','SP','P','PC'}) do a2.set_register(name, saved.cpu[name]) end
    result.cpu_restored = a2.registers()
    write_json(k0.work .. '/probe-' .. saved.module .. '.json', result)
    k0.saved=nil
    return result
end

function a2.korean_probe_stop()
    local saved = assert(k0.saved, 'no active probe')
    local probe = k0.manifest.probes[saved.module]
    assert(not saved.breakpoint, 'probe completion breakpoint is already armed')
    -- An ordinary pause may stop the 6502 microcode between bus cycles.
    -- Re-arm the self-JMP address and run to a real instruction boundary
    -- before modifying PC, P or SP. Do not infer this from PC alone.
    saved.breakpoint=a2.breakpoint(probe.done).id
    return {breakpoint=saved.breakpoint, done=probe.done, scheduled=a2.go()}
end

function a2.korean_probe_present()
    local saved = assert(k0.saved, 'no active probe')
    local probe = k0.manifest.probes[saved.module]
    assert(a2.registers().PC == probe.done, 'probe not complete')
    a2.clear_breakpoint(assert(saved.breakpoint))
    saved.breakpoint=nil
    -- Run the probe's self-JMP so the video device can render a complete frame.
    -- Call pause, probe_stop, then finish; never change PC at an ordinary pause.
    local before = a2.status().time
    local scheduled = a2.go()
    return {scheduled=scheduled, emulated_time_before=before}
end

function a2.korean_inputs(all)
    local result = {}
    for tag,port in pairs(manager.machine.ioport.ports) do
        for name,field in pairs(port.fields) do
            if all or name:lower():find('apple') or name:lower():find('button')
               or name:lower():find('left') or name:lower():find('right')
               or name:lower():find('up') or name:lower():find('down') then
                result[#result+1] = {port=tag,name=name}
            end
        end
    end
    return result
end

function a2.korean_fast_text(held)
    local port = assert(manager.machine.ioport.ports[':keyb_special'])
    local field = assert(port.fields['Open Apple'])
    if held then field:set_value(1) else field:clear_value() end
    return {open_apple_held=held, note='Release before resuming city-menu input'}
end

function a2.korean_press(portname, name)
    assert(not k0.pulse, 'previous key pulse is still active')
    local field = assert(assert(manager.machine.ioport.ports[portname]).fields[name])
    k0.pulse = {field=field, frames=0}
    field:set_value(1)
    if not k0.key_listener_installed then
        emu.register_frame_done(function()
            local pulse = k0.pulse
            if not pulse then return end
            pulse.frames=pulse.frames+1
            if pulse.frames >= 4 then
                pulse.field:clear_value()
                k0.pulse=nil
            end
        end)
        k0.key_listener_installed=true
    end
    return {port=portname, name=name, scheduled_release_after_frames=4}
end

function a2.korean_release_keys()
    if k0.pulse then
        k0.pulse.field:clear_value()
        k0.pulse.frames=4
        k0.pulse=nil
    end
    return {released=true}
end

function a2.korean_memory_survey(name)
    assert(name:match('^[a-z0-9_-]+$'))
    a2.registers() -- require a stable CPU before changing the read mapping
    local space = manager.machine.devices[':maincpu'].spaces.program
    local was_aux = (space:read_u8(0xC013) & 0x80) ~= 0
    local function dump(path, first, last)
        local f = assert(io.open(path,'wb'))
        for address=first,last do f:write(string.char(space:read_u8(address))) end
        f:close()
    end
    -- Host Lua executes while the CPU is stopped; no instruction fetch occurs
    -- under this temporary RAMRD mapping. RAMWRT and ALTZP are left alone.
    space:write_u8(0xC002,0)
    dump(k0.work..'/'..name..'-main.bin',0x0200,0xBFFF)
    space:write_u8(0xC003,0)
    dump(k0.work..'/'..name..'-aux.bin',0x0200,0xBFFF)
    space:write_u8(was_aux and 0xC003 or 0xC002,0)
    assert(((space:read_u8(0xC013) & 0x80) ~= 0) == was_aux, 'RAMRD restore failed')
    dump(k0.work..'/'..name..'-active-lc.bin',0xD000,0xFFFF)
    local result = a2.korean_checkpoint(name)
    result.dump_ranges = {main={first=0x0200,last=0xBFFF},aux={first=0x0200,last=0xBFFF},
                          active_lc={first=0xD000,last=0xFFFF}}
    result.ramrd_restored=true
    write_json(k0.work..'/'..name..'.json',result)
    return result
end

return k0
