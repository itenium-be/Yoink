# Vaporwave Scene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `kind: "vaporwave"` animated scene renderer (8 flag-toggled 80s/outrun layers) wired into the existing notification dispatch, schema, and the `vaporwave` theme.

**Architecture:** New `lib/scene-vaporwave.ps1` defines two WPF-free, unit-tested geometry helpers (`New-GridPathData`, `New-MountainPathData`), eight `Add-Vaporwave*` layer functions, and a `Start-Vaporwave($box, $cfg)` entry that draws enabled layers back-to-front into `$box.Scene`. It mirrors `lib/scene-spooky.ps1` exactly and reuses the already-global helpers `New-Brush`, `New-SceneStop`, `Add-Twinkle`. Dispatch, schema, and `settings.json` gain one entry each.

**Tech Stack:** PowerShell + WPF (WSL→`powershell.exe`), JSON/JSONC settings, jq + python3 (`jsonschema`) test assertions, Pester-free `*.Tests.ps1` scripts run via `powershell.exe -File`.

**Spec:** `docs/superpowers/specs/2026-06-29-vaporwave-scene-design.md`

**Working dir:** the repo root (`/mnt/c/temp/notify`) or its isolated worktree. All paths below are relative to it; commands use `$PWD` so they work from either.

---

## File Structure

- **Create** `lib/scene-vaporwave.ps1` — two geometry helpers + 8 layer functions + `Start-Vaporwave`. One responsibility: render the vaporwave scene.
- **Create** `tests/scene-vaporwave.Tests.ps1` — WPF-free unit tests for the two geometry helpers (mirrors `tests/scene-spooky.Tests.ps1`).
- **Modify** `show-notification.ps1` — dot-source the renderer, add the 6 **new** flag reads to `$sceneCfg`, add `vaporwave` to `$sceneKinds`.
- **Modify** `settings.schema.json` — add `"vaporwave"` to `scene.kind` enum + 6 **new** boolean flag properties.
- **Modify** `tests/settings.Tests.sh` — assert the vaporwave scene is schema-wired (mirrors the spooky checks).
- **Modify** `settings.json` — add the default `scene` block to the `vaporwave` theme.

Draw order (back→front): `haze → sun → stars → mountains → grid → palms → scanlines → glow`. Scene horizon is `y = h * 0.52`.

**IMPORTANT — flag reuse:** the flags `sun` and `stars` **already exist** as shared scene properties (defined for `waves`/`space`) — they are already read into `$sceneCfg` and already declared in the schema. The vaporwave renderer **reuses** them. Do **NOT** re-add `sun`/`stars` to `$sceneCfg` or the schema (a duplicate JSON key is invalid). Only the 6 genuinely-new flags — `haze, mountains, grid, palms, scanlines, glow` — are added to dispatch and schema.

Conventions to copy from `lib/scene-spooky.ps1`:
- Geometry helpers use `[System.Globalization.CultureInfo]::InvariantCulture` and `'0.##'` formatting so XAML gets `.` decimals (an `nl-BE` locale would emit `,` and break `Geometry.Parse`).
- Layer functions take `($canvas, [double]$w, [double]$h, ...)` and append to `$canvas.Children`.
- `Add-Twinkle $el $lo $hi $seconds $beginOffset` (already global) loops an auto-reversing opacity fade.

---

## Task 1: Geometry helper `New-GridPathData` (TDD)

**Files:**
- Create: `lib/scene-vaporwave.ps1`
- Create: `tests/scene-vaporwave.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/scene-vaporwave.Tests.ps1`:

```powershell
. "$PSScriptRoot\..\lib\scene-vaporwave.ps1"

$script:fail = 0
function Assert-Eq($got, $exp, $msg) {
  if ("$got" -ne "$exp") { Write-Host "FAIL: $msg`n  exp=[$exp]`n  got=[$got]"; $script:fail++ }
  else { Write-Host "ok: $msg" }
}
function Assert-True($cond, $msg) { Assert-Eq ([bool]$cond) $true $msg }

# Perspective grid: width 100, horizon y=60, bottom y=200, 3 columns, 2 rows,
# vanishing point x=50. Bottom xs = 0, 33.33, 66.67, 100 (cols+1 verticals).
# Horizontal rows tighten toward the horizon: y = 60 + 140 * (r/rows)^2.
#   r=1 -> 60 + 140*0.25 = 95 ; r=2 -> 60 + 140 = 200.
$d = New-GridPathData 100 60 200 3 2 50

Assert-True ($d.StartsWith('M')) "grid path starts with M (moveto)"
Assert-True ($d.Contains('M 50,60 L 0,200')) "left vertical: vanishing point -> bottom-left"
Assert-True ($d.Contains('L 100,200')) "right vertical reaches bottom-right (100,200)"
Assert-True ($d.Contains('33.33,200')) "interior vertical hits bottom at x=33.33"
Assert-True ($d.Contains('M 0,95 L 100,95')) "near-horizon row tightened to y=95"
Assert-True ($d.Contains('M 0,200 L 100,200')) "front row at the bottom edge"
# One 'M 50,60 ' move per vertical line (cols+1 = 4).
Assert-Eq ([regex]::Matches($d, 'M 50,60 ').Count) 4 "one move per vertical (cols+1)"

# Invariant decimals: XAML needs '.', NOT the ',' an nl-BE locale emits.
Assert-True ($d.Contains('33.33')) "uses '.' decimal separator"
Assert-True (-not $d.Contains('33,33')) "does not use ',' decimal separator"

# Degenerate inputs are coerced, never throw / divide by zero.
$d2 = New-GridPathData 100 50 150 0 0 50
Assert-True ($d2.StartsWith('M')) "cols<1 / rows<1 still yields a path"

if ($script:fail -gt 0) { exit 1 } else { Write-Host "ALL PASS" }
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$PWD/tests/scene-vaporwave.Tests.ps1")"
```
Expected: FAIL — `New-GridPathData` is not defined (the lib file doesn't exist yet; dot-source errors / command not found).

- [ ] **Step 3: Write the minimal implementation**

Create `lib/scene-vaporwave.ps1` with the header comment and this helper:

```powershell
# Scenery renderer: vaporwave — eight independent, flag-toggled 80s/outrun layers.
# New-GridPathData / New-MountainPathData are WPF-free + unit-tested; the
# Add-Vaporwave* helpers build live WPF visuals. Dot-sourced by show-notification.ps1.

# XAML path geometry for a receding perspective grid: `cols`+1 vertical threads
# fanning from the vanishing point (vanishX, horizonY) to evenly-spaced points along
# the bottom edge, plus `rows` full-width horizontal threads whose spacing tightens
# toward the horizon (y = horizonY + (bottomY-horizonY) * (r/rows)^2). One combined
# Path data string (multiple M subpaths), stroked.
# Invariant culture: XAML needs '.' decimals; nl-BE would emit ',' and choke Parse.
function New-GridPathData([double]$w, [double]$horizonY, [double]$bottomY, [int]$cols, [int]$rows, [double]$vanishX) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  if ($cols -lt 1) { $cols = 1 }
  if ($rows -lt 1) { $rows = 1 }
  $f = { param($v) ([double]$v).ToString('0.##', $ic) }
  $sb = New-Object System.Text.StringBuilder
  for ($c = 0; $c -le $cols; $c++) {
    $bx = $w * $c / $cols
    [void]$sb.Append(("M {0},{1} L {2},{3} " -f (&$f $vanishX), (&$f $horizonY), (&$f $bx), (&$f $bottomY)))
  }
  for ($r = 1; $r -le $rows; $r++) {
    $t = $r / $rows
    $y = $horizonY + ($bottomY - $horizonY) * $t * $t
    [void]$sb.Append(("M 0,{0} L {1},{0} " -f (&$f $y), (&$f $w)))
  }
  $sb.ToString().TrimEnd()
}
```

(For `New-GridPathData 100 60 200 3 2 50`: bottom xs = `0, 33.33, 66.67, 100`; verticals from `(50,60)`; rows at `y=95` and `y=200`. Matches the assertions.)

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$PWD/tests/scene-vaporwave.Tests.ps1")"
```
Expected: all `ok:` lines, `ALL PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add lib/scene-vaporwave.ps1 tests/scene-vaporwave.Tests.ps1
git commit -m "Add vaporwave New-GridPathData geometry helper"
```

---

## Task 2: Geometry helper `New-MountainPathData` (TDD)

**Files:**
- Modify: `lib/scene-vaporwave.ps1`
- Modify: `tests/scene-vaporwave.Tests.ps1`

- [ ] **Step 1: Write the failing test**

In `tests/scene-vaporwave.Tests.ps1`, insert before the final `if ($script:fail ...` block:

```powershell
# Mountain ridge: closed silhouette across width 100, base y=80, peak y=20, 2 peaks.
# Peak p spans w/peaks; apex at its centre (peakY), valley at its right edge (baseY).
#   p=0 -> apex (25,20), valley (50,80) ; p=1 -> apex (75,20), valley (100,80).
$m = New-MountainPathData 100 80 20 2
Assert-True ($m.StartsWith('M 0,80')) "mountain path starts at the left base (0,80)"
Assert-True ($m.EndsWith('Z'))        "mountain path is closed (filled silhouette ends with Z)"
Assert-True ($m.Contains('L 25,20'))  "first apex at peakY (25,20)"
Assert-True ($m.Contains('L 75,20'))  "second apex at peakY (75,20)"
Assert-True ($m.Contains('L 50,80'))  "interior valley returns to baseY (50,80)"
Assert-True ($m.Contains('L 100,80')) "ridge spans the full width back to base"

# Invariant decimals: a 3-peak ridge puts the first apex at 100*0.5/3 = 16.67.
$m2 = New-MountainPathData 100 80 20 3
Assert-True ($m2.Contains('16.67')) "uses '.' decimal separator"
Assert-True (-not $m2.Contains('16,67')) "does not use ',' decimal separator"

# Degenerate peaks are coerced, never loop forever.
$m3 = New-MountainPathData 100 80 20 0
Assert-True ($m3.StartsWith('M')) "peaks<1 still yields a path"
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$PWD/tests/scene-vaporwave.Tests.ps1")"
```
Expected: FAIL — `New-MountainPathData` is not defined.

- [ ] **Step 3: Write the minimal implementation**

In `lib/scene-vaporwave.ps1`, after `New-GridPathData`, add:

```powershell
# Filled, closed mountain-ridge silhouette: a flat baseline jagged up into `peaks`
# triangular peaks. M at the left base, then for each peak an apex (peakY) at its
# centre and a valley (baseY) at its right edge, finally back along the base + Z.
function New-MountainPathData([double]$w, [double]$baseY, [double]$peakY, [int]$peaks) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  if ($peaks -lt 1) { $peaks = 1 }
  $f = { param($v) ([double]$v).ToString('0.##', $ic) }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append(("M 0,{0} " -f (&$f $baseY)))
  for ($p = 0; $p -lt $peaks; $p++) {
    $apexX = $w * ($p + 0.5) / $peaks
    $valleyX = $w * ($p + 1) / $peaks
    [void]$sb.Append(("L {0},{1} L {2},{3} " -f (&$f $apexX), (&$f $peakY), (&$f $valleyX), (&$f $baseY)))
  }
  [void]$sb.Append(("L {0},{1} Z" -f (&$f $w), (&$f $baseY)))
  $sb.ToString()
}
```

(For `New-MountainPathData 100 80 20 2`: apexes at `25` and `75` (peakY=20), valleys at `50` and `100` (baseY=80). For 3 peaks the first apex is `16.67`. Matches the assertions.)

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$PWD/tests/scene-vaporwave.Tests.ps1")"
```
Expected: all `ok:`, `ALL PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add lib/scene-vaporwave.ps1 tests/scene-vaporwave.Tests.ps1
git commit -m "Add vaporwave New-MountainPathData geometry helper"
```

---

## Task 3: Layer functions + `Start-Vaporwave`

No unit test (WPF visuals can't be asserted headlessly); the verification step is that the file dot-sources without error, and the XAML snapshot (Task 4) confirms the scene Canvas. Each step adds functions and re-runs the geometry tests (which dot-source the whole file) to prove it parses.

**Files:**
- Modify: `lib/scene-vaporwave.ps1`

- [ ] **Step 1: Add the haze + sun layers**

Append to `lib/scene-vaporwave.ps1`:

```powershell
# --- layers (back to front) --------------------------------------------------

# Sunset sky wash: a translucent pink -> purple -> cyan vertical gradient backdrop,
# kept semi-transparent so the dark card and centred text stay legible.
function Add-VaporwaveHaze($canvas, [double]$w, [double]$h) {
  $r = New-Object System.Windows.Shapes.Rectangle
  $r.Width = $w; $r.Height = $h
  $g = New-Object System.Windows.Media.LinearGradientBrush
  $g.StartPoint = '0,0'; $g.EndPoint = '0,1'
  $g.GradientStops.Add((New-SceneStop '#CCFF6AD5' 0.0))
  $g.GradientStops.Add((New-SceneStop '#99C774E8' 0.4))
  $g.GradientStops.Add((New-SceneStop '#66AD8CFF' 0.7))
  $g.GradientStops.Add((New-SceneStop '#6694D0FF' 1.0))
  $r.Fill = $g
  [System.Windows.Controls.Canvas]::SetLeft($r, 0); [System.Windows.Controls.Canvas]::SetTop($r, 0)
  $canvas.Children.Add($r) | Out-Null
}

# Banded retro sun sitting on the horizon: a circle (clipped Canvas) filled solid
# across its upper 55%, then sliced into horizontal bands that thin and spread apart
# toward the bottom (the gaps reveal the haze behind). Colour ramps yellow -> pink ->
# magenta down the disc. Gentle opacity pulse, like Add-OceanSun.
function Add-VaporwaveSun($canvas, [double]$w, [double]$h, [double]$speed) {
  $d = $h * 0.5
  $horizon = $h * 0.52
  $cx = $w * 0.5
  $sun = New-Object System.Windows.Controls.Canvas
  $sun.Width = $d; $sun.Height = $d
  $clip = New-Object System.Windows.Media.EllipseGeometry
  $clip.Center = New-Object System.Windows.Point ($d / 2), ($d / 2)
  $clip.RadiusX = $d / 2; $clip.RadiusY = $d / 2
  $sun.Clip = $clip
  # Sample the yellow -> pink -> magenta ramp as a solid colour at fraction t (0..1).
  $col = {
    param([double]$t)
    $a = @(255, 251, 150); $b = @(255, 106, 213); $c = @(255, 113, 206)
    if ($t -le 0.5) { $lo = $a; $hi = $b; $u = $t / 0.5 } else { $lo = $b; $hi = $c; $u = ($t - 0.5) / 0.5 }
    $rr = [int]($lo[0] + ($hi[0] - $lo[0]) * $u)
    $gg = [int]($lo[1] + ($hi[1] - $lo[1]) * $u)
    $bb = [int]($lo[2] + ($hi[2] - $lo[2]) * $u)
    New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb($rr, $gg, $bb))
  }
  $solidH = $d * 0.55
  $top = New-Object System.Windows.Shapes.Rectangle
  $top.Width = $d; $top.Height = $solidH; $top.Fill = (& $col 0.28)
  [System.Windows.Controls.Canvas]::SetTop($top, 0)
  $sun.Children.Add($top) | Out-Null
  $y = $solidH; $bh = $d * 0.07; $gap = $d * 0.02
  while ($y -lt $d) {
    $bar = New-Object System.Windows.Shapes.Rectangle
    $bar.Width = $d; $bar.Height = $bh; $bar.Fill = (& $col ($y / $d))
    [System.Windows.Controls.Canvas]::SetTop($bar, $y)
    $sun.Children.Add($bar) | Out-Null
    $y += $bh + $gap
    $bh = [Math]::Max(1.5, $bh - $d * 0.008)
    $gap += $d * 0.006
  }
  [System.Windows.Controls.Canvas]::SetLeft($sun, $cx - $d / 2)
  [System.Windows.Controls.Canvas]::SetTop($sun, $horizon - $d)
  $canvas.Children.Add($sun) | Out-Null
  $pulse = New-Object System.Windows.Media.Animation.DoubleAnimation 0.8, 0.97, ([System.Windows.Duration][TimeSpan]::FromSeconds(5.0 / $speed))
  $pulse.AutoReverse = $true; $pulse.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $sun.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $pulse)
}
```

- [ ] **Step 2: Add the stars, mountains, and grid layers**

Append:

```powershell
# Twinkling dots confined to the upper sky (above the horizon band).
function Add-VaporwaveStars($canvas, [double]$w, [double]$h, [double]$speed) {
  $skyH = [int]($h * 0.48)
  for ($i = 0; $i -lt 28; $i++) {
    $sz = 1.2 + (Get-Random -Minimum 0 -Maximum 18) / 10.0
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = $sz; $e.Height = $sz; $e.Fill = New-Brush '#FFFFFFFF'
    [System.Windows.Controls.Canvas]::SetLeft($e, (Get-Random -Minimum 0 -Maximum ([int]$w)))
    [System.Windows.Controls.Canvas]::SetTop($e, (Get-Random -Minimum 0 -Maximum $skyH))
    $canvas.Children.Add($e) | Out-Null
    $dur = (1.6 + (Get-Random -Minimum 0 -Maximum 30) / 10.0) / $speed
    Add-Twinkle $e 0.15 0.9 $dur ((Get-Random -Minimum 0 -Maximum 30) / 10.0)
  }
}

# Distant neon-rimmed mountain ridge resting on the horizon. Dark near-card fill so
# the grid reads in front of it; a thin neon-cyan stroke gives the wireframe edge.
function Add-VaporwaveMountains($canvas, [double]$w, [double]$h, [double]$opacity) {
  $horizon = $h * 0.52
  $data = New-MountainPathData $w $horizon ($horizon - $h * 0.16) 5
  $path = New-Object System.Windows.Shapes.Path
  $path.Data = [System.Windows.Media.Geometry]::Parse($data)
  $path.Fill = New-Brush '#CC160F1F'
  $path.Stroke = New-Brush '#FF01CDFE'
  $path.StrokeThickness = 1.2
  $path.Opacity = [Math]::Min(1.0, $opacity * 2.2)
  [System.Windows.Controls.Canvas]::SetLeft($path, 0); [System.Windows.Controls.Canvas]::SetTop($path, 0)
  $canvas.Children.Add($path) | Out-Null
}

# Receding neon perspective grid from the horizon to the bottom edge, scrolling
# gently toward the viewer. The seamless-scroll is approximate: translate down by
# the nearest-row spacing on a short loop (a subtle backdrop, not a precise floor).
function Add-VaporwaveGrid($canvas, [double]$w, [double]$h, [double]$opacity, [double]$speed) {
  $horizon = $h * 0.52
  $rows = 8
  $data = New-GridPathData $w $horizon $h 12 $rows ($w * 0.5)
  $path = New-Object System.Windows.Shapes.Path
  $path.Data = [System.Windows.Media.Geometry]::Parse($data)
  $path.Stroke = New-Brush '#FF01CDFE'
  $path.StrokeThickness = 1.0
  $path.Opacity = [Math]::Min(1.0, $opacity * 2.0)
  [System.Windows.Controls.Canvas]::SetLeft($path, 0); [System.Windows.Controls.Canvas]::SetTop($path, 0)
  $tt = New-Object System.Windows.Media.TranslateTransform
  $path.RenderTransform = $tt
  $canvas.Children.Add($path) | Out-Null
  $rf = [double]($rows - 1) / $rows
  $nearStep = ($h - $horizon) * (1.0 - $rf * $rf)
  $drift = New-Object System.Windows.Media.Animation.DoubleAnimation 0, $nearStep, ([System.Windows.Duration][TimeSpan]::FromSeconds(2.6 / $speed))
  $drift.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $drift)
}
```

- [ ] **Step 3: Add the palms, scanlines, and glow layers**

Append:

```powershell
# Angular palm silhouettes framing the bottom corners. Straight-segment fronds drawn
# inline (no curves -> no geometry helper needed). Invariant culture so the inline
# path coords keep '.' decimals. Off by default: the 🌴 hero already owns the motif.
function Add-VaporwavePalms($canvas, [double]$w, [double]$h) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  $f = { param($v) ([double]$v).ToString('0.##', $ic) }
  $fill = New-Brush '#E60D0A14'
  $palm = {
    param([double]$bx, [double]$by, [double]$ph, [int]$dir)
    $tw = $ph * 0.05
    $crownY = $by - $ph
    $cx = $bx + $dir * $ph * 0.08
    $d = "M $(&$f ($bx - $tw)),$(&$f $by) " +
         "L $(&$f ($bx + $tw)),$(&$f $by) " +
         "L $(&$f ($cx + $tw)),$(&$f $crownY) " +
         "L $(&$f ($cx - $tw)),$(&$f $crownY) Z"
    $fronds = @(@(-0.42, -0.10), @(-0.22, 0.16), @(0.0, 0.30), @(0.22, 0.16), @(0.42, -0.10))
    foreach ($fr in $fronds) {
      $tipX = $cx + $ph * $fr[0]
      $tipY = $crownY - $ph * 0.34 + $ph * $fr[1]
      $d += " M $(&$f $cx),$(&$f $crownY) " +
            "L $(&$f $tipX),$(&$f $tipY) " +
            "L $(&$f ($cx + $ph * $fr[0] * 0.5)),$(&$f ($crownY - $ph * 0.04)) Z"
    }
    $p = New-Object System.Windows.Shapes.Path
    $p.Data = [System.Windows.Media.Geometry]::Parse($d)
    $p.Fill = $fill
    [System.Windows.Controls.Canvas]::SetLeft($p, 0); [System.Windows.Controls.Canvas]::SetTop($p, 0)
    $canvas.Children.Add($p) | Out-Null
  }
  & $palm ($w * 0.10) $h ($h * 0.42) (-1)
  & $palm ($w * 0.90) $h ($h * 0.42) (1)
}

# VHS scanlines: thin dark horizontal lines across the whole card, rolling slowly
# downward. The roll loops seamlessly by translating exactly one line spacing (lines
# repeat every $step, and one extra line is drawn past the bottom).
function Add-VaporwaveScanlines($canvas, [double]$w, [double]$h, [double]$opacity, [double]$speed) {
  $group = New-Object System.Windows.Controls.Canvas
  $step = 4.0
  $fill = New-Brush '#FF000000'
  $y = 0.0
  while ($y -lt $h + $step) {
    $line = New-Object System.Windows.Shapes.Rectangle
    $line.Width = $w; $line.Height = 1.0; $line.Fill = $fill
    [System.Windows.Controls.Canvas]::SetTop($line, $y)
    $group.Children.Add($line) | Out-Null
    $y += $step
  }
  $group.Opacity = [Math]::Min(0.5, $opacity * 1.1)
  [System.Windows.Controls.Canvas]::SetLeft($group, 0); [System.Windows.Controls.Canvas]::SetTop($group, 0)
  $tt = New-Object System.Windows.Media.TranslateTransform
  $group.RenderTransform = $tt
  $canvas.Children.Add($group) | Out-Null
  $drift = New-Object System.Windows.Media.Animation.DoubleAnimation 0, $step, ([System.Windows.Duration][TimeSpan]::FromSeconds(6.0 / $speed))
  $drift.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $drift)
}

# Neon bloom band along the horizon: a wide rectangle with a vertical transparent ->
# cyan -> transparent gradient, flickering subtly via Add-Twinkle.
function Add-VaporwaveGlow($canvas, [double]$w, [double]$h, [double]$opacity, [double]$speed) {
  $horizon = $h * 0.52
  $bandH = $h * 0.18
  $r = New-Object System.Windows.Shapes.Rectangle
  $r.Width = $w; $r.Height = $bandH
  $g = New-Object System.Windows.Media.LinearGradientBrush
  $g.StartPoint = '0,0'; $g.EndPoint = '0,1'
  $g.GradientStops.Add((New-SceneStop '#0001CDFE' 0.0))
  $g.GradientStops.Add((New-SceneStop '#9901CDFE' 0.5))
  $g.GradientStops.Add((New-SceneStop '#0001CDFE' 1.0))
  $r.Fill = $g
  [System.Windows.Controls.Canvas]::SetLeft($r, 0); [System.Windows.Controls.Canvas]::SetTop($r, $horizon - $bandH / 2)
  $canvas.Children.Add($r) | Out-Null
  Add-Twinkle $r ($opacity * 1.4) ([Math]::Min(1.0, $opacity * 2.0)) (4.5 / $speed) 0
}
```

- [ ] **Step 4: Add the `Start-Vaporwave` entry point**

Append:

```powershell
# Render the vaporwave scene into $box.Scene. $cfg: @{ colors; opacity; speed; + the
# eight layer flags }. Back-to-front draw order; called from a Loaded handler so the
# card ActualWidth/Height are known. Nothing draws unless its flag is set.
function Start-Vaporwave($box, $cfg) {
  $canvas = $box.Scene
  if ($null -eq $canvas) { return }
  $card = $box.Card
  $w = [double]$card.ActualWidth; $h = [double]$card.ActualHeight
  if ($w -le 0 -or $h -le 0) { return }

  $opacity = [double]$cfg.opacity; if ($opacity -le 0) { $opacity = 0.22 }
  $speed = [double]$cfg.speed; if ($speed -le 0) { $speed = 1.0 }

  $canvas.Width = $w; $canvas.Height = $h

  if ($cfg.haze)      { Add-VaporwaveHaze      $canvas $w $h }
  if ($cfg.sun)       { Add-VaporwaveSun       $canvas $w $h $speed }
  if ($cfg.stars)     { Add-VaporwaveStars     $canvas $w $h $speed }
  if ($cfg.mountains) { Add-VaporwaveMountains  $canvas $w $h $opacity }
  if ($cfg.grid)      { Add-VaporwaveGrid      $canvas $w $h $opacity $speed }
  if ($cfg.palms)     { Add-VaporwavePalms     $canvas $w $h }
  if ($cfg.scanlines) { Add-VaporwaveScanlines $canvas $w $h $opacity $speed }
  if ($cfg.glow)      { Add-VaporwaveGlow      $canvas $w $h $opacity $speed }
}
```

- [ ] **Step 5: Verify the file still parses (re-run the geometry tests)**

The test dot-sources the whole renderer, so a syntax error anywhere fails it.

Run:
```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$PWD/tests/scene-vaporwave.Tests.ps1")"
```
Expected: `ALL PASS`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add lib/scene-vaporwave.ps1
git commit -m "Add vaporwave scene layers and Start-Vaporwave entry point"
```

---

## Task 4: Wire the renderer into dispatch

**Files:**
- Modify: `show-notification.ps1` (the `lib\scene-*` includes; the `$sceneCfg` hashtable; the `$sceneKinds` table)

- [ ] **Step 1: Dot-source the renderer**

Find:
```powershell
. (Join-Path $PSScriptRoot 'lib\scene-spooky.ps1')
```
Add directly below it:
```powershell
. (Join-Path $PSScriptRoot 'lib\scene-vaporwave.ps1')
```

- [ ] **Step 2: Add the 6 new flag reads to `$sceneCfg`**

`sun` and `stars` are already present in `$sceneCfg` (shared with waves/space) — do **not** add them again. Find the last scene-flag line in the `$sceneCfg = @{ ... }` block:
```powershell
    lightning    = [bool](Get-Prop $theme.scene 'lightning')
```
Add directly below it (before the closing `}`):
```powershell
    haze         = [bool](Get-Prop $theme.scene 'haze')
    mountains    = [bool](Get-Prop $theme.scene 'mountains')
    grid         = [bool](Get-Prop $theme.scene 'grid')
    palms        = [bool](Get-Prop $theme.scene 'palms')
    scanlines    = [bool](Get-Prop $theme.scene 'scanlines')
    glow         = [bool](Get-Prop $theme.scene 'glow')
```

- [ ] **Step 3: Add `vaporwave` to the dispatch table**

Find:
```powershell
  spooky  = { param($b, $c) Start-Spooky $b $c }
```
Add directly below it (before the closing `}` of `$sceneKinds`):
```powershell
  vaporwave = { param($b, $c) Start-Vaporwave $b $c }
