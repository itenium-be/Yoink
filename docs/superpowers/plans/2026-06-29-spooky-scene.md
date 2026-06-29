# Spooky Scene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `kind: "spooky"` animated scene renderer (8 flag-toggled Halloween/haunted layers) wired into the existing notification dispatch, schema, and the `spooky` theme.

**Architecture:** New `lib/scene-spooky.ps1` defines two WPF-free, unit-tested geometry helpers (`New-WebPathData`, `New-BatPathData`), eight `Add-Spooky*` layer functions, and a `Start-Spooky($box, $cfg)` entry that draws enabled layers back-to-front into `$box.Scene`. It mirrors `lib/scene-unicorn.ps1` exactly and reuses the already-global helpers `New-Brush`, `New-SceneStop`, `New-WavePathData`, `Add-Twinkle`, `Add-OceanSun`, `Add-OceanClouds`. Dispatch, schema, and `settings.json` gain one entry each.

**Tech Stack:** PowerShell + WPF (WSL→`powershell.exe`), JSON/JSONC settings, jq + python3 (`jsonschema`) test assertions, Pester-free `*.Tests.ps1` scripts run via `powershell.exe -File`.

**Spec:** `docs/superpowers/specs/2026-06-29-spooky-scene-design.md`

**Working dir:** `/mnt/c/temp/notify` on `main`. All paths below are relative to it.

---

## File Structure

- **Create** `lib/scene-spooky.ps1` — geometry helpers + 8 layer functions + `Start-Spooky`. One responsibility: render the spooky scene.
- **Create** `tests/scene-spooky.Tests.ps1` — WPF-free unit tests for the two geometry helpers (mirrors `tests/scene-unicorn.Tests.ps1`).
- **Modify** `show-notification.ps1` — dot-source the renderer, add 8 flag reads to `$sceneCfg`, add `spooky` to `$sceneKinds`.
- **Modify** `settings.schema.json` — add `"spooky"` to `scene.kind` enum + 8 boolean flag properties.
- **Modify** `tests/settings.Tests.sh` — assert the spooky scene is schema-wired (mirrors the unicorn checks).
- **Modify** `settings.json` — add the default `scene` block to the `spooky` theme.

Draw order (back→front): `moon → fog → gravestones → webs → ghosts → bats → eyes → lightning`.

Conventions to copy from `lib/scene-unicorn.ps1`:
- Geometry helpers use `[System.Globalization.CultureInfo]::InvariantCulture` and `'0.##'` formatting so XAML gets `.` decimals (an `nl-BE` locale would emit `,` and break `Geometry.Parse`).
- Layer functions take `($canvas, [double]$w, [double]$h, ...)` and append to `$canvas.Children`.
- `Add-Twinkle $el $lo $hi $seconds $beginOffset` (already global) loops an auto-reversing opacity fade.

---

## Task 1: Geometry helper `New-WebPathData` (TDD)

**Files:**
- Create: `lib/scene-spooky.ps1`
- Create: `tests/scene-spooky.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/scene-spooky.Tests.ps1`:

