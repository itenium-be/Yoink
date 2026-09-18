# /yoink — DND, doctor, attach — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the `/yoink` slash command with `off`/`on` (scoped, timed, per-channel), `attach`, and `doctor`, per `docs/superpowers/specs/2026-07-14-yoink-dnd-doctor-attach-design.md`.

**Architecture:** All logic lives in `bin/yoink.sh`; `commands/yoink.md` is a thin wrapper that shells out to it. DND state is a new `~/.claude/yoink/dnd.json` (pure JSON, `jq`-readable) so the `notify-fire.sh` hot path never has to parse the JSONC `settings.json`. The `off-behavior` *default* lives in `settings.json` and is read once, interactively, through a new PowerShell probe script; the resolved value is copied into `dnd.json`. The trusted-terminal HWND capture is extracted from the SessionStart hook into `bin/capture-hwnd.sh` so `/yoink attach` can reuse it.

**Tech Stack:** bash + `jq` (hooks, command), Windows PowerShell 5.1 (renderer, settings probe — `settings.json` is JSONC and only PS can parse it, via `Remove-JsonComments`). Tests are the existing dependency-free `tests/run.sh` harness, which stubs `powershell.exe`.

---

## File Structure

| File                                   | Responsibility                                                                 |
|----------------------------------------|--------------------------------------------------------------------------------|
| `bin/capture-hwnd.sh` **(new)**        | Run `capture-window.ps1`, apply the trusted-terminal allowlist, write `sessions/<sid>.json`. Called by the SessionStart hook and by `/yoink attach`. |
| `bin/yoink.sh` **(new)**               | The `/yoink` dispatcher: `off`, `on`, `attach`, `doctor`. All command logic.    |
| `commands/yoink.md` **(new)**          | Slash-command wrapper. No logic.                                               |
| `settings-probe.ps1` **(new)**         | Parse the user `settings.json` strictly, print `status=` / `error=` / `off-behavior=`. The only JSONC reader bash talks to. |
| `hooks/notify-capture.sh`              | Shrinks to a delegation to `bin/capture-hwnd.sh`.                              |
| `hooks/notify-fire.sh`                 | Gains the DND gate: suppress the card, honour the `allow` channels.            |
| `show-notification.ps1`                | Gains `-SoundOnly`: play the themed wav, create no window.                     |
| `notify-lib.ps1`                       | Gains `Get-OffBehavior` (default `bell`, validates the channel names).         |
| `settings.json`, `settings.schema.json`| The `off-behavior` default + its schema.                                       |
| `tests/run.sh`                         | Extended with the DND / attach / doctor cases.                                 |
| `tests/settings-probe.Tests.sh` **(new)** | Drives the real PowerShell against valid / invalid / missing settings fixtures. |

### `dnd.json` shape

```json
{
  "all":      { "until": 0, "allow": ["bell"] },
  "sessions": { "6f3a": { "until": 1752600000, "allow": [] } },
  "projects": { "/home/x/proj": { "until": 0, "allow": ["bell", "sound"] } }
}
```

`until` is an epoch in seconds, `0` = indefinite. `allow` ⊆ `{bell, sound}` — `card` is never in it, because a card *is* the notification.

---

## Task 1: Extract the HWND capture into `bin/capture-hwnd.sh`

Pure refactor plus a `--force` flag. `notify-capture.sh` keeps behaving exactly as it does today (the existing tests must stay green untouched), and `/yoink attach` gets something to call in Task 5.

**Files:**
- Create: `bin/capture-hwnd.sh`
- Modify: `hooks/notify-capture.sh` (whole file)
- Test: `tests/run.sh`

- [ ] **Step 1: Write the failing tests**

Append to `tests/run.sh`, just after the existing `capture honors YOINK_TERMINALS` block (keep the powershell stub rewriting idiom of the surrounding tests):

