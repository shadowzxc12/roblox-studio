# Headless server simulation

Runs the real server code (ServerScriptService + ReplicatedStorage modules) on a tiny fake
Roblox engine with virtual time and bot players, so the round flow, tagging, matchmaking,
shop and data saving can be checked without Studio. Needs the `luau` CLI.

```
python3 tests/sim/build.py Normal 6 360            # mode, players, seconds  (+ optional leave time, scenario file)
luau tests/sim/sim_built.lua

python3 tests/sim/build.py Infection 8 330 40      # a player leaves at t=40
python3 tests/sim/build.py Normal 5 30 nil run_lobby.lua    # matchmaking in a lobby server
python3 tests/sim/build.py Normal 3 60 nil run_studio.lua   # Studio local match
python3 tests/sim/build.py Normal 0 10 nil run_shop.lua     # shop + settings validation
python3 tests/sim/build.py Normal 0 10 nil run_dsfail.lua   # DataStore outage
```
