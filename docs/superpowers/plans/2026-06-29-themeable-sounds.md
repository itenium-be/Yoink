# Themeable Notification Sounds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each theme its own pair of notification sounds (done / needs-input), pickable + previewable in the settings-editor, persisted to settings.json, and played on the live notification.

**Architecture:** Theme owns the wav filename per event; the event's `sound` boolean gates playback. Resolution happens in PowerShell (handles `activeTheme: "random"`). All audio is wav (SoundPlayer). The editor injects the `sounds/*.wav` list as a pseudo-enum and renders a combo + Play button per theme/event.

**Tech Stack:** Windows PowerShell 5.1 (WPF), bash hooks, jq, ffmpeg, JSON Schema.

**Test commands:**
- Model: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w tests/settings-model.Tests.ps1)" 2>&1 | tr -d '\r' | tail -3`
- Editor seam: `bash tests/settings-editor.Tests.sh`
- settings.json: `bash tests/settings.Tests.sh`

---

### Task 1: Convert non-wav sounds to wav

**Files:**
- Modify: `sounds/*.{mp3,aiff,ogg,flac}` (convert → `.wav`, delete originals)

- [ ] **Step 1: Convert every non-wav to wav, then remove the source**

```bash
cd sounds
for f in *.mp3 *.aiff *.ogg *.flac; do
  [ -e "$f" ] || continue
  ffmpeg -nostdin -y -loglevel error -i "$f" "${f%.*}.wav" && rm -f "$f"
done
```

- [ ] **Step 2: Verify no non-wav remain**

Run: `ls sounds | grep -viE '\.wav$' | wc -l`
Expected: `0`

- [ ] **Step 3: Commit**

```bash
git add sounds
git commit -m "Convert downloaded notification sounds to wav"
```

---

### Task 2: Schema — boolean event sound + theme sound object

**Files:**
- Modify: `settings.schema.json`

- [ ] **Step 1: Replace the event `sound` enum with a boolean**

Find in `definitions.event.properties`:

```json
        "sound": {
          "enum": ["asterisk", "exclamation", ""],
          "description": "Windows system sound. Empty = built-in default; any other value falls back to asterisk."
        },
```

Replace with:

```json
        "sound": {
          "type": "boolean",
          "description": "Master toggle: play this event's themed sound."
        },
```

- [ ] **Step 2: Add a `sound` property to `definitions.theme.properties`**

After the `card` property (before `scene`) in `definitions.theme.properties`, add:

```json
        "sound": {
          "type": "object",
          "additionalProperties": false,
          "description": "Wav filenames (relative to sounds/) played per event. Empty = silent.",
          "properties": {
            "done": { "type": "string" },
            "needs-input": { "type": "string" }
          }
        },
```

- [ ] **Step 3: Verify schema is valid json**

Run: `jq -e '.definitions.event.properties.sound.type, .definitions.theme.properties.sound.type' settings.schema.json`
Expected: `"boolean"` then `"object"`

- [ ] **Step 4: Commit**

```bash
git add settings.schema.json
git commit -m "Schema: event sound boolean toggle + per-theme sound files"
```

---

### Task 3: settings.json — event toggles true + per-theme sound blocks

**Files:**
- Modify: `settings.json`
- Test: `tests/settings.Tests.sh`

- [ ] **Step 1: Add failing assertions to `tests/settings.Tests.sh`**

Insert after the `done body array` check:

```bash
check "done sound is boolean"        "[[ \"\$(jq -r '.events.done.sound|type' '$F')\" == 'boolean' ]]"
check "needs-input sound is boolean" "[[ \"\$(jq -r '.events[\"needs-input\"].sound|type' '$F')\" == 'boolean' ]]"
check "every theme has sound pair" \
  "[[ \"\$(jq '[.themes[]|select(.sound.done != null and .sound[\"needs-input\"] != null)]|length' '$F')\" == '9' ]]"
check "schema event sound is boolean" "[[ \"\$(jq -r '.definitions.event.properties.sound.type' '$SCHEMA')\" == 'boolean' ]]"
check "schema theme sound is object"  "[[ \"\$(jq -r '.definitions.theme.properties.sound.type' '$SCHEMA')\" == 'object' ]]"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/settings.Tests.sh; echo "exit=$?"`
Expected: FAIL lines for the new checks, `exit=1`

- [ ] **Step 3: Edit settings.json — set both event toggles to `true`**

