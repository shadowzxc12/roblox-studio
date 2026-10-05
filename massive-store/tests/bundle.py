"""Bundles the pure shared modules (ReplicatedStorage/Shared) + a test file into one Luau script
that runs with the plain `luau` CLI (no Roblox needed).

  python3 tests/bundle.py tests/test_shared.lua > /tmp/t.lua && luau /tmp/t.lua
"""
import json, os, sys, glob

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SHARED = os.path.join(ROOT, 'src', 'ReplicatedStorage', 'Shared')
PURE = ['Config', 'Util', 'Rarity', 'Items', 'Zones', 'Buildables', 'StoreLayout', 'Nav',
        'InventoryCore', 'Progression', 'Missions', 'Cosmetics']

out = ['local SOURCES = {}']
for name in PURE:
    path = os.path.join(SHARED, name + '.lua')
    if not os.path.exists(path):
        continue
    src = open(path).read()
    assert ']=====]' not in src
    out.append(f'SOURCES[{json.dumps(name)}] = [=====[{src}]=====]')

out.append(r'''
local cache = {}
local Shared = {}
local function load(name)
	if cache[name] ~= nil then return cache[name] end
	local src = SOURCES[name]
	if not src then error("no module " .. name) end
	local fn, err = loadstring(src, "=" .. name)
	if not fn then error(err) end
	local env = setmetatable({ script = { Parent = Shared, Name = name } }, { __index = getfenv() })
	setfenv(fn, env)
	cache[name] = fn()
	return cache[name]
end
setmetatable(Shared, { __index = function(_, k) return { __module = k } end })
local realRequire = require
require = function(m)
	if type(m) == "table" and m.__module then return load(m.__module) end
	return realRequire(m)
end
function Load(name) return load(name) end
''')
out.append(open(sys.argv[1]).read())
print('\n'.join(out))
