-- Bootstrap shared by the owned mailbox plugin and optional Lua console.
local root = assert(os.getenv('CARMEN_MAME_ROOT'), 'use python3 -m tools.korean.mame')
local work = assert(os.getenv('CARMEN_MAME_WORK'))
a2 = dofile(os.getenv('CARMEN_MAME_CONTROL') or
            '/home/iolo/.codex/skills/a2skills/a2-mame/scripts/control.lua')
k0 = dofile(root .. '/tools/korean/runtime.lua')
a2.call('attach', 'korean_attach', root, work)
a2.call('devices', 'devices')