```

- [ ] **Step 4: Verify the scene Canvas is emitted for a vaporwave theme**

Run (swaps a temp vaporwave settings.json in, emits the XAML, restores):
```bash
S="$PWD/settings.json"; cp "$S" /tmp/vw-s.bak
cat > "$S" <<'JSON'
{ "activeTheme": "t", "themes": { "t": { "scene": { "kind": "vaporwave", "haze": true, "grid": true } } } }
JSON
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$PWD/show-notification.ps1")" -Event done -EmitXaml | tr -d '\r' | grep -q 'x:Name="scene"' && echo "SCENE CANVAS PRESENT" || echo "MISSING"
cp /tmp/vw-s.bak "$S"
```
Expected: `SCENE CANVAS PRESENT`, no PowerShell errors on stderr.

- [ ] **Step 5: Commit**

```bash
git add show-notification.ps1
git commit -m "Wire vaporwave scene into notification dispatch"
```

---

## Task 5: Schema wiring + settings test (TDD)

**Files:**
- Modify: `tests/settings.Tests.sh`
- Modify: `settings.schema.json`
- Modify: `settings.json`

- [ ] **Step 1: Write the failing schema checks**

In `tests/settings.Tests.sh`, find the spooky schema checks ending with:
```bash
check "schema defines spooky scene flags" \
  "[[ \"\$(jq -c '.definitions.scene.properties|[has(\"moon\"),has(\"fog\"),has(\"gravestones\"),has(\"webs\"),has(\"ghosts\"),has(\"bats\"),has(\"eyes\"),has(\"lightning\")]' '$SCHEMA')\" == '[true,true,true,true,true,true,true,true]' ]]"