```bash
# --- capture-hwnd --force accepts an untrusted host (VS Code / conhost escape hatch) ---
cat > "$TMP/bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
case "$*" in *capture*) echo "444 conhost" ;; esac
EOF
chmod +x "$TMP/bin/powershell.exe"
bash "$(dirname "$0")/../bin/capture-hwnd.sh" "forced" "/tmp/f"
ok "capture-hwnd skips untrusted host without --force" '[[ ! -f "$YOINK_DIR/sessions/forced.json" ]]'
bash "$(dirname "$0")/../bin/capture-hwnd.sh" "forced" "/tmp/f" --force
ok "capture-hwnd --force stores untrusted hwnd" '[[ "$(jq -r .hwnd "$YOINK_DIR/sessions/forced.json" 2>/dev/null)" == "444" ]]'
ok "capture-hwnd --force stores cwd" '[[ "$(jq -r .cwd "$YOINK_DIR/sessions/forced.json" 2>/dev/null)" == "/tmp/f" ]]'
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh`
Expected: the three new `capture-hwnd …` lines FAIL (`bin/capture-hwnd.sh` does not exist). Every pre-existing line still PASSes.

- [ ] **Step 3: Write `bin/capture-hwnd.sh`**

The trust list, the comment explaining why host-based consoles are excluded, and the `YOINK_PS_CAPTURE` override all move here verbatim from `notify-capture.sh`.

```bash
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
```

- [ ] **Step 4: Rewrite `hooks/notify-capture.sh` to delegate**

```bash
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
```

- [ ] **Step 5: Run the tests**

Run: `bash tests/run.sh`
Expected: PASS — including the four pre-existing `capture …` cases, which now exercise the extracted script through the hook.

- [ ] **Step 6: Commit**

```bash
git add bin/capture-hwnd.sh hooks/notify-capture.sh tests/run.sh
git commit -m "Extract HWND capture into bin/capture-hwnd.sh with a --force escape hatch"
```

---

## Task 2: `off-behavior` setting + `settings-probe.ps1`

`settings.json` is JSONC — `jq` cannot read it. This is the one seam through which bash learns the `off-behavior` default and whether the user's settings even parse.

**Files:**
- Create: `settings-probe.ps1`, `tests/settings-probe.Tests.sh`, `tests/fixtures/settings-bad.json`, `tests/fixtures/settings-good.json`
- Modify: `notify-lib.ps1` (append), `settings.json`, `settings.schema.json`, `tests/run.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/settings-probe.Tests.sh`:

```bash
#!/usr/bin/env bash
# settings-probe is the only path by which bash reads the JSONC settings.json.
# Needs the REAL powershell.exe — run it outside the hook stub's PATH.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
PROBE="$(wslpath -w "$ROOT/settings-probe.ps1")"
pass=0; fail=0
ok(){ if eval "$2"; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1"; fail=$((fail+1)); fi; }

probe(){ powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PROBE" -SettingsDir "$(wslpath -w "$1")" | tr -d '\r'; }

GOOD="$(probe "$FIX/probe-good")"
ok "good settings report ok"        '[[ "$GOOD" == *"status=ok"* ]]'
ok "good settings report channels"  '[[ "$GOOD" == *"off-behavior=bell,sound"* ]]'

BAD="$(probe "$FIX/probe-bad")"
ok "bad settings report error"      '[[ "$BAD" == *"status=error"* ]]'
ok "bad settings name the file"     '[[ "$BAD" == *"error="* ]]'

MISSING="$(probe "$FIX/probe-missing")"
ok "missing settings are ok"        '[[ "$MISSING" == *"status=ok"* ]]'
ok "missing settings default bell"  '[[ "$MISSING" == *"off-behavior=bell"* ]]'

echo "----"; echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
```

Create the fixtures:

`tests/fixtures/probe-good/settings.json` — comments included on purpose, they are the point of the JSONC path:
```json
{
  // the off-behavior default, with a comment that jq could never survive
  "off-behavior": ["bell", "sound"]
}
```

`tests/fixtures/probe-bad/settings.json`:
```json
{ "off-behavior": ["bell",, }
```

