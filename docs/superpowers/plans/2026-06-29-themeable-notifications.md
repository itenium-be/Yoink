# Themeable Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drive the notification popup's theme, per-event styling, and body text from a `settings.json` of 9 themes plus `{{token}}` body templates, falling back to today's exact look when the file is absent.

**Architecture:** Pure helpers (config load/merge, gradient-stop XAML, body templating) live in a dot-sourceable `notify-lib.ps1` so they can be unit-tested without WPF. `show-notification.ps1` resolves the active theme + event and inlines those values into its XAML, rendering the body into a dynamic `bodyPanel`. A new `notify-context.sh` gathers context tokens into `sessions/$SID.ctx.json`; `notify-fire.sh` calls it and passes the path via `-Context`.

**Tech Stack:** Windows PowerShell 5.1 (WPF/XAML, `ConvertFrom-Json`), Bash + `jq`, all on WSL invoking `powershell.exe`. No third-party modules; tests are dependency-free assertion scripts.

**Spec:** `docs/superpowers/specs/2026-06-29-themeable-notifications-design.md`

---

## Addendum (2026-06-29): architecture correction after Task 6

Tasks 1–6 (`settings.json`, `notify-lib.ps1`, `notify-context.sh`) are architecture-independent and stand as committed. Task 7 was written against a **monolithic** `show-notification.ps1`, but the renderer was since refactored into a thin orchestrator (`show-notification.ps1`) plus `lib/` modules — the XAML/card build lives in `lib/notification-box.ps1` (`New-NotificationBox`), and mascots are **PNG-flipbook choreography** (`lib/mascot-player.ps1`: look → jump → confetti/flag-wave), not emoji/fireworks. Decisions:

- **`palette` is removed** from the theme model (settings.json, `Get-NotifyDefaults`, `Resolve-Theme`, tests). Fireworks particle colours derive from the theme `gradient` via a new pure helper `Get-StopColors`.
- **`indicator` is kept** and re-wired as a small themed badge on the card, shown **alongside** the flipbook mascot: emoji (👋) → self-animating waving Rectangle filled by the theme gradient; `"fireworks"` → an `fx` Canvas burst coloured from `Get-StopColors $theme.gradient`.
- Task 7 integrates into `lib/notification-box.ps1` + the orchestrator (dot-source `notify-lib.ps1`, resolve config, pass `$theme`/`$ev`/body lines into `New-NotificationBox`; `-Context`/`-EmitXaml` on the orchestrator). See revised Tasks 7a/7b below.

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `settings.json` (new) | All theme + event + body data. The only file a user edits to restyle. |
| `notify-lib.ps1` (new) | Pure helpers: defaults, config load/merge, theme/event resolution, gradient-stop XAML, body templating. No WPF. |
| `show-notification.ps1` (modify) | Dot-source the lib; inline resolved theme/event into XAML; render `bodyPanel`; add `-Context`/`-EmitXaml`. |
| `notify-context.sh` (new) | Gather context tokens from hook stdin + transcript + git → JSON on stdout. |
| `~/.claude/hooks/notify-fire.sh` (modify) | Call `notify-context.sh`, write ctx file, pass `-Context`. |
| `tests/notify-lib.Tests.ps1` (new) | Assertion tests for `notify-lib.ps1`. |
| `tests/notify-context.Tests.sh` (new) | Assertion tests for `notify-context.sh` with fixtures. |
| `tests/fixtures/` (new) | Fixture hook-stdin JSON + transcript JSONL. |
| `tests/golden/` (new) | Golden `-EmitXaml` output for the default (no-config) render. |

**Testing note:** PowerShell tests are run with
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w <path>)"`.
Each test script dot-sources the unit under test, asserts with a local `Assert-Eq`,
and `exit 1`s on any failure. Bash tests run directly under WSL.

---

## Task 1: settings.json with all 9 themes

**Files:**
- Create: `settings.json`
- Create: `tests/settings.Tests.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/settings.Tests.sh`:

```bash
#!/usr/bin/env bash
# Validates settings.json parses and exposes the expected structure.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
F="$ROOT/settings.json"
fail=0
check() { if eval "$2"; then echo "ok: $1"; else echo "FAIL: $1"; fail=1; fi; }

check "file exists"            "[[ -f '$F' ]]"
check "valid json"            "jq -e . '$F' >/dev/null"
check "activeTheme present"   "[[ -n \"\$(jq -r '.activeTheme' '$F')\" ]]"
check "9 themes"              "[[ \"\$(jq '.themes|length' '$F')\" == '9' ]]"
check "unicorn theme"         "jq -e '.themes.unicorn' '$F' >/dev/null"
check "needs-input body array" "jq -e '.events[\"needs-input\"].body|type==\"array\"' '$F' >/dev/null"
check "done body array"       "jq -e '.events.done.body|type==\"array\"' '$F' >/dev/null"
check "every theme has hero/gradient/rim/card/palette" \
  "[[ \"\$(jq '[.themes[]|select(.hero and .gradient and .rim and .card and .palette)]|length' '$F')\" == '9' ]]"

exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/settings.Tests.sh`
Expected: FAIL "file exists" (settings.json not created yet).

- [ ] **Step 3: Create settings.json**

Create `settings.json` (UTF-8, no BOM):

