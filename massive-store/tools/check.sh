#!/usr/bin/env bash
# Syntax-checks every Luau file and lints it for unknown globals / shadowing / unused code.
#   LUAU_BIN=/path/to/luau-binaries tools/check.sh
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${LUAU_BIN:-$ROOT/.luau}"
TMP="$(mktemp -d)"
cat > "$TMP/.luaurc" <<'RC'
{
  "languageMode": "nocheck",
  "lint": { "*": true, "LocalUnused": false, "ImportUnused": false, "FunctionUnused": false, "UnknownType": false },
  "globals": ["game","workspace","script","Instance","Vector3","Vector2","CFrame","Color3","ColorSequence",
    "ColorSequenceKeypoint","NumberSequence","NumberSequenceKeypoint","NumberRange","UDim","UDim2","Enum",
    "Ray","RaycastParams","OverlapParams","TweenInfo","Font","PhysicalProperties","Random","task","typeof",
    "tick","wait","delay","spawn","warn","Rect","BrickColor","DateTime","Region3","utf8","shared","settings",
    "UserSettings","elapsedTime","time","version","Load"]
}
RC
fail=0
while IFS= read -r f; do
  rel="${f#$ROOT/}"
  if ! "$BIN/luau-compile" --binary "$f" > /dev/null 2> "$TMP/err"; then
    echo "SYNTAX $rel"; cat "$TMP/err"; fail=1
  fi
  dest="$TMP/$(echo "$rel" | tr '/' '_')"
  cp "$f" "$dest"
done < <(find "$ROOT/src" -name '*.lua')
( cd "$TMP" && "$BIN/luau-analyze" --formatter=plain *.lua 2>&1 ) | grep -v "^$" > "$TMP/lint.txt" || true
if [ -s "$TMP/lint.txt" ]; then
  cat "$TMP/lint.txt"
  fail=1
fi
rm -rf "$TMP"
if [ $fail -eq 0 ]; then echo "check ok"; fi
exit $fail
