#!/usr/bin/env bash
# Runs every automated check:
#   1. syntax + lint of all Luau files            (tools/check.sh)
#   2. store generator / pure module tests        (tests/test_*.lua)
#   3. headless server+client simulations          (tests/sim/run*.lua)
# Needs the luau CLI tools (luau, luau-analyze, luau-compile) in $LUAU_BIN (default ./.luau).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LUAU_BIN="${LUAU_BIN:-$ROOT/.luau}"
TMP="$(mktemp -d)"
cd "$ROOT"

"$ROOT/tools/check.sh"

for t in tests/test_*.lua; do
  echo "== $t"
  python3 tests/bundle.py "$t" > "$TMP/t.lua"
  "$LUAU_BIN/luau" "$TMP/t.lua" | tail -3
done

run_sim() {
  echo "== sim $*"
  python3 tests/sim/build.py "$@" > "$TMP/sim.lua"
  "$LUAU_BIN/luau" "$TMP/sim.lua" > "$TMP/out.txt" 2>&1 || { tail -40 "$TMP/out.txt"; exit 1; }
  grep -E "OK|SIM OK" "$TMP/out.txt" | tail -1
}
run_sim tests/sim/run.lua
run_sim tests/sim/run_locust.lua
run_sim tests/sim/run_systems.lua
run_sim tests/sim/run_modes.lua MODE=Infection
run_sim tests/sim/run_modes.lua MODE=Solo
run_sim tests/sim/run_modes.lua MODE=Hardcore
run_sim tests/sim/run_client.lua
rm -rf "$TMP"
echo "ALL TESTS PASSED"
