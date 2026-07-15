#!/usr/bin/env bash
# Stop/Notification hook. $1 = event: "done" | "needs-input".
set -uo pipefail
EVENT="${1:-done}"
# Two roots: PLUGIN_ROOT holds the scripts (overwritten on every plugin update);
# YOINK_DIR holds user state + settings (must survive updates). The fallback lets the
# hook run from a plain checkout when CLAUDE_PLUGIN_ROOT isn't set (dev / manual use).
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
YOINK_DIR="${YOINK_DIR:-$HOME/.claude/yoink}"
SESS_DIR="$YOINK_DIR/sessions"
LOG="$YOINK_DIR/notify.log"
mkdir -p "$SESS_DIR" "$YOINK_DIR/sounds"

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

# DND (/yoink off). "GO" = not muted. Otherwise the card is always suppressed and only the
# listed channels survive — intersected across every matching scope, so a blanket `off` is
# never loosened by a per-project one. jq output is empty on a missing/corrupt file, which
# is neither "GO" nor a channel list, so we fail open and notify.
DND="$YOINK_DIR/dnd.json"
ALLOW="GO"
if [[ -f "$DND" ]]; then
  OUT="$(jq -r --arg s "$SID" --arg p "$CWD" --argjson now "$(date +%s)" '
    def alive: .until == 0 or .until > $now;
    [ .all, .sessions[$s], .projects[$p] ] | map(select(. != null and alive))
    | if length == 0 then "GO"
      else ( map(.allow)
             | reduce .[] as $a (["bell","sound"]; [ .[] | select(. as $c | $a | index($c)) ])
             | join(",") | if . == "" then "NONE" else . end )
      end' "$DND" 2>/dev/null)"
  [[ -n "$OUT" ]] && ALLOW="$OUT"
fi

# Ring the bell on this session's own terminal tab (flashes the exact tab).
if [[ "$ALLOW" == "GO" || "$ALLOW" == *bell* ]]; then
  { printf '\a' > /dev/tty; } 2>/dev/null || true
fi

[[ "$ALLOW" != "GO" && "$ALLOW" != *sound* ]] && exit 0

HWND=0
REC="$SESS_DIR/$SID.json"
[[ -f "$REC" ]] && HWND="$(jq -r '.hwnd // 0' "$REC" 2>/dev/null)"

[[ "$EVENT" == "needs-input" ]] || EVENT="done"

PS_SCRIPT="${YOINK_PS_SHOW:-$(wslpath -w "$PLUGIN_ROOT/show-notification.ps1" 2>/dev/null)}"

# -SettingsDir points the renderer at the user dir so its settings.json + sound overrides
# win over the bundled defaults that ship inside the plugin.
WSETTINGS="$(wslpath -w "$YOINK_DIR" 2>/dev/null)"

# Muted but sound-allowed: play the themed wav, draw no card. No context needed — the
# wav comes from the theme, not the body templates.
if [[ "$ALLOW" != "GO" ]]; then
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT" \
    -Hwnd "$HWND" -Event "$EVENT" -SettingsDir "$WSETTINGS" -SoundOnly \
    >>"$LOG" 2>&1 &
  exit 0
fi

# Gather context tokens ({{message}}, {{branch}}, {{last_prompt}}, ...) for the body templates.
CTX="$SESS_DIR/${SID:-nosid}.ctx.json"
printf '%s' "$INPUT" | bash "$PLUGIN_ROOT/notify-context.sh" "$EVENT" > "$CTX" 2>/dev/null || : > "$CTX"
WCTX="$(wslpath -w "$CTX" 2>/dev/null)"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT" \
  -Hwnd "$HWND" -Folder "$FOLDER" -Event "$EVENT" -Context "$WCTX" -SettingsDir "$WSETTINGS" \
  >>"$LOG" 2>&1 &
exit 0
