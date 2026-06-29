#!/usr/bin/env bash
# Regression: -EmitXaml for the BUILT-IN defaults (settings.json moved aside => the
# Get-NotifyDefaults unicorn theme) matches the golden. Rendering against defaults
# instead of the live settings.json keeps this test deterministic when a user edits
# their themes/events. Crash-safe: a trap restores settings.json on any exit.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/settings.json"
BAK="$(mktemp)"; HAD_SETTINGS=0
if [[ -f "$S" ]]; then HAD_SETTINGS=1; mv "$S" "$BAK"; fi
restore() { [[ "$HAD_SETTINGS" == "1" && -f "$BAK" ]] && mv "$BAK" "$S"; rm -f "$BAK"; }
trap restore EXIT

GOT="$(powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w "$ROOT/show-notification.ps1")" -Event done -EmitXaml | tr -d '\r')"

if diff <(printf '%s' "$GOT") "$ROOT/tests/golden/default.xaml" >/dev/null; then
  echo "ok: default XAML matches golden"; exit 0
else
  echo "FAIL: default XAML drifted from golden"; diff <(printf '%s' "$GOT") "$ROOT/tests/golden/default.xaml"; exit 1
fi