Change `"sound": ""` to `"sound": true` on the `needs-input` event line and the `done` event line.

- [ ] **Step 4: Add a `sound` block to every theme**

For each of the 9 themes, add a `"sound": { "done": "", "needs-input": "" }` member (e.g. right after the theme's `"card"` line). Themes: unicorn, cosmic, ocean, sakura, matrix, dragon, vaporwave, robot, spooky.

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/settings.Tests.sh; echo "exit=$?"`
Expected: all `ok:`, `exit=0`

- [ ] **Step 6: Commit**

```bash
git add settings.json tests/settings.Tests.sh
git commit -m "settings: event sound toggles + empty per-theme sound blocks"
```

---

### Task 4: notify-lib.ps1 — boolean defaults, no string coercion, theme passthrough

**Files:**
- Modify: `notify-lib.ps1` (defaults ~lines 22-25, `Resolve-Event` ~line 173, `Resolve-Theme` ~line 151)

- [ ] **Step 1: Default event `sound` to boolean true**

Line 22 (`needs-input`): change `sound='exclamation';` → `sound=$true;`
Line 24 (`done`): change `sound='asterisk';` → `sound=$true;`

- [ ] **Step 2: Stop coercing `sound` to string in `Resolve-Event`**

Line 173: change `sound     = [string]$snd` → `sound     = $snd`

Why: `[string]$true` is `"True"`, and `[bool]"False"` is `$true` (non-empty string is truthy) — coercion would make the toggle impossible to turn off.

- [ ] **Step 3: Pass the theme `sound` through `Resolve-Theme`**

In the hashtable returned by `Resolve-Theme` (after `scene = (Get-Prop $t 'scene')`), add:

```powershell
    sound      = (Get-Prop $t 'sound')
```

- [ ] **Step 4: Verify the model tests still pass (sanity, no behaviour asserted yet)**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w tests/settings-model.Tests.ps1)" 2>&1 | tr -d '\r' | tail -1`
Expected: `ALL PASS`

- [ ] **Step 5: Commit**

```bash
git add notify-lib.ps1
git commit -m "notify-lib: boolean sound toggle + theme sound passthrough"
```

---

### Task 5: show-notification.ps1 — theme-resolved playback

**Files:**
- Modify: `show-notification.ps1` (param line 5; sound block lines 92-99)

- [ ] **Step 1: Remove the unused `-Sound` parameter**

Delete line 5: `  [string]$Sound = "",`

- [ ] **Step 2: Replace the sound block (current lines 92-99)**

```powershell
# --- Sound --- theme picks the wav; the event toggle gates it. Toggle off, no file, or
# missing file => silent. (Resolution lives here, not in bash, because activeTheme "random"
# is only resolved once the card is built.)
if ([bool]$ev.sound) {
  $sndFile = if ($theme.sound) { [string](Get-Prop $theme.sound $Event) } else { '' }
  if ($sndFile) {
    $sndPath = Join-Path $PSScriptRoot "sounds\$sndFile"
    if (Test-Path $sndPath) { try { (New-Object System.Media.SoundPlayer $sndPath).Play() } catch {} }
  }
}
```

- [ ] **Step 3: Verify the script parses (no live window)**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[void][System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw '$(wslpath -w show-notification.ps1)'), [ref]\$null); 'parse ok'" 2>&1 | tr -d '\r' | tail -1`
Expected: `parse ok`

- [ ] **Step 4: Commit**

```bash
git add show-notification.ps1
git commit -m "show-notification: play theme-resolved wav gated by event toggle"
```

---

### Task 6: notify-fire.sh — drop sound plumbing

**Files:**
- Modify: `hooks/notify-fire.sh` (lines 37-38, 41-42, 49-51)

- [ ] **Step 1: Remove the SND/WSND lines and the -Sound arg**

Delete these (lines 37-38):

```bash
if [[ "$EVENT" == "needs-input" ]]; then SND="$NOTIFY_DIR/sounds/needs-input.wav";
else EVENT="done"; SND="$NOTIFY_DIR/sounds/done.wav"; fi
```

Replace with (keep the needs-input/done normalization the second branch did):

```bash
[[ "$EVENT" == "needs-input" ]] || EVENT="done"
```

Delete lines 41-42:

```bash
WSND=""
[[ -f "$SND" ]] && WSND="$(wslpath -w "$SND" 2>/dev/null)"
```

In the `powershell.exe` invocation, remove `-Sound "$WSND"` from the argument list.

