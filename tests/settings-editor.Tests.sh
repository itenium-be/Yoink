#!/usr/bin/env bash
# settings-editor.ps1 without the live window: -DryRun prints the field list, -DryRun -SaveTo
# round-trips the model to JSON, and -SelfTest builds the window + one synchronous card rebuild
# (catches scope/function-visibility errors -DryRun can't). WPF needs STA -> pass -STA.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CFG="$TMP/settings.json"
cat > "$CFG" <<'JSON'
{ "activeTheme": "sakura",
  "events": { "done": { "label": "Done!", "mascot": { "move": "walk", "end": "confetti" } } },
  "themes": { "sakura": { "hero": "🌸", "card": "#1A1620",
              "scene": { "kind": "sakura", "petals": true, "count": 22 } },
              "dragon": { "hero": "🐉", "card": "#1A0F0A" } } }
JSON

run() { powershell.exe -NoProfile -ExecutionPolicy Bypass -STA \
  -File "$(wslpath -w "$ROOT/settings-editor.ps1")" "$@" | tr -d '\r'; }

fail=0
check() { if eval "$2"; then echo "ok: $1"; else echo "FAIL: $1"; fail=1; fi; }

OUT="$(run -SettingsPath "$(wslpath -w "$CFG")" -DryRun)"
check "lists activeTheme dropdown"  "grep -q 'dropdown activeTheme' <<<\"\$OUT\""
check "lists event label field"     "grep -q 'text events.done.label' <<<\"\$OUT\""
check "lists scene petals checkbox" "grep -q 'checkbox themes.sakura.scene.petals' <<<\"\$OUT\""

run -SettingsPath "$(wslpath -w "$CFG")" -DryRun -SaveTo "$(wslpath -w "$TMP/out.json")" >/dev/null
check "save writes valid json" "jq -e . '$TMP/out.json' >/dev/null"
check "save keeps label" "[[ \"\$(jq -r .events.done.label '$TMP/out.json')\" == 'Done!' ]]"

OUT2="$(run -SettingsPath "$(wslpath -w "$CFG")" -SelfTest)"
check "selftest builds + rebuilds" "grep -q 'selftest ok' <<<\"\$OUT2\""

exit $fail
