"""Bundles the real game sources + the fake engine + a scenario into one Luau file.

  python3 tests/sim/build.py tests/sim/run.lua > /tmp/sim.lua && luau /tmp/sim.lua
  python3 tests/sim/build.py tests/sim/run_modes.lua MODE=Solo > /tmp/sim.lua   (sets G.MODE = "Solo")
"""
import json, os, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SRC = os.path.join(ROOT, 'src')

tree = []
sources = {}
def add(path, cls, src_rel):
    tree.append({'Path': path, 'Class': cls, 'Source': src_rel})
    sources[src_rel] = open(os.path.join(ROOT, src_rel)).read()

for base, inst_base in [('src/ReplicatedStorage/Shared', 'ReplicatedStorage/Shared'),
                        ('src/ServerScriptService', 'ServerScriptService'),
                        ('src/ReplicatedFirst', 'ReplicatedFirst'),
                        ('src/StarterPlayerScripts', 'StarterPlayer/StarterPlayerScripts')]:
    for dirpath, _, files in os.walk(os.path.join(ROOT, base)):
        for f in sorted(files):
            if not f.endswith('.lua'):
                continue
            rel_file = os.path.relpath(os.path.join(dirpath, f), ROOT)
            sub = os.path.relpath(dirpath, os.path.join(ROOT, base))
            name = f[:-4]
            cls = 'ModuleScript'
            if name.endswith('.server'):
                name, cls = name[:-7], 'Script'
            elif name.endswith('.client'):
                name, cls = name[:-7], 'LocalScript'
            inst_path = inst_base + ('' if sub == '.' else '/' + sub) + '/' + name
            add(inst_path, cls, rel_file)

out = ['SOURCES = {}']
for k, v in sources.items():
    assert ']=====]' not in v
    out.append(f'SOURCES[{json.dumps(k)}] = [=====[{v}]=====]')
out.append('TREE = ' + '{' + ','.join('{Path=%s,Class=%s,Source=%s}' % (json.dumps(t['Path']), json.dumps(t['Class']), json.dumps(t['Source'])) for t in tree) + '}')
here = os.path.dirname(__file__)
out.append(open(os.path.join(here, 'engine.lua')).read())
for arg in sys.argv[2:]:
    k, v = arg.split('=', 1)
    out.append('G.%s = %s' % (k, json.dumps(v)))
out.append(open(sys.argv[1]).read())
inner = '\n'.join(out)
assert ']======]' not in inner
print('local inner = [======[' + inner + ']======]\n'
      'local ENV = setmetatable({}, {__index = getfenv()})\nENV.ENV = ENV\nENV.G = {}\n'
      'local f, err = loadstring(inner, "=sim")\nif not f then error(err) end\nsetfenv(f, ENV)\nf()\n')
