#!/usr/bin/env bash
# The /yoink command. All logic lives here; commands/yoink.md is a thin wrapper.
# Usage: yoink.sh off [all|session|project] [30m|2h|1d] [--allow bell,sound]
#        yoink.sh on  [all|session|project]
#        yoink.sh attach [--force]
#        yoink.sh doctor
set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
YOINK_DIR="${YOINK_DIR:-$HOME/.claude/yoink}"
DND="$YOINK_DIR/dnd.json"
SID="${CLAUDE_CODE_SESSION_ID:-}"
mkdir -p "$YOINK_DIR"

die(){ printf '%s\n' "$1" >&2; exit 1; }

# 30m | 2h | 1d -> seconds.
duration_secs(){
  [[ "$1" =~ ^([0-9]+)([mhd])$ ]] || return 1
  local n="${BASH_REMATCH[1]}"
  case "${BASH_REMATCH[2]}" in
    m) echo $((n * 60)) ;;
    h) echo $((n * 3600)) ;;
    d) echo $((n * 86400)) ;;
  esac
}

# The off-behavior default, resolved through the PS probe — settings.json is JSONC and
# jq cannot read it. Falls back to bell if PowerShell is unreachable.
probe(){
  local ps; ps="$(wslpath -w "$PLUGIN_ROOT/settings-probe.ps1" 2>/dev/null)"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ps" \
    -SettingsDir "$(wslpath -w "$YOINK_DIR" 2>/dev/null)" 2>/dev/null | tr -d '\r'
}
default_allow(){
  local v; v="$(probe | sed -n 's/^off-behavior=//p')"
  printf '%s' "${v:-bell}"
}

# csv -> compact json array, keeping only the known channels.
allow_json(){
  local csv="$1" out=()
  IFS=',' read -ra parts <<<"$csv"
  for p in "${parts[@]}"; do
    [[ "$p" == "bell" || "$p" == "sound" ]] && out+=("$p")
  done
  printf '%s' "$(printf '%s\n' "${out[@]:-}" | jq -Rc 'select(length > 0)' | jq -sc '.')"
}

# Drop expired entries on every write; no reaper needed.
prune_filter='
  def alive($now): .until == 0 or .until > $now;
  (if (.all != null and (.all | alive($now))) then {all: .all} else {} end)
  + {sessions: ((.sessions // {}) | with_entries(select(.value | alive($now)))),
     projects: ((.projects // {}) | with_entries(select(.value | alive($now))))}
'

read_dnd(){ [[ -f "$DND" ]] && cat "$DND" || echo '{}'; }
write_dnd(){ printf '%s\n' "$1" > "$DND"; }

cmd_off(){
  local scope="" dur="" allow=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      all|session|project) scope="$1" ;;
      --allow) shift; allow="${1:-}" ;;
      *) duration_secs "$1" >/dev/null || die "unknown argument: $1 (scope: all|session|project, duration: 30m|2h|1d)"; dur="$1" ;;
    esac
    shift
  done
  scope="${scope:-all}"
  [[ "$scope" == "session" && -z "$SID" ]] && die "no CLAUDE_CODE_SESSION_ID — cannot scope to this session"

  local until=0
  [[ -n "$dur" ]] && until=$(( $(date +%s) + $(duration_secs "$dur") ))
  local allow_j; allow_j="$(allow_json "${allow:-$(default_allow)}")"

  local assign entry now; now="$(date +%s)"
  entry="$(jq -nc --argjson until "$until" --argjson allow "$allow_j" '{until:$until, allow:$allow}')"
  # Fixed fragment per scope — the session id / cwd flow in as jq --arg values, never
  # spliced into the program, so a `"` in either can't break the string literal.
  case "$scope" in
    all)     assign='.all = $e' ;;
    session) assign='.sessions[$sid] = $e' ;;
    project) assign='.projects[$proj] = $e' ;;
  esac
  local new
  new="$(read_dnd | jq --argjson now "$now" --arg sid "$SID" --arg proj "$PWD" \
    --argjson e "$entry" "$prune_filter | $assign")" \
    || die "failed to update dnd state (jq error); left dnd.json untouched"
  [[ -n "$new" ]] || die "refusing to write empty dnd state"
  write_dnd "$new"

  local when="until further notice"
  [[ "$until" != 0 ]] && when="until $(date -d "@$until" '+%H:%M')"
  printf 'yoink off (%s) %s — still firing: %s\n' "$scope" "$when" \
    "$(jq -r 'if length == 0 then "nothing" else join(", ") end' <<<"$allow_j")"
}

cmd_on(){
  local scope="${1:-}"
  [[ -n "$scope" && "$scope" != "all" && "$scope" != "session" && "$scope" != "project" ]] \
    && die "unknown scope: $scope (all|session|project)"
  [[ "$scope" == "session" && -z "$SID" ]] && die "no CLAUDE_CODE_SESSION_ID — cannot scope to this session"
  local now; now="$(date +%s)"
  local f
  case "$scope" in
    all)     f='del(.all)' ;;
    session) f='del(.sessions[$sid])' ;;
    project) f='del(.projects[$proj])' ;;
    # Bare `on` clears every scope that could be silencing you here: otherwise
    # `off session` then `on` leaves you muted and convinced yoink is broken.
    *)       f='del(.all) | del(.sessions[$sid]) | del(.projects[$proj])' ;;
  esac
  local new
  new="$(read_dnd | jq --argjson now "$now" --arg sid "$SID" --arg proj "$PWD" \
    "$prune_filter | $f")" \
    || die "failed to update dnd state (jq error); left dnd.json untouched"
  [[ -n "$new" ]] || die "refusing to write empty dnd state"
  write_dnd "$new"
  printf 'yoink on (%s)\n' "${scope:-all scopes here}"
}

case "${1:-}" in
  off)    shift; cmd_off "$@" ;;
  on)     shift; cmd_on "$@" ;;
  *)      die "usage: /yoink off|on [all|session|project] [30m|2h|1d]" ;;
esac