- [ ] **Step 2: Verify hook tests still pass (hwnd + event forwarding)**

Run: `bash tests/run.sh 2>&1 | tail -3`
Expected: `0 failed`

- [ ] **Step 3: Commit**

```bash
git add hooks/notify-fire.sh
git commit -m "notify-fire: drop -Sound plumbing (resolved in PowerShell now)"
```

---

### Task 7: settings-model.ps1 — checkbox event sound + theme sound fields

**Files:**
- Modify: `lib/settings-model.ps1` (`Get-SchemaEnums`, `Get-EditorFields`)
- Test: `tests/settings-model.Tests.ps1`

- [ ] **Step 1: Add failing assertions to `tests/settings-model.Tests.ps1`**

The test model's themes lack `sound`; give `sakura` one and inject a wav list. After the line
that builds `$enums` (`$enums = Get-SchemaEnums ...`), add:

```powershell
$enums['sound.files'] = @('', 'unicorn-shine.wav', 'sakura-multi-hit.wav')
```

In the `$model` themes, change the sakura theme to include a sound block:

```powershell
    sakura = [ordered]@{ hero='🌸'; card='#1A1620'; sound=[ordered]@{ done='sakura-multi-hit.wav'; 'needs-input'='' }; scene=[ordered]@{ kind='sakura'; petals=$true; count=22; glyphs='katakana' } }
```

After the existing `$byLabel['hero']` assertions, add:

```powershell
Assert-Eq $byLabel['sound'].kind 'checkbox' "event sound is checkbox"
Assert-Eq ($byLabel['sound.done'].path -join '.') 'themes.sakura.sound.done' "theme sound.done path"
Assert-Eq $byLabel['sound.done'].kind 'sound' "theme sound.done is sound kind"
Assert-Eq ($byLabel['sound.done'].options -join ',') ',unicorn-shine.wav,sakura-multi-hit.wav' "sound options injected"
Assert-Eq ($byLabel['sound.needs-input'].path -join '.') 'themes.sakura.sound.needs-input' "theme sound.needs-input path"
```

- [ ] **Step 2: Run to verify it fails**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w tests/settings-model.Tests.ps1)" 2>&1 | tr -d '\r' | grep -E 'FAIL|sound'`
Expected: FAIL lines for the new sound assertions

- [ ] **Step 3: Drop the unused `sound` enum from `Get-SchemaEnums`**

Delete this line (the schema field is boolean now, no enum):

```powershell
    'sound'        = @(Get-ModelValue $schema @('definitions','event','properties','sound','enum'))
```

- [ ] **Step 4: Make the event `sound` field a checkbox in `Get-EditorFields`**

Change:

```powershell
  Add-Field $fields ($ep + 'sound')               'sound'       'dropdown' $enums['sound']
```

to:

```powershell
  Add-Field $fields ($ep + 'sound')               'sound'       'checkbox' @()
```

- [ ] **Step 5: Emit the two theme sound fields in `Get-EditorFields`**

After the `card` field line (`Add-Field $fields ($tp + 'card') 'card' 'text' @()`), add:

```powershell
  $soundOpts = @($enums['sound.files'])
  Add-Field $fields ($tp + @('sound','done'))        'sound.done'        'sound' $soundOpts
  Add-Field $fields ($tp + @('sound','needs-input')) 'sound.needs-input' 'sound' $soundOpts
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w tests/settings-model.Tests.ps1)" 2>&1 | tr -d '\r' | tail -1`
Expected: `ALL PASS`

- [ ] **Step 7: Commit**

```bash
git add lib/settings-model.ps1 tests/settings-model.Tests.ps1
git commit -m "settings-model: checkbox event sound + per-theme sound picker fields"
```

---

### Task 8: settings-editor.ps1 — wav enum injection, sound control, theme rows

**Files:**
- Modify: `settings-editor.ps1`
- Test: `tests/settings-editor.Tests.sh`

- [ ] **Step 1: Add failing assertions to `tests/settings-editor.Tests.sh`**

After the `lists scene petals checkbox` check, add:

```bash
check "lists event sound checkbox"   "grep -q 'checkbox events.done.sound' <<<\"\$OUT\""
check "lists theme sound.done"       "grep -q 'sound themes.sakura.sound.done' <<<\"\$OUT\""
check "lists theme sound.needs-input" "grep -q 'sound themes.sakura.sound.needs-input' <<<\"\$OUT\""
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/settings-editor.Tests.sh; echo "exit=$?"`
Expected: FAIL lines for the new checks, `exit=1`

