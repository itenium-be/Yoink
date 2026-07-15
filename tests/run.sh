#!/usr/bin/env bash
# Dependency-free tests for the notifier hooks. Stubs powershell.exe.
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/.." && pwd)/hooks"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export YOINK_DIR="$TMP/notify"
mkdir -p "$TMP/bin" "$YOINK_DIR/sessions"

# Stub powershell.exe: capture mode prints a fake HWND; show mode records args.
cat > "$TMP/bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$YOINK_DIR/ps_calls.log"
case "$*" in
  *capture*) echo "123456 WindowsTerminal" ;;
esac
EOF
chmod +x "$TMP/bin/powershell.exe"
ORIG_PATH="$PATH"
export PATH="$TMP/bin:$PATH"
export YOINK_PS_CAPTURE="capture-window.ps1"
export YOINK_PS_SHOW="show-notification.ps1"

pass=0; fail=0
ok(){ if eval "$2"; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1"; fail=$((fail+1)); fi; }

# --- capture writes a record with the HWND ---
echo '{"session_id":"abc","cwd":"/home/x/proj"}' | bash "$HOOKS/notify-capture.sh"
ok "capture writes session json" '[[ -f "$YOINK_DIR/sessions/abc.json" ]]'
ok "capture stores hwnd 123456" '[[ "$(jq -r .hwnd "$YOINK_DIR/sessions/abc.json")" == "123456" ]]'

# --- capture ignores non-terminal foreground ---
cat > "$TMP/bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
case "$*" in *capture*) echo "999 explorer" ;; esac
EOF
chmod +x "$TMP/bin/powershell.exe"
echo '{"session_id":"xyz","cwd":"/tmp"}' | bash "$HOOKS/notify-capture.sh"
ok "capture skips non-terminal" '[[ ! -f "$YOINK_DIR/sessions/xyz.json" ]]'

# --- capture trusts other modern terminals (alacritty) ---
cat > "$TMP/bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
case "$*" in *capture*) echo "222 alacritty" ;; esac
EOF
chmod +x "$TMP/bin/powershell.exe"
echo '{"session_id":"ala","cwd":"/tmp"}' | bash "$HOOKS/notify-capture.sh"
ok "capture trusts alacritty" '[[ "$(jq -r .hwnd "$YOINK_DIR/sessions/ala.json" 2>/dev/null)" == "222" ]]'

# --- YOINK_TERMINALS overrides the whitelist ---
cat > "$TMP/bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
case "$*" in *capture*) echo "333 mycoolterm" ;; esac
EOF
chmod +x "$TMP/bin/powershell.exe"
YOINK_TERMINALS="mycoolterm" bash "$HOOKS/notify-capture.sh" <<<'{"session_id":"ct","cwd":"/tmp"}'
ok "capture honors YOINK_TERMINALS" '[[ "$(jq -r .hwnd "$YOINK_DIR/sessions/ct.json" 2>/dev/null)" == "333" ]]'

# --- capture-hwnd --force accepts an untrusted host (VS Code / conhost escape hatch) ---
cat > "$TMP/bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
case "$*" in *capture*) echo "444 conhost" ;; esac
EOF
chmod +x "$TMP/bin/powershell.exe"
bash "$(dirname "$0")/../bin/capture-hwnd.sh" "forced" "/tmp/f"
ok "capture-hwnd skips untrusted host without --force" '[[ ! -f "$YOINK_DIR/sessions/forced.json" ]]'
bash "$(dirname "$0")/../bin/capture-hwnd.sh" "forced" "/tmp/f" --force
ok "capture-hwnd --force stores untrusted hwnd" '[[ "$(jq -r .hwnd "$YOINK_DIR/sessions/forced.json" 2>/dev/null)" == "444" ]]'
ok "capture-hwnd --force stores cwd" '[[ "$(jq -r .cwd "$YOINK_DIR/sessions/forced.json" 2>/dev/null)" == "/tmp/f" ]]'

# --- /yoink off | on ---
cat > "$TMP/bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *settings-probe*) printf 'status=ok\noff-behavior=bell\n' ;;
  *capture*) echo "123456 WindowsTerminal" ;;
esac
EOF
chmod +x "$TMP/bin/powershell.exe"
YOINK="$(cd "$(dirname "$0")/.." && pwd)/bin/yoink.sh"
DND="$YOINK_DIR/dnd.json"
export CLAUDE_CODE_SESSION_ID="sid-1"

