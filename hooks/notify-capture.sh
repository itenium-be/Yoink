#!/usr/bin/env bash
# SessionStart hook: record the HWND of the terminal that launched this session.
set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

INPUT="$(cat)"
SID="$(jq -r '.session_id // empty' <<<"$INPUT" 2>/dev/null)"
CWD="$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)"
[[ -z "$SID" ]] && exit 0

bash "$PLUGIN_ROOT/bin/capture-hwnd.sh" "$SID" "$CWD" >/dev/null 2>&1
exit 0
