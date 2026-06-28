#!/usr/bin/env bash
# Dependency-free tests for the notifier hooks. Stubs powershell.exe.
set -uo pipefail
HOOKS="$HOME/.claude/hooks"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CLAUDE_NOTIFY_DIR="$TMP/notify"
mkdir -p "$TMP/bin" "$CLAUDE_NOTIFY_DIR/sessions"

# Stub powershell.exe: capture mode prints a fake HWND; show mode records args.
cat > "$TMP/bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$CLAUDE_NOTIFY_DIR/ps_calls.log"
case "$*" in
  *capture*) echo "123456 WindowsTerminal" ;;
esac
EOF
chmod +x "$TMP/bin/powershell.exe"
export PATH="$TMP/bin:$PATH"
export CLAUDE_NOTIFY_PS_CAPTURE="capture-window.ps1"
export CLAUDE_NOTIFY_PS_SHOW="show-notification.ps1"

pass=0; fail=0
ok(){ if eval "$2"; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1"; fail=$((fail+1)); fi; }

# --- capture writes a record with the HWND ---
echo '{"session_id":"abc","cwd":"/home/x/proj"}' | bash "$HOOKS/notify-capture.sh"
ok "capture writes session json" '[[ -f "$CLAUDE_NOTIFY_DIR/sessions/abc.json" ]]'
ok "capture stores hwnd 123456" '[[ "$(jq -r .hwnd "$CLAUDE_NOTIFY_DIR/sessions/abc.json")" == "123456" ]]'

# --- capture ignores non-terminal foreground ---
cat > "$TMP/bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
case "$*" in *capture*) echo "999 explorer" ;; esac
EOF
chmod +x "$TMP/bin/powershell.exe"
echo '{"session_id":"xyz","cwd":"/tmp"}' | bash "$HOOKS/notify-capture.sh"
ok "capture skips non-terminal" '[[ ! -f "$CLAUDE_NOTIFY_DIR/sessions/xyz.json" ]]'

# --- fire passes stored hwnd + done status ---
cat > "$TMP/bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
echo "$@" > "$CLAUDE_NOTIFY_DIR/last_show.txt"
EOF
chmod +x "$TMP/bin/powershell.exe"
echo '{"session_id":"abc","cwd":"/home/x/proj"}' | bash "$HOOKS/notify-fire.sh" done
sleep 0.3
ok "fire forwards stored hwnd" 'grep -q -- "-Hwnd 123456" "$CLAUDE_NOTIFY_DIR/last_show.txt"'
ok "fire sets done event" 'grep -q -- "-Event done" "$CLAUDE_NOTIFY_DIR/last_show.txt"'

# --- fire on unknown session falls back to hwnd 0 ---
echo '{"session_id":"nope","cwd":"/x"}' | bash "$HOOKS/notify-fire.sh" needs-input
sleep 0.3
ok "fire fallback hwnd 0" 'grep -q -- "-Hwnd 0" "$CLAUDE_NOTIFY_DIR/last_show.txt"'
ok "fire needs-input event" 'grep -q -- "-Event needs-input" "$CLAUDE_NOTIFY_DIR/last_show.txt"'

echo "----"; echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
