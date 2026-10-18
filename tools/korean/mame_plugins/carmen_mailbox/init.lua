-- Local command mailbox for an owned MAME process. No stdin or network server.
local exports={name='carmen_mailbox',version='0.1.0',description='Carmen development mailbox'}

function exports.startplugin()
    local root=assert(os.getenv('CARMEN_MAME_ROOT'))
    local work=assert(os.getenv('CARMEN_MAME_WORK'))
    local directory=work..'/mailbox'
    local json=require('json')
    local initialized,busy=false,false

    local function write_json(path,value)
        local temporary=path..'.tmp'
        local encoded=json.stringify(value)
        local f=assert(io.open(temporary,'wb'))
        f:write(encoded); f:write('\n'); f:close()
        assert(os.rename(temporary,path))
    end

    -- The same host-periodic hook used by MAME 0.285's console plugin. Unlike
    -- emulated frame callbacks, it runs while paused or stopped in the debugger.
    emu.register_periodic(function()
        if busy then return end
        busy=true
        if not initialized then
            local machine=manager.machine
            local cpu=machine and machine.devices[':maincpu']
            if not cpu or not cpu.spaces.program or not machine.debugger or not cpu.state.PC then
                busy=false; return
            end
            local ok,err=pcall(dofile,root..'/tools/korean/start.lua')
            write_json(directory..'/ready.json',{ok=ok,error=not ok and tostring(err) or nil,
                driver=machine.system.name,version=emu.app_version(),transport='workspace-file-mailbox'})
            initialized=true
            if not ok then busy=false; return end
        end
        local f=io.open(directory..'/request.json','rb')
        if not f then busy=false; return end
        local raw=f:read('a'); f:close()
        -- Archive the exact accepted request before executing it. Clients use
        -- atomic rename, so the periodic hook never reads a partially written file.
        local parsed,request=pcall(json.parse,raw)
        if not parsed or type(request)~='table' or type(request.id)~='string'
            or not request.id:match('^[a-z0-9-]+$') or #request.id>64 then
            os.rename(directory..'/request.json',directory..'/invalid-request.json')
            busy=false; return
        end
        assert(os.rename(directory..'/request.json',directory..'/'..request.id..'.request.json'))
        local ok,result=pcall(function()
            if request.operation then
                assert(request.operation~='call' and type(a2[request.operation])=='function','unknown operation')
                return a2[request.operation](table.unpack(request.args or {}))
            end
            assert(type(request.code)=='string' and #request.code<=65536,'Lua source required')
            local fn,err=load(request.code,'mailbox:'..request.id,'t',_G)
            assert(fn,err)
            return fn()
        end)
        local response={id=request.id,ok=ok,result=ok and result or nil,error=not ok and tostring(result) or nil}
        local encoded,err=pcall(write_json,directory..'/'..request.id..'.response.json',response)
        if not encoded then
            write_json(directory..'/'..request.id..'.response.json',{id=request.id,ok=false,error=tostring(err)})
        end
        busy=false
    end)
end

return exports