```powershell
. "$PSScriptRoot\..\lib\scene-spooky.ps1"

$script:fail = 0
function Assert-Eq($got, $exp, $msg) {
  if ("$got" -ne "$exp") { Write-Host "FAIL: $msg`n  exp=[$exp]`n  got=[$got]"; $script:fail++ }
  else { Write-Host "ok: $msg" }
}
function Assert-True($cond, $msg) { Assert-Eq ([bool]$cond) $true $msg }

# Corner web: anchor (0,0), radius 100, 3 spokes across 0..90deg, 2 ring threads.
# Spoke angles 0,45,90 -> tips (100,0) (70.71,70.71) (0,100).
$d = New-WebPathData 0 0 100 3 2

Assert-True ($d.StartsWith('M')) "web path starts with M (moveto)"
Assert-True ($d.Contains('M 0,0 L 100,0')) "spoke 0deg runs origin -> (100,0)"
Assert-True ($d.Contains('L 0,100')) "spoke 90deg tip at (0,100)"
Assert-True ($d.Contains('70.71,70.71')) "spoke 45deg tip at (70.71,70.71)"
# One 'M 0,0 ' move per spoke (ring threads start elsewhere).
Assert-Eq ([regex]::Matches($d, 'M 0,0 ').Count) 3 "one move per spoke"
# 2 ring threads, each an M..L..L polyline across 3 spokes -> 2 'L' per ring + spoke Ls.
Assert-True ($d.Contains('33.33,0')) "inner ring crosses spoke 0 at r=33.33"

# Invariant decimals: XAML needs '.', NOT the ',' an nl-BE locale emits.
Assert-True ($d.Contains('70.71')) "uses '.' decimal separator"
Assert-True (-not $d.Contains('70,71')) "does not use ',' decimal separator"

# Degenerate inputs are coerced, never throw / loop forever.
$d2 = New-WebPathData 0 0 50 1 0
Assert-True ($d2.StartsWith('M')) "spokes<2 / rings<1 still yields a path"

if ($script:fail -gt 0) { exit 1 } else { Write-Host "ALL PASS" }
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /mnt/c/temp/notify/tests/scene-spooky.Tests.ps1)"
```
Expected: FAIL — `New-WebPathData` is not defined (the lib file doesn't exist yet, dot-source errors / command not found).

- [ ] **Step 3: Write the minimal implementation**

Create `lib/scene-spooky.ps1` with the header comment and this helper:

```powershell
# Scenery renderer: spooky — eight independent, flag-toggled Halloween/haunted
# layers. New-WebPathData / New-BatPathData are WPF-free + unit-tested; the
# Add-Spooky* helpers build live WPF visuals. Dot-sourced by show-notification.ps1.

# XAML path geometry for a corner spiderweb: `spokes` radial threads fanning 0..90deg
# from (cx,cy), plus `rings` concentric polyline threads connecting the spokes at
# fractional radii. One combined Path data string (multiple M subpaths), stroked.
# Invariant culture: XAML needs '.' decimals; nl-BE would emit ',' and choke Parse.
function New-WebPathData([double]$cx, [double]$cy, [double]$r, [int]$spokes, [int]$rings) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  if ($spokes -lt 2) { $spokes = 2 }
  if ($rings -lt 1) { $rings = 1 }
  $f = { param($v) ([double]$v).ToString('0.##', $ic) }
  $angles = @()
  for ($s = 0; $s -lt $spokes; $s++) {
    $t = $s / ($spokes - 1)
    $angles += (90.0 * $t)
  }
  $sb = New-Object System.Text.StringBuilder
  foreach ($deg in $angles) {
    $rad = $deg * [Math]::PI / 180.0
    $x = $cx + $r * [Math]::Cos($rad)
    $y = $cy + $r * [Math]::Sin($rad)
    [void]$sb.Append(("M {0},{1} L {2},{3} " -f (&$f $cx), (&$f $cy), (&$f $x), (&$f $y)))
  }
  for ($ringi = 1; $ringi -le $rings; $ringi++) {
    $rr = $r * $ringi / ($rings + 1)
    for ($s = 0; $s -lt $spokes; $s++) {
      $rad = $angles[$s] * [Math]::PI / 180.0
      $x = $cx + $rr * [Math]::Cos($rad)
      $y = $cy + $rr * [Math]::Sin($rad)
      $cmd = if ($s -eq 0) { 'M' } else { 'L' }
      [void]$sb.Append(("{0} {1},{2} " -f $cmd, (&$f $x), (&$f $y)))
    }
  }
  $sb.ToString().TrimEnd()
}
```

(For the `New-WebPathData 0 0 100 3 2` test: ring 1 radius = `100*1/3 = 33.33`, spoke 0 → `(33.33,0)`; spoke 45° tip = `100*cos45 = 70.71`. These match the assertions.)

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /mnt/c/temp/notify/tests/scene-spooky.Tests.ps1)"
```
Expected: all `ok:` lines, `ALL PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
cd /mnt/c/temp/notify
git add lib/scene-spooky.ps1 tests/scene-spooky.Tests.ps1
git commit -m "Add spooky New-WebPathData geometry helper"
```

---

## Task 2: Geometry helper `New-BatPathData` (TDD)

**Files:**
- Modify: `lib/scene-spooky.ps1`
- Modify: `tests/scene-spooky.Tests.ps1`

- [ ] **Step 1: Write the failing test**

In `tests/scene-spooky.Tests.ps1`, insert before the final `if ($script:fail ...` block:

```powershell
# Bat silhouette: filled, closed path centred on (0,0), width 100 height 60.
# Wing tips reach +/- hw (=50); a 0.75*hw point gives a predictable .5 decimal.
$b = New-BatPathData 100 60
Assert-True ($b.StartsWith('M')) "bat path starts with M (moveto)"
Assert-True ($b.EndsWith('Z'))   "bat path is closed (filled shape ends with Z)"
Assert-True ($b.Contains('50,')) "right wing tip reaches +hw (50)"
Assert-True ($b.Contains('-50,')) "left wing tip reaches -hw (-50)"
Assert-True ($b.Contains('37.5')) "uses '.' decimal separator (0.75*hw)"
Assert-True (-not $b.Contains('37,5')) "does not use ',' decimal separator"
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /mnt/c/temp/notify/tests/scene-spooky.Tests.ps1)"
```
Expected: FAIL — `New-BatPathData` is not defined.

- [ ] **Step 3: Write the minimal implementation**

In `lib/scene-spooky.ps1`, after `New-WebPathData`, add:

```powershell
# Filled, closed bat silhouette centred on (0,0): a small body with two scalloped
# wings. Right side is built explicitly then mirrored to the left, so the shape is
# symmetric. Wing tips reach +/-w/2; top/bottom reach +/-h/2.
function New-BatPathData([double]$w, [double]$h) {
  $ic = [System.Globalization.CultureInfo]::InvariantCulture
  $hw = $w / 2; $hh = $h / 2
  $f = { param($v) ([double]$v).ToString('0.##', $ic) }
  # Right half, top-of-head -> outer wing -> wing notch -> bottom-of-body.
  $right =
    "L $(&$f ($hw*0.15)),$(&$f (-$hh*0.55)) " +   # right ear/shoulder
    "L $(&$f ($hw*0.40)),$(&$f (-$hh*0.15)) " +   # inner wing
    "L $(&$f ($hw*0.75)),$(&$f (-$hh*0.45)) " +   # outer wing rise (-> 37.5,... for hw=50)
    "L $(&$f $hw),$(&$f (-$hh*0.10)) " +          # wing tip (+hw)
    "L $(&$f ($hw*0.70)),$(&$f ($hh*0.35)) " +    # scallop
    "L $(&$f ($hw*0.30)),$(&$f ($hh*0.10)) " +    # back toward body
    "L 0,$(&$f $hh) "                              # bottom of body
  $left =
    "L $(&$f (-$hw*0.30)),$(&$f ($hh*0.10)) " +
    "L $(&$f (-$hw*0.70)),$(&$f ($hh*0.35)) " +
    "L $(&$f (-$hw)),$(&$f (-$hh*0.10)) " +        # wing tip (-hw)
    "L $(&$f (-$hw*0.75)),$(&$f (-$hh*0.45)) " +
    "L $(&$f (-$hw*0.40)),$(&$f (-$hh*0.15)) " +
    "L $(&$f (-$hw*0.15)),$(&$f (-$hh*0.55)) "
  "M 0,$(&$f (-$hh*0.30)) " + $right + $left + "Z"
}
```

(For `New-BatPathData 100 60`: `hw=50`, so `hw*0.75 = 37.5` → `'37.5'`; wing tips at `50` and `-50`. Matches the assertions.)

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /mnt/c/temp/notify/tests/scene-spooky.Tests.ps1)"
```
Expected: all `ok:`, `ALL PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
cd /mnt/c/temp/notify
git add lib/scene-spooky.ps1 tests/scene-spooky.Tests.ps1
git commit -m "Add spooky New-BatPathData geometry helper"
```