rm -f "$DND"
bash "$YOINK" off >/dev/null
ok "off defaults to scope all"       '[[ "$(jq -r ".all.until" "$DND")" == "0" ]]'
ok "off copies off-behavior default" '[[ "$(jq -rc ".all.allow" "$DND")" == "[\"bell\"]" ]]'

rm -f "$DND"
bash "$YOINK" off session 2h >/dev/null
ok "off session keys on session id"  '[[ "$(jq -r ".sessions[\"sid-1\"].until" "$DND")" -gt "$(date +%s)" ]]'
ok "off 2h expires in ~2h"           '[[ "$(jq -r ".sessions[\"sid-1\"].until" "$DND")" -le "$(( $(date +%s) + 7200 ))" ]]'

rm -f "$DND"
(cd /tmp && bash "$YOINK" off project --allow bell,sound >/dev/null)
ok "off project keys on cwd"         '[[ "$(jq -rc ".projects[\"/tmp\"].allow" "$DND")" == "[\"bell\",\"sound\"]" ]]'

rm -f "$DND"
bash "$YOINK" off 30m >/dev/null
ok "off takes a bare duration"       '[[ "$(jq -r ".all.until" "$DND")" -gt "$(date +%s)" ]]'

# on with no scope clears everything that could be silencing you here
rm -f "$DND"
bash "$YOINK" off >/dev/null
bash "$YOINK" off session >/dev/null
bash "$YOINK" on >/dev/null
ok "bare on clears all"              '[[ "$(jq -r ".all // \"gone\"" "$DND")" == "gone" ]]'
ok "bare on clears this session"     '[[ "$(jq -r ".sessions[\"sid-1\"] // \"gone\"" "$DND")" == "gone" ]]'

rm -f "$DND"
bash "$YOINK" off >/dev/null
bash "$YOINK" off session >/dev/null
bash "$YOINK" on session >/dev/null
ok "on session keeps all"            '[[ "$(jq -r ".all.until" "$DND")" == "0" ]]'

ok "off rejects a bad duration"      '! bash "$YOINK" off 5x >/dev/null 2>&1'
ok "off rejects a bad scope"         '! bash "$YOINK" off everywhere >/dev/null 2>&1'

# --- fire passes stored hwnd + done status ---
cat > "$TMP/bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
echo "$@" > "$YOINK_DIR/last_show.txt"
EOF
chmod +x "$TMP/bin/powershell.exe"
echo '{"session_id":"abc","cwd":"/home/x/proj"}' | bash "$HOOKS/notify-fire.sh" done
sleep 0.3
ok "fire forwards stored hwnd" 'grep -q -- "-Hwnd 123456" "$YOINK_DIR/last_show.txt"'
ok "fire sets done event" 'grep -q -- "-Event done" "$YOINK_DIR/last_show.txt"'

# --- fire on unknown session falls back to hwnd 0 ---
echo '{"session_id":"nope","cwd":"/x"}' | bash "$HOOKS/notify-fire.sh" needs-input
sleep 0.3
ok "fire fallback hwnd 0" 'grep -q -- "-Hwnd 0" "$YOINK_DIR/last_show.txt"'
ok "fire needs-input event" 'grep -q -- "-Event needs-input" "$YOINK_DIR/last_show.txt"'

# --- mascot outline step ---
ok "mascot outline ring" 'python3 "$(dirname "$0")/normalize-outline.test.py" >/dev/null 2>&1'

# The editor's live preview dispatches scenes through card-choreography, so it must
# dot-source every scene lib the renderer does — otherwise Start-<Scene> is undefined
# the moment that theme is previewed (and only for that theme, so it slips through).
_scenes(){ grep -oE 'scene-[a-z]+\.ps1' "$1" | sort -u; }
ok "editor loads every renderer scene" \
  '[[ -z "$(comm -23 <(_scenes "$(dirname "$0")/../show-notification.ps1") <(_scenes "$(dirname "$0")/../settings-editor.ps1"))" ]]'

# settings-model (pure PS) + editor seam need the REAL powershell, not the hook stub.
PATH="$ORIG_PATH"
ok "settings model" 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$(dirname "$0")/settings-model.Tests.ps1")" >/dev/null 2>&1'
ok "settings editor seam" 'bash "$(dirname "$0")/settings-editor.Tests.sh" >/dev/null 2>&1'
ok "settings probe" 'bash "$(dirname "$0")/settings-probe.Tests.sh" >/dev/null 2>&1'
ok "card body width-bounded" 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$(dirname "$0")/notification-box.Tests.ps1")" >/dev/null 2>&1'
ok "card does not steal focus" 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$(dirname "$0")/focus.Tests.ps1")" >/dev/null 2>&1'

echo "----"; echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
