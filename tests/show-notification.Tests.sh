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

# -SoundOnly: play the wav, draw no card. The observable is whether a screens/*.pid marker
# ever APPEARS: the card path writes one (stably ~1.2s in) before its window; the sound path
# returns without touching screens/. A before/after count can't catch a regression — the card
# path self-cleans its marker on close — and headless ShowDialog runtime is too variable for a
# raw timeout, so we poll for the marker instead of timing the process.
rm -f "$ROOT/screens"/*.pid 2>/dev/null
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w "$ROOT/show-notification.ps1")" -Event done -Hwnd 0 -SoundOnly >/dev/null 2>&1 &
SO_PID=$!
SO_CARD=0
for _ in $(seq 1 60); do   # ~6s: comfortably past the sound path's ~1s exit and green's ~2.8s worst case
  if ls "$ROOT/screens"/*.pid >/dev/null 2>&1; then SO_CARD=1; break; fi
  kill -0 "$SO_PID" 2>/dev/null || break   # sound path exited without a marker
  sleep 0.1
done
kill "$SO_PID" 2>/dev/null; wait "$SO_PID" 2>/dev/null
rm -f "$ROOT/screens"/*.pid 2>/dev/null
if [[ "$SO_CARD" == 0 ]]; then
  echo "ok: -SoundOnly draws no card"
else
  echo "FAIL: -SoundOnly built a card (screens/*.pid marker appeared)"; exit 1
fi

GOT="$(powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w "$ROOT/show-notification.ps1")" -Event done -EmitXaml | tr -d '\r')"

if diff <(printf '%s' "$GOT") "$ROOT/tests/golden/default.xaml" >/dev/null; then
  echo "ok: default XAML matches golden"; exit 0
else
  echo "FAIL: default XAML drifted from golden"; diff <(printf '%s' "$GOT") "$ROOT/tests/golden/default.xaml"; exit 1
fi