`tests/fixtures/probe-missing/.keep` — an empty file (the dir exists, `settings.json` does not).

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/settings-probe.Tests.sh`
Expected: FAIL — `settings-probe.ps1` does not exist, so every case fails.

- [ ] **Step 3: Add `Get-OffBehavior` to `notify-lib.ps1`**

Append to `notify-lib.ps1`:

```powershell
# Channels that still fire while DND is active. "card" is never among them: a card *is*
# the notification. Missing key => bell, so you can still see which tab wanted you.
function Get-OffBehavior($cfg) {
  $v = Get-Prop $cfg 'off-behavior'
  if ($null -eq $v) { return @('bell') }
  @(@($v) | Where-Object { $_ -eq 'bell' -or $_ -eq 'sound' })
}
```

- [ ] **Step 4: Write `settings-probe.ps1`**

`Get-NotifyConfig` never throws — it silently falls back to defaults on a parse error, which is exactly what doctor must *not* do. So the probe parses the user file itself.

```powershell
# Bash-readable probe of the user settings.json. Prints key=value lines:
#   status=ok|error   error=<message>   off-behavior=bell,sound
# The only path by which bash learns anything from the JSONC settings file.
param([string]$SettingsDir = "")
. (Join-Path $PSScriptRoot 'notify-lib.ps1')

$path = if ($SettingsDir) { Join-Path $SettingsDir 'settings.json' } else { '' }
if ($path -and (Test-Path $path)) {
  try {
    $raw = Remove-JsonComments (Get-Content -Raw -Encoding UTF8 $path)
    $cfg = $raw | ConvertFrom-Json
  } catch {
    Write-Output "status=error"
    Write-Output ("error=" + ($_.Exception.Message -replace '\r?\n', ' '))
    exit 0
  }
} else {
  $cfg = $null
}
Write-Output "status=ok"
Write-Output ("off-behavior=" + ((Get-OffBehavior $cfg) -join ','))
```

- [ ] **Step 5: Run it to verify it passes**

Run: `bash tests/settings-probe.Tests.sh`
Expected: `6 passed, 0 failed`

- [ ] **Step 6: Wire it into the suite and ship the default + schema**

Add to `tests/run.sh`, in the block at the end that restores the real `PATH` (next to `settings editor seam`):

```bash
ok "settings probe" 'bash "$(dirname "$0")/settings-probe.Tests.sh" >/dev/null 2>&1'
```

Add to `settings.json`, directly under `"play-sound-when-terminal-is-active"`:

```json
  "off-behavior": ["bell"],
```

Add to `settings.schema.json`, in `properties`, directly after `play-sound-when-terminal-is-active`:

```json
    "off-behavior": {
      "type": "array",
      "description": "Channels that still fire while /yoink off is active. The card is always suppressed — a card is the notification. \"bell\" is the ASCII BEL on the session's own tab (your terminal decides whether that flashes or dings). Default [\"bell\"].",
      "items": { "type": "string", "enum": ["bell", "sound"] },
      "uniqueItems": true
    },
```

- [ ] **Step 7: Run the whole suite**

Run: `bash tests/run.sh`
Expected: all PASS, including `settings probe`.

- [ ] **Step 8: Commit**

```bash
git add settings-probe.ps1 notify-lib.ps1 settings.json settings.schema.json tests/settings-probe.Tests.sh tests/fixtures tests/run.sh
git commit -m "Add off-behavior setting and settings-probe.ps1"
```

---

## Task 3: `bin/yoink.sh` — `off` and `on`

**Files:**
- Create: `bin/yoink.sh`
- Test: `tests/run.sh`

- [ ] **Step 1: Write the failing tests**

Append to `tests/run.sh` (after the capture-hwnd block). The stub for `powershell.exe` must answer the probe, so rewrite it first:

```bash
# --- /yoink off | on ---
cat > "$TMP/bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *settings-probe*) printf 'status=ok\noff-behavior=bell\n' ;;
  *capture*) echo "123456 WindowsTerminal" ;;
esac
EOF
chmod +x "$TMP/bin/powershell.exe"
YOINK="$(dirname "$0")/../bin/yoink.sh"
DND="$YOINK_DIR/dnd.json"
export CLAUDE_CODE_SESSION_ID="sid-1"

rm -f "$DND"
bash "$YOINK" off >/dev/null
ok "off defaults to scope all"       '[[ "$(jq -r ".all.until" "$DND")" == "0" ]]'
ok "off copies off-behavior default" '[[ "$(jq -rc ".all.allow" "$DND")" == "[\"bell\"]" ]]'

rm -f "$DND"
bash "$YOINK" off session 2h >/dev/null
ok "off session keys on session id"  '[[ "$(jq -r ".sessions[\"sid-1\"].until" "$DND")" -gt "$(date +%s)" ]]'
ok "off 2h expires in ~2h"           '[[ "$(jq -r ".sessions[\"sid-1\"].until" "$DND")" -le "$(( $(date +%s) + 7200 ))" ]]'

