import json,glob,os,sys
root=os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
proj=json.load(open(f'{root}/default.project.json'))
rem=proj['tree']['ReplicatedStorage']['Remotes']
ev=[k for k,v in rem.items() if isinstance(v,dict) and v.get('$className')=='RemoteEvent']
fn=[k for k,v in rem.items() if isinstance(v,dict) and v.get('$className')=='RemoteFunction']
out=['SOURCES = {}']
for f in glob.glob(f'{root}/src/**/*.lua',recursive=True):
    rel=os.path.relpath(f,f'{root}/src')
    src=open(f).read(); assert ']=====]' not in src
    out.append(f'SOURCES[{json.dumps(rel)}] = [=====[{src}]=====]')
out.append('REMOTE_EVENTS = '+'{'+','.join(json.dumps(e) for e in ev)+'}')
out.append('REMOTE_FUNCTIONS = '+'{'+','.join(json.dumps(e) for e in fn)+'}')
mode,players,dur=sys.argv[1],sys.argv[2],sys.argv[3]
leave=sys.argv[4] if len(sys.argv)>4 else 'nil'
out.append(f'G.TEST_MODE={json.dumps(mode)} G.TEST_PLAYERS={players} G.TEST_DURATION={dur} G.LEAVE_AT={leave}')
out.append(open(os.path.dirname(__file__)+'/mock.lua').read())
out.append('G.SIM_REF = G.SIM')
out.append(open(os.path.dirname(__file__)+'/'+(sys.argv[5] if len(sys.argv)>5 else 'run.lua')).read())
inner='\n'.join(out); assert ']======]' not in inner
wrapper='local inner = [======['+inner+']======]\nlocal ENV = setmetatable({}, {__index = getfenv()})\nENV.ENV = ENV\nENV.G = {}\nlocal f, err = loadstring(inner, "=sim")\nif not f then error(err) end\nsetfenv(f, ENV)\nf()\n'
open(os.path.dirname(__file__)+'/sim_built.lua','w').write(wrapper)