```json
{
  "activeTheme": "unicorn",
  "events": {
    "needs-input": {
      "label": "Needs you", "accent": "#FF7A18", "indicator": "👋", "mascot": "flag", "sound": "exclamation",
      "body": [
        { "text": "{{message}}",            "style": "headline" },
        { "text": "{{folder}} · {{branch}}", "style": "sub" },
        { "text": "{{last_prompt}}",         "style": "muted" }
      ]
    },
    "done": {
      "label": "Done!", "accent": "#22C55E", "indicator": "fireworks", "mascot": "confetti", "sound": "asterisk",
      "body": [
        { "text": "{{last_assistant}}",       "style": "headline" },
        { "text": "{{folder}} · {{branch}}",   "style": "sub" },
        { "text": "{{agents}} agents running", "style": "muted" }
      ]
    }
  },
  "themes": {
    "unicorn": {
      "hero": "🦄",
      "gradient": ["#FF5F6D 0", "#FFC371 0.28", "#3CFFB0 0.5", "#36D1DC 0.72", "#A56BFF 1"],
      "rim": ["#7C3AED 0", "#2563EB 0.17", "#06B6D4 0.34", "#22C55E 0.5", "#EAB308 0.67", "#F97316 0.84", "#EC4899 1"],
      "card": "#18181B",
      "palette": ["#FF5F6D", "#FFC371", "#FFD93D", "#3CFFB0", "#36D1DC", "#A56BFF", "#EC4899"]
    },
    "cosmic": {
      "hero": "🚀",
      "gradient": ["#3A1C71 0", "#5B2A86 0.3", "#7B2FF7 0.55", "#2C7DFA 0.8", "#22D3EE 1"],
      "rim": ["#1E1B4B 0", "#4338CA 0.25", "#7C3AED 0.5", "#2563EB 0.75", "#06B6D4 1"],
      "card": "#0B0B1A",
      "palette": ["#A78BFA", "#7C3AED", "#22D3EE", "#2563EB", "#E879F9", "#F0ABFC"]
    },
    "ocean": {
      "hero": "🐳",
      "gradient": ["#0EA5E9 0", "#22D3EE 0.3", "#2DD4BF 0.6", "#14B8A6 0.8", "#0891B2 1"],
      "rim": ["#0C4A6E 0", "#0369A1 0.25", "#0891B2 0.5", "#06B6D4 0.75", "#14B8A6 1"],
      "card": "#0A1620",
      "palette": ["#7DD3FC", "#22D3EE", "#2DD4BF", "#5EEAD4", "#38BDF8"]
    },
    "sakura": {
      "hero": "🌸",
      "gradient": ["#FF8FB1 0", "#FFB7C5 0.3", "#FBC2EB 0.6", "#E0AAFF 0.85", "#C8A2FF 1"],
      "rim": ["#DB2777 0", "#EC4899 0.25", "#F472B6 0.5", "#E879F9 0.75", "#C084FC 1"],
      "card": "#1A1620",
      "palette": ["#FBCFE8", "#F9A8D4", "#F472B6", "#E9D5FF", "#C4B5FD"]
    },
    "matrix": {
      "hero": "👾",
      "gradient": ["#00FF41 0", "#22C55E 0.35", "#16A34A 0.6", "#00C853 0.8", "#39FF14 1"],
      "rim": ["#052E16 0", "#14532D 0.25", "#16A34A 0.5", "#22C55E 0.75", "#4ADE80 1"],
      "card": "#050A05",
      "palette": ["#39FF14", "#22C55E", "#4ADE80", "#86EFAC", "#00FF41"]
    },
    "dragon": {
      "hero": "🐉",
      "gradient": ["#7F1D1D 0", "#DC2626 0.3", "#F97316 0.6", "#FBBF24 0.85", "#FDE047 1"],
      "rim": ["#450A0A 0", "#991B1B 0.25", "#DC2626 0.5", "#EA580C 0.75", "#F59E0B 1"],
      "card": "#1A0F0A",
      "palette": ["#FCA5A5", "#F87171", "#FB923C", "#FBBF24", "#FDE047"]
    },
    "vaporwave": {
      "hero": "🌴",
      "gradient": ["#FF6AD5 0", "#C774E8 0.3", "#AD8CFF 0.55", "#8795E8 0.8", "#94D0FF 1"],
      "rim": ["#FF71CE 0", "#B967FF 0.25", "#01CDFE 0.5", "#05FFA1 0.75", "#FFFB96 1"],
      "card": "#160F1F",
      "palette": ["#FF6AD5", "#C774E8", "#AD8CFF", "#8795E8", "#94D0FF"]
    },
    "robot": {
      "hero": "🤖",
      "gradient": ["#94A3B8 0", "#64748B 0.3", "#38BDF8 0.6", "#0EA5E9 0.8", "#22D3EE 1"],
      "rim": ["#1E293B 0", "#334155 0.25", "#475569 0.5", "#0EA5E9 0.75", "#38BDF8 1"],
      "card": "#0E141B",
      "palette": ["#CBD5E1", "#94A3B8", "#38BDF8", "#22D3EE", "#7DD3FC"]
    },
    "spooky": {
      "hero": "🎃",
      "gradient": ["#F97316 0", "#EA580C 0.3", "#7C2D12 0.55", "#6B21A8 0.8", "#4C1D95 1"],
      "rim": ["#7C2D12 0", "#9A3412 0.25", "#EA580C 0.5", "#6B21A8 0.75", "#4C1D95 1"],
      "card": "#100A14",
      "palette": ["#FB923C", "#F97316", "#A855F7", "#7C3AED", "#FDE047"]
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/settings.Tests.sh`
Expected: every line `ok:`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add settings.json tests/settings.Tests.sh
git commit -m "Add settings.json with 9 notification themes"
```

---

## Task 2: notify-lib.ps1 — defaults + property helpers

**Files:**
- Create: `notify-lib.ps1`
- Create: `tests/notify-lib.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/notify-lib.Tests.ps1`:

```powershell
. "$PSScriptRoot\..\notify-lib.ps1"