```
Add directly below it (before `exit $fail`):
```bash
check "vaporwave has vaporwave scene"       "[[ \"\$(jq -r '.themes.vaporwave.scene.kind // empty' '$F')\" == 'vaporwave' ]]"
check "schema scene.kind allows vaporwave"  "jq -e '.definitions.scene.properties.kind.enum|index(\"vaporwave\")' '$SCHEMA' >/dev/null"
check "schema defines vaporwave scene flags" \
  "[[ \"\$(jq -c '.definitions.scene.properties|[has(\"haze\"),has(\"sun\"),has(\"stars\"),has(\"mountains\"),has(\"grid\"),has(\"palms\"),has(\"scanlines\"),has(\"glow\")]' '$SCHEMA')\" == '[true,true,true,true,true,true,true,true]' ]]"
```
(`sun` and `stars` already exist in the schema; this check confirms the full vaporwave flag set is present.)

- [ ] **Step 2: Run the tests to verify the new checks fail**

Run:
```bash
cd "$PWD" && bash tests/settings.Tests.sh
```
Expected: the three new lines FAIL (`vaporwave has vaporwave scene`, `schema scene.kind allows vaporwave`, `schema defines vaporwave scene flags`); everything else `ok`.

- [ ] **Step 3: Add `vaporwave` to the schema `kind` enum**

In `settings.schema.json`, find:
```json
        "kind": { "enum": ["waves", "space", "matrix", "sakura", "unicorn", "spooky"], "description": "Scenery renderer: \"waves\" (ocean), \"space\" (cosmic), \"matrix\" (digital rain), \"sakura\" (cherry-blossom petals), \"unicorn\" (rainbow / aurora / glitter / pastel) or \"spooky\" (Halloween / haunted)." },