rm -f "$DND"
(cd /tmp && bash "$YOINK" off project --allow bell,sound >/dev/null)
ok "off project keys on cwd"         '[[ "$(jq -rc ".projects[\"/tmp\"].allow" "$DND")" == "[\"bell\",\"sound\"]" ]]'

rm -f "$DND"
bash "$YOINK" off 30m >/dev/null
ok "off takes a bare duration"       '[[ "$(jq -r ".all.until" "$DND")" -gt "$(date +%s)" ]]'

# on with no scope clears everything that could be silencing you here
rm -f "$DND"
bash "$YOINK" off >/dev/null
bash "$YOINK" off session >/dev/null
bash "$YOINK" on >/dev/null
ok "bare on clears all"              '[[ "$(jq -r ".all // \"gone\"" "$DND")" == "gone" ]]'
ok "bare on clears this session"     '[[ "$(jq -r ".sessions[\"sid-1\"] // \"gone\"" "$DND")" == "gone" ]]'

rm -f "$DND"
bash "$YOINK" off >/dev/null
bash "$YOINK" off session >/dev/null
bash "$YOINK" on session >/dev/null
ok "on session keeps all"            '[[ "$(jq -r ".all.until" "$DND")" == "0" ]]'

ok "off rejects a bad duration"      '! bash "$YOINK" off 5x >/dev/null 2>&1'
ok "off rejects a bad scope"         '! bash "$YOINK" off everywhere >/dev/null 2>&1'
```

- [ ] **Step 2: Run to verify they fail**

Run: `bash tests/run.sh`
Expected: the new `off …` / `on …` cases FAIL (`bin/yoink.sh` does not exist).

- [ ] **Step 3: Write `bin/yoink.sh`**

```bash
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

  local key entry now; now="$(date +%s)"
  entry="$(jq -nc --argjson until "$until" --argjson allow "$allow_j" '{until:$until, allow:$allow}')"
  case "$scope" in
    all)     key='.all' ;;
    session) key=".sessions[\"$SID\"]" ;;
    project) key=".projects[\"$PWD\"]" ;;
  esac
  write_dnd "$(read_dnd | jq --argjson now "$now" --argjson e "$entry" "$prune_filter | $key = \$e")"

  local when="until further notice"
  [[ "$until" != 0 ]] && when="until $(date -d "@$until" '+%H:%M')"
  printf 'yoink off (%s) %s — still firing: %s\n' "$scope" "$when" \
    "$(jq -r 'if length == 0 then "nothing" else join(", ") end' <<<"$allow_j")"
}

cmd_on(){
  local scope="${1:-}"
  [[ -n "$scope" && "$scope" != "all" && "$scope" != "session" && "$scope" != "project" ]] \
    && die "unknown scope: $scope (all|session|project)"
  local now; now="$(date +%s)"
  local f
  case "$scope" in
    all)     f='del(.all)' ;;
    session) f="del(.sessions[\"$SID\"])" ;;
    project) f="del(.projects[\"$PWD\"])" ;;
    # Bare `on` clears every scope that could be silencing you here: otherwise
    # `off session` then `on` leaves you muted and convinced yoink is broken.
    *)       f="del(.all) | del(.sessions[\"$SID\"]) | del(.projects[\"$PWD\"])" ;;
  esac
  write_dnd "$(read_dnd | jq --argjson now "$now" "$prune_filter | $f")"
  printf 'yoink on (%s)\n' "${scope:-all scopes here}"
}

case "${1:-}" in
  off)    shift; cmd_off "$@" ;;
  on)     shift; cmd_on "$@" ;;
  *)      die "usage: /yoink off|on [all|session|project] [30m|2h|1d]" ;;
