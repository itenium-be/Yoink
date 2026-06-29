#!/usr/bin/env bash
# Stop/Notification hook. $1 = event: "done" | "needs-input".
set -uo pipefail
EVENT="${1:-done}"
NOTIFY_DIR="${CLAUDE_NOTIFY_DIR:-$HOME/.claude/notify}"
SESS_DIR="$NOTIFY_DIR/sessions"
LOG="$NOTIFY_DIR/notify.log"
mkdir -p "$SESS_DIR" "$NOTIFY_DIR/sounds"

INPUT="$(cat)"
SID="$(jq -r '.session_id // empty' <<<"$INPUT" 2>/dev/null)"
CWD="$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)"
FOLDER="$(basename "${CWD:-$PWD}")"

# Coalesce multi-agent runs: the Stop hook fires once per background agent as each finishes
# and re-wakes the main loop, so a single long job emits many "done"s. Only the final Stop —
# when none are still pending — should notify. pendingBackgroundAgentCount rides on the
# per-turn turn_duration record (absent => 0); the brief sleep lets the just-ended turn flush
# before we read it. Fails open (notifies) if the count can't be read. needs-input is exempt:
# it's a direct request for you and must always surface.
if [[ "$EVENT" == "done" ]]; then
  TRANSCRIPT="$(jq -r '.transcript_path // empty' <<<"$INPUT" 2>/dev/null)"
  if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
    sleep 0.3
    PENDING="$(jq -rc 'select(.type=="system" and .subtype=="turn_duration") | (.pendingBackgroundAgentCount // 0)' "$TRANSCRIPT" 2>/dev/null | tail -1)"
    [[ "$PENDING" =~ ^[1-9][0-9]*$ ]] && exit 0
  fi
fi

# Ring the bell on this session's own terminal tab (flashes the exact tab).
{ printf '\a' > /dev/tty; } 2>/dev/null || true

HWND=0
REC="$SESS_DIR/$SID.json"
[[ -f "$REC" ]] && HWND="$(jq -r '.hwnd // 0' "$REC" 2>/dev/null)"

if [[ "$EVENT" == "needs-input" ]]; then SND="$NOTIFY_DIR/sounds/needs-input.wav";
else EVENT="done"; SND="$NOTIFY_DIR/sounds/done.wav"; fi

PS_SCRIPT="${CLAUDE_NOTIFY_PS_SHOW:-$(wslpath -w "$NOTIFY_DIR/show-notification.ps1" 2>/dev/null)}"
WSND=""
[[ -f "$SND" ]] && WSND="$(wslpath -w "$SND" 2>/dev/null)"

# Gather context tokens ({{message}}, {{branch}}, {{last_prompt}}, ...) for the body templates.
CTX="$SESS_DIR/${SID:-nosid}.ctx.json"
printf '%s' "$INPUT" | bash "$NOTIFY_DIR/notify-context.sh" "$EVENT" > "$CTX" 2>/dev/null || : > "$CTX"
WCTX="$(wslpath -w "$CTX" 2>/dev/null)"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT" \
  -Hwnd "$HWND" -Folder "$FOLDER" -Event "$EVENT" -Sound "$WSND" -Context "$WCTX" \
  >>"$LOG" 2>&1 &
exit 0
