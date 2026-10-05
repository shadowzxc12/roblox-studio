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

def script_entry(inst_path, rel_file):
    name = os.path.basename(rel_file)[:-4]
    cls = 'ModuleScript'
    if name.endswith('.server'):
        name, cls = name[:-7], 'Script'
    elif name.endswith('.client'):
        name, cls = name[:-7], 'LocalScript'
    return inst_path, name, cls

# walk a Rojo project tree ($path dirs / files + explicit children), like `rojo build` does
def walk(node, inst_path):
    path = node.get('$path')
    if path:
        full = os.path.join(ROOT, path)
        if os.path.isdir(full):
            for dirpath, _, files in os.walk(full):
                for f in sorted(files):
                    if not f.endswith('.lua'):
                        continue
                    rel_file = os.path.relpath(os.path.join(dirpath, f), ROOT)
                    sub = os.path.relpath(dirpath, full)
                    base = inst_path + ('' if sub == '.' else '/' + sub)
                    _, name, cls = script_entry(base, rel_file)
                    add(base + '/' + name, cls, rel_file)
        elif full.endswith('.lua'):
            _, name, cls = script_entry(inst_path, path)
            add(inst_path, cls, path)
    for key, child in node.items():
        if key.startswith('$') or not isinstance(child, dict):
            continue
        walk(child, inst_path + '/' + key if inst_path else key)

args = sys.argv[2:]
project = 'default.project.json'
for a in list(args):
    if a.startswith('PROJECT='):
        project = a.split('=', 1)[1]
        args.remove(a)
proj = json.load(open(os.path.join(ROOT, project)))
for service, node in proj['tree'].items():
    if service.startswith('$'):
        continue
    if service == 'StarterPlayer':
        # scripts live under StarterPlayer/StarterPlayerScripts
        for key, child in node.items():
            if not key.startswith('$') and isinstance(child, dict):
                walk(child, 'StarterPlayer/' + key)
        continue
    walk(node, service)

out = ['SOURCES = {}']
for k, v in sources.items():
    assert ']=====]' not in v
    out.append(f'SOURCES[{json.dumps(k)}] = [=====[{v}]=====]')
out.append('TREE = ' + '{' + ','.join('{Path=%s,Class=%s,Source=%s}' % (json.dumps(t['Path']), json.dumps(t['Class']), json.dumps(t['Source'])) for t in tree) + '}')
here = os.path.dirname(__file__)
out.append(open(os.path.join(here, 'engine.lua')).read())
for arg in args:
    k, v = arg.split('=', 1)
    out.append('G.%s = %s' % (k, json.dumps(v)))
out.append(open(sys.argv[1]).read())
inner = '\n'.join(out)
assert ']======]' not in inner
print('local inner = [======[' + inner + ']======]\n'
      'local ENV = setmetatable({}, {__index = getfenv()})\nENV.ENV = ENV\nENV.G = {}\n'
      'local f, err = loadstring(inner, "=sim")\nif not f then error(err) end\nsetfenv(f, ENV)\nf()\n')