esac
```

- [ ] **Step 4: Run to verify they pass**

Run: `bash tests/run.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add bin/yoink.sh tests/run.sh
git commit -m "Add /yoink off and on with scoped, timed DND state"
```

---

## Task 4: The DND gate in `notify-fire.sh`

**Files:**
- Modify: `hooks/notify-fire.sh:34-43`
- Test: `tests/run.sh`

- [ ] **Step 1: Write the failing tests**

Append to `tests/run.sh`, after the `/yoink off | on` block. The show stub from the earlier fire tests must be back in place:

```bash
# --- DND gates notify-fire ---
cat > "$TMP/bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
echo "$@" > "$YOINK_DIR/last_show.txt"
EOF
chmod +x "$TMP/bin/powershell.exe"
FUTURE=$(( $(date +%s) + 3600 ))
PAST=$(( $(date +%s) - 60 ))
fire(){ rm -f "$YOINK_DIR/last_show.txt"; echo '{"session_id":"abc","cwd":"/home/x/proj"}' | bash "$HOOKS/notify-fire.sh" done; sleep 0.3; }
card_shown(){ [[ -f "$YOINK_DIR/last_show.txt" ]] && ! grep -q -- "-SoundOnly" "$YOINK_DIR/last_show.txt"; }

echo '{"all":{"until":0,"allow":[]}}' > "$DND"
fire
ok "dnd all suppresses the card" '! card_shown'

echo "{\"sessions\":{\"abc\":{\"until\":$FUTURE,\"allow\":[]}}}" > "$DND"
fire
ok "dnd session suppresses the card" '! card_shown'

echo '{"projects":{"/home/x/proj":{"until":0,"allow":[]}}}' > "$DND"
fire
ok "dnd project suppresses the card" '! card_shown'

echo '{"sessions":{"other":{"until":0,"allow":[]}}}' > "$DND"
fire
ok "dnd on another session still notifies" 'card_shown'

echo "{\"all\":{\"until\":$PAST,\"allow\":[]}}" > "$DND"
fire
ok "expired dnd still notifies" 'card_shown'

echo '{"all":{"until":0,"allow":["sound"]}}' > "$DND"
fire
ok "allow sound calls the renderer sound-only" 'grep -q -- "-SoundOnly" "$YOINK_DIR/last_show.txt"'

echo '{"all":{"until":0,"allow":["bell"]}}' > "$DND"
fire
ok "allow bell alone never calls the renderer" '[[ ! -f "$YOINK_DIR/last_show.txt" ]]'

# most restrictive scope wins: a blanket [] is not loosened by a project-level ["sound"]
echo '{"all":{"until":0,"allow":[]},"projects":{"/home/x/proj":{"until":0,"allow":["sound"]}}}' > "$DND"
fire
ok "allow is intersected across scopes" '[[ ! -f "$YOINK_DIR/last_show.txt" ]]'

echo 'not json {{{' > "$DND"
fire
ok "unparseable dnd fails open" 'card_shown'

rm -f "$DND"
fire
ok "no dnd file notifies" 'card_shown'
```

- [ ] **Step 2: Run to verify they fail**

Run: `bash tests/run.sh`
Expected: every `dnd …` / `allow …` case FAILs — the card is shown regardless.

- [ ] **Step 3: Add the gate**

In `hooks/notify-fire.sh`, replace the bell line (currently line 35) — that is, everything between the coalescing block and `HWND=0` — with:

```bash
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

if [[ "$ALLOW" != "GO" && "$ALLOW" != *sound* ]]; then exit 0; fi
```

Then, further down, the renderer call becomes conditional. Replace the existing `powershell.exe … &` invocation (currently lines 54-56) with:

```bash
# Muted but sound-allowed: play the themed wav, draw no card. No context needed — the
# wav comes from the theme, not the body templates.
if [[ "$ALLOW" != "GO" ]]; then
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT" \
    -Hwnd "$HWND" -Event "$EVENT" -SettingsDir "$WSETTINGS" -SoundOnly \
    >>"$LOG" 2>&1 &
  exit 0
fi

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT" \
  -Hwnd "$HWND" -Folder "$FOLDER" -Event "$EVENT" -Context "$WCTX" -SettingsDir "$WSETTINGS" \
  >>"$LOG" 2>&1 &