$script:fail = 0
function Assert-Eq($got, $exp, $msg) {
  if ("$got" -ne "$exp") { Write-Host "FAIL: $msg`n  exp=[$exp]`n  got=[$got]"; $script:fail++ }
  else { Write-Host "ok: $msg" }
}

# --- Get-Prop ---
$h = @{ a = 1 }
$o = [pscustomobject]@{ a = 2 }
Assert-Eq (Get-Prop $h 'a') 1 "Get-Prop hashtable"
Assert-Eq (Get-Prop $o 'a') 2 "Get-Prop pscustomobject"
Assert-Eq (Get-Prop $null 'a') '' "Get-Prop null -> empty"
Assert-Eq (Get-Prop $h 'missing') '' "Get-Prop missing -> empty"

# --- Coalesce ---
Assert-Eq (Coalesce '' $null 'x') 'x' "Coalesce skips empty/null"
Assert-Eq (Coalesce 'a' 'b') 'a' "Coalesce first non-empty"

# --- Defaults ---
$d = Get-NotifyDefaults
Assert-Eq $d.activeTheme 'unicorn' "defaults activeTheme"
Assert-Eq $d.themes.unicorn.hero '🦄' "defaults unicorn hero"
Assert-Eq $d.events['needs-input'].body[0].text '{{folder}}' "defaults needs-input body is folder"

if ($script:fail -gt 0) { exit 1 } else { Write-Host "ALL PASS" }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w tests/notify-lib.Tests.ps1)"`
Expected: FAIL — `notify-lib.ps1` not found / functions undefined.

- [ ] **Step 3: Create notify-lib.ps1**

Create `notify-lib.ps1`:

```powershell
# Pure helpers for show-notification.ps1. No WPF — dot-sourceable and unit-testable.

# Read a property from either a hashtable or a (JSON-derived) PSCustomObject.
function Get-Prop($obj, [string]$name) {
  if ($null -eq $obj) { return $null }
  if ($obj -is [hashtable]) { return $obj[$name] }
  $p = $obj.PSObject.Properties[$name]
  if ($p) { return $p.Value } else { return $null }
}

# First argument that is neither $null nor an empty string.
function Coalesce {
  foreach ($v in $args) { if ($null -ne $v -and "$v" -ne '') { return $v } }
  return $null
}

# Built-in fallback config — identical to the pre-config hardcoded look.
function Get-NotifyDefaults {
  @{
    activeTheme = 'unicorn'
    events = @{
      'needs-input' = @{ label='Needs you'; accent='#FF7A18'; indicator='👋'; mascot='flag'; sound='exclamation';
        body=@(@{ text='{{folder}}'; style='sub' }) }
      'done' = @{ label='Done!'; accent='#22C55E'; indicator='fireworks'; mascot='confetti'; sound='asterisk';
        body=@(@{ text='{{folder}}'; style='sub' }) }
    }
    themes = @{
      unicorn = @{
        hero='🦄'
        gradient=@('#FF5F6D 0','#FFC371 0.28','#3CFFB0 0.5','#36D1DC 0.72','#A56BFF 1')
        rim=@('#7C3AED 0','#2563EB 0.17','#06B6D4 0.34','#22C55E 0.5','#EAB308 0.67','#F97316 0.84','#EC4899 1')
        card='#18181B'
        palette=@('#FF5F6D','#FFC371','#FFD93D','#3CFFB0','#36D1DC','#A56BFF','#EC4899')
      }
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w tests/notify-lib.Tests.ps1)"`
Expected: all `ok:`, prints `ALL PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add notify-lib.ps1 tests/notify-lib.Tests.ps1
git commit -m "Add notify-lib defaults and property helpers"
```

---

## Task 3: notify-lib.ps1 — New-GradientStops

**Files:**
- Modify: `notify-lib.ps1`
- Modify: `tests/notify-lib.Tests.ps1`

- [ ] **Step 1: Add the failing test**

In `tests/notify-lib.Tests.ps1`, insert before the final `if ($script:fail ...)`:

```powershell
# --- New-GradientStops ---
Assert-Eq (New-GradientStops @('#FF0000 0','#00FF00 1')) `
  "<GradientStop Color=`"#FF0000`" Offset=`"0`"/>`n<GradientStop Color=`"#00FF00`" Offset=`"1`"/>" `
  "gradient stops -> xaml"
Assert-Eq (New-GradientStops @('bad','#0000FF 0.5')) `
  "<GradientStop Color=`"#0000FF`" Offset=`"0.5`"/>" `
  "gradient skips unparseable stop"
Assert-Eq (New-GradientStops @('#123456')) '' "stop without offset skipped"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w tests/notify-lib.Tests.ps1)"`
Expected: FAIL — `New-GradientStops` not defined.

- [ ] **Step 3: Implement New-GradientStops**

Append to `notify-lib.ps1`:

```powershell
# ["#RRGGBB offset", ...] -> newline-joined <GradientStop/> XAML. Unparseable stops are skipped.
function New-GradientStops([string[]]$stops) {
  $out = foreach ($s in $stops) {
    $parts = (($s -replace '\s+', ' ').Trim()) -split ' '
    if ($parts.Count -lt 2) { continue }
    $color = $parts[0]; $offset = $parts[1]
    if ($color -notmatch '^#[0-9A-Fa-f]{6}$') { continue }
    "<GradientStop Color=`"$color`" Offset=`"$offset`"/>"
  }
  ($out -join "`n")
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w tests/notify-lib.Tests.ps1)"`
Expected: `ALL PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add notify-lib.ps1 tests/notify-lib.Tests.ps1
git commit -m "Add New-GradientStops helper"
```

---

## Task 4: notify-lib.ps1 — config load + theme/event resolution

**Files:**
- Modify: `notify-lib.ps1`
- Modify: `tests/notify-lib.Tests.ps1`

- [ ] **Step 1: Add the failing test**

In `tests/notify-lib.Tests.ps1`, insert before the final `if`:

```powershell
# --- Get-NotifyConfig / resolution (uses repo settings.json one dir up) ---
$cfg = Get-NotifyConfig (Join-Path $PSScriptRoot '..')
Assert-Eq (Resolve-ThemeName $cfg) 'unicorn' "active theme name from settings.json"

$theme = Resolve-Theme $cfg 'ocean'
Assert-Eq $theme.hero '🐳' "resolve named theme hero"
$missing = Resolve-Theme $cfg 'nope'
Assert-Eq $missing.hero '🦄' "unknown theme -> unicorn default"

$ev = Resolve-Event $cfg 'needs-input'
Assert-Eq $ev.label 'Needs you' "resolve event label"
Assert-Eq $ev.indicator '👋' "resolve event indicator"
Assert-Eq $ev.body[1].text '{{folder}} · {{branch}}' "resolve event body line"

# Missing file -> defaults (today's look)
$dcfg = Get-NotifyConfig 'C:\does\not\exist'
Assert-Eq (Resolve-Theme $dcfg 'unicorn').card '#18181B' "missing config -> default theme"
Assert-Eq (Resolve-Event $dcfg 'done').body[0].text '{{folder}}' "missing config -> default body"

# random resolves to one of the configured names
$names = $cfg.themes.PSObject.Properties.Name
$r = Resolve-ThemeName ([pscustomobject]@{ activeTheme='random'; themes=$cfg.themes })
Assert-Eq ($names -contains $r) 'True' "random theme name is a configured theme"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w tests/notify-lib.Tests.ps1)"`
Expected: FAIL — `Get-NotifyConfig`/`Resolve-*` not defined.

- [ ] **Step 3: Implement config + resolution**

Append to `notify-lib.ps1`:

```powershell
# Load settings.json from $Dir if present; otherwise return built-in defaults. Never throws.
function Get-NotifyConfig([string]$Dir) {
  $path = Join-Path $Dir 'settings.json'
  if (Test-Path $path) {
    try {
      return (Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json)
    } catch {
      Write-Warning "notify: failed to parse settings.json: $($_.Exception.Message)"
    }
  }
  return Get-NotifyDefaults
}

# Enumerate theme names from either shape.
function Get-ThemeNames($cfg) {
  $themes = Get-Prop $cfg 'themes'
  if ($themes -is [hashtable]) { return @($themes.Keys) }
  if ($themes) { return @($themes.PSObject.Properties.Name) }
  return @('unicorn')
}

# Active theme name; "random" picks one of the configured themes.
function Resolve-ThemeName($cfg) {
  $name = Coalesce (Get-Prop $cfg 'activeTheme') 'unicorn'
  if ($name -eq 'random') { $name = Get-ThemeNames $cfg | Get-Random }
  return $name
}

# A theme as a hashtable, every field falling back to the unicorn default.
function Resolve-Theme($cfg, [string]$name) {
  $def = (Get-NotifyDefaults).themes.unicorn
  $t = Get-Prop (Get-Prop $cfg 'themes') $name
  @{
    hero     = (Coalesce (Get-Prop $t 'hero')     $def.hero)
    gradient = (Coalesce (Get-Prop $t 'gradient') $def.gradient)
    rim      = (Coalesce (Get-Prop $t 'rim')      $def.rim)
    card     = (Coalesce (Get-Prop $t 'card')     $def.card)
    palette  = (Coalesce (Get-Prop $t 'palette')  $def.palette)
  }
}

# An event as a hashtable, every field falling back to that event's default.
function Resolve-Event($cfg, [string]$event) {
  $defs = (Get-NotifyDefaults).events
  $def = $defs[$event]; if ($null -eq $def) { $def = $defs['done'] }
  $e = Get-Prop (Get-Prop $cfg 'events') $event
  @{
    label     = (Coalesce (Get-Prop $e 'label')     $def.label)
    accent    = (Coalesce (Get-Prop $e 'accent')    $def.accent)
    indicator = (Coalesce (Get-Prop $e 'indicator') $def.indicator)
    mascot    = (Coalesce (Get-Prop $e 'mascot')    $def.mascot)
    sound     = (Coalesce (Get-Prop $e 'sound')     $def.sound)
    body      = (Coalesce (Get-Prop $e 'body')      $def.body)
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w tests/notify-lib.Tests.ps1)"`
Expected: `ALL PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add notify-lib.ps1 tests/notify-lib.Tests.ps1
git commit -m "Add config load and theme/event resolution"
```

---

