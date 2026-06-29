# Settings Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A single PowerShell/WPF window that edits `settings.json` (controls on top, the live notification card looping on the bottom) with ephemeral edits and a Save button.

**Architecture:** A pure model layer (`lib/settings-model.ps1`) loads `settings.json` into a mutable ordered-hashtable model, derives the form's field list from the model + `settings.schema.json`, and serializes back on Save. The existing WPF card renderer is reused by extracting its load-time setup (`Initialize-NotificationCard`) and its mascot/scene choreography (`Start-CardChoreography`) so the editor can host the card's inner Grid under its controls. The editor window (`settings-editor.ps1`) wires controls → model → a debounced full card rebuild.

**Tech Stack:** Windows PowerShell 5.1, WPF (PresentationFramework), the repo's existing `notify-lib.ps1` helpers. Tests follow the repo conventions: pure-PS assertions in `*.Tests.ps1` (run via `powershell.exe -File`) and behavioural seams in `*.Tests.sh`.

---

## File Structure

- **Create** `lib/settings-model.ps1` — pure model layer: deep load, get/set by path, JSON serialize, value coercion, schema-enum reader, editor field list, sample token context. No WPF.
- **Create** `lib/card-choreography.ps1` — `Start-CardChoreography`: anchor/geometry setup + mascot phase dispatch + scene config/dispatch, extracted verbatim from `show-notification.ps1`.
- **Modify** `lib/notification-box.ps1` — add `Initialize-NotificationCard`; add `RimBrush/Fx/BodyTbs/Theme/Ev` to the returned bag; call `Initialize-NotificationCard` from the window's `Add_Loaded`. **XAML output must not change.**
- **Modify** `show-notification.ps1` — replace the inlined anchor/geometry + mascot + scene `Add_Loaded` blocks with a single `Start-CardChoreography` call.
- **Create** `settings-editor.ps1` — the WPF editor window (not unit-tested; delegates to the tested libs).
- **Create** `tests/settings-model.Tests.ps1` — pure assertions for the model layer.
- **Create** `tests/settings-editor.Tests.sh` — exercises `settings-editor.ps1 -DryRun` (field list) and the Save round-trip.

A repo convention worth noting: `New-NotificationBox -EmitXaml` returns the Window XAML and is golden-tested by `tests/show-notification.Tests.sh` and `tests/scene.Tests.sh`. Every renderer-touching task below must keep those green.

---

## Task 1: Model layer — deep load, path get/set, serialize

**Files:**
- Create: `lib/settings-model.ps1`
- Test: `tests/settings-model.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/settings-model.Tests.ps1` (note the UTF-8 BOM-free file is fine; match the existing `notify-lib.Tests.ps1` harness):

```powershell
. "$PSScriptRoot\..\lib\settings-model.ps1"

$script:fail = 0
function Assert-Eq($got, $exp, $msg) {
  if ("$got" -ne "$exp") { Write-Host "FAIL: $msg`n  exp=[$exp]`n  got=[$got]"; $script:fail++ }
  else { Write-Host "ok: $msg" }
}

# --- ConvertTo-HashtableDeep ---
$o = [pscustomobject]@{ a = 1; b = [pscustomobject]@{ c = 2 }; d = @(1,2) }
$h = ConvertTo-HashtableDeep $o
Assert-Eq ($h -is [System.Collections.IDictionary]) 'True' "deep convert -> dictionary"
Assert-Eq $h['b']['c'] 2 "deep convert nested"
Assert-Eq $h['d'].Count 2 "deep convert array"

# --- Get/Set-ModelValue ---
$m = [ordered]@{ events = [ordered]@{ done = [ordered]@{ label = 'Done!' } } }
Assert-Eq (Get-ModelValue $m @('events','done','label')) 'Done!' "get nested"
Assert-Eq (Get-ModelValue $m @('events','nope','label')) '' "get missing -> null"
Set-ModelValue $m @('events','done','label') 'Hi'
Assert-Eq (Get-ModelValue $m @('events','done','label')) 'Hi' "set existing"
Set-ModelValue $m @('themes','sakura','card') '#000000'
Assert-Eq (Get-ModelValue $m @('themes','sakura','card')) '#000000' "set creates intermediate"

# --- ConvertTo-SettingsJson round-trips through ConvertFrom-Json ---
$json = ConvertTo-SettingsJson $m
$back = $json | ConvertFrom-Json
Assert-Eq $back.events.done.label 'Hi' "serialize round-trips label"
Assert-Eq $back.themes.sakura.card '#000000' "serialize round-trips new key"

# --- ConvertTo-ModelValue coercion ---
Assert-Eq (ConvertTo-ModelValue 'checkbox' $true) 'True' "checkbox -> bool"
Assert-Eq (ConvertTo-ModelValue 'number' '22') 22 "number int"
Assert-Eq (ConvertTo-ModelValue 'number' '1.5') 1.5 "number double"
Assert-Eq (ConvertTo-ModelValue 'text' 42) '42' "text -> string"

if ($script:fail -gt 0) { exit 1 } else { Write-Host "ALL PASS" }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$PWD/tests/settings-model.Tests.ps1")"`
Expected: FAIL — `settings-model.ps1` does not exist / functions not defined.

- [ ] **Step 3: Write minimal implementation**

Create `lib/settings-model.ps1`:

