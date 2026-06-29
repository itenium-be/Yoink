#!/usr/bin/env bash
# SessionStart hook: record the HWND of the terminal that launched this session.
set -uo pipefail
NOTIFY_DIR="${CLAUDE_NOTIFY_DIR:-$HOME/.claude/notify}"
SESS_DIR="$NOTIFY_DIR/sessions"
mkdir -p "$SESS_DIR"

INPUT="$(cat)"
SID="$(jq -r '.session_id // empty' <<<"$INPUT" 2>/dev/null)"
CWD="$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)"
[[ -z "$SID" ]] && exit 0

PS_SCRIPT="${CLAUDE_NOTIFY_PS_CAPTURE:-$(wslpath -w "$NOTIFY_DIR/capture-window.ps1" 2>/dev/null)}"
OUT="$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT" 2>/dev/null | tr -d '\r')"
HWND="${OUT%% *}"
PROC="${OUT#* }"

# Only trust the handle when the foreground window is the terminal host.
if [[ "$PROC" == "WindowsTerminal" || "$PROC" == "wt" ]] && [[ "$HWND" =~ ^[0-9]+$ ]] && [[ "$HWND" != "0" ]]; then
  jq -n --arg hwnd "$HWND" --arg cwd "$CWD" '{hwnd:($hwnd|tonumber), cwd:$cwd}' \
    > "$SESS_DIR/$SID.json"
fi
exit 0
