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

# Scene config is wired in the schema so the unicorn theme validates against it.
# scene has additionalProperties:false, so every flag the theme uses must be
# defined and "unicorn" must be an allowed kind.
SCHEMA="$ROOT/settings.schema.json"
check "unicorn has unicorn scene"        "[[ \"\$(jq -r '.themes.unicorn.scene.kind // empty' '$F')\" == 'unicorn' ]]"
check "schema scene.kind allows unicorn" "jq -e '.definitions.scene.properties.kind.enum|index(\"unicorn\")' '$SCHEMA' >/dev/null"
check "schema defines unicorn scene flags" \
  "[[ \"\$(jq -c '.definitions.scene.properties|[has(\"aurora\"),has(\"rainbow\"),has(\"glitter\"),has(\"sparkles\"),has(\"shootingStar\")]' '$SCHEMA')\" == '[true,true,true,true,true]' ]]"

check "spooky has spooky scene"          "[[ \"\$(jq -r '.themes.spooky.scene.kind // empty' '$F')\" == 'spooky' ]]"
check "schema scene.kind allows spooky"  "jq -e '.definitions.scene.properties.kind.enum|index(\"spooky\")' '$SCHEMA' >/dev/null"
check "schema defines spooky scene flags" \
  "[[ \"\$(jq -c '.definitions.scene.properties|[has(\"moon\"),has(\"fog\"),has(\"gravestones\"),has(\"webs\"),has(\"ghosts\"),has(\"bats\"),has(\"eyes\"),has(\"lightning\")]' '$SCHEMA')\" == '[true,true,true,true,true,true,true,true]' ]]"

check "robot has robot scene"            "[[ \"\$(jq -r '.themes.robot.scene.kind // empty' '$F')\" == 'robot' ]]"
check "robot scene base is circuit"      "[[ \"\$(jq -r '.themes.robot.scene.base // empty' '$F')\" == 'circuit' ]]"
check "schema scene.kind allows robot"   "jq -e '.definitions.scene.properties.kind.enum|index(\"robot\")' '$SCHEMA' >/dev/null"
check "schema defines robot scene flags" \
  "[[ \"\$(jq -c '.definitions.scene.properties|[has(\"base\"),has(\"leds\"),has(\"rings\"),has(\"glow\")]' '$SCHEMA')\" == '[true,true,true,true]' ]]"

check "vaporwave has vaporwave scene"       "[[ \"\$(jq -r '.themes.vaporwave.scene.kind // empty' '$F')\" == 'vaporwave' ]]"
check "schema scene.kind allows vaporwave"  "jq -e '.definitions.scene.properties.kind.enum|index(\"vaporwave\")' '$SCHEMA' >/dev/null"
check "schema defines vaporwave scene flags" \
  "[[ \"\$(jq -c '.definitions.scene.properties|[has(\"haze\"),has(\"sun\"),has(\"stars\"),has(\"mountains\"),has(\"grid\"),has(\"palms\"),has(\"scanlines\"),has(\"glow\")]' '$SCHEMA')\" == '[true,true,true,true,true,true,true,true]' ]]"

exit $fail
