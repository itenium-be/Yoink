#!/usr/bin/env bash
# Gather notification context tokens as a JSON object on stdout.
# Usage: notify-context.sh <event>   < hook_stdin_json
set -uo pipefail
EVENT="${1:-done}"
INPUT="$(cat)"

j() { jq -r "$1" <<<"$INPUT" 2>/dev/null; }
CWD="$(j '.cwd // empty')"; [[ -z "$CWD" ]] && CWD="$PWD"
TR="$(j '.transcript_path // empty')"
MESSAGE="$(j '.message // empty')"
PERM="$(j '.permission_mode // empty')"
FOLDER="$(basename "$CWD")"

tr_last() { [[ -f "$TR" ]] && jq -r "$1" "$TR" 2>/dev/null | grep -v '^null$' | tail -1 || true; }
BRANCH="$(tr_last 'select(.gitBranch!=null).gitBranch')"
[[ -z "$BRANCH" ]] && BRANCH="$(git -C "$CWD" branch --show-current 2>/dev/null || true)"
MODEL="$(tr_last 'select(.type=="assistant").message.model')"
AGENTS="$(tr_last 'select(.pendingBackgroundAgentCount!=null).pendingBackgroundAgentCount')"
PTOOL="$(tr_last 'select(.type=="assistant").message.content[]?|select(.type=="tool_use").name')"
LPROMPT="$(tr_last 'select(.type=="last-prompt").lastPrompt')"
# Slurped, not tr_last: an assistant message spans multiple lines and tr_last keeps only
# the last one of them.
LASSIST="$([[ -f "$TR" ]] && jq -rs '[.[]|select(.type=="assistant")|.message.content[]?|select(.type=="text").text]|last // empty' "$TR" 2>/dev/null || true)"

REPO=""; TOP="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$TOP" ]] && REPO="$(basename "$TOP")"
DIRTY=""; [[ -n "$(git -C "$CWD" status --porcelain 2>/dev/null)" ]] && DIRTY="●"

# "1 agent" is the main thread alone, so the badge counts only subagents (count - 1)
# and drops out (blank) when none are running.
if [[ -z "$AGENTS" || "$AGENTS" -le 1 ]]; then AGENTS=""; else AGENTS=$(( AGENTS - 1 )); fi

trunc() { local s="$1" n=300; if (( ${#s} > n )); then printf '%s…' "${s:0:n}"; else printf '%s' "$s"; fi; }
LPROMPT="$(trunc "$LPROMPT")"; LASSIST="$(trunc "$LASSIST")"

jq -n \
  --arg folder "$FOLDER" --arg cwd "$CWD" --arg repo "$REPO" --arg branch "$BRANCH" \
  --arg dirty "$DIRTY" --arg message "$MESSAGE" --arg last_prompt "$LPROMPT" \
  --arg last_assistant "$LASSIST" --arg model "$MODEL" --arg agents "$AGENTS" \
  --arg pending_tool "$PTOOL" --arg permission_mode "$PERM" --arg event "$EVENT" \
  '{folder:$folder,cwd:$cwd,repo:$repo,branch:$branch,dirty:$dirty,message:$message,
    last_prompt:$last_prompt,last_assistant:$last_assistant,model:$model,agents:$agents,
    pending_tool:$pending_tool,permission_mode:$permission_mode,event:$event}'
