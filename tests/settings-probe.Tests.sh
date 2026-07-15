#!/usr/bin/env bash
# settings-probe is the only path by which bash reads the JSONC settings.json.
# Needs the REAL powershell.exe — run it outside the hook stub's PATH.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
PROBE="$(wslpath -w "$ROOT/settings-probe.ps1")"
pass=0; fail=0
ok(){ if eval "$2"; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1"; fail=$((fail+1)); fi; }

probe(){ powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PROBE" -SettingsDir "$(wslpath -w "$1")" | tr -d '\r'; }

GOOD="$(probe "$FIX/probe-good")"
ok "good settings report ok"        '[[ "$GOOD" == *"status=ok"* ]]'
ok "good settings report channels"  '[[ "$GOOD" == *"off-behavior=bell,sound"* ]]'

BAD="$(probe "$FIX/probe-bad")"
ok "bad settings report error"      '[[ "$BAD" == *"status=error"* ]]'
ok "bad settings name the file"     '[[ "$BAD" == *"error="* ]]'

MISSING="$(probe "$FIX/probe-missing")"
ok "missing settings are ok"        '[[ "$MISSING" == *"status=ok"* ]]'
ok "missing settings default bell"  '[[ "$MISSING" == *"off-behavior=bell"* ]]'

echo "----"; echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
