#!/usr/bin/env bash
# Tests notify-context.sh token gathering against fixtures.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cp "$FIX/transcript.jsonl" "$TMP/transcript.jsonl"
# Use a non-git cwd so repo/dirty are deterministically empty.
mkdir -p /tmp/notify-ctx-test
STDIN="$(sed "s#TRANSCRIPT_PATH#$TMP/transcript.jsonl#" "$FIX/stdin-needs-input.json")"

OUT="$(printf '%s' "$STDIN" | bash "$ROOT/notify-context.sh" needs-input)"
fail=0
g() { jq -r "$1" <<<"$OUT"; }
check() { if [[ "$(g "$2")" == "$3" ]]; then echo "ok: $1"; else echo "FAIL: $1 -> [$(g "$2")]"; fail=1; fi; }

check "folder"        '.folder'         'notify-ctx-test'
check "message"       '.message'        'Claude needs your permission to use Bash'
check "branch"        '.branch'         'main'
check "model"         '.model'          'claude-sonnet-4'
check "last_prompt"   '.last_prompt'    'fix the flag mascot'
check "last_assistant" '.last_assistant' 'All done with the flag.'
check "agents blank when zero" '.agents' ''
check "event"         '.event'          'needs-input'
check "permission"    '.permission_mode' 'default'
check "last_assistant_clean (plain text passes through)" '.last_assistant_clean' 'All done with the flag.'
check "duration blank without record" '.duration' ''
check "tokens blank without usage"    '.tokens'  ''
check "errors blank when nothing errored" '.errors'  ''
check "diff_stat blank outside a repo"     '.diff_stat'     ''
check "files_changed blank outside a repo" '.files_changed' ''

# "1 agent" is the main thread alone; the badge counts only subagents (count - 1).
agents_for() {
  local count="$1"
  local trf="$TMP/tr-$count.jsonl"
  sed "s#\"pendingBackgroundAgentCount\":0#\"pendingBackgroundAgentCount\":$count#" "$TMP/transcript.jsonl" >"$trf"
  printf '%s' "$STDIN" | sed "s#$TMP/transcript.jsonl#$trf#" | bash "$ROOT/notify-context.sh" needs-input | jq -r '.agents'
}
checke() { if [[ "$(agents_for "$2")" == "$3" ]]; then echo "ok: $1"; else echo "FAIL: $1 -> [$(agents_for "$2")]"; fail=1; fi; }
checke "agents blank when one"  1 ''
checke "agents subtracts one"   2 '1'
checke "agents subtracts one (many)" 5 '4'

# --- turn-scoped tokens: everything after the last prompt, and nothing before it ---
cp "$FIX/transcript-rich.jsonl" "$TMP/rich.jsonl"
RICH_STDIN="$(sed "s#TRANSCRIPT_PATH#$TMP/rich.jsonl#" "$FIX/stdin-needs-input.json")"
OUT="$(printf '%s' "$RICH_STDIN" | bash "$ROOT/notify-context.sh" done)"

check "duration humanized"          '.duration' '2m13s'
# 800 + 500: the previous turn's 999 is out of scope, and the split records that repeat
# one assistant message (same message.id, same usage) must not be counted twice.
check "tokens sums the turn"        '.tokens'   '1.3k'
check "errors counts erroring tools" '.errors'   '2'
check "last_assistant_clean strips markdown, takes the first sentence" \
      '.last_assistant_clean' 'Fixed the flag mascot in mascot-flag-waver.ps1.'

# Re-run the rich transcript with one field patched.
patched() {
  local trf="$TMP/patched.jsonl"
  sed "$1" "$TMP/rich.jsonl" >"$trf"
  printf '%s' "$RICH_STDIN" | sed "s#$TMP/rich.jsonl#$trf#" | bash "$ROOT/notify-context.sh" done | jq -r "$2"
}
checkp() { if [[ "$(patched "$2" "$3")" == "$4" ]]; then echo "ok: $1"; else echo "FAIL: $1 -> [$(patched "$2" "$3")]"; fail=1; fi; }
checkp "duration under a minute" 's#"durationMs":133000#"durationMs":45000#' '.duration' '45s'
checkp "tokens below 1k stay plain" 's#"output_tokens":800#"output_tokens":80#;s#"output_tokens":500#"output_tokens":10#' '.tokens' '90'

# Mid-turn (needs-input): the turn has no closing turn_duration yet, so the previous turn's
# record must neither time this one nor swallow its tokens.
checkp "duration blank mid-turn" '/"durationMs":133000/d' '.duration' ''
checkp "tokens still scoped to the open turn" '/"durationMs":133000/d' '.tokens' '1.3k'

# --- diff_stat / files_changed: working tree + staged, relative to HEAD ---
REPO="$TMP/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main
printf 'one\ntwo\n' >"$REPO/a.txt"
git -C "$REPO" add a.txt
git -C "$REPO" -c user.email=t@t -c user.name=t commit -qm init
repo_ctx() { printf '%s' "$STDIN" | sed "s#/tmp/notify-ctx-test#$REPO#" | bash "$ROOT/notify-context.sh" needs-input; }

OUT="$(repo_ctx)"
check "diff_stat blank on a clean tree"     '.diff_stat'     ''
check "files_changed blank on a clean tree" '.files_changed' ''

printf 'one\nTWO\nthree\n' >"$REPO/a.txt"
OUT="$(repo_ctx)"
check "diff_stat counts one file"  '.diff_stat'     '1 file +2 −1'
check "files_changed counts one"   '.files_changed' '1'

printf 'b\n' >"$REPO/b.txt"
git -C "$REPO" add b.txt
OUT="$(repo_ctx)"
check "diff_stat includes staged"     '.diff_stat'     '2 files +3 −1'
check "files_changed includes staged" '.files_changed' '2'

exit $fail
