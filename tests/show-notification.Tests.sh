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

# -SoundOnly: play the wav, draw no card. Timing is the reliable observable: the card path
# self-cleans its screens/*.pid marker when the dialog closes, so a marker count alone can't
# fail. The sound path returns in ~1s; the card path enters ShowDialog (~5-6s+ headless, up
# to the timeout on a real display), so a 4s bound turns "a card was built" into RC=124.
MARKERS_BEFORE="$(ls "$ROOT/screens" 2>/dev/null | wc -l)"
timeout 4s powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w "$ROOT/show-notification.ps1")" -Event done -Hwnd 0 -SoundOnly >/dev/null 2>&1
RC=$?
MARKERS_AFTER="$(ls "$ROOT/screens" 2>/dev/null | wc -l)"
if [[ "$RC" == "0" && "$MARKERS_BEFORE" == "$MARKERS_AFTER" ]]; then
  echo "ok: -SoundOnly draws no card"
else
  echo "FAIL: -SoundOnly rc=$RC markers $MARKERS_BEFORE -> $MARKERS_AFTER"; exit 1
fi

GOT="$(powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w "$ROOT/show-notification.ps1")" -Event done -EmitXaml | tr -d '\r')"

if diff <(printf '%s' "$GOT") "$ROOT/tests/golden/default.xaml" >/dev/null; then
  echo "ok: default XAML matches golden"; exit 0
else
  echo "FAIL: default XAML drifted from golden"; diff <(printf '%s' "$GOT") "$ROOT/tests/golden/default.xaml"; exit 1
fi
