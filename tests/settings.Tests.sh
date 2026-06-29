#!/usr/bin/env bash
# Validates settings.json parses and exposes the expected structure.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
F="$ROOT/settings.json"
fail=0
check() { if eval "$2"; then echo "ok: $1"; else echo "FAIL: $1"; fail=1; fi; }

check "file exists"            "[[ -f '$F' ]]"
check "valid json"            "jq -e . '$F' >/dev/null"
check "activeTheme present"   "jq -e '.activeTheme' '$F' >/dev/null 2>&1"
check "activeTheme names a real theme" "jq -e '.themes[.activeTheme]' '$F' >/dev/null 2>&1"
check "9 themes"              "[[ \"\$(jq '.themes|length' '$F')\" == '9' ]]"
check "unicorn theme"         "jq -e '.themes.unicorn' '$F' >/dev/null"
check "needs-input body array" "jq -e '.events[\"needs-input\"].body|type==\"array\"' '$F' >/dev/null"
check "done body array"       "jq -e '.events.done.body|type==\"array\"' '$F' >/dev/null"
check "every theme has hero/gradient/rim/card" \
  "[[ \"\$(jq '[.themes[]|select(.hero and .gradient and .rim and .card)]|length' '$F')\" == '9' ]]"
check "ocean has waves scene" "[[ \"\$(jq -r '.themes.ocean.scene.kind // empty' '$F')\" == 'waves' ]]"
check "ocean scene has sky+sun+clouds" "[[ \"\$(jq -rc '[.themes.ocean.scene.sky,.themes.ocean.scene.sun,.themes.ocean.scene.clouds]' '$F')\" == '[true,true,true]' ]]"

exit $fail