exit 0
```

- [ ] **Step 4: Run to verify they pass**

Run: `bash tests/run.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/notify-fire.sh tests/run.sh
git commit -m "Gate notifications on DND state in notify-fire"
```

---

## Task 5: `-SoundOnly` in the renderer

The hook now passes `-SoundOnly`; PowerShell must honour it. Today an unknown parameter makes `show-notification.ps1` fail outright, so this is not optional polish.

**Files:**
- Modify: `show-notification.ps1:1-9` (param block), `show-notification.ps1:89-91`
- Test: `tests/show-notification.Tests.sh`

- [ ] **Step 1: Write the failing test**

Append to `tests/show-notification.Tests.sh`, before the final `diff` block — the marker file under `screens/` is written only on the card path, so its absence proves no window was drawn:

```bash
# -SoundOnly: play the wav, draw no card. The per-monitor pid marker is only written on
# the card path, so an untouched screens/ dir is the proof.
MARKERS_BEFORE="$(ls "$ROOT/screens" 2>/dev/null | wc -l)"
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w "$ROOT/show-notification.ps1")" -Event done -Hwnd 0 -SoundOnly >/dev/null 2>&1
RC=$?
MARKERS_AFTER="$(ls "$ROOT/screens" 2>/dev/null | wc -l)"
if [[ "$RC" == "0" && "$MARKERS_BEFORE" == "$MARKERS_AFTER" ]]; then
  echo "ok: -SoundOnly draws no card"
else
  echo "FAIL: -SoundOnly rc=$RC markers $MARKERS_BEFORE -> $MARKERS_AFTER"; exit 1
fi
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/show-notification.Tests.sh`
Expected: FAIL — PowerShell rejects the unknown `-SoundOnly` parameter with a non-zero exit.

- [ ] **Step 3: Add the switch**

In the `param(...)` block of `show-notification.ps1`, add after `[string]$SettingsDir = "",`:

```powershell
  [switch]$SoundOnly,   # DND: play the themed wav, draw no card
```

And directly after the sound block (the `if ([bool]$ev.sound -and …) { … }` that ends on line 89), before `if ($terminalActive) { return }`:

```powershell
if ($SoundOnly) { return }
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/show-notification.Tests.sh`
Expected: `ok: -SoundOnly draws no card` and `ok: default XAML matches golden`.

- [ ] **Step 5: Commit**

```bash
git add show-notification.ps1 tests/show-notification.Tests.sh
git commit -m "Add -SoundOnly to the renderer for DND sound-through"
```

---

## Task 6: `/yoink attach`

**Files:**
- Modify: `bin/yoink.sh` (add `cmd_attach`, extend the dispatcher)
- Test: `tests/run.sh`

- [ ] **Step 1: Write the failing tests**

Append to `tests/run.sh`, after the DND gate block:

```bash
# --- /yoink attach ---
cat > "$TMP/bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *settings-probe*) printf 'status=ok\noff-behavior=bell\n' ;;
  *capture*) echo "777 WindowsTerminal" ;;
esac
EOF
chmod +x "$TMP/bin/powershell.exe"
rm -f "$YOINK_DIR/sessions/sid-1.json"
bash "$YOINK" attach >/dev/null
ok "attach binds the foreground window to this session" \
  '[[ "$(jq -r .hwnd "$YOINK_DIR/sessions/sid-1.json" 2>/dev/null)" == "777" ]]'

cat > "$TMP/bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
case "$*" in *capture*) echo "888 explorer" ;; esac
EOF
chmod +x "$TMP/bin/powershell.exe"
rm -f "$YOINK_DIR/sessions/sid-1.json"
ok "attach refuses an untrusted host" '! bash "$YOINK" attach >/dev/null 2>&1'
bash "$YOINK" attach --force >/dev/null
ok "attach --force takes it anyway" \
  '[[ "$(jq -r .hwnd "$YOINK_DIR/sessions/sid-1.json" 2>/dev/null)" == "888" ]]'
```

- [ ] **Step 2: Run to verify they fail**

Run: `bash tests/run.sh`
Expected: the three `attach …` cases FAIL (unknown subcommand).

- [ ] **Step 3: Implement `cmd_attach`**

Add to `bin/yoink.sh`, above the dispatcher:

```bash
# The SessionStart hook only captures the window if the terminal happened to be focused
# then, and only if its host is on the allowlist. When you type /yoink attach the terminal
# *is* the foreground window by construction — so this is the more reliable capture path,
# not merely a repair.
cmd_attach(){
  [[ -z "$SID" ]] && die "no CLAUDE_CODE_SESSION_ID — cannot bind a window to this session"
  local out
  if out="$(bash "$PLUGIN_ROOT/bin/capture-hwnd.sh" "$SID" "$PWD" "${1:-}" 2>&1)"; then
    printf 'yoink attached to window %s\n' "$out"
  else
    die "$out — focus your terminal and retry, or /yoink attach --force to take it anyway"
  fi
}
```

And extend the dispatcher:

```bash
case "${1:-}" in
  off)    shift; cmd_off "$@" ;;
  on)     shift; cmd_on "$@" ;;
  attach) shift; cmd_attach "$@" ;;
  *)      die "usage: /yoink off|on [all|session|project] [30m|2h|1d] | attach [--force]" ;;
