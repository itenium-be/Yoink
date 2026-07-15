#!/usr/bin/env bash
# settings-probe is the only path by which bash reads the JSONC settings.json.
# Needs the REAL powershell.exe — run it outside the hook stub's PATH.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
PROBE="$(wslpath -w "$ROOT/settings-probe.ps1")"
pass=0; fail=0
ok(){ if eval "$2"; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1"; fail=$((fail+1)); fi; }

probe(){
  local dir="$1" fallback="${2:-}"
  if [[ -n "$fallback" ]]; then
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PROBE" -SettingsDir "$(wslpath -w "$dir")" -FallbackDir "$(wslpath -w "$fallback")" | tr -d '\r'
  else
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PROBE" -SettingsDir "$(wslpath -w "$dir")" | tr -d '\r'
  fi
}

GOOD="$(probe "$FIX/probe-good")"
ok "good settings report ok"        '[[ "$GOOD" == *"status=ok"* ]]'
ok "good settings report channels"  '[[ "$GOOD" == *"off-behavior=bell,sound"* ]]'

BAD="$(probe "$FIX/probe-bad")"
ok "bad settings report error"      '[[ "$BAD" == *"status=error"* ]]'
ok "bad settings name the file"     '[[ "$BAD" == *"error="* ]]'

MISSING="$(probe "$FIX/probe-missing")"
ok "missing settings are ok"        '[[ "$MISSING" == *"status=ok"* ]]'
ok "missing settings default bell"  '[[ "$MISSING" == *"off-behavior=bell"* ]]'

# User dir absent, bundled fallback present -> the bundled tier resolves the default,
# proving the fix (previously this fell straight to hardcoded bell).
FALLBACK="$(probe "$FIX/probe-missing" "$FIX/probe-bundled")"
ok "no user settings falls back to bundled"     '[[ "$FALLBACK" == *"status=ok"* ]]'
ok "bundled fallback off-behavior"              '[[ "$FALLBACK" == *"off-behavior=bell,sound"* ]]'

# User dir present with a value that differs from the bundled fixture -> user must win.
USERWINS="$(probe "$FIX/probe-userwins" "$FIX/probe-bundled")"
ok "user settings take precedence over bundled" '[[ "$USERWINS" == *"off-behavior=bell"* && "$USERWINS" != *"off-behavior=bell,sound"* ]]'

# A broken USER file is still a doctor-facing error even when a valid bundled fallback
# exists — the bundled tier only supplies a default, it never rescues a broken user file.
BADWITHFALLBACK="$(probe "$FIX/probe-bad" "$FIX/probe-bundled")"
ok "broken user settings still error with fallback present" '[[ "$BADWITHFALLBACK" == *"status=error"* ]]'

echo "----"; echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