- [ ] **Step 3: Inject the wav file list as a pseudo-enum**

After line 15 (`$script:enums = Get-SchemaEnums ...`), add:

```powershell
# Wav files the theme sound pickers offer (leading '' = silent). Enumerated here, not in the
# pure model layer, because it's a filesystem read.
$script:soundsDir = Join-Path $PSScriptRoot 'sounds'
$script:enums['sound.files'] = @('') + @(if (Test-Path $script:soundsDir) { (Get-ChildItem $script:soundsDir -Filter *.wav | Sort-Object Name).Name })
```

- [ ] **Step 4: Add the Play handler (near the other `$on*` handlers, after `$onCombo`)**

```powershell
# Preview a theme sound: play the combo's selected wav from sounds/ (a blank selection is a no-op).
$onPlaySound = {
  $t = $this.Tag; $sel = [string]$t.combo.SelectedItem
  if ($sel) { try { (New-Object System.Media.SoundPlayer (Join-Path $script:soundsDir $sel)).Play() } catch {} }
}
```

- [ ] **Step 5: Add a `'sound'` case to `New-FieldControl`**

Inside the `switch ($f.kind)` in `New-FieldControl`, before the `default` arm, add:

```powershell
    'sound' {
      $c = New-Object System.Windows.Controls.ComboBox
      foreach ($o in $f.options) { $c.Items.Add([string]$o) | Out-Null }
      $c.SelectedItem = [string](Get-ModelValue $script:model $f.path)
      $c.HorizontalAlignment = 'Stretch'; $c.VerticalAlignment = 'Center'
      $c.Tag = $f; $c.Add_SelectionChanged($onCombo)
      $play = New-Object System.Windows.Controls.Button
      $play.Content = ([char]0x25B6); $play.Width = 28; $play.Margin = New-Object System.Windows.Thickness 6, 0, 0, 0
      $play.Tag = @{ combo = $c }; $play.Add_Click($onPlaySound)
      $dock = New-Object System.Windows.Controls.DockPanel
      [System.Windows.Controls.DockPanel]::SetDock($play, 'Right')
      $dock.Children.Add($play) | Out-Null; $dock.Children.Add($c) | Out-Null
      return $dock
    }
```

- [ ] **Step 6: Render the two theme sound rows in `Build-Form`**

In the Theme section, after `Add-Row 'card' (New-FieldControl (& $find 'card'))` (line ~397), add:

```powershell
  Add-Row 'sound done'  (New-FieldControl (& $find 'sound.done'))
  Add-Row 'sound input' (New-FieldControl (& $find 'sound.needs-input'))
```

- [ ] **Step 7: Run editor tests + self-test to verify they pass**

Run: `bash tests/settings-editor.Tests.sh; echo "exit=$?"`
Expected: all `ok:` including `selftest builds + rebuilds`, `exit=0`

- [ ] **Step 8: Commit**

```bash
git add settings-editor.ps1 tests/settings-editor.Tests.sh
git commit -m "settings-editor: theme sound pickers with Play preview"
```

---

### Task 9: Update SOUNDS.md

**Files:**
- Modify: `SOUNDS.md` (note: gitignored — update for reference only)

- [ ] **Step 1: Rewrite the model section**

Replace the "General / default (keep as fallback)" section to state: playback is the event
boolean toggle AND the theme's wav for that event; missing/blank → silent; no system-sound
fallback. Keep the download sites and per-theme search-term suggestions.

- [ ] **Step 2: Confirm gitignored (no commit needed)**

Run: `git check-ignore SOUNDS.md && echo ignored || echo tracked`
Expected: `ignored` (skip the add/commit) — otherwise `git add SOUNDS.md && git commit -m "docs: SOUNDS.md reflects themed-sound model"`

---

### Task 10: Full suite + finish

- [ ] **Step 1: Run the whole test suite**

Run: `bash tests/run.sh 2>&1 | tail -4`
Expected: `0 failed`

- [ ] **Step 2: Run the two settings suites directly**

Run: `bash tests/settings.Tests.sh && bash tests/settings-editor.Tests.sh && echo ALLGREEN`
Expected: ends with `ALLGREEN`

- [ ] **Step 3: Confirm clean tree**

Run: `git status --short`
Expected: empty (everything committed)
