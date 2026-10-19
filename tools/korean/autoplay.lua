-- Memory-assisted Carmen World player for the approved Korean 800K release.
-- Launch: python3 -m tools.korean.mame --session play --autoplay --visible
-- Reads the native route/culprit; inputs are single keyboard-latch responses.
-- No RAM, CPU registers, case clocks, ranks, routes, or game code are patched.
-- See docs/korean/autoplay.md for prerequisites, limitations, and receipts.
local json = require('json')
local root = assert(os.getenv('CARMEN_MAME_ROOT'), 'use tools.korean.mame --autoplay')
local work = assert(os.getenv('CARMEN_MAME_WORK'))
local function read_json(path)
    local f = assert(io.open(path, 'rb')); local data = f:read('a'); f:close()
    return assert(json.parse(data))
end
local N = read_json(root .. '/build/korean/maps/N-symbols.json')
local R = read_json(root .. '/build/korean/maps/R-symbols.json')
local machine = manager.machine
assert(machine.system.name == 'apple2e' and machine.debugger, 'requires apple2e -debug')
local cpu = machine.devices[':maincpu']
local mem = cpu.spaces.program
local player = {active=true, phase='intro', arrests=0, cases=0, keys=0}
local name = os.getenv('CARMEN_DETECTIVE') or 'LUASLEUTH'
local limit = tonumber(os.getenv('CARMEN_CASE_LIMIT') or '30')
assert(name:match('^[A-Z]+$') and #name <= 15, 'invalid detective name')
assert(limit and limit >= 1 and limit <= 30, 'invalid case limit')
local exit_on_done = os.getenv('CARMEN_EXIT_ON_DONE') == '1'
local events = assert(io.open(work .. '/autoplay.jsonl', 'w'))
local owned, handlers = {}, {}
local pending_key, tap, menu, input, initial_solved, case_solved
local retiring, hall, name_index = false, false, 1
local last_progress = os.time()
local started = os.time()
local function byte(address) return mem:read_u8(address) end
local function state()
    return {suspect=byte(0), route_index=byte(2), city=byte(17), hideout=byte(16),
        day=byte(18), hour=byte(19), warrant=byte(23), rank=byte(91), solved=byte(92)}
end
local function record(event, extra)
    local row = {event=event, seconds=os.time()-started, emulated_seconds=machine.time:as_double(),
        case=player.cases, arrests=player.arrests, state=state(), detail=extra}
    events:write(json.stringify(row), '\n'); events:flush()
    print('CARMEN ' .. json.stringify(row))
end
local function clear_breakpoints()
    for _, id in ipairs(owned) do cpu.debug:bpclear(id) end
    owned, handlers = {}, {}
end
local function stop(reason, err)
    if not player.active then return end
    player.active, player.result, player.error = false, reason, err
    pending_key = nil
    if tap then tap:remove(); tap=nil end
    clear_breakpoints()
    machine.debugger.execution_state = 'stop'
    record(reason, err)
    local result = {result=reason, error=err, detective=name, arrests=player.arrests,
        cases=player.cases, keys=player.keys, state=state(), elapsed_seconds=os.time()-started,
        assisted=true, hall_of_fame=hall, mame=emu.app_version()}
    local f=assert(io.open(work .. '/autoplay-result.json','w'))
    f:write(json.stringify(result), '\n'); f:close()
    -- Exact displayed HGR bytes avoid a paused video frame lag.
    local page=(byte(0xC01C)&128)~=0 and 0x4000 or 0x2000
    local hgr=assert(io.open(work .. '/autoplay-final.hgr','wb'))
    for a=page,page+8191 do hgr:write(string.char(byte(a))) end
    hgr:close()
    for _, screen in pairs(machine.screens) do screen:snapshot(work .. '/autoplay-final.png'); break end
    events:close()
    if exit_on_done then machine:exit() end
end
function player.stop() stop('stopped') end
local function on(address, handler)
    assert(type(address)=='number', 'missing source symbol')
    assert(not handlers[address], string.format('duplicate breakpoint %04x',address))
    owned[#owned+1]=cpu.debug:bpset(address, '1', '')
    handlers[address]=handler
end
local function key(value)
    assert(not pending_key, 'previous key was not consumed')
    pending_key=value
    player.keys=player.keys+1
end
-- Inject only one byte into an actual CPU keyboard read, never debugger reads.
-- Unlike a held natural-keyboard key, it cannot leak into the next menu.
tap=mem:install_read_tap(0xC000,0xC000,'carmen-player-keyboard',function(_, data)
    if pending_key and not machine:side_effects_disabled() then
        local value=pending_key; pending_key=nil
        return value|0x80
    end
    return data
end)
local function choose(wanted)
    local row, first, last=byte(0x6C),byte(0x6E),byte(0x6F)
    assert(wanted>=first and wanted<=last, 'desired menu row outside native bounds')
    if row==wanted then key(13); return end
    local count=last-first+1
    key((wanted-row)%count <= (row-wanted)%count and 0x15 or 0x08)
end
local function menu_key()
    if menu=='city' then
        if byte(23)~=byte(0) then choose(3)
        elseif byte(17)~=byte(16) then choose(1)
        else choose(2) end
    elseif menu=='computer-save' then choose(1)
    elseif menu=='computer' then
        local suspect=byte(0)
        assert(suspect<10, 'invalid suspect')
        for category=0,5 do
            local wanted=byte(N.SUSPECT_TRAIT_MATRIX+6*suspect+category)
            if byte(27+category)~=wanted then choose(category); return end
        end
        choose(6)
    elseif menu=='travel' then
        local city=byte(17)
        local target=byte(3+byte(2))
        local first,last=byte(N.J_ROUTE_OFFSETS+city),byte(N.J_ROUTE_OFFSETS+city+1)
        for offset=first,last-1 do
            if byte(N.J_ROUTE_DESTS+offset)==target then choose(offset-first); return end
        end
        error('planned next city is absent from the native destination menu')
    elseif menu=='investigate' then
        assert(byte(17)==byte(16), 'investigation outside hideout')
        for place=0,2 do
            if byte(N.CITY_PLACE_STATE+place)<128 then choose(place); return end
        end
        error('no marked suspect location in final city')
    else error('unknown menu context: ' .. tostring(menu)) end
end
local function install_game()
    clear_breakpoints()
    for _,label in ipairs({'N_POLL_MENU_KEYBOARD','N_POLL_GAME_KEYBOARD','N_POLL_KEY_OR_BUTTON'}) do
        local address=N[label]
        assert(byte(address)==0xAD and byte(address+1)==0 and byte(address+2)==0xC0,
            'loaded game does not match keyboard symbols: '..label)
    end
    player.phase='game'
    on(N.N_READ_NAME_KEY,function() input='name' end)
    on(N.N_REJECT_RESERVED_NAME,function() error('detective name is reserved') end)
    on(N.N_REJECT_HALL_NAME,function() error('detective name is already in the Hall of Fame') end)
    on(N.N_READ_YES_NO_RESPONSE,function() input='yes' end)
    on(N.N_POLL_GAME_KEYBOARD,function()
        if hall and retiring then stop('carmen-arrested'); return end
        if input=='name' then
            assert(name_index<=#name+1, 'name input was rejected; choose another detective name')
            key(name_index<=#name and name:byte(name_index) or 13)
            name_index=name_index+1
        elseif input=='yes' then key(string.byte('Y'))
        else key(13) end
        input=nil
    end)
    on(N.N_POLL_KEY_OR_BUTTON,function()
        if hall and retiring then stop('carmen-arrested') else key(13) end
    end)
    on(N.N_POLL_MENU_KEYBOARD,menu_key)
    on(N.N_WAIT_CITY_INPUT,function()
        menu='city'
        if not initial_solved then initial_solved=byte(92) end
        if case_solved~=byte(92) then
            case_solved=byte(92); player.cases=player.cases+1
            record('case-start')
        end
        record('city')
    end)
    for label, context in pairs({N_SHOW_TRAVEL_MENU='travel', N_SHOW_INVESTIGATION_MENU='investigate',
        N_SHOW_COMPUTER_SAVE_MENU='computer-save', N_OPEN_COMPUTER='computer'}) do
        local value=context
        on(N[label],function() menu=value end)
    end
    on(N.N_EVALUATE_WARRANT,function() record('request-warrant') end)
    on(N.N_FINISH_WARRANT_SCREEN,function()
        assert(byte(23)==byte(0), 'computer did not issue the correct warrant')
        record('warrant-issued')
    end)
    on(N.N_HANDLE_CORRECT_ARREST,function()
        assert(byte(23)==byte(0), 'arrest without correct warrant')
        player.arrests=player.arrests+1
        retiring=byte(0)==0
        record('correct-arrest')
    end)
    on(N.N_ASK_FOR_NEXT_CASE,function()
        assert(byte(92)==initial_solved+player.arrests, 'native solved count did not advance')
        record('case-saved')
        if player.arrests>=limit then stop('case-limit') end
    end)
    on(N.N_SHOW_HALL_OF_FAME,function()
        if retiring then
            assert(byte(91)==5 and byte(92)==initial_solved+player.arrests,
                'Carmen retirement did not update rank and solved count')
            hall=true
            record('hall-of-fame')
        end
    end)
    for _,label in ipairs({'N_REPORT_CASE_TIMEOUT','N_REPORT_WRONG_WARRANT'}) do
        local failure=label
        on(N[label],function() error(failure) end)
    end
    record('game-loaded')
end
-- R and N overlap at $6000: install N breakpoints only after R has departed.
on(R.R_POLL_START_INPUT,function() key(13) end)
on(R.R_ENTER_GAME,function()
    clear_breakpoints()
    on(N.N_MAIN_ENTRY,install_game)
end)
record('started', {name=name,case_limit=limit})
emu.register_periodic(function()
    if not player.active then return end
    local ok,err=pcall(function()
        if os.time()-last_progress>180 then error('no input/checkpoint progress for 180 seconds') end
        if machine.debugger.execution_state~='stop' then return end
        local pc=cpu.state.PC.value
        local handler=handlers[pc]
        assert(handler, string.format('unexpected debugger stop at $%04X',pc))
        assert(not pending_key, 'keyboard response was not consumed before next breakpoint')
        last_progress=os.time()
        handler()
        if player.active then emu.unpause(); cpu.debug:go() end
    end)
    if not ok then stop('error', tostring(err)) end
end)
emu.unpause(); cpu.debug:go()
return player