esac
```

- [ ] **Step 4: Run to verify they pass**

Run: `bash tests/run.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add bin/yoink.sh tests/run.sh
git commit -m "Add /yoink attach to bind the foreground window to the session"
```

---

## Task 7: `/yoink doctor`

**Files:**
- Modify: `bin/yoink.sh` (add `cmd_doctor`, extend the dispatcher)
- Test: `tests/run.sh`

- [ ] **Step 1: Write the failing tests**

Append to `tests/run.sh`:

```bash
# --- /yoink doctor ---
cat > "$TMP/bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *settings-probe*) printf 'status=ok\noff-behavior=bell\n' ;;
  *capture*) echo "777 WindowsTerminal" ;;
esac
EOF
chmod +x "$TMP/bin/powershell.exe"
rm -f "$DND"
bash "$YOINK" attach >/dev/null
ok "doctor passes on a healthy install" 'bash "$YOINK" doctor >/dev/null 2>&1'

rm -f "$YOINK_DIR/sessions/sid-1.json"
ok "doctor fails on a missing hwnd record" '! bash "$YOINK" doctor >/dev/null 2>&1'
ok "doctor points at attach"              'bash "$YOINK" doctor 2>&1 | grep -q "/yoink attach"'

bash "$YOINK" attach >/dev/null
cat > "$TMP/bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
case "$*" in *settings-probe*) printf 'status=error\nerror=bad json at line 3\n' ;; esac
EOF
chmod +x "$TMP/bin/powershell.exe"
ok "doctor fails on unparseable settings" '! bash "$YOINK" doctor >/dev/null 2>&1'
ok "doctor surfaces the parse error"      'bash "$YOINK" doctor 2>&1 | grep -q "bad json at line 3"'

cat > "$TMP/bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *settings-probe*) printf 'status=ok\noff-behavior=bell\n' ;;
  *capture*) echo "777 WindowsTerminal" ;;