```
Replace with:
```json
        "kind": { "enum": ["waves", "space", "matrix", "sakura", "unicorn", "spooky", "vaporwave"], "description": "Scenery renderer: \"waves\" (ocean), \"space\" (cosmic), \"matrix\" (digital rain), \"sakura\" (cherry-blossom petals), \"unicorn\" (rainbow / aurora / glitter / pastel), \"spooky\" (Halloween / haunted) or \"vaporwave\" (80s outrun: sun / grid / scanlines)." },
```

- [ ] **Step 4: Add the 6 new vaporwave flag properties**

In `settings.schema.json`, find the last scene flag property (the spooky `lightning`):
```json
        "lightning": { "type": "boolean", "description": "spooky: draw occasional full-card lightning flashes." }
```
Add a comma after it and append the 6 new vaporwave flags (`sun`/`stars` are already declared above for waves/space and are reused — do not re-add them):
```json
        "lightning": { "type": "boolean", "description": "spooky: draw occasional full-card lightning flashes." },
        "haze": { "type": "boolean", "description": "vaporwave: draw a sunset sky wash (pink/purple/cyan)." },
        "mountains": { "type": "boolean", "description": "vaporwave: draw a neon wireframe mountain ridge on the horizon." },
        "grid": { "type": "boolean", "description": "vaporwave: draw a receding neon perspective grid." },
        "palms": { "type": "boolean", "description": "vaporwave: draw palm silhouettes framing the corners." },
        "scanlines": { "type": "boolean", "description": "vaporwave: draw rolling VHS scanlines over the card." },
        "glow": { "type": "boolean", "description": "vaporwave: draw a neon bloom band along the horizon." }
