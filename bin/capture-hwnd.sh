#!/usr/bin/env bash
# Capture the foreground window and bind it to a session: writes sessions/<sid>.json.
# Usage: capture-hwnd.sh <session-id> <cwd> [--force]
# Exits 0 on a written record, 1 otherwise (untrusted host, no handle, no session id).
set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
YOINK_DIR="${YOINK_DIR:-$HOME/.claude/yoink}"
SESS_DIR="$YOINK_DIR/sessions"
mkdir -p "$SESS_DIR"

SID="${1:-}"; CWD="${2:-}"; FORCE="${3:-}"
[[ -z "$SID" ]] && exit 1

PS_SCRIPT="${YOINK_PS_CAPTURE:-$(wslpath -w "$PLUGIN_ROOT/capture-window.ps1" 2>/dev/null)}"
OUT="$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT" 2>/dev/null | tr -d '\r')"
HWND="${OUT%% *}"
PROC="${OUT#* }"

# Only trust the handle when the foreground window is a known terminal host.
# Override the list via YOINK_TERMINALS (space-separated process names).
# Host-based consoles (conhost, ConEmu) are excluded on purpose: they hand back a
# child window, not the top-level handle we need to flash/focus. --force takes the
# handle anyway, for users who accept that.
TERMINALS="${YOINK_TERMINALS:-WindowsTerminal wt alacritty wezterm-gui Hyper Tabby}"
trusted=0
for t in $TERMINALS; do [[ "$PROC" == "$t" ]] && { trusted=1; break; }; done
[[ "$FORCE" == "--force" ]] && trusted=1

if [[ "$trusted" == 1 ]] && [[ "$HWND" =~ ^[0-9]+$ ]] && [[ "$HWND" != "0" ]]; then
  jq -n --arg hwnd "$HWND" --arg cwd "$CWD" '{hwnd:($hwnd|tonumber), cwd:$cwd}' \
    > "$SESS_DIR/$SID.json"
  printf '%s %s\n' "$HWND" "$PROC"
  exit 0
fi
printf 'no trusted terminal window (foreground process: %s)\n' "${PROC:-none}" >&2
exit 1