```powershell
# Pure model layer for settings-editor.ps1. No WPF — dot-sourceable and unit-testable.
. (Join-Path $PSScriptRoot '..\notify-lib.ps1')   # Remove-JsonComments

# JSON-derived PSCustomObject/array -> ordered hashtable / array, recursively. Ordered so
# Save keeps a stable key order.
function ConvertTo-HashtableDeep($obj) {
  if ($obj -is [System.Management.Automation.PSCustomObject]) {
    $h = [ordered]@{}
    foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = ConvertTo-HashtableDeep $p.Value }
    return $h
  }
  if ($obj -is [System.Collections.IList] -and $obj -isnot [string]) {
    return @($obj | ForEach-Object { ConvertTo-HashtableDeep $_ })
  }
  return $obj
}

# Load a JSON (or JSONC) file into a deep ordered-hashtable model.
function Read-SettingsModel([string]$Path) {
  $raw = Remove-JsonComments (Get-Content -Raw -Encoding UTF8 $Path)
  ConvertTo-HashtableDeep ($raw | ConvertFrom-Json)
}

# Read a nested value by path; $null if any segment is missing.
function Get-ModelValue($model, [string[]]$Path) {
  $cur = $model
  foreach ($k in $Path) {
    if ($null -eq $cur -or -not ($cur -is [System.Collections.IDictionary])) { return $null }
    $cur = $cur[$k]
  }
  $cur
}

# Set a nested value by path, creating intermediate ordered hashtables as needed.
function Set-ModelValue($model, [string[]]$Path, $Value) {
  $cur = $model
  for ($i = 0; $i -lt $Path.Count - 1; $i++) {
    $k = $Path[$i]
    if ($null -eq $cur[$k] -or -not ($cur[$k] -is [System.Collections.IDictionary])) { $cur[$k] = [ordered]@{} }
    $cur = $cur[$k]
  }
  $cur[$Path[$Path.Count - 1]] = $Value
}

# Model -> pretty JSON string for Save (comments are not preserved).
function ConvertTo-SettingsJson($model) {
  $model | ConvertTo-Json -Depth 12
}

# Coerce a raw control value to the type implied by a field kind.
function ConvertTo-ModelValue([string]$Kind, $Raw) {
  switch ($Kind) {
    'checkbox' { return [bool]$Raw }
    'number'   {
      if ([string]$Raw -match '^-?\d+$') { return [int]$Raw }
      $d = 0.0
      if ([double]::TryParse([string]$Raw, [ref]$d)) { return $d }
      return $Raw
    }
    default    { return [string]$Raw }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$PWD/tests/settings-model.Tests.ps1")"`
Expected: PASS — ends with `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add lib/settings-model.ps1 tests/settings-model.Tests.ps1
git commit -m "Add settings-editor model layer (load/get/set/serialize)"
```

---

## Task 2: Schema enums + editor field list + sample context

**Files:**
- Modify: `lib/settings-model.ps1`
- Test: `tests/settings-model.Tests.ps1:end` (append before the final exit guard)

- [ ] **Step 1: Write the failing test**

In `tests/settings-model.Tests.ps1`, insert these blocks **before** the final `if ($script:fail ...)` line:

```powershell
# --- Get-SchemaEnums (reads the real schema) ---
$enums = Get-SchemaEnums "$PSScriptRoot\..\settings.schema.json"
Assert-Eq ($enums['mascot.move'] -join ',') 'walk,jump' "schema mascot.move enum"
Assert-Eq ($enums['mascot.end'] -join ',')  'confetti,gym,flag' "schema mascot.end enum"
Assert-Eq ($enums['scene.glyphs'] -join ',') 'katakana,latin,digits,binary,mixed' "schema glyphs enum"

# --- Get-EditorFields ---
$model = [ordered]@{
  activeTheme = 'sakura'
  events = [ordered]@{ done = [ordered]@{ label='Done!'; mascot=[ordered]@{ move='walk'; end='confetti' } } }
  themes = [ordered]@{
    sakura = [ordered]@{ hero='🌸'; card='#1A1620'; scene=[ordered]@{ kind='sakura'; petals=$true; count=22; glyphs='katakana' } }
    dragon = [ordered]@{ hero='🐉'; card='#1A0F0A' }
  }
}
$fields = Get-EditorFields $model $enums 'done' 'sakura'
$byLabel = @{}; foreach ($f in $fields) { $byLabel[$f.label] = $f }
Assert-Eq ($byLabel['activeTheme'].options -join ',') 'sakura,dragon,random' "activeTheme options = themes + random"
Assert-Eq $byLabel['activeTheme'].kind 'dropdown' "activeTheme is dropdown"
Assert-Eq ($byLabel['label'].path -join '.') 'events.done.label' "event label path"
Assert-Eq ($byLabel['mascot.move'].path -join '.') 'events.done.mascot.move' "mascot.move path"
Assert-Eq $byLabel['mascot.move'].kind 'dropdown' "mascot.move dropdown"
Assert-Eq ($byLabel['hero'].path -join '.') 'themes.sakura.hero' "theme hero path"
Assert-Eq $byLabel['scene.petals'].kind 'checkbox' "scene bool -> checkbox"
Assert-Eq $byLabel['scene.count'].kind 'number' "scene number -> number"
Assert-Eq $byLabel['scene.glyphs'].kind 'dropdown' "scene glyphs -> dropdown"
Assert-Eq ($fields | Where-Object { $_.label -eq 'scene.kind' }).Count 0 "scene.kind not exposed"

# --- Sample context resolves body/footer non-empty ---
$ctx = Get-SampleContext
$lines = @(Resolve-BodyLines @(@{ text='{{folder}}'; style='sub' }) $ctx)
Assert-Eq $lines.Count 1 "sample context resolves folder line"
Assert-Eq $lines[0].text 'my-project' "sample folder value"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$PWD/tests/settings-model.Tests.ps1")"`
Expected: FAIL — `Get-SchemaEnums`/`Get-EditorFields`/`Get-SampleContext` not defined.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/settings-model.ps1`:

```powershell
# Read the enum option lists the editor needs from settings.schema.json.
function Get-SchemaEnums([string]$SchemaPath) {
  $schema = ConvertTo-HashtableDeep ((Remove-JsonComments (Get-Content -Raw -Encoding UTF8 $SchemaPath)) | ConvertFrom-Json)
  @{
    'mascot.move'  = @(Get-ModelValue $schema @('definitions','event','properties','mascot','properties','move','enum'))
    'mascot.end'   = @(Get-ModelValue $schema @('definitions','event','properties','mascot','properties','end','enum'))
    'sound'        = @(Get-ModelValue $schema @('definitions','event','properties','sound','enum'))
    'scene.glyphs' = @(Get-ModelValue $schema @('definitions','scene','properties','glyphs','enum'))
  }
}