## Task 5: notify-lib.ps1 — Resolve-BodyLines (token templating)

**Files:**
- Modify: `notify-lib.ps1`
- Modify: `tests/notify-lib.Tests.ps1`

- [ ] **Step 1: Add the failing test**

In `tests/notify-lib.Tests.ps1`, insert before the final `if`:

```powershell
# --- Resolve-BodyLines ---
$ctx = @{ folder='notify'; branch=''; message='Needs permission'; agents=''; last_prompt='fix flag' }

$body = @(
  @{ text='{{message}}';             style='headline' },
  @{ text='{{folder}} · {{branch}}';  style='sub' },
  @{ text='{{agents}} agents running'; style='muted' },
  @{ text='{{last_prompt}}';          style='weird' }
)
$lines = @(Resolve-BodyLines $body $ctx)
Assert-Eq $lines.Count 3 "all-empty 'agents' line dropped"
Assert-Eq $lines[0].text 'Needs permission' "headline resolved"
Assert-Eq $lines[0].style 'headline' "headline style kept"
Assert-Eq $lines[1].text 'notify' "empty branch -> dangling separator trimmed"
Assert-Eq $lines[2].text 'fix flag' "muted line resolved"
Assert-Eq $lines[2].style 'sub' "unknown style normalised to sub"

# both tokens empty -> whole line dropped
$lines2 = @(Resolve-BodyLines @(@{ text='{{folder}} · {{branch}}'; style='sub' }) @{ folder=''; branch='' })
Assert-Eq $lines2.Count 0 "line with all-empty tokens dropped"

# pure literal always kept
$lines3 = @(Resolve-BodyLines @(@{ text='hello'; style='sub' }) @{})
Assert-Eq $lines3.Count 1 "pure literal kept"
Assert-Eq $lines3[0].text 'hello' "pure literal text"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w tests/notify-lib.Tests.ps1)"`
Expected: FAIL — `Resolve-BodyLines` not defined.

- [ ] **Step 3: Implement Resolve-BodyLines**

Append to `notify-lib.ps1`:

```powershell
# Body templates + context -> cleaned, styled lines.
# Rules: a line whose tokens ALL resolve empty is dropped whole; otherwise dangling
# separator chars are trimmed; empty results are dropped; pure-literal lines are kept.
function Resolve-BodyLines($body, [hashtable]$ctx) {
  $rx = [regex]'\{\{(\w+)\}\}'
  $sep = " `t·-|/".ToCharArray()
  $out = @()
  foreach ($line in $body) {
    $tpl   = [string](Get-Prop $line 'text')
    $style = [string](Get-Prop $line 'style')
    if (@('headline','sub','muted') -notcontains $style) { $style = 'sub' }

    $names = @($rx.Matches($tpl) | ForEach-Object { $_.Groups[1].Value })
    $vals = @{}; $anyVal = $false
    foreach ($n in $names) {
      $v = ''
      if ($ctx.ContainsKey($n)) { $v = [string]$ctx[$n] }
      $vals[$n] = $v
      if ($v -ne '') { $anyVal = $true }
    }
    if ($names.Count -ge 1 -and -not $anyVal) { continue }

    $text = $rx.Replace($tpl, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $vals[$m.Groups[1].Value] })
    $text = ($text -replace '\s+', ' ').Trim().Trim($sep).Trim()
    if ($text -eq '') { continue }
    $out += @{ text = $text; style = $style }
  }
  ,$out
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w tests/notify-lib.Tests.ps1)"`
Expected: `ALL PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add notify-lib.ps1 tests/notify-lib.Tests.ps1
git commit -m "Add body template resolution with cleaning rules"
```

---

## Task 6: notify-context.sh — gather context tokens

**Files:**
- Create: `notify-context.sh`
- Create: `tests/notify-context.Tests.sh`
- Create: `tests/fixtures/stdin-needs-input.json`
- Create: `tests/fixtures/transcript.jsonl`

- [ ] **Step 1: Write the failing test and fixtures**

Create `tests/fixtures/stdin-needs-input.json`:

```json
{"session_id":"test-sid","cwd":"/tmp/notify-ctx-test","transcript_path":"TRANSCRIPT_PATH","message":"Claude needs your permission to use Bash","permission_mode":"default","hook_event_name":"Notification"}
```

Create `tests/fixtures/transcript.jsonl`:

```jsonl
{"type":"last-prompt","lastPrompt":"fix the flag mascot"}
{"type":"assistant","gitBranch":"main","message":{"model":"claude-sonnet-4","content":[{"type":"text","text":"All done with the flag."}]}}
{"pendingBackgroundAgentCount":0}
```

Create `tests/notify-context.Tests.sh`:

```bash
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

exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/notify-context.Tests.sh`
Expected: FAIL — `notify-context.sh` not found.

- [ ] **Step 3: Implement notify-context.sh**

Create `notify-context.sh`:

