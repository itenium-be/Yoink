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

# Everything Claude touched: `diff HEAD` spans staged + unstaged in one pass.
DIFFSTAT=""; FILES=""
SHORTSTAT="$(git -C "$CWD" diff HEAD --shortstat 2>/dev/null || true)"
if [[ "$SHORTSTAT" =~ ([0-9]+)\ file ]]; then
  FILES="${BASH_REMATCH[1]}"
  INS=0; [[ "$SHORTSTAT" =~ ([0-9]+)\ insertion ]] && INS="${BASH_REMATCH[1]}"
  DEL=0; [[ "$SHORTSTAT" =~ ([0-9]+)\ deletion  ]] && DEL="${BASH_REMATCH[1]}"
  NOUN="files"; [[ "$FILES" == "1" ]] && NOUN="file"
  DIFFSTAT="$FILES $NOUN +$INS −$DEL"
fi

# A turn_duration record closes a turn, so the current turn is everything after the last
# one that still has an assistant behind it. (last-prompt looks like a turn marker but
# isn't: Claude Code re-emits it mid-turn, which would cut the turn in half.) The same
# record only times the turn once it's the trailing one — mid-turn it belongs to the
# previous turn, and there is no duration to report yet.
# Assistant messages span several records that each repeat message.usage, so dedupe on id.
TURN="$(if [[ -f "$TR" ]]; then jq -s -c '
  ([to_entries[] | select(.value.type == "assistant") | .key] | last // -1) as $last_assistant
  | [to_entries[] | select(.value.subtype == "turn_duration") | .key] as $ends
  | ($ends | map(select(. < $last_assistant)) | last // -1) as $start
  | ($ends | last // -1) as $end
  | .[$start + 1:] as $turn
  | { ms: (if $end > $last_assistant then .[$end].durationMs else null end),
      tokens: ([$turn[] | select(.type == "assistant")] | unique_by(.message.id)
               | map(.message.usage.output_tokens // 0) | add // 0),
      errors: ([$turn[] | select(.type == "user") | .message.content[]?
               | select(type == "object" and .type == "tool_result" and .is_error == true)] | length) }
' "$TR" 2>/dev/null; fi)"
tv() { jq -r "$1 // empty" <<<"${TURN:-null}" 2>/dev/null; }
TOKENS="$(tv .tokens)"; TOKENS="${TOKENS:-0}"
ERRORS="$(tv .errors)"; [[ "$ERRORS" == "0" ]] && ERRORS=""
if   (( TOKENS <= 0 ));   then TOKENS=""
elif (( TOKENS < 1000 )); then :
elif (( TOKENS < 10000 )); then TOKENS="$(( TOKENS / 1000 )).$(( TOKENS % 1000 / 100 ))k"
else TOKENS="$(( TOKENS / 1000 ))k"
fi

DURATION=""
MS="$(tv .ms)"
if [[ "$MS" =~ ^[0-9]+$ ]]; then
  SECS=$(( MS / 1000 ))
  if (( SECS >= 60 )); then DURATION="$(( SECS / 60 ))m$(( SECS % 60 ))s"; else DURATION="${SECS}s"; fi
fi

# Markdown -> a single plain sentence fit for a card headline. Heading lines are blanked
# rather than unwrapped: "## Summary" would otherwise win over the sentence beneath it.
clean_md() {
  local s
  s="$(awk '/^[[:space:]]*```/ { f = !f; next } !f' <<<"$1")"
  s="$(sed -E 's/!\[[^]]*\]\([^)]*\)//g
               s/\[([^]]*)\]\([^)]*\)/\1/g
               s/^[[:space:]]*#+[[:space:]].*$//
               s/^[[:space:]]*>[[:space:]]?//
               s/^[[:space:]]*([-*+]|[0-9]+\.)[[:space:]]+//
               s/[`*~]//g' <<<"$s")"
  s="$(grep -m1 -v '^[[:space:]]*$' <<<"$s")"
  sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/([.!?])[[:space:]].*/\1/' <<<"$s"
}
LCLEAN="$(clean_md "$LASSIST")"
[[ -z "$LCLEAN" ]] && LCLEAN="$LASSIST"

# "1 agent" is the main thread alone, so the badge counts only subagents (count - 1)
# and drops out (blank) when none are running.
if [[ -z "$AGENTS" || "$AGENTS" -le 1 ]]; then AGENTS=""; else AGENTS=$(( AGENTS - 1 )); fi

trunc() { local s="$1" n=300; if (( ${#s} > n )); then printf '%s…' "${s:0:n}"; else printf '%s' "$s"; fi; }
LPROMPT="$(trunc "$LPROMPT")"; LASSIST="$(trunc "$LASSIST")"; LCLEAN="$(trunc "$LCLEAN")"

jq -n \
  --arg folder "$FOLDER" --arg cwd "$CWD" --arg repo "$REPO" --arg branch "$BRANCH" \
  --arg dirty "$DIRTY" --arg message "$MESSAGE" --arg last_prompt "$LPROMPT" \
  --arg last_assistant "$LASSIST" --arg last_assistant_clean "$LCLEAN" \
  --arg model "$MODEL" --arg agents "$AGENTS" \
  --arg pending_tool "$PTOOL" --arg permission_mode "$PERM" --arg event "$EVENT" \
  --arg duration "$DURATION" --arg diff_stat "$DIFFSTAT" --arg files_changed "$FILES" \
  --arg errors "$ERRORS" --arg tokens "$TOKENS" \
  '{folder:$folder,cwd:$cwd,repo:$repo,branch:$branch,dirty:$dirty,message:$message,
    last_prompt:$last_prompt,last_assistant:$last_assistant,last_assistant_clean:$last_assistant_clean,
    model:$model,agents:$agents,pending_tool:$pending_tool,permission_mode:$permission_mode,event:$event,
    duration:$duration,diff_stat:$diff_stat,files_changed:$files_changed,errors:$errors,tokens:$tokens}'
