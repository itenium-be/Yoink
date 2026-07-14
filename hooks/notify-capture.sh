#!/usr/bin/env bash
# SessionStart hook: record the HWND of the terminal that launched this session.
set -uo pipefail
# PLUGIN_ROOT holds the scripts; YOINK_DIR holds user state. Fallback covers dev/manual runs.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
YOINK_DIR="${YOINK_DIR:-$HOME/.claude/yoink}"
SESS_DIR="$YOINK_DIR/sessions"
mkdir -p "$SESS_DIR"

INPUT="$(cat)"
SID="$(jq -r '.session_id // empty' <<<"$INPUT" 2>/dev/null)"
CWD="$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)"
[[ -z "$SID" ]] && exit 0

PS_SCRIPT="${YOINK_PS_CAPTURE:-$(wslpath -w "$PLUGIN_ROOT/capture-window.ps1" 2>/dev/null)}"
OUT="$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT" 2>/dev/null | tr -d '\r')"
HWND="${OUT%% *}"
PROC="${OUT#* }"

# Only trust the handle when the foreground window is a known terminal host.
# Override the list via YOINK_TERMINALS (space-separated process names).
# Host-based consoles (conhost, ConEmu) are excluded on purpose: they hand back a
# child window, not the top-level handle we need to flash/focus.
TERMINALS="${YOINK_TERMINALS:-WindowsTerminal wt alacritty wezterm-gui Hyper Tabby}"
trusted=0
for t in $TERMINALS; do [[ "$PROC" == "$t" ]] && { trusted=1; break; }; done

if [[ "$trusted" == 1 ]] && [[ "$HWND" =~ ^[0-9]+$ ]] && [[ "$HWND" != "0" ]]; then
  jq -n --arg hwnd "$HWND" --arg cwd "$CWD" '{hwnd:($hwnd|tonumber), cwd:$cwd}' \
    > "$SESS_DIR/$SID.json"
fi
exit 0
