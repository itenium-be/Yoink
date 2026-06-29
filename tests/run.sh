#!/usr/bin/env bash
# Dependency-free tests for the notifier hooks. Stubs powershell.exe.
set -uo pipefail
HOOKS="$HOME/.claude/hooks"
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

echo "----"; echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