```bash
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
LASSIST="$(tr_last 'select(.type=="assistant").message.content[]?|select(.type=="text").text')"

REPO=""; TOP="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$TOP" ]] && REPO="$(basename "$TOP")"
DIRTY=""; [[ -n "$(git -C "$CWD" status --porcelain 2>/dev/null)" ]] && DIRTY="●"

# Blank a zero/empty agent count so the "{{agents}} agents running" line drops out.
[[ "$AGENTS" == "0" || -z "$AGENTS" ]] && AGENTS=""

trunc() { local s="$1" n=120; if (( ${#s} > n )); then printf '%s…' "${s:0:n}"; else printf '%s' "$s"; fi; }
LPROMPT="$(trunc "$LPROMPT")"; LASSIST="$(trunc "$LASSIST")"

jq -n \
  --arg folder "$FOLDER" --arg cwd "$CWD" --arg repo "$REPO" --arg branch "$BRANCH" \
  --arg dirty "$DIRTY" --arg message "$MESSAGE" --arg last_prompt "$LPROMPT" \
  --arg last_assistant "$LASSIST" --arg model "$MODEL" --arg agents "$AGENTS" \
  --arg pending_tool "$PTOOL" --arg permission_mode "$PERM" --arg event "$EVENT" \
  '{folder:$folder,cwd:$cwd,repo:$repo,branch:$branch,dirty:$dirty,message:$message,
    last_prompt:$last_prompt,last_assistant:$last_assistant,model:$model,agents:$agents,
    pending_tool:$pending_tool,permission_mode:$permission_mode,event:$event}'
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x notify-context.sh && bash tests/notify-context.Tests.sh`
Expected: every line `ok:`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add notify-context.sh tests/notify-context.Tests.sh tests/fixtures
git commit -m "Add notify-context.sh token gatherer"
```

---

## Task 7: show-notification.ps1 — render from config

**Files:**
- Modify: `show-notification.ps1`
- Create: `tests/golden/default.xaml`
- Create: `tests/show-notification.Tests.sh`

This task is integration: pure logic is already covered by Tasks 2–5. Verification here
is an `-EmitXaml` golden check (theme/event values inlined correctly) plus a visual render.

- [ ] **Step 1: Add `-Context` / `-EmitXaml` params and dot-source the lib**

In `show-notification.ps1`, replace the `param(...)` block (lines 1-8) with:

```powershell
param(
  [long]$Hwnd = 0,
  [string]$Folder = "",
  [string]$Event = "done",
  [string]$Sound = "",
  [string]$Context = "",
  [int]$Seconds = 0,   # 0 = stay until clicked or the target terminal is focused
  [switch]$DryRun,
  [switch]$EmitXaml
)
. (Join-Path $PSScriptRoot 'notify-lib.ps1')
```

- [ ] **Step 2: Replace the per-event styling block with config resolution**

Replace the `# --- Per-event styling ---` block (lines 49-79, the whole
`if ($Event -eq 'needs-input') { ... } else { ... }`) with:

```powershell
# --- Resolve config (theme + event) ---
$cfg   = Get-NotifyConfig $PSScriptRoot
$theme = Resolve-Theme $cfg (Resolve-ThemeName $cfg)
$ev    = Resolve-Event $cfg $Event
$statusText = $ev.label
$accent     = $ev.accent

$heroStops = New-GradientStops $theme.gradient
$rimStops  = New-GradientStops $theme.rim

if ($ev.indicator -eq 'fireworks') {
  $indicator = '<Canvas x:Name="fx" Width="64" Height="64" HorizontalAlignment="Center" VerticalAlignment="Center"/>'
} else {
  $indicator = @"
<Rectangle Width="58" Height="58" HorizontalAlignment="Center" VerticalAlignment="Center" RenderTransformOrigin="0.5,0.85">
  <Rectangle.Fill>
    <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">$heroStops</LinearGradientBrush>
  </Rectangle.Fill>
  <Rectangle.OpacityMask>
    <VisualBrush Stretch="Uniform"><VisualBrush.Visual>
      <TextBlock Text="$($ev.indicator)" FontSize="60" FontFamily="Segoe UI Emoji"/>
    </VisualBrush.Visual></VisualBrush>
  </Rectangle.OpacityMask>
  <Rectangle.RenderTransform><RotateTransform Angle="0"/></Rectangle.RenderTransform>
  <Rectangle.Triggers>
    <EventTrigger RoutedEvent="FrameworkElement.Loaded">
      <BeginStoryboard><Storyboard RepeatBehavior="Forever" AutoReverse="True">
        <DoubleAnimation Storyboard.TargetProperty="(UIElement.RenderTransform).(RotateTransform.Angle)" From="-25" To="25" Duration="0:0:0.28"/>
      </Storyboard></BeginStoryboard>
    </EventTrigger>
  </Rectangle.Triggers>
</Rectangle>
"@
}
```

- [ ] **Step 3: Inline theme values into the XAML and swap the body for a panel**

In the `$xaml` here-string:

(a) Replace the rim `LinearGradientBrush` content (the 7 hardcoded `<GradientStop>` under
`x:Name="rimBrush"`, lines 91-94) with `$rimStops`:

```xaml
      <LinearGradientBrush x:Name="rimBrush" StartPoint="0,0" EndPoint="1,1">$rimStops</LinearGradientBrush>
```

(b) Replace the card `Background="#18181B"` with the theme card:

```xaml
    <Border x:Name="card" CornerRadius="21" Margin="3" Background="$($theme.card)" ClipToBounds="True">
```

(c) Replace the hero `unicorn` Rectangle fill stops (lines 106-108) with `$heroStops`,
and its emoji glyph (line 114) with `$($theme.hero)`:

```xaml
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">$heroStops</LinearGradientBrush>
```
```xaml
                <TextBlock Text="$($theme.hero)" FontSize="190" FontFamily="Segoe UI Emoji"/>
```

(d) Replace the single `folder` TextBlock plus the `click to focus` TextBlock (lines 133-134) with:

```xaml
          <StackPanel x:Name="bodyPanel" Margin="2,10,0,0"/>
          <TextBlock Text="click to focus" FontSize="13" Foreground="#999999" Margin="2,8,0,2"/>
```

- [ ] **Step 4: Add the EmitXaml escape hatch**

Immediately after the `$xaml = @"..."@` here-string ends (before
`$win = [Windows.Markup.XamlReader]::Parse($xaml)`), insert:

```powershell
if ($EmitXaml) { Write-Output $xaml; return }
```

- [ ] **Step 5: Remove the old folder fill and render the body panel**

Delete the line `$win.FindName('folder').Text = $Folder` (was line 153).

In the `$win.Add_Loaded({ ... })` handler, after the fade animation is started, add:

```powershell
  # Body: substitute {{tokens}} from context and stack a TextBlock per surviving line.
  $ctx = @{ folder = $Folder; event = $Event }
  if ($Context -and (Test-Path $Context)) {
    try {
      $cj = Get-Content -Raw -Encoding UTF8 $Context | ConvertFrom-Json
      foreach ($p in $cj.PSObject.Properties) { $ctx[$p.Name] = [string]$p.Value }
    } catch {}
  }
  $bodyPanel = $win.FindName('bodyPanel')
  foreach ($ln in (Resolve-BodyLines $ev.body $ctx)) {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $ln.text
    $tb.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    switch ($ln.style) {
      'headline' { $tb.FontSize = 22; $tb.FontWeight = [System.Windows.FontWeights]::SemiBold; $tb.Foreground = (New-Brush '#FFFFFF'); $tb.Margin = (New-Object System.Windows.Thickness 0,4,0,0) }
      'muted'    { $tb.FontSize = 13; $tb.Foreground = (New-Brush '#999999'); $tb.Margin = (New-Object System.Windows.Thickness 0,4,0,0) }
      default    { $tb.FontSize = 19; $tb.Foreground = (New-Brush '#FFFFFF'); $tb.Margin = (New-Object System.Windows.Thickness 0,4,0,0) }
    }
    $bodyPanel.Children.Add($tb) | Out-Null
  }
```

Note: `New-Brush` is already defined in the script (line 162). `Start-Fireworks` and
`Start-Mascot` are unchanged except the palette/mascot source — see Step 6.

- [ ] **Step 6: Source fireworks palette and mascot from config**

Replace the `$colors = '#FF5F6D',...` line in `Start-Fireworks` (line 166) with a
parameter passed from the resolved theme. Change the function signature and call:

In `Start-Fireworks`, change `function Start-Fireworks($canvas) {` to
`function Start-Fireworks($canvas, $colors) {` and delete the hardcoded `$colors = ...` line.

Update the mascot/fireworks dispatch in `Add_Loaded` (lines 234-237) to:

```powershell
  if (-not (Start-Mascot $win $ev.mascot)) {
    if ($ev.indicator -eq 'fireworks') { Start-Fireworks ($win.FindName('fx')) $theme.palette }
  }
```

Update the `Sound` fallback block (lines 156-160) to use `$ev.sound`:

```powershell
try {
  if ($Sound -and (Test-Path $Sound)) { (New-Object System.Media.SoundPlayer $Sound).Play() }
  elseif ($ev.sound -eq 'exclamation') { [System.Media.SystemSounds]::Exclamation.Play() }
  else { [System.Media.SystemSounds]::Asterisk.Play() }
} catch {}
```

Also update the logo-wave guard (line 261) from `if ($Event -eq 'needs-input')` — leave as-is;
the block-glyph logo behaviour is out of scope and only shows when no mascot is present.

- [ ] **Step 7: Generate the golden default XAML**

Run (no settings.json influence on default theme since unicorn is the default; the golden
captures the rendered-from-config XAML for `done`):

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w show-notification.ps1)" -Event done -EmitXaml \
  | tr -d '\r' > tests/golden/default.xaml
```

Inspect it: confirm it contains `🦄` (hero), the unicorn rim stops, `Background="#18181B"`,
and `x:Name="bodyPanel"`. This is the regression baseline.

- [ ] **Step 8: Write the golden regression test**

Create `tests/show-notification.Tests.sh`:

```bash
#!/usr/bin/env bash
# Regression: -EmitXaml output for the default config matches the golden file.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GOT="$(powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w "$ROOT/show-notification.ps1")" -Event done -EmitXaml | tr -d '\r')"
if diff <(printf '%s' "$GOT") "$ROOT/tests/golden/default.xaml" >/dev/null; then
  echo "ok: default XAML matches golden"; exit 0
else
  echo "FAIL: default XAML drifted from golden"; diff <(printf '%s' "$GOT") "$ROOT/tests/golden/default.xaml"; exit 1
fi
```

- [ ] **Step 9: Run the golden test**

Run: `bash tests/show-notification.Tests.sh`
Expected: `ok: default XAML matches golden`, exit 0.

- [ ] **Step 10: Visual check — needs-input + done on the default theme**

Run each and eyeball the popup (unicorn hero, rim spin, body lines resolved, mascot intact):

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w show-notification.ps1)" -Hwnd 0 -Folder demo -Event needs-input -Seconds 6
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w show-notification.ps1)" -Hwnd 0 -Folder demo -Event done -Seconds 6
```

Expected: both render with exit 0, no errors. With no `-Context`, the body shows the
`demo` folder line (default body) for each event.

- [ ] **Step 11: Commit**