# Ordered list of form-field descriptors for the selected event + theme.
# Each: @{ path=[string[]]; label=string; kind='text'|'dropdown'|'checkbox'|'number'; options=[string[]] }
function Get-EditorFields($model, $enums, [string]$Event, [string]$Theme) {
  $fields = New-Object System.Collections.Generic.List[object]
  function script:Add-Field($list, $path, $label, $kind, $opts) {
    $list.Add(@{ path = @($path); label = $label; kind = $kind; options = @($opts) }) | Out-Null
  }

  $themeNames = @((Get-ModelValue $model @('themes')).Keys)
  Add-Field $fields @('activeTheme') 'activeTheme' 'dropdown' ($themeNames + 'random')

  $ep = @('events', $Event)
  Add-Field $fields ($ep + 'label')               'label'       'text'     @()
  Add-Field $fields ($ep + 'accent')              'accent'      'text'     @()
  Add-Field $fields ($ep + 'indicator')           'indicator'   'text'     @()
  Add-Field $fields ($ep + @('mascot','move'))    'mascot.move' 'dropdown' $enums['mascot.move']
  Add-Field $fields ($ep + @('mascot','end'))     'mascot.end'  'dropdown' $enums['mascot.end']
  Add-Field $fields ($ep + 'sound')               'sound'       'dropdown' $enums['sound']

  $tp = @('themes', $Theme)
  Add-Field $fields ($tp + 'hero') 'hero' 'text' @()
  Add-Field $fields ($tp + 'card') 'card' 'text' @()

  $scene = Get-ModelValue $model ($tp + 'scene')
  if ($scene -is [System.Collections.IDictionary]) {
    foreach ($k in @($scene.Keys)) {
      if ($k -eq 'kind' -or $k -eq 'colors') { continue }   # readonly / array (deferred)
      $sp = $tp + @('scene', $k)
      if ($k -eq 'glyphs')         { Add-Field $fields $sp "scene.$k" 'dropdown' $enums['scene.glyphs'] }
      elseif ($scene[$k] -is [bool]) { Add-Field $fields $sp "scene.$k" 'checkbox' @() }
      else                         { Add-Field $fields $sp "scene.$k" 'number' @() }
    }
  }
  $fields
}

# Fixed sample values for {{token}} expansion in the preview (no live session needed).
function Get-SampleContext {
  @{
    folder = 'my-project'; cwd = '/home/wouter/code/my-project'; repo = 'my-project'
    branch = 'main'; dirty = '●'; message = 'Waiting for your input'
    last_prompt = 'add a dark mode toggle'; last_assistant = 'Done — all tests pass'
    model = 'claude-sonnet'; agents = '2'; pending_tool = 'Edit'; permission_mode = 'default'; event = 'done'
  }
}
```

Note: `Resolve-BodyLines`/`Resolve-Footer` come from `notify-lib.ps1`, already dot-sourced at the top of `settings-model.ps1`.

- [ ] **Step 4: Run test to verify it passes**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$PWD/tests/settings-model.Tests.ps1")"`
Expected: PASS — `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add lib/settings-model.ps1 tests/settings-model.Tests.ps1
git commit -m "Add schema-enum reader, editor field list, sample context"
```

---

## Task 3: Extract `Initialize-NotificationCard` (no XAML change)

**Files:**
- Modify: `lib/notification-box.ps1` (the `Add_Loaded` block at lines 184-256 and the returned bag at 258-263)
- Guard test: `tests/show-notification.Tests.sh`, `tests/scene.Tests.sh`

This is a refactor: the golden XAML tests are the safety net.

- [ ] **Step 1: Run the golden guard to confirm green baseline**

Run: `bash tests/show-notification.Tests.sh && bash tests/scene.Tests.sh`
Expected: `ok: default XAML matches golden` and both scene checks `ok`.

- [ ] **Step 2: Add `Initialize-NotificationCard` and enrich the bag**

In `lib/notification-box.ps1`, **add this function** just above `function New-NotificationBox`:

```powershell
# Load-time card setup that is independent of any hosting Window: corner-clip, rim spin,
# fireworks, and the body-line marquee. Call AFTER the card has been laid out (its Loaded),
# whether it lives in the notification Window or is hosted inside the settings editor.
function Initialize-NotificationCard($box) {
  $card = $box.Card
  if ($card) {
    $cg = New-Object System.Windows.Media.RectangleGeometry
    $cg.Rect = New-Object System.Windows.Rect 0, 0, $card.ActualWidth, $card.ActualHeight
    $cg.RadiusX = 21; $cg.RadiusY = 21
    $card.Clip = $cg
  }

  $rimBrush = $box.RimBrush
  if ($rimBrush) {
    $rot = New-Object System.Windows.Media.RotateTransform
    $rot.CenterX = 0.5; $rot.CenterY = 0.5
    $rimBrush.RelativeTransform = $rot
    $spin = New-Object System.Windows.Media.Animation.DoubleAnimation 0, 360, ([System.Windows.Duration][TimeSpan]::FromSeconds(4))
    $spin.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $rot.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $spin)
  }
  if ($box.Ev.indicator -eq 'fireworks') { Start-Fireworks ($box.Fx) (@(Get-StopColors $box.Theme.gradient)) }

  foreach ($tb in $box.BodyTbs) {
    $avail = $tb.ActualWidth
    if ($avail -le 0) { continue }
    $ft = New-Object System.Windows.Media.FormattedText(
      $tb.Text, [System.Globalization.CultureInfo]::CurrentCulture, [System.Windows.FlowDirection]::LeftToRight,
      (New-Object System.Windows.Media.Typeface($tb.FontFamily, $tb.FontStyle, $tb.FontWeight, $tb.FontStretch)),
      $tb.FontSize, [System.Windows.Media.Brushes]::Black)
    if ($ft.WidthIncludingTrailingWhitespace -le $avail + 1) { continue }
    $full = $ft.WidthIncludingTrailingWhitespace
    $tb.ToolTip = $tb.Text

    $panel = $tb.Parent
    $idx = $panel.Children.IndexOf($tb)
    $vp = New-Object System.Windows.Controls.Grid
    $vp.Width = $avail; $vp.Height = $tb.ActualHeight; $vp.HorizontalAlignment = 'Left'
    $vp.ClipToBounds = $true; $vp.Margin = $tb.Margin
    $panel.Children.RemoveAt($idx)
    $tb.Margin = (New-Object System.Windows.Thickness 0)
    $tb.HorizontalAlignment = 'Left'
    $tb.TextTrimming = [System.Windows.TextTrimming]::None
    $tb.TextWrapping = [System.Windows.TextWrapping]::NoWrap
    $tt = New-Object System.Windows.Media.TranslateTransform
    $tb.RenderTransform = $tt
    $vp.Children.Add($tb) | Out-Null
    $panel.Children.Insert($idx, $vp)

    $travel = -($full - $avail + 6)
    $scroll = [int]([Math]::Abs($travel) * 12)
    $kf = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $kf.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $stops = @(@(0, 0), @(1500, 0), @((1500 + $scroll), $travel), @((3000 + $scroll), $travel), @((3000 + 2 * $scroll), 0))
    foreach ($s in $stops) {
      $kt = [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds($s[0]))
      $kf.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame([double]$s[1], $kt))) | Out-Null
    }
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $kf)
  }
}
```

- [ ] **Step 3: Rewire `New-NotificationBox` to build the bag first, then call the helper**

In `lib/notification-box.ps1`, **replace** the whole `$win.Add_Loaded({ ... }.GetNewClosure())` block (currently lines 184-256) **and** the trailing `return @{ ... }` (lines 258-263) with:

```powershell
  $bodyTbsLocal = $bodyTbs

  $box = @{
    Win = $win; Card = $win.FindName('card'); Slot = $win.FindName('slot')
    Overlay = $win.FindName('overlay'); Mascot = $win.FindName('mascot')
    Scene = $win.FindName('scene'); RimBrush = $win.FindName('rimBrush'); Fx = $win.FindName('fx')
    BodyTbs = $bodyTbsLocal; Theme = $Theme; Ev = $Ev
    Event = $Event
  }

  $win.Add_Loaded({
    Initialize-NotificationCard $box
    # Window-only: position bottom-right of the work area and fade in.
    $src = [System.Windows.PresentationSource]::FromVisual($win)
    $sx = $src.CompositionTarget.TransformToDevice.M11
    $sy = $src.CompositionTarget.TransformToDevice.M22
    $wpx = $win.ActualWidth * $sx; $hpx = $win.ActualHeight * $sy; $pad = 12 * $sx
    $win.Left = ($WorkArea.Right  - $wpx - $pad) / $sx
    $win.Top  = ($WorkArea.Bottom - $hpx - $pad) / $sy
    $fade = New-Object System.Windows.Media.Animation.DoubleAnimation 0, 1, ([System.Windows.Duration][TimeSpan]::FromMilliseconds(250))
    $win.BeginAnimation([System.Windows.Window]::OpacityProperty, $fade)
  }.GetNewClosure())

  return $box
```

(The body-line `$bodyTbs` population loop earlier in the function is unchanged; only the `Add_Loaded` and the return are restructured. The card-clip / rim-spin / fireworks / marquee logic now lives in `Initialize-NotificationCard`.)

- [ ] **Step 4: Run the golden guard — XAML and behaviour unchanged**

Run: `bash tests/show-notification.Tests.sh && bash tests/scene.Tests.sh`
Expected: `ok: default XAML matches golden`; scene checks `ok`. (XAML is emitted before any of this code runs, so it must be byte-identical.)

- [ ] **Step 5: Commit**

```bash
git add lib/notification-box.ps1
git commit -m "Extract Initialize-NotificationCard from notification window load"
```

---

## Task 4: Extract `Start-CardChoreography`