```

- [ ] **Step 5: Add the default scene block to the `vaporwave` theme**

In `settings.json`, find the `vaporwave` theme:
```json
    "vaporwave": {
      "hero": "🌴",
      "gradient": ["#FF6AD5 0", "#C774E8 0.3", "#AD8CFF 0.55", "#8795E8 0.8", "#94D0FF 1"],
      "rim": ["#FF71CE 0", "#B967FF 0.25", "#01CDFE 0.5", "#05FFA1 0.75", "#FFFB96 1"],
      "card": "#160F1F"
    },
```
Replace with (add `,` after the `card` line and insert the `scene` line; keep the trailing `},` that precedes the `robot` theme):
```json
    "vaporwave": {
      "hero": "🌴",
      "gradient": ["#FF6AD5 0", "#C774E8 0.3", "#AD8CFF 0.55", "#8795E8 0.8", "#94D0FF 1"],
      "rim": ["#FF71CE 0", "#B967FF 0.25", "#01CDFE 0.5", "#05FFA1 0.75", "#FFFB96 1"],
      "card": "#160F1F",
      "scene": { "kind": "vaporwave", "haze": true, "sun": true, "grid": true, "scanlines": true }
    },
```

- [ ] **Step 6: Run the settings tests to verify they pass**

Run:
```bash
cd "$PWD" && bash tests/settings.Tests.sh
```
Expected: all `ok:`, exit 0 (the three new checks now pass).

- [ ] **Step 7: Full schema validation (0 errors)**

Run:
```bash
cd "$PWD" && python3 - <<'PY'
import json,subprocess,sys
raw=open("settings.json").read()
s=subprocess.run([sys.executable,"tests/strip-jsonc.py"],input=raw,capture_output=True,text=True).stdout
import jsonschema
errs=list(jsonschema.Draft7Validator(json.load(open("settings.schema.json"))).iter_errors(json.loads(s)))
print(f"{len(errs)} error(s)"); [print(" -",list(e.path),e.message) for e in errs]
PY
```
Expected: `0 error(s)`.

- [ ] **Step 8: Commit**

```bash
git add settings.schema.json settings.json tests/settings.Tests.sh
git commit -m "Wire vaporwave scene into schema and settings"
```

---

## Task 6: Verification & visual acceptance

**Files:** none (verification only)

- [ ] **Step 1: Default-equivalence golden test stays green**

The no-scene default look must be byte-identical. Run:
```bash
cd "$PWD" && bash tests/scene.Tests.sh
```
Expected: `ok: scened theme emits scene Canvas`, `ok: plain theme omits scene Canvas`, exit 0.

- [ ] **Step 2: Per-flag render smoke (each of the 8 flags alone, exit 0, no stderr)**

Run:
```bash
cd "$PWD"
S=settings.json; cp "$S" /tmp/vw-s.bak
for flag in haze sun stars mountains grid palms scanlines glow; do
  cat > "$S" <<JSON
{ "activeTheme": "vaporwave", "themes": { "vaporwave": { "hero":"🌴","gradient":["#FF6AD5 0","#94D0FF 1"],"rim":["#FF71CE 0","#FFFB96 1"],"card":"#160F1F","scene": { "kind": "vaporwave", "$flag": true } } } }
JSON
  err=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$PWD/show-notification.ps1")" -Event done -EmitXaml 2>&1 1>/dev/null | tr -d '\r')
  if [ -z "$err" ]; then echo "ok: $flag"; else echo "FAIL: $flag -> $err"; fi