```bash
git add show-notification.ps1 tests/golden/default.xaml tests/show-notification.Tests.sh
git commit -m "Render notification popup from settings.json config"
```

---

## Task 8: Wire the hook and run full acceptance

**Files:**
- Modify: `~/.claude/hooks/notify-fire.sh`

- [ ] **Step 1: Gather context and pass -Context in notify-fire.sh**

In `~/.claude/hooks/notify-fire.sh`, after the `HWND` resolution block (after line 20)
and before the `powershell.exe ... show-notification.ps1` invocation, add:

```bash
CTX="$SESS_DIR/${SID:-nosid}.ctx.json"
printf '%s' "$INPUT" | bash "$NOTIFY_DIR/notify-context.sh" "$EVENT" > "$CTX" 2>/dev/null || : > "$CTX"
WCTX="$(wslpath -w "$CTX" 2>/dev/null)"
```

Then change the `powershell.exe` invocation (lines 29-31) to add `-Context`:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT" \
  -Hwnd "$HWND" -Folder "$FOLDER" -Event "$EVENT" -Sound "$WSND" -Context "$WCTX" \
  >>"$LOG" 2>&1 &
```

- [ ] **Step 2: Re-run the lib + context + golden tests (no regressions)**

```bash
bash tests/settings.Tests.sh
bash tests/notify-context.Tests.sh
bash tests/show-notification.Tests.sh
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w tests/notify-lib.Tests.ps1)"
```

Expected: all exit 0 / `ALL PASS`.

- [ ] **Step 3: Per-theme render smoke (all 9 themes)**

Temporarily point `activeTheme` at each theme and confirm exit 0 + no error output:

```bash
for t in unicorn cosmic ocean sakura matrix dragon vaporwave robot spooky; do
  tmp="$(mktemp)"; jq --arg t "$t" '.activeTheme=$t' settings.json > "$tmp" && mv "$tmp" settings.json
  powershell.exe -NoProfile -ExecutionPolicy Bypass \
    -File "$(wslpath -w show-notification.ps1)" -Hwnd 0 -Folder demo -Event done -Seconds 3 \
    && echo "ok: $t" || echo "FAIL: $t"
done
git checkout settings.json   # restore activeTheme=unicorn
```

Expected: `ok: <theme>` for all 9. Eyeball 2-3 (e.g. cosmic, matrix, sakura): correct
hero emoji, rim/card colours, indicator gradient matches theme.

- [ ] **Step 4: Default-equivalence check**

```bash
mv settings.json /tmp/settings.json.bak
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w show-notification.ps1)" -Hwnd 0 -Folder demo -Event needs-input -Seconds 5
mv /tmp/settings.json.bak settings.json
```

Expected: with no `settings.json`, the popup still renders (unicorn theme, "Needs you",
👋 indicator, flag mascot, single `demo` body line) — i.e. today's look, exit 0.

- [ ] **Step 5: End-to-end through the real hook**

Trigger a real `needs-input` (or invoke the hook with a representative stdin), then confirm
`sessions/<sid>.ctx.json` was written and the popup body shows the resolved `{{message}}`,
`{{folder}} · {{branch}}`, and `{{last_prompt}}` lines.

```bash
tail -5 /mnt/c/temp/notify/notify.log
ls -t /mnt/c/temp/notify/sessions/*.ctx.json | head -1 | xargs cat | jq .
```

Expected: no errors in the log; the ctx json holds populated tokens.

- [ ] **Step 6: Commit**

```bash
git add ~/.claude/hooks/notify-fire.sh
git commit -m "Wire context gathering into notify-fire hook"
```

Note: `~/.claude/hooks/notify-fire.sh` is outside the `notify` repo. If it is not tracked
there, commit it in whatever repo manages `~/.claude` (or note the manual edit). The other
files are all in the `notify` repo.

---

## Self-Review

**Spec coverage:**
- JSON format, file location → Task 1. ✅
- Theme/event model + 9 themes → Task 1 (data), Task 4 (resolution). ✅
- `activeTheme` + `"random"` → Task 4 (`Resolve-ThemeName`). ✅
- Gradient stop `"#hex offset"` encoding → Task 3 (`New-GradientStops`). ✅
- Body templating (styled lines, `{{token}}`, cleaning rules, all-empty drop) → Task 5. ✅
- Context tokens + gather → Task 6 (`notify-context.sh`). ✅
- Resolution flow (gather → ctx file → substitute → render) → Tasks 6, 7, 8. ✅
- Fallback: missing file/field/context → Tasks 2,4,5 (defaults + Coalesce), Task 8 Step 4. ✅
- `-EmitXaml` golden + per-theme render + visual → Task 7, Task 8. ✅
- Out-of-scope (logo, footer, geometry) untouched → Tasks 7 keeps `click to focus`, logo. ✅

**Placeholder scan:** No TBD/TODO; every code step shows full code. ✅

**Type/name consistency:** `Get-Prop`, `Coalesce`, `Get-NotifyDefaults`, `New-GradientStops`,
`Get-NotifyConfig`, `Get-ThemeNames`, `Resolve-ThemeName`, `Resolve-Theme`, `Resolve-Event`,
`Resolve-BodyLines` are defined once and called with matching signatures across Tasks 2-7.
Context token names in `notify-context.sh` (folder, branch, message, last_prompt,
last_assistant, agents, …) match the `{{tokens}}` used in `settings.json` bodies (Task 1)
and the resolution in `Resolve-BodyLines` (Task 5). ✅
```