> **Execution correction (the plan body below is stale):** the repo gained a `unicorn`
> scene after this plan was written. The real `show-notification.ps1` has a FIVE-entry
> `$sceneKinds` (incl. `unicorn = { ... Start-Unicorn ... }`) and FIVE extra `$sceneCfg`
> props beyond `parallax` (`aurora`, `rainbow`, `glitter`, `sparkles`, `shootingStar`), plus
> a `lib\scene-unicorn.ps1` dot-source. **Move the CURRENT inlined code verbatim** (incl.
> unicorn), not the 4-kind body printed below. Also wire the `Add_Loaded` with a **plain
> scriptblock, NOT `.GetNewClosure()`** — the closure form rebinds scope so the dot-sourced
> phase/scene functions become invisible (there's an existing WHY comment about this).

**Files:**
- Create: `lib/card-choreography.ps1`
- Modify: `show-notification.ps1` (remove inlined anchor/geometry block + the two `Add_Loaded` choreography blocks; add the call)
- Guard test: `tests/show-notification.Tests.sh`

- [ ] **Step 1: Run the golden guard baseline**

Run: `bash tests/show-notification.Tests.sh`
Expected: `ok: default XAML matches golden`.

- [ ] **Step 2: Create `lib/card-choreography.ps1`**

Move the anchor/geometry setup (`show-notification.ps1` lines 99-112) and the bodies of the two `Add_Loaded` choreography blocks (lines 122-133 mascot, 137-173 scene) into one function. The function assumes the card is already laid out (callers invoke it from a `Loaded` handler):

```powershell
# Mascot + scene choreography for an already-laid-out card. $box is the bag from
# New-NotificationBox (or a card hosted elsewhere). $Root is the repo root (for mascot art).
# Requires the mascot-*, scene-* libs to be dot-sourced by the caller.
function Start-CardChoreography($box, $theme, $ev, [string]$Root) {
  # --- Mascot canvas geometry (one display height drives every phase) ---
  $anchor = Get-Content (Join-Path $Root 'mascots\anchor.json') -Raw | ConvertFrom-Json
  $box.MascotH = 243.0
  $box.DisplayScale = $box.MascotH / $anchor.canvasH
  $core = @{ W = $anchor.canvasW; H = $anchor.canvasH; AX = [double]$anchor.anchorX; AY = [double]$anchor.anchorY }
  $box.Geom = @{ looking = $core; jump = $core; walking = $core; confetti = $core; flag = $core }
  foreach ($e in 'gym', 'horizontal-jump') {
    $ea = Get-Content (Join-Path $Root "mascots\$e\anchor.json") -Raw | ConvertFrom-Json
    $box.Geom[$e] = @{ W = $ea.canvasW; H = $ea.canvasH; AX = [double]$ea.anchorX; AY = [double]$ea.anchorY }
  }

  # --- Mascot phases: look -> jump onto edge -> move -> celebrate ---
  $box.Move = $ev.mascot.move
  $box.End  = $ev.mascot.end
  Start-JumpPrep $box {
    Start-Jump $box {
      $celebrate = {
        if     ($box.End -eq 'gym')  { Start-Gym $box }
        elseif ($box.End -eq 'flag') { Start-FlagWave $box }
        else                         { Start-Confetti $box }
      }
      if ($box.Move -eq 'jump') { Start-HJump $box $celebrate } else { Start-Walk $box $celebrate }
    }
  }

  # --- Scenery ---
  $sceneCfg = $null
  if ($theme.scene -and (Get-Prop $theme.scene 'kind')) {
    $sceneCols = @(Get-Prop $theme.scene 'colors')
    if (-not $sceneCols -or $sceneCols.Count -eq 0) { $sceneCols = @(Get-StopColors $theme.gradient) }
    $sceneCfg = @{
      kind    = [string](Get-Prop $theme.scene 'kind')
      colors  = $sceneCols
      opacity = (Coalesce (Get-Prop $theme.scene 'opacity') 0.22)
      speed   = (Coalesce (Get-Prop $theme.scene 'speed')   1.0)
      sky     = [bool](Get-Prop $theme.scene 'sky')
      sun     = [bool](Get-Prop $theme.scene 'sun')
      clouds  = [bool](Get-Prop $theme.scene 'clouds')
      stars   = [bool](Get-Prop $theme.scene 'stars')
      nebula  = [bool](Get-Prop $theme.scene 'nebula')
      comets  = [bool](Get-Prop $theme.scene 'comets')
      streaks = [bool](Get-Prop $theme.scene 'streaks')
      density = (Coalesce (Get-Prop $theme.scene 'density') 0.85)
      glyphs  = [string](Coalesce (Get-Prop $theme.scene 'glyphs') 'katakana')
      petals   = [bool](Coalesce (Get-Prop $theme.scene 'petals') $true)
      count    = [int](Coalesce (Get-Prop $theme.scene 'count') 22)
      bloom    = [bool](Get-Prop $theme.scene 'bloom')
      branch   = [bool](Get-Prop $theme.scene 'branch')
      parallax = [bool](Get-Prop $theme.scene 'parallax')
    }
  }
  $sceneKinds = @{
    waves  = { param($b, $c) Start-Waves $b $c }
    space  = { param($b, $c) Start-Space $b $c }
    matrix = { param($b, $c) Start-Matrix $b $c }
    sakura = { param($b, $c) Start-Sakura $b $c }
  }
  if ($sceneCfg) {
    $fn = $sceneKinds[$sceneCfg.kind]
    if ($fn) { try { & $fn $box $sceneCfg } catch { Write-Warning "scene '$($sceneCfg.kind)' failed: $_" } }
  }
}
```

- [ ] **Step 3: Rewire `show-notification.ps1`**

Add the dot-source near the other `lib\` sources (after line 27):

```powershell
. (Join-Path $PSScriptRoot 'lib\card-choreography.ps1')
```

**Delete** lines 99-173 (the `# Normalized frames...` anchor/geometry block, the mascot `$win.Add_Loaded({...})`, and the scene `$win.Add_Loaded({...})`). **Replace** them with:

```powershell
# Mascot + scene choreography, started once the card has laid out.
$win.Add_Loaded({ Start-CardChoreography $box $theme $ev $PSScriptRoot }.GetNewClosure())
```

(`$box`, `$theme`, `$ev` are already in scope from lines 46-96.)

- [ ] **Step 4: Run the golden guard + a manual smoke check**

Run: `bash tests/show-notification.Tests.sh`
Expected: `ok: default XAML matches golden`.

Manual (optional, on Windows): `powershell.exe -ExecutionPolicy Bypass -File show-notification.ps1 -Event done -Seconds 6` shows the card with the mascot walking and confetti — i.e. choreography still runs.

- [ ] **Step 5: Commit**

```bash
git add lib/card-choreography.ps1 show-notification.ps1
git commit -m "Extract Start-CardChoreography shared by notifier and editor"
```

---

## Task 5: The editor window `settings-editor.ps1` + `-DryRun` seam

> **Execution correction (closure scope — the code below uses `.GetNewClosure()` everywhere,
> which will BREAK at runtime):** a `.GetNewClosure()` scriptblock rebinds to a module scope
> that cannot see dot-sourced (script-scoped) functions like `Set-ModelValue`,
> `Initialize-NotificationCard`, `Start-CardChoreography`. Use this strategy instead:
> - Dot-source **`lib\scene-unicorn.ps1`** too (the plan's dot-source list omits it).
> - Keep the rebuilt card refs script-scoped: assign `$script:box/$script:theme/$script:ev`
>   inside the rebuild so a **plain** scriptblock (no closure) can see both them and the
>   dot-sourced functions. Register the debounce-timer `Add_Tick`, `Add_Loaded`, and the
>   Save/Reload `Add_Click` as **plain** scriptblocks.
> - For the per-control handlers in the `foreach` loop, do NOT use `.GetNewClosure()` to
>   snapshot `$field`/`$c`. Instead stash the field descriptor on the control
>   (`$c.Tag = $field`) and use ONE shared plain handler per kind that reads the sender's
>   `.Tag` (e.g. `param($s,$e) $f=$s.Tag; Set-ModelValue $script:model $f.path ...`). Plain
>   scriptblock → script scope → dot-sourced functions visible; `.Tag` carries per-control
>   state without closure capture.
> - Add a headless `-SelfTest` switch that builds the window and runs ONE synchronous
>   rebuild (catching function-visibility / scope errors that `-DryRun` can't), then exits.
>   Wire it into `tests/settings-editor.Tests.sh`.

**Files:**
- Create: `settings-editor.ps1`
- Test: `tests/settings-editor.Tests.sh`

The window itself isn't unit-tested; the `-DryRun` field-list dump and the Save round-trip are.

- [ ] **Step 1: Write the failing test**

Create `tests/settings-editor.Tests.sh`:

```bash
#!/usr/bin/env bash
# Exercises settings-editor.ps1 without WPF: -DryRun prints the resolved field list, and
# -DryRun -Save <file> writes the (unchanged) model back as JSON. Uses a temp settings file.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CFG="$TMP/settings.json"
cat > "$CFG" <<'JSON'
{ "activeTheme": "sakura",
  "events": { "done": { "label": "Done!", "mascot": { "move": "walk", "end": "confetti" } } },
  "themes": { "sakura": { "hero": "🌸", "card": "#1A1620",
              "scene": { "kind": "sakura", "petals": true, "count": 22 } },
              "dragon": { "hero": "🐉", "card": "#1A0F0A" } } }
JSON

run() { powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w "$ROOT/settings-editor.ps1")" "$@" | tr -d '\r'; }

fail=0
check() { if eval "$2"; then echo "ok: $1"; else echo "FAIL: $1"; fail=1; fi; }

OUT="$(run -SettingsPath "$(wslpath -w "$CFG")" -DryRun)"
check "lists activeTheme dropdown" "grep -q 'dropdown activeTheme' <<<\"\$OUT\""
check "lists event label field"    "grep -q 'text events.done.label' <<<\"\$OUT\""
check "lists scene petals checkbox" "grep -q 'checkbox themes.sakura.scene.petals' <<<\"\$OUT\""

# Save round-trip: write to a new file, then confirm it parses and keeps a known value.
run -SettingsPath "$(wslpath -w "$CFG")" -DryRun -SaveTo "$(wslpath -w "$TMP/out.json")" >/dev/null
check "save writes valid json" "jq -e . '$TMP/out.json' >/dev/null"
check "save keeps label" "[[ \"\$(jq -r .events.done.label '$TMP/out.json')\" == 'Done!' ]]"

exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/settings-editor.Tests.sh`
Expected: FAIL — `settings-editor.ps1` does not exist.

- [ ] **Step 3: Write the editor**

Create `settings-editor.ps1`:

```powershell
param(
  [string]$SettingsPath = (Join-Path $PSScriptRoot 'settings.json'),
  [string]$Event = 'done',
  [switch]$DryRun,        # print the field list and exit (no WPF)
  [string]$SaveTo = ''    # with -DryRun: serialize the model to this path and exit
)
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

. (Join-Path $PSScriptRoot 'notify-lib.ps1')
. (Join-Path $PSScriptRoot 'lib\settings-model.ps1')

# --- Load model + derive selected theme (concrete even when activeTheme is "random") ---
$model = Read-SettingsModel $SettingsPath
$enums = Get-SchemaEnums (Join-Path $PSScriptRoot 'settings.schema.json')
$themeNames = @((Get-ModelValue $model @('themes')).Keys)
$active = [string](Get-ModelValue $model @('activeTheme'))
$selectedTheme = if ($active -and $active -ne 'random' -and ($themeNames -contains $active)) { $active } else { $themeNames[0] }
$fields = Get-EditorFields $model $enums $Event $selectedTheme

# --- Headless seam: print the field list (and optionally Save), then exit ---
if ($DryRun) {
  foreach ($f in $fields) { Write-Output ("{0} {1}" -f $f.kind, ($f.path -join '.')) }
  if ($SaveTo) { Set-Content -Path $SaveTo -Value (ConvertTo-SettingsJson $model) -Encoding UTF8 }
  return
}

# --- WPF libs only needed for the live window ---
. (Join-Path $PSScriptRoot 'lib\notification-box.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-player.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-clip.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-jump-prep.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-jump.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-walk.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-hjump.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-gym.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-confetti.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-flag-waver.ps1')
. (Join-Path $PSScriptRoot 'lib\scene-waves.ps1')
. (Join-Path $PSScriptRoot 'lib\scene-space.ps1')
. (Join-Path $PSScriptRoot 'lib\scene-matrix.ps1')
. (Join-Path $PSScriptRoot 'lib\scene-sakura.ps1')
. (Join-Path $PSScriptRoot 'lib\card-choreography.ps1')

$ctx = Get-SampleContext

# --- Shell: controls (scrollable) on top, card host on the bottom ---
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="claude-notify settings" Width="680" Height="900" Background="#15151A">
  <DockPanel>
    <DockPanel DockPanel.Dock="Top" LastChildFill="False" Margin="10,8">
      <Button x:Name="save" Content="Save" Width="90" Height="28" DockPanel.Dock="Right" Margin="6,0,0,0"/>
      <Button x:Name="reload" Content="Reload" Width="90" Height="28" DockPanel.Dock="Right"/>
      <TextBlock x:Name="status" Foreground="#9CA3AF" VerticalAlignment="Center"/>
    </DockPanel>
    <Border DockPanel.Dock="Bottom" Height="461" Background="#0B0B10">
      <Grid x:Name="cardHost"/>
    </Border>
    <ScrollViewer VerticalScrollBarVisibility="Auto">
      <StackPanel x:Name="form" Margin="12"/>
    </ScrollViewer>
  </DockPanel>
</Window>
"@
$win = [Windows.Markup.XamlReader]::Parse($xaml)
$form = $win.FindName('form'); $cardHost = $win.FindName('cardHost'); $status = $win.FindName('status')

# --- Debounced full rebuild of the bottom card from the current model ---
$rebuildTimer = New-Object System.Windows.Threading.DispatcherTimer
$rebuildTimer.Interval = [TimeSpan]::FromMilliseconds(150)
$rebuildTimer.Add_Tick({
  $rebuildTimer.Stop()
  $cardHost.Children.Clear()
  $themeName = [string](Get-ModelValue $model @('activeTheme'))
  if (-not $themeName -or $themeName -eq 'random' -or -not ($themeNames -contains $themeName)) { $themeName = $selectedTheme }
  $theme = Resolve-Theme $model $themeName
  $ev    = Resolve-Event $model $Event
  $bodyLines = @(Resolve-BodyLines $ev.body $ctx)
  $footer    = @(Resolve-Footer $ev.footer $ctx)
  $wa = New-Object System.Drawing.Rectangle 0, 0, 1920, 1080
  $box = New-NotificationBox -Event $Event -Theme $theme -Ev $ev -BodyLines $bodyLines -Footer $footer -WorkArea $wa
  $grid = $box.Win.Content; $box.Win.Content = $null      # steal the card's inner Grid
  $grid.Opacity = 1                                       # the Window starts at 0 for its fade
  $cardHost.Children.Add($grid) | Out-Null
  # Run card setup + choreography once the stolen Grid has laid out in its new host.
  $cardHost.Dispatcher.BeginInvoke([action]{
    Initialize-NotificationCard $box
    Start-CardChoreography $box $theme $ev $PSScriptRoot
  }, [System.Windows.Threading.DispatcherPriority]::Loaded) | Out-Null
}.GetNewClosure())
function Request-Rebuild { $rebuildTimer.Stop(); $rebuildTimer.Start() }

# --- Build a labelled control per field ---
function Add-Row($labelText, $control) {
  $row = New-Object System.Windows.Controls.DockPanel
  $row.Margin = New-Object System.Windows.Thickness 0, 0, 0, 6
  $lbl = New-Object System.Windows.Controls.TextBlock
  $lbl.Text = $labelText; $lbl.Width = 130; $lbl.Foreground = (New-Brush '#D1D5DB'); $lbl.VerticalAlignment = 'Center'
  [System.Windows.Controls.DockPanel]::SetDock($lbl, 'Left')
  $row.Children.Add($lbl) | Out-Null
  $row.Children.Add($control) | Out-Null
  $form.Children.Add($row) | Out-Null
}

foreach ($f in $fields) {
  $field = $f   # capture per-iteration for the closures below
  switch ($field.kind) {
    'checkbox' {
      $c = New-Object System.Windows.Controls.CheckBox
      $c.IsChecked = [bool](Get-ModelValue $model $field.path)
      $c.VerticalAlignment = 'Center'
      $c.Add_Click({ Set-ModelValue $model $field.path ([bool]$c.IsChecked); Request-Rebuild }.GetNewClosure())
      Add-Row $field.label $c
    }
    'dropdown' {
      $c = New-Object System.Windows.Controls.ComboBox
      foreach ($o in $field.options) { $c.Items.Add([string]$o) | Out-Null }
      $c.SelectedItem = [string](Get-ModelValue $model $field.path)
      $c.Add_SelectionChanged({ Set-ModelValue $model $field.path ([string]$c.SelectedItem); Request-Rebuild }.GetNewClosure())
      Add-Row $field.label $c
    }
    default {   # 'text' and 'number'
      $c = New-Object System.Windows.Controls.TextBox
      $c.Text = [string](Get-ModelValue $model $field.path); $c.Width = 360; $c.HorizontalAlignment = 'Left'
      $kind = $field.kind
      $c.Add_TextChanged({ Set-ModelValue $model $field.path (ConvertTo-ModelValue $kind $c.Text); Request-Rebuild }.GetNewClosure())
      Add-Row $field.label $c
    }
  }
}

$win.FindName('save').Add_Click({
  Set-Content -Path $SettingsPath -Value (ConvertTo-SettingsJson $model) -Encoding UTF8
  $status.Text = "Saved $([DateTime]::Now.ToString('HH:mm:ss'))"
}.GetNewClosure())
$win.FindName('reload').Add_Click({
  $script:model = Read-SettingsModel $SettingsPath
  $status.Text = "Reloaded — restart to rebuild the form"; Request-Rebuild
}.GetNewClosure())

$win.Add_Loaded({ Request-Rebuild }.GetNewClosure())
$win.ShowDialog() | Out-Null
```

Note on `New-Brush`: it is defined in `lib/notification-box.ps1`, dot-sourced above.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/settings-editor.Tests.sh`
Expected: PASS — all `ok:` lines, exit 0.

- [ ] **Step 5: Commit**

```bash
git add settings-editor.ps1 tests/settings-editor.Tests.sh
git commit -m "Add settings editor window with live looping card preview"
```

---

## Task 6: Wire tests into the runner + document

**Files:**
- Modify: `tests/run.sh` (append the two new suites)
- Modify: `README.md` (add a "Settings editor" section)

- [ ] **Step 1: Append the new suites to `tests/run.sh`**

Before the final `echo "----"` summary line, add:

```bash
# --- settings model (pure PS) + editor seam ---
ok "settings model" 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$(dirname "$0")/settings-model.Tests.ps1")" >/dev/null 2>&1'
ok "settings editor seam" 'bash "$(dirname "$0")/settings-editor.Tests.sh" >/dev/null 2>&1'
```

- [ ] **Step 2: Run the full suite**

Run: `bash tests/run.sh`
Expected: ends `… passed, 0 failed` (includes the two new lines as PASS).

- [ ] **Step 3: Document the editor in `README.md`**

Add this section after the "Trigger manually" section:

```markdown
## Settings editor

A live editor for `settings.json` — controls on top, the notification card looping below.
Edits are in-memory until you press **Save**.

```powershell
.\settings-editor.ps1
```

Pick the event, theme, mascot moves, sounds and the active theme's scene toggles; the card
re-renders as you change them. Body/footer text and gradient colours aren't editable yet —
edit those in `settings.json` directly.
```

- [ ] **Step 4: Verify the docs render**

Run: `grep -n "Settings editor" README.md`
Expected: matches the new heading.

- [ ] **Step 5: Commit**

```bash
git add tests/run.sh README.md
git commit -m "Wire settings-editor tests into runner; document the editor"
```

---

## Notes for the implementer

- **Windows PowerShell 5.1, not Core.** No `ConvertFrom-Json -AsHashtable`; that's why `ConvertTo-HashtableDeep` exists. `[ordered]@{}` is used so Save keeps a stable key order.
- **The golden XAML tests are the contract** for Tasks 3-4. If `tests/show-notification.Tests.sh` goes red, the extraction changed emitted markup — revert and move only code that runs at/after `Loaded`, never the `$xaml` here-string.
- **Reparenting the card:** the editor "steals" `$box.Win.Content` (the inner Grid) into its own host and never shows the notification Window. The element-bag references (`Card/Overlay/Mascot/RimBrush/Fx/BodyTbs`) stay valid after reparenting because they were resolved at build time.
- **Supersedes the spec's `New-NotificationCard` split:** the design doc proposed a separate `New-NotificationCard` returning the inner Grid. This plan instead reuses `New-NotificationBox` and steals its `Content` — same outcome (a hostable card), but the `$xaml` here-string is never touched, so the byte-identical-XAML constraint is guaranteed rather than re-verified. Only `Initialize-NotificationCard` and `Start-CardChoreography` are extracted.
- **Preview Windows aren't explicitly closed** each rebuild (they're never shown; `Content` is detached). Acceptable for v1; revisit if a long editing session shows memory growth.
- **Reload caveat (documented in the UI):** Reload refreshes the model and the preview but not the already-built form controls; a full form rebuild on Reload is deferred (YAGNI for v1).
```