done
cp /tmp/vw-s.bak "$S"
```
Expected: `ok:` for all 8 flags, no `FAIL`.

- [ ] **Step 2.5: Run the full test suite**

Run:
```bash
cd "$PWD"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$PWD/tests/scene-vaporwave.Tests.ps1")"
bash tests/settings.Tests.sh
bash tests/scene.Tests.sh
bash tests/run.sh
```
Expected: each exits 0 / `ALL PASS` / `0 failed`.

- [ ] **Step 3: Visual check (live popup, default preset)**

Temporarily point `activeTheme` at `vaporwave` for this check (back up & restore `settings.json`), then run:
```bash
cd "$PWD"
S=settings.json; cp "$S" /tmp/vw-s.bak
# edit settings.json: set "activeTheme": "vaporwave" (default scene block already added in Task 5)
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w "$PWD/show-notification.ps1")" \
  -Hwnd 0 -Folder demo -Event done -Seconds 8
cp /tmp/vw-s.bak "$S"
```
Expected: a popup with the haze sky wash + banded sun on the horizon + neon perspective grid scrolling + rolling VHS scanlines, all behind a readable 🌴 hero and body text. Screenshot for the prune-later evaluation. (Repeat with `-Event needs-input` to check the other event.)

- [ ] **Step 4: (Optional) activate the theme**

Only if the user wants vaporwave live: set `"activeTheme": "vaporwave"` in `settings.json`, re-run the settings tests, and commit:
```bash
cd "$PWD"
# edit settings.json: "activeTheme": "vaporwave"
bash tests/settings.Tests.sh
git add settings.json && git commit -m "Activate vaporwave theme"
```

---

## Self-Review (completed by plan author)

- **Spec coverage:** model/config (Task 5 step 5), 8 layers + draw order (Task 3), two unit-tested geometry helpers (Tasks 1–2), dispatch wiring (Task 4), schema enum + flags (Task 5), back-compat golden test (Task 6 step 1), error handling — `ActualWidth/Height ≤ 0` early return is in `Start-Vaporwave` (Task 3 step 4), unknown-kind/throw paths are pre-existing dispatch behavior (unchanged), testing items 1–7 map to Tasks 1–2 + Task 6. Default preset `haze+sun+grid+scanlines` (Task 5 step 5). All spec sections covered.
- **Flag reuse correctness:** `sun` and `stars` are shared scene flags already present in `$sceneCfg` and the schema; the plan reuses them and adds only the 6 new flags (`haze, mountains, grid, palms, scanlines, glow`) — no duplicate JSON keys. The renderer still reads all 8 (`$cfg.sun`, `$cfg.stars` resolve from the existing reads).
- **Placeholder scan:** no TBD/TODO; every code step shows complete code; every command shows expected output.
- **Type/name consistency:** flag names `haze, sun, stars, mountains, grid, palms, scanlines, glow` are identical across `Start-Vaporwave`, `$sceneCfg`, schema properties, settings checks, and the per-flag smoke loop. Function names `New-GridPathData`, `New-MountainPathData`, `Add-Vaporwave{Haze,Sun,Stars,Mountains,Grid,Palms,Scanlines,Glow}`, `Start-Vaporwave` are consistent between definition (Task 3) and dispatch (Task 4). Helper signatures match call sites: `Add-VaporwaveSun $canvas $w $h $speed`, `Add-VaporwaveMountains $canvas $w $h $opacity`, etc.