esac
EOF
chmod +x "$TMP/bin/powershell.exe"
bash "$YOINK" off >/dev/null
ok "doctor reports active dnd" 'bash "$YOINK" doctor 2>&1 | grep -qi "muted"'
bash "$YOINK" on >/dev/null
```

- [ ] **Step 2: Run to verify they fail**

Run: `bash tests/run.sh`
Expected: the `doctor …` cases FAIL (unknown subcommand).

- [ ] **Step 3: Implement `cmd_doctor`**

Add to `bin/yoink.sh`, above the dispatcher:

```bash
cmd_doctor(){
  local rc=0
  check(){ if eval "$2"; then printf '  ok    %s\n' "$1"; else printf '  FAIL  %s — %s\n' "$1" "$3"; rc=1; fi; }

  printf 'yoink doctor\n'
  check "jq on PATH"            'command -v jq >/dev/null'          "install jq"
  check "powershell.exe reachable" 'command -v powershell.exe >/dev/null' "not on PATH from WSL"

  local rec="$YOINK_DIR/sessions/${SID:-none}.json"
  check "window bound to this session" \
    '[[ -n "$SID" && -f "$rec" && "$(jq -r ".hwnd // 0" "$rec" 2>/dev/null)" != "0" ]]' \
    "no HWND record — run /yoink attach"

  local p; p="$(probe)"
  check "settings.json parses" '[[ "$p" == *"status=ok"* ]]' \
    "$(sed -n 's/^error=//p' <<<"$p")"

  check "sounds dir resolves" \
    '[[ -d "$YOINK_DIR/sounds" || -d "$PLUGIN_ROOT/sounds" ]]' "no sounds dir"

  # A silently-muted yoink is the most likely reason anyone runs doctor at all.
  local muted
  muted="$(read_dnd | jq -r --argjson now "$(date +%s)" '
    def alive: .until == 0 or .until > $now;
    [ (if .all != null then "all" else empty end),
      ((.sessions // {}) | keys[] | "session " + .),
      ((.projects // {}) | keys[] | "project " + .) ] as $names
    | [ (.all // empty), ((.sessions // {}) | .[]), ((.projects // {}) | .[]) ]
    | map(select(alive)) | length' 2>/dev/null)"
  if [[ "${muted:-0}" -gt 0 ]]; then
    printf '  note  MUTED — %s active /yoink off scope(s); /yoink on to clear\n' "$muted"
  fi

  return $rc
}
```

Extend the dispatcher:

```bash
case "${1:-}" in
  off)    shift; cmd_off "$@" ;;
  on)     shift; cmd_on "$@" ;;
  attach) shift; cmd_attach "$@" ;;
  doctor) shift; cmd_doctor ;;
  *)      die "usage: /yoink off|on [all|session|project] [30m|2h|1d] | attach [--force] | doctor" ;;
esac
```

- [ ] **Step 4: Run to verify they pass**

Run: `bash tests/run.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add bin/yoink.sh tests/run.sh
git commit -m "Add /yoink doctor"
```

---

## Task 8: The slash command + docs

No tests: `commands/yoink.md` carries no logic, which is the point.

**Files:**
- Create: `commands/yoink.md`
- Modify: `README.md`

- [ ] **Step 1: Write `commands/yoink.md`**

```markdown
---
description: Yoink notifications — mute (off/on), bind the window (attach), self-check (doctor)
argument-hint: off [all|session|project] [30m|2h|1d] | on [scope] | attach [--force] | doctor
allowed-tools: Bash(bash:*)
---

!`bash "${CLAUDE_PLUGIN_ROOT}/bin/yoink.sh" $ARGUMENTS`

Relay the output above to the user verbatim. Add nothing.
```

- [ ] **Step 2: Verify the command registers**

Run: `/yoink doctor` in a fresh Claude Code session with the plugin installed.
Expected: the doctor report, one `ok`/`FAIL` line per check. If the command is not found, the plugin did not pick up `commands/` — check that the dir sits at the plugin root next to `hooks/`.

- [ ] **Step 3: Document it in `README.md`**

Add a `## /yoink` section:

```markdown
## /yoink

| Command                                     | Effect                                                                       |
|---------------------------------------------|------------------------------------------------------------------------------|
| `/yoink off [scope] [duration] [--allow …]` | Mute. Scope `all` (default), `session`, or `project`. Duration `30m`/`2h`/`1d`, omit for indefinite. |
| `/yoink on [scope]`                         | Unmute. Bare `on` clears every scope that could be silencing you here.        |
| `/yoink attach [--force]`                   | Bind the foreground window to this session — fixes a missed HWND capture.     |
| `/yoink doctor`                             | Self-check: jq, powershell.exe, window binding, settings, sounds, active mutes. |

While muted the card never shows. `off-behavior` in `settings.json` picks what still does:

    "off-behavior": ["bell"]

`bell` is the ASCII BEL on the session's own tab — your terminal decides whether that flashes or dings.
`sound` plays the themed wav with no card. `[]` is fully dark.
```

- [ ] **Step 4: Commit**

```bash
git add commands/yoink.md README.md
git commit -m "Add the /yoink slash command and document it"
```

---

## Self-Review

- **Spec coverage:** `dnd.json` shape (T3), `off-behavior` default + copy-into-state (T2, T3), the four subcommands (T3, T6, T7), the fire gate with intersection and fail-open (T4), `-SoundOnly` (T5), shared capture with `--force` (T1), doctor's five checks + DND note (T7), the thin command seam (T8), README (T8). Every spec section maps to a task.
- **Ordering:** T5 (`-SoundOnly`) lands after T4 asserts the hook *passes* the flag against a stub. Do not ship the branch with T4 merged and T5 unmerged — the renderer would reject the unknown parameter at runtime.
- **Naming consistency:** `until` / `allow` / `bell` / `sound`, `bin/yoink.sh`, `bin/capture-hwnd.sh`, `settings-probe.ps1`, `Get-OffBehavior`, `-SoundOnly` are used identically in every task.
