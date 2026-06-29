#!/usr/bin/env bash
# Validates settings.json parses and exposes the expected structure.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RAW="$ROOT/settings.json"
# Validate against a comment-stripped copy: settings.json is JSONC (the runtime
# strips comments before parsing), so jq must see it the same way.
F="$(mktemp)"; trap 'rm -f "$F"' EXIT
python3 "$ROOT/tests/strip-jsonc.py" < "$RAW" > "$F"
fail=0
check() { if eval "$2"; then echo "ok: $1"; else echo "FAIL: $1"; fail=1; fi; }

check "file exists"            "[[ -f '$RAW' ]]"
check "valid jsonc"           "jq -e . '$F' >/dev/null"
check "jsonc strips comments"  "printf '{\n  // pick\n  \"a\": 1 /* x */\n}' | python3 '$ROOT/tests/strip-jsonc.py' | jq -e '.a==1' >/dev/null"
check "jsonc keeps // in strings" "printf '{\"u\":\"http://x//y\"}' | python3 '$ROOT/tests/strip-jsonc.py' | jq -e '.u==\"http://x//y\"' >/dev/null"
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
check "cosmic has space scene" "[[ \"\$(jq -r '.themes.cosmic.scene.kind // empty' '$F')\" == 'space' ]]"
check "cosmic scene has stars+nebula+comets" "[[ \"\$(jq -rc '[.themes.cosmic.scene.stars,.themes.cosmic.scene.nebula,.themes.cosmic.scene.comets]' '$F')\" == '[true,true,true]' ]]"
check "matrix has matrix scene" "[[ \"\$(jq -r '.themes.matrix.scene.kind // empty' '$F')\" == 'matrix' ]]"
check "matrix scene streaks is boolean" "[[ \"\$(jq -r '.themes.matrix.scene.streaks|type' '$F')\" == 'boolean' ]]"
check "matrix hero uses object form" "[[ \"\$(jq -r '.themes.matrix.hero|type' '$F')\" == 'object' ]]"
check "matrix hero has emoji + fixed fill" "jq -e '.themes.matrix.hero | .emoji and (.color // .colors)' '$F' >/dev/null"

exit $fail