---

## Task 3: Layer functions + `Start-Spooky`

No unit test (WPF visuals can't be asserted headlessly); the verification step is that the file dot-sources without error, and the XAML snapshot (Task 5) confirms the scene Canvas. Each step adds one function and re-runs the geometry tests (which dot-source the whole file) to prove it parses.

**Files:**
- Modify: `lib/scene-spooky.ps1`

- [ ] **Step 1: Add the moon, fog, and gravestones layers**

Append to `lib/scene-spooky.ps1`:

```powershell
# --- layers (back to front) --------------------------------------------------

# Pale full moon with a soft halo in the upper-right; gentle opacity pulse.
# Mirrors Add-OceanSun but cold-white and right-anchored.
function Add-SpookyMoon($canvas, [double]$w, [double]$h, [double]$speed) {
  $d = $h * 0.5
  $e = New-Object System.Windows.Shapes.Ellipse
  $e.Width = $d; $e.Height = $d
  $rg = New-Object System.Windows.Media.RadialGradientBrush
  $rg.GradientStops.Add((New-SceneStop '#FFF7F0E0' 0.0))
  $rg.GradientStops.Add((New-SceneStop '#66E8E0C8' 0.45))
  $rg.GradientStops.Add((New-SceneStop '#00E8E0C8' 1.0))
  $e.Fill = $rg
  [System.Windows.Controls.Canvas]::SetLeft($e, $w * 0.84 - $d / 2)
  [System.Windows.Controls.Canvas]::SetTop($e, $h * 0.20 - $d / 2)
  $canvas.Children.Add($e) | Out-Null
  $pulse = New-Object System.Windows.Media.Animation.DoubleAnimation 0.55, 0.8, ([System.Windows.Duration][TimeSpan]::FromSeconds(5.0 / $speed))
  $pulse.AutoReverse = $true; $pulse.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $e.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $pulse)
}

# Low translucent mist bands drifting along the bottom, with a slow opacity sway.
# Reuses New-WavePathData (wavy top edge, flat filled bottom) like the aurora layer.
function Add-SpookyFog($canvas, [double]$w, [double]$h, [double]$opacity, [double]$speed) {
  for ($i = 0; $i -lt 2; $i++) {
    $top = $h * (0.74 + 0.10 * $i)
    $amp = $h * 0.03
    $period = $w * (0.9 + 0.3 * $i)
    $pathW = $w + $period
    $data = New-WavePathData $pathW $period $amp $top $h ([Math]::Max(4.0, $period / 24.0))
    $path = New-Object System.Windows.Shapes.Path
    $path.Data = [System.Windows.Media.Geometry]::Parse($data)
    $vg = New-Object System.Windows.Media.LinearGradientBrush
    $vg.StartPoint = '0,0'; $vg.EndPoint = '0,1'
    $vg.GradientStops.Add((New-SceneStop '#99B8B8C8' 0.0))
    $vg.GradientStops.Add((New-SceneStop '#33B8B8C8' 1.0))
    $path.Fill = $vg
    $path.Opacity = $opacity * (1.3 - 0.3 * $i)
    [System.Windows.Controls.Canvas]::SetLeft($path, 0); [System.Windows.Controls.Canvas]::SetTop($path, 0)
    $tt = New-Object System.Windows.Media.TranslateTransform
    $path.RenderTransform = $tt
    $canvas.Children.Add($path) | Out-Null
    $dur = [System.Windows.Duration][TimeSpan]::FromSeconds((30 + 10 * $i) / $speed)
    $drift = New-Object System.Windows.Media.Animation.DoubleAnimation 0, (-$period), $dur
    $drift.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $drift)
    Add-Twinkle $path ($opacity * 0.8) ($opacity * 1.3) (6.0 + $i) ($i * 0.9)
  }
}

# Static silhouette of tilted gravestones along the bottom edge (dark rounded rects).
function Add-SpookyGravestones($canvas, [double]$w, [double]$h) {
  $fill = New-Brush '#CC0A0710'
  $n = 5
  for ($i = 0; $i -lt $n; $i++) {
    $gw = $w * (0.06 + ($i % 2) * 0.02)
    $gh = $h * (0.16 + ($i % 3) * 0.04)
    $r = New-Object System.Windows.Shapes.Rectangle
    $r.Width = $gw; $r.Height = $gh
    $r.RadiusX = $gw * 0.5; $r.RadiusY = $gw * 0.5
    $r.Fill = $fill
    $x = $w * (0.05 + 0.2 * $i)
    [System.Windows.Controls.Canvas]::SetLeft($r, $x)
    [System.Windows.Controls.Canvas]::SetTop($r, $h - $gh + $gh * 0.25)
    $rt = New-Object System.Windows.Media.RotateTransform (($i % 2) * 6 - 3)
    $r.RenderTransform = $rt
    $canvas.Children.Add($r) | Out-Null
  }
}
```

- [ ] **Step 2: Add the webs, ghosts, and bats layers**

Append:

```powershell
# Corner spiderweb (top-left): radial spokes + ring threads via New-WebPathData,
# stroked thin and faint, with a slow shimmer.
function Add-SpookyWebs($canvas, [double]$w, [double]$h, [double]$opacity, [double]$speed) {
  $data = New-WebPathData 0 0 ($h * 0.7) 6 4
  $path = New-Object System.Windows.Shapes.Path
  $path.Data = [System.Windows.Media.Geometry]::Parse($data)
  $path.Stroke = New-Brush '#FFD8D8E0'
  $path.StrokeThickness = 1.0
  $path.Opacity = $opacity * 1.4
  [System.Windows.Controls.Canvas]::SetLeft($path, 0); [System.Windows.Controls.Canvas]::SetTop($path, 0)
  $canvas.Children.Add($path) | Out-Null
  Add-Twinkle $path ($opacity * 1.1) ($opacity * 1.6) (7.0 / $speed) 0
}

# Pale ghost wisps rising bottom->top while fading; negative phase spreads them up
# the column at t=0. Reuses the unicorn glitter drift idiom, bigger and fewer.
function Add-SpookyGhosts($canvas, [double]$w, [double]$h, [double]$speed) {
  $n = 5
  for ($i = 0; $i -lt $n; $i++) {
    $sz = $h * (0.10 + (Get-Random -Minimum 0 -Maximum 6) / 100.0)
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = $sz * 0.7; $e.Height = $sz
    $rg = New-Object System.Windows.Media.RadialGradientBrush
    $rg.GradientStops.Add((New-SceneStop '#CCE8E8F0' 0.0))
    $rg.GradientStops.Add((New-SceneStop '#00E8E8F0' 1.0))
    $e.Fill = $rg
    [System.Windows.Controls.Canvas]::SetLeft($e, (Get-Random -Minimum 0 -Maximum ([int]$w)))
    [System.Windows.Controls.Canvas]::SetTop($e, $h)
    $tt = New-Object System.Windows.Media.TranslateTransform
    $e.RenderTransform = $tt
    $canvas.Children.Add($e) | Out-Null
    $rise = $h * 1.2
    $dur = 11.0 + (Get-Random -Minimum 0 -Maximum 80) / 10.0
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation 0, (-$rise), ([System.Windows.Duration][TimeSpan]::FromSeconds($dur / $speed))
    $anim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $phase = $i / $n
    $anim.BeginTime = [TimeSpan]::FromSeconds( -($phase * $dur / $speed) )
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $anim)
    Add-Twinkle $e 0.2 0.75 (3.0 + (Get-Random -Minimum 0 -Maximum 20) / 10.0) ((Get-Random -Minimum 0 -Maximum 20) / 10.0)
  }
}

# Small bat silhouettes flapping diagonally across the card on a long loop; a
# scale pulse on Y fakes the wing-flap. Uses New-BatPathData.
function Add-SpookyBats($canvas, [double]$w, [double]$h, [double]$speed) {
  for ($i = 0; $i -lt 3; $i++) {
    $bw = $w * (0.06 + 0.02 * $i)
    $bh = $bw * 0.6
    $bat = New-Object System.Windows.Shapes.Path
    $bat.Data = [System.Windows.Media.Geometry]::Parse((New-BatPathData $bw $bh))
    $bat.Fill = New-Brush '#E60A0710'
    $startY = $h * (0.18 + 0.16 * $i)
    $tt = New-Object System.Windows.Media.TranslateTransform (-$bw), $startY
    $st = New-Object System.Windows.Media.ScaleTransform 1, 1
    $tg = New-Object System.Windows.Media.TransformGroup
    $tg.Children.Add($st); $tg.Children.Add($tt)
    $bat.RenderTransform = $tg
    $canvas.Children.Add($bat) | Out-Null
    $cycle = (12.0 + 3.0 * $i) / $speed
    $travelX = New-Object System.Windows.Media.Animation.DoubleAnimation (-$bw), ($w + $bw), ([System.Windows.Duration][TimeSpan]::FromSeconds($cycle))
    $travelX.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $travelX)
    $flap = New-Object System.Windows.Media.Animation.DoubleAnimation 1.0, 0.55, ([System.Windows.Duration][TimeSpan]::FromSeconds(0.35 / $speed))
    $flap.AutoReverse = $true; $flap.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $st.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $flap)
  }
}
```

- [ ] **Step 3: Add the eyes and lightning layers**

Append:

```powershell
# Pairs of glowing eyes that blink in the dark at staggered intervals (a quick dip
# to near-zero via a long-period twinkle reading as a blink).
function Add-SpookyEyes($canvas, [double]$w, [double]$h, [double]$speed) {
  $hues = @('#FFE05A', '#9CFF5A', '#FF7A18')
  for ($i = 0; $i -lt 3; $i++) {
    $sz = $h * 0.035
    $gap = $sz * 1.8
    $x = $w * (0.2 + 0.28 * $i)
    $y = $h * (0.45 + 0.12 * ($i % 2))
    $pair = New-Object System.Windows.Controls.Canvas
    foreach ($dx in @(0, $gap)) {
      $e = New-Object System.Windows.Shapes.Ellipse
      $e.Width = $sz; $e.Height = $sz
      $rg = New-Object System.Windows.Media.RadialGradientBrush
      $rg.GradientStops.Add((New-SceneStop ('#FF' + $hues[$i].Substring(1)) 0.0))
      $rg.GradientStops.Add((New-SceneStop ('#00' + $hues[$i].Substring(1)) 1.0))
      $e.Fill = $rg
      [System.Windows.Controls.Canvas]::SetLeft($e, $dx)
      $pair.Children.Add($e) | Out-Null
    }
    [System.Windows.Controls.Canvas]::SetLeft($pair, $x)
    [System.Windows.Controls.Canvas]::SetTop($pair, $y)
    $canvas.Children.Add($pair) | Out-Null
    Add-Twinkle $pair 0.15 0.95 ((3.5 + $i) / $speed) ($i * 1.3)
  }
}

# Occasional full-card lightning flash with a long idle gap: opacity keyframes spike
# briefly then sit dark until the loop repeats (same gating idiom as shootingStar).
function Add-SpookyLightning($canvas, [double]$w, [double]$h, [double]$speed) {
  $r = New-Object System.Windows.Shapes.Rectangle
  $r.Width = $w; $r.Height = $h
  $r.Fill = New-Brush '#FFEFE6FF'
  $r.Opacity = 0
  [System.Windows.Controls.Canvas]::SetLeft($r, 0); [System.Windows.Controls.Canvas]::SetTop($r, 0)
  $canvas.Children.Add($r) | Out-Null
  $cycle = 11.0 / $speed
  $op = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
  $op.Duration = [System.Windows.Duration][TimeSpan]::FromSeconds($cycle)
  $op.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $op.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame 0.0,  ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds(0)))) | Out-Null
  $op.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame 0.45, ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($cycle * 0.02)))) | Out-Null
  $op.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame 0.0,  ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($cycle * 0.06)))) | Out-Null
  $op.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame 0.5,  ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($cycle * 0.10)))) | Out-Null
  $op.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame 0.0,  ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($cycle * 0.16)))) | Out-Null
  $op.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame 0.0,  ([System.Windows.Media.Animation.KeyTime][TimeSpan]::FromSeconds($cycle)))) | Out-Null
  $r.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $op)
}
```

- [ ] **Step 4: Add the `Start-Spooky` entry point**

Append:

```powershell
# Render the spooky scene into $box.Scene. $cfg: @{ colors; opacity; speed; + the
# eight layer flags }. Back-to-front draw order; called from a Loaded handler so the
# card ActualWidth/Height are known. Nothing draws unless its flag is set.
function Start-Spooky($box, $cfg) {
  $canvas = $box.Scene
  if ($null -eq $canvas) { return }
  $card = $box.Card
  $w = [double]$card.ActualWidth; $h = [double]$card.ActualHeight
  if ($w -le 0 -or $h -le 0) { return }

  $opacity = [double]$cfg.opacity; if ($opacity -le 0) { $opacity = 0.22 }
  $speed = [double]$cfg.speed; if ($speed -le 0) { $speed = 1.0 }

  $canvas.Width = $w; $canvas.Height = $h

  if ($cfg.moon)        { Add-SpookyMoon        $canvas $w $h $speed }
  if ($cfg.fog)         { Add-SpookyFog         $canvas $w $h $opacity $speed }
  if ($cfg.gravestones) { Add-SpookyGravestones $canvas $w $h }
  if ($cfg.webs)        { Add-SpookyWebs        $canvas $w $h $opacity $speed }
  if ($cfg.ghosts)      { Add-SpookyGhosts      $canvas $w $h $speed }
  if ($cfg.bats)        { Add-SpookyBats        $canvas $w $h $speed }
  if ($cfg.eyes)        { Add-SpookyEyes        $canvas $w $h $speed }
  if ($cfg.lightning)   { Add-SpookyLightning   $canvas $w $h $speed }
}
```

- [ ] **Step 5: Verify the file still parses (re-run the geometry tests)**

The test dot-sources the whole renderer, so a syntax error anywhere fails it.

Run:
```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /mnt/c/temp/notify/tests/scene-spooky.Tests.ps1)"
```
Expected: `ALL PASS`, exit 0.

- [ ] **Step 6: Commit**

```bash
cd /mnt/c/temp/notify
git add lib/scene-spooky.ps1
git commit -m "Add spooky scene layers and Start-Spooky entry point"
```

---

## Task 4: Wire the renderer into dispatch

**Files:**
- Modify: `show-notification.ps1` (the `lib\scene-*` includes; the `$sceneCfg` hashtable; the `$sceneKinds` table)

- [ ] **Step 1: Dot-source the renderer**

Find:
```powershell
. (Join-Path $PSScriptRoot 'lib\scene-unicorn.ps1')
```
Add directly below it:
```powershell
. (Join-Path $PSScriptRoot 'lib\scene-spooky.ps1')
```

- [ ] **Step 2: Add the 8 flag reads to `$sceneCfg`**

Find the last scene-flag line in the `$sceneCfg = @{ ... }` block:
```powershell
    shootingStar = [bool](Get-Prop $theme.scene 'shootingStar')
```
Add directly below it (before the closing `}`):
```powershell
    moon         = [bool](Get-Prop $theme.scene 'moon')
    fog          = [bool](Get-Prop $theme.scene 'fog')
    gravestones  = [bool](Get-Prop $theme.scene 'gravestones')
    webs         = [bool](Get-Prop $theme.scene 'webs')
    ghosts       = [bool](Get-Prop $theme.scene 'ghosts')
    bats         = [bool](Get-Prop $theme.scene 'bats')
    eyes         = [bool](Get-Prop $theme.scene 'eyes')
    lightning    = [bool](Get-Prop $theme.scene 'lightning')
```

- [ ] **Step 3: Add `spooky` to the dispatch table**

Find:
```powershell
  unicorn = { param($b, $c) Start-Unicorn $b $c }
```
Add directly below it (before the closing `}` of `$sceneKinds`):
```powershell
  spooky  = { param($b, $c) Start-Spooky $b $c }
```

- [ ] **Step 4: Verify the scene Canvas is emitted for a spooky theme**

Run (swaps a temp spooky settings.json in via the existing scene test harness path — here, a direct one-off `-EmitXaml`):
```bash
cd /mnt/c/temp/notify
S=settings.json; cp "$S" /tmp/s.bak
cat > "$S" <<'JSON'
{ "activeTheme": "t", "themes": { "t": { "scene": { "kind": "spooky", "moon": true, "bats": true } } } }
JSON
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$PWD/show-notification.ps1")" -Event done -EmitXaml | tr -d '\r' | grep -q 'x:Name="scene"' && echo "SCENE CANVAS PRESENT" || echo "MISSING"
cp /tmp/s.bak "$S"
```
Expected: `SCENE CANVAS PRESENT`, no PowerShell errors on stderr.

- [ ] **Step 5: Commit**

```bash
cd /mnt/c/temp/notify
git add show-notification.ps1
git commit -m "Wire spooky scene into notification dispatch"
```

---

## Task 5: Schema wiring + settings test (TDD)

**Files:**
- Modify: `tests/settings.Tests.sh`
- Modify: `settings.schema.json`
- Modify: `settings.json`

- [ ] **Step 1: Write the failing schema checks**

In `tests/settings.Tests.sh`, find the unicorn schema checks ending with:
```bash
check "schema defines unicorn scene flags" \
  "[[ \"\$(jq -c '.definitions.scene.properties|[has(\"aurora\"),has(\"rainbow\"),has(\"glitter\"),has(\"sparkles\"),has(\"shootingStar\")]' '$SCHEMA')\" == '[true,true,true,true,true]' ]]"
```
Add directly below it (before `exit $fail`):
```bash
check "spooky has spooky scene"          "[[ \"\$(jq -r '.themes.spooky.scene.kind // empty' '$F')\" == 'spooky' ]]"
check "schema scene.kind allows spooky"  "jq -e '.definitions.scene.properties.kind.enum|index(\"spooky\")' '$SCHEMA' >/dev/null"
check "schema defines spooky scene flags" \
  "[[ \"\$(jq -c '.definitions.scene.properties|[has(\"moon\"),has(\"fog\"),has(\"gravestones\"),has(\"webs\"),has(\"ghosts\"),has(\"bats\"),has(\"eyes\"),has(\"lightning\")]' '$SCHEMA')\" == '[true,true,true,true,true,true,true,true]' ]]"
```

- [ ] **Step 2: Run the tests to verify the new checks fail**

Run:
```bash
cd /mnt/c/temp/notify && bash tests/settings.Tests.sh
```
Expected: the three new lines FAIL (`spooky has spooky scene`, `schema scene.kind allows spooky`, `schema defines spooky scene flags`); everything else `ok`.

- [ ] **Step 3: Add `spooky` to the schema `kind` enum**

In `settings.schema.json`, find:
```json
        "kind": { "enum": ["waves", "space", "matrix", "sakura", "unicorn"], "description": "Scenery renderer: \"waves\" (ocean), \"space\" (cosmic), \"matrix\" (digital rain), \"sakura\" (cherry-blossom petals) or \"unicorn\" (rainbow / aurora / glitter / pastel)." },
```
Replace with:
```json
        "kind": { "enum": ["waves", "space", "matrix", "sakura", "unicorn", "spooky"], "description": "Scenery renderer: \"waves\" (ocean), \"space\" (cosmic), \"matrix\" (digital rain), \"sakura\" (cherry-blossom petals), \"unicorn\" (rainbow / aurora / glitter / pastel) or \"spooky\" (Halloween / haunted)." },
```

- [ ] **Step 4: Add the 8 spooky flag properties**

In `settings.schema.json`, find the last scene flag property:
```json
        "shootingStar": { "type": "boolean", "description": "unicorn: draw occasional shooting-star streaks." }
```
Add a comma after it and append the spooky flags:
```json
        "shootingStar": { "type": "boolean", "description": "unicorn: draw occasional shooting-star streaks." },
        "moon": { "type": "boolean", "description": "spooky: draw a pale full moon with a soft halo." },
        "fog": { "type": "boolean", "description": "spooky: draw low drifting mist bands along the bottom." },
        "gravestones": { "type": "boolean", "description": "spooky: draw a gravestone silhouette along the bottom edge." },
        "webs": { "type": "boolean", "description": "spooky: draw a corner spiderweb." },
        "ghosts": { "type": "boolean", "description": "spooky: draw pale ghost wisps rising and fading." },
        "bats": { "type": "boolean", "description": "spooky: draw small bat silhouettes flapping across." },
        "eyes": { "type": "boolean", "description": "spooky: draw pairs of glowing eyes that blink in the dark." },
        "lightning": { "type": "boolean", "description": "spooky: draw occasional full-card lightning flashes." }
```

- [ ] **Step 5: Add the default scene block to the `spooky` theme**

In `settings.json`, find the `spooky` theme:
```json
    "spooky": {
      "hero": "🎃",
      "gradient": ["#F97316 0", "#EA580C 0.3", "#7C2D12 0.55", "#6B21A8 0.8", "#4C1D95 1"],
      "rim": ["#7C2D12 0", "#9A3412 0.25", "#EA580C 0.5", "#6B21A8 0.75", "#4C1D95 1"],
      "card": "#100A14"
    }
```
Replace the `"card"` line + close so it reads:
```json
    "spooky": {
      "hero": "🎃",
      "gradient": ["#F97316 0", "#EA580C 0.3", "#7C2D12 0.55", "#6B21A8 0.8", "#4C1D95 1"],
      "rim": ["#7C2D12 0", "#9A3412 0.25", "#EA580C 0.5", "#6B21A8 0.75", "#4C1D95 1"],
      "card": "#100A14",
      "scene": { "kind": "spooky", "moon": true, "fog": true, "bats": true, "webs": true }
    }
```
(Note: `spooky` is the last theme in the object — keep whatever trailing `}` / comma structure already follows it; only add the `,` after `card` and the new `scene` line.)

- [ ] **Step 6: Run the settings tests to verify they pass**

Run:
```bash
cd /mnt/c/temp/notify && bash tests/settings.Tests.sh
```
Expected: all `ok:`, exit 0 (the three new checks now pass).

- [ ] **Step 7: Full schema validation (0 errors)**

Run:
```bash
cd /mnt/c/temp/notify && python3 - <<'PY'
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
cd /mnt/c/temp/notify
git add settings.schema.json settings.json tests/settings.Tests.sh
git commit -m "Wire spooky scene into schema and settings"
```

---

## Task 6: Verification & visual acceptance

**Files:** none (verification only)

- [ ] **Step 1: Default-equivalence golden test stays green**

The no-scene default look must be byte-identical. Run:
```bash
cd /mnt/c/temp/notify && bash tests/scene.Tests.sh
```
Expected: `ok: scened theme emits scene Canvas`, `ok: plain theme omits scene Canvas`, exit 0.

- [ ] **Step 2: Per-flag render smoke (each of the 8 flags alone, exit 0, no stderr)**

Run:
```bash
cd /mnt/c/temp/notify
S=settings.json; cp "$S" /tmp/s.bak
for flag in moon fog gravestones webs ghosts bats eyes lightning; do
  cat > "$S" <<JSON
{ "activeTheme": "spooky", "themes": { "spooky": { "hero":"🎃","gradient":["#F97316 0","#4C1D95 1"],"rim":["#7C2D12 0","#4C1D95 1"],"card":"#100A14","scene": { "kind": "spooky", "$flag": true } } } }
JSON
  err=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$PWD/show-notification.ps1")" -Event done -EmitXaml 2>&1 1>/dev/null | tr -d '\r')
  if [ -z "$err" ]; then echo "ok: $flag"; else echo "FAIL: $flag -> $err"; fi
done
cp /tmp/s.bak "$S"
```
Expected: `ok:` for all 8 flags, no `FAIL`.

- [ ] **Step 2.5: Run the full test suite**

Run:
```bash
cd /mnt/c/temp/notify
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$PWD/tests/scene-spooky.Tests.ps1")"
bash tests/settings.Tests.sh
bash tests/scene.Tests.sh
bash tests/run.sh
```
Expected: each exits 0 / `ALL PASS` / `0 failed`.

- [ ] **Step 3: Visual check (live popup, default preset)**

Run with the committed default preset (`activeTheme: "spooky"` is set only if the user chose it; otherwise temporarily set it for this check):
```bash
cd /mnt/c/temp/notify
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w "$PWD/show-notification.ps1")" \
  -Hwnd 0 -Folder demo -Event done -Seconds 8
```
Expected: a popup with moon + drifting fog + bats crossing + a corner web behind the 🎃 hero and body text, all readable. Screenshot for the prune-later evaluation. (Repeat with `-Event needs-input` to check the other event.)

- [ ] **Step 4: (Optional) activate the theme**

Only if the user wants spooky live: set `"activeTheme": "spooky"` in `settings.json`, re-run the settings tests, and commit:
```bash
cd /mnt/c/temp/notify
# edit settings.json: "activeTheme": "spooky"
bash tests/settings.Tests.sh
git add settings.json && git commit -m "Activate spooky theme"
```

---

## Self-Review (completed by plan author)

- **Spec coverage:** model/config (Task 5 step 5), 8 layers + draw order (Task 3), two unit-tested geometry helpers (Tasks 1–2), dispatch wiring (Task 4), schema enum + flags (Task 5), back-compat golden test (Task 6 step 1), error handling — `ActualWidth/Height ≤ 0` early return is in `Start-Spooky` (Task 3 step 4), unknown-kind/throw paths are pre-existing dispatch behavior (unchanged), testing items 1–7 map to Tasks 1–2 + Task 6. Default preset `moon+fog+bats+webs` (Task 5 step 5). All spec sections covered.
- **Placeholder scan:** no TBD/TODO; every code step shows complete code; every command shows expected output.
- **Type/name consistency:** flag names `moon, fog, gravestones, webs, ghosts, bats, eyes, lightning` are identical across `Start-Spooky`, `$sceneCfg`, schema properties, settings checks, and the per-flag smoke loop. Function names `New-WebPathData`, `New-BatPathData`, `Add-Spooky{Moon,Fog,Gravestones,Webs,Ghosts,Bats,Eyes,Lightning}`, `Start-Spooky` are consistent between definition (Task 3) and dispatch (Task 4).
