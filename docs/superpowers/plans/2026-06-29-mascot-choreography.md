# Mascot Choreography + Composable Lib Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the monolithic `show-notification.ps1` into composable `lib/*.ps1` blocks and add a three-phase mascot choreography (looking -> jump onto the top edge -> loop confetti/flag).

**Architecture:** A thin orchestrator dot-sources focused lib files once and drives a single live WPF window. The notification box gains transparent headroom and an unclipped overlay `Canvas` so the mascot can sit on its top edge. Mascot phases are `Start-*` functions wrapping a shared flipbook engine, chained via completion callbacks.

**Tech Stack:** Windows PowerShell 5.1, WPF (PresentationFramework), WinForms (screen/DPI), `DispatcherTimer` for frame playback.

**Testing note:** WPF rendering cannot be unit-tested in the WSL bash harness (it stubs `powershell.exe`). The automated test for this work is `powershell.exe -NoProfile -ExecutionPolicy Bypass -File show-notification.ps1 -DryRun`, which dot-sources every lib (so any parse/wiring error fails fast) and asserts the required mascot frame dirs exist. The existing `tests/run.sh` (bash hooks) must stay green. Visual phases are verified by running both events manually.

---

## File Structure

| File                        | Responsibility |
|-----------------------------|----------------|
| `show-notification.ps1`     | Orchestrator: params, assemblies, screen resolve, dot-source libs, DryRun checks, play sound, build box, run phase sequence, wire flash/click/poll, `ShowDialog`. |
| `lib/win-focus.ps1`         | `WinFocus` `Add-Type` + flash/foreground helpers. |
| `lib/notification-box.ps1`  | `New-NotificationBox` -> window + card XAML, headroom, overlay canvas, mascot `Image`, rim spin, fade-in. Returns `$box` hashtable. |
| `lib/mascot-player.ps1`     | `Start-Flipbook` shared frame-playback engine. |
| `lib/mascot-jump-prep.ps1`  | `Start-JumpPrep` -> `looking` in slot. |
| `lib/mascot-jump.ps1`       | `Start-Jump` -> `jump` + vertical translate to top edge. |
| `lib/mascot-confetti.ps1`   | `Start-Confetti` -> loop `confetti` on top edge. |
| `lib/mascot-flag-waver.ps1` | `Start-FlagWave` -> loop `flag` on top edge. |

`$box` is a hashtable: `@{ Win; Card; Slot; Overlay; Mascot; Logo; Event }`.

---

## Task 1: Extract `lib/win-focus.ps1` and make DryRun dot-source libs

**Files:**
- Create: `lib/win-focus.ps1`
- Modify: `show-notification.ps1`

- [ ] **Step 1: Create `lib/win-focus.ps1`** — move the `Add-Type @"...WinFocus..."@` block (lines 11-33 of the original) verbatim into this file.

- [ ] **Step 2: Dot-source it in `show-notification.ps1`** — after the `Add-Type -AssemblyName ...` line, add:

```powershell
. (Join-Path $PSScriptRoot 'lib\win-focus.ps1')
```

Remove the inline `Add-Type @"...WinFocus..."@` block.

- [ ] **Step 3: Move the DryRun early-return below the dot-source** so a lib parse error is caught by DryRun. The DryRun block stays as-is otherwise.

- [ ] **Step 4: Verify DryRun**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File show-notification.ps1 -DryRun`
Expected: prints `screen=... wa=...` and exits 0.

- [ ] **Step 5: Commit**

```bash
git add lib/win-focus.ps1 show-notification.ps1
git commit -m "Extract win-focus into lib"
```

---

## Task 2: Extract `lib/notification-box.ps1` with headroom + overlay canvas

**Files:**
- Create: `lib/notification-box.ps1`
- Modify: `show-notification.ps1`

`New-NotificationBox -Event <string> -Folder <string>` returns the `$box` hashtable. It owns the XAML, dynamic content (logo/status/folder), sound is NOT here (stays in orchestrator), rim spin + fade-in on `Loaded`.

Layout changes vs original XAML:
- Window `Height="330"` (was 240) to add headroom above the card.
- Card outer `Border` gets `Margin="14,104,14,14"` (was `14`) so the card keeps its ~212px visual height and the top 90px is transparent headroom.
- The mascot `Image` moves OUT of the inline slot into a window-level overlay:
  add, as the LAST child of the root `Grid` (top z-index), an unclipped canvas:

```xml
<Canvas x:Name="overlay" Panel.ZIndex="10" IsHitTestVisible="False">
  <Image x:Name="mascot" Width="128" Height="110" Visibility="Collapsed"
         RenderOptions.BitmapScalingMode="HighQuality"/>
</Canvas>
```

  The inline slot keeps only the `logo` TextBlock (the `mascot` Image is removed from the slot Grid). The slot Grid stays `Width="128" Height="110"`.

- [ ] **Step 1: Create `lib/notification-box.ps1`** — define `function New-NotificationBox`. Move the XAML here with the layout changes above. After `XamlReader::Parse`, fill `logo`/`status`/`folder` and set the accent (the per-event `$statusText`/`$accent`/`$indicator` logic moves here). Keep the `Add_Loaded` handler that does the card round-clip, screen positioning, fade-in, and rim spin. Positioning uses the passed work-area; accept `-WorkArea` as a param. Return:

```powershell
return @{ Win = $win; Card = $win.FindName('card'); Slot = $win.FindName('logo').Parent;
          Overlay = $win.FindName('overlay'); Mascot = $win.FindName('mascot');
          Logo = $win.FindName('logo'); Event = $Event }
```

- [ ] **Step 2: Call it from `show-notification.ps1`** — replace the inline `$xaml`/`XamlReader::Parse`/content-fill/`Add_Loaded` blocks with:

```powershell
. (Join-Path $PSScriptRoot 'lib\notification-box.ps1')
$box = New-NotificationBox -Event $Event -Folder $Folder -WorkArea $wa
$win = $box.Win
```

Keep the sound block, the flash, the click-to-focus handler, the needs-input logo-wave timer, and the poll/dismiss timer in the orchestrator (they reference `$win`/`$Hwnd`).

- [ ] **Step 3: Verify DryRun** — Run the Task 1 DryRun command. Expected: `screen=... wa=...`, exit 0.

- [ ] **Step 4: Visual smoke** — manually (from PowerShell) run the box without mascot to confirm headroom + layout:

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File show-notification.ps1 -Event done -Seconds 3`
Expected: popup appears bottom-right with empty headroom strip above the card; auto-closes after 3s. (Mascot wired in later tasks.)

- [ ] **Step 5: Commit**

```bash
git add lib/notification-box.ps1 show-notification.ps1
git commit -m "Extract notification-box with headroom and overlay canvas"
```

---

## Task 3: Add `lib/mascot-player.ps1` shared flipbook engine

**Files:**
- Create: `lib/mascot-player.ps1`
- Modify: `show-notification.ps1` (dot-source it)

- [ ] **Step 1: Create `lib/mascot-player.ps1`**:

```powershell
# Frame-by-frame flipbook player for an Image element.
# -Loop $true plays forever; otherwise calls -OnDone once after the last frame.
function Start-Flipbook {
  param(
    [System.Windows.Controls.Image]$Image,
    [string]$Dir,
    [int]$Fps = 30,
    [switch]$Loop,
    [scriptblock]$OnDone
  )
  $files = @(Get-ChildItem -Path $Dir -Filter 'frame_*.png' -ErrorAction SilentlyContinue | Sort-Object Name)
  if ($files.Count -eq 0) { if ($OnDone) { & $OnDone }; return }
  $frames = foreach ($f in $files) {
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bi.UriSource = New-Object System.Uri($f.FullName)
    $bi.EndInit(); $bi.Freeze(); $bi
  }
  $Image.Source = $frames[0]
  $Image.Visibility = [System.Windows.Visibility]::Visible
  $state = [pscustomobject]@{ Idx = 0 }
  $timer = New-Object System.Windows.Threading.DispatcherTimer
  $timer.Interval = [TimeSpan]::FromMilliseconds([int](1000 / $Fps))
  $timer.Add_Tick({
    $state.Idx++
    if ($state.Idx -ge $frames.Count) {
      if ($Loop) { $state.Idx = 0 }
      else { $timer.Stop(); if ($OnDone) { & $OnDone }; return }
    }
    $Image.Source = $frames[$state.Idx]
  }.GetNewClosure())
  $timer.Start()
}
```

- [ ] **Step 2: Dot-source in `show-notification.ps1`** — add `. (Join-Path $PSScriptRoot 'lib\mascot-player.ps1')` with the other lib dot-sources.

- [ ] **Step 3: Verify DryRun** — Run the DryRun command. Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add lib/mascot-player.ps1 show-notification.ps1
git commit -m "Add shared mascot flipbook player"
```

---

## Task 4: Add the four phase libs

**Files:**
- Create: `lib/mascot-jump-prep.ps1`, `lib/mascot-jump.ps1`, `lib/mascot-confetti.ps1`, `lib/mascot-flag-waver.ps1`
- Modify: `show-notification.ps1` (dot-source them)

The mascot's resting (slot) position and the top-edge target are computed in `Start-JumpPrep` from live layout and stashed on `$box` so `Start-Jump` can animate between them. Helper to place the overlay image at the slot:

- [ ] **Step 1: Create `lib/mascot-jump-prep.ps1`**:

```powershell
# Phase 1: look around in the slot, then hand off. Records slot + top-edge
# positions on $box (window coords) for the jump to animate between.
function Start-JumpPrep {
  param([hashtable]$Box, [scriptblock]$OnDone)
  $win = $Box.Win; $slot = $Box.Slot; $m = $Box.Mascot
  $p = $slot.TransformToVisual($win).Transform([System.Windows.Point]::new(0,0))
  # Center the mascot over the slot (slot is 128x110, mascot 128x110 -> aligned).
  $Box.SlotLeft = $p.X; $Box.SlotTop = $p.Y
  # Land straddling the card's top edge, directly above the slot (vertical only).
  $cardTop = $Box.Card.TransformToVisual($win).Transform([System.Windows.Point]::new(0,0)).Y
  $Box.TopLeft = $p.X; $Box.TopTop = $cardTop - ($m.Height * 0.72)
  [System.Windows.Controls.Canvas]::SetLeft($m, $Box.SlotLeft)
  [System.Windows.Controls.Canvas]::SetTop($m, $Box.SlotTop)
  Start-Flipbook -Image $m -Dir (Join-Path $PSScriptRoot '..\mascots\looking') -OnDone $OnDone
}
```

- [ ] **Step 2: Create `lib/mascot-jump.ps1`**:

```powershell
# Phase 2: play the jump frames while translating straight up onto the top edge.
function Start-Jump {
  param([hashtable]$Box, [scriptblock]$OnDone)
  $m = $Box.Mascot
  $dur = [System.Windows.Duration][TimeSpan]::FromMilliseconds(700)
  $up = New-Object System.Windows.Media.Animation.DoubleAnimation $Box.SlotTop, $Box.TopTop, $dur
  # Drive Canvas.Top via the attached property animation.
  $m.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty, $up)
  Start-Flipbook -Image $m -Dir (Join-Path $PSScriptRoot '..\mascots\jump') -OnDone {
    [System.Windows.Controls.Canvas]::SetTop($m, $Box.TopTop)  # pin final position
    if ($OnDone) { & $OnDone }
  }.GetNewClosure()
}
```

- [ ] **Step 3: Create `lib/mascot-confetti.ps1`**:

```powershell
# Phase 3 (done): loop confetti on the top edge until dismissed.
function Start-Confetti {
  param([hashtable]$Box)
  Start-Flipbook -Image $Box.Mascot -Dir (Join-Path $PSScriptRoot '..\mascots\confetti') -Loop
}
```

- [ ] **Step 4: Create `lib/mascot-flag-waver.ps1`**:

```powershell
# Phase 3 (needs-input): loop flag wave on the top edge until dismissed.
function Start-FlagWave {
  param([hashtable]$Box)
  Start-Flipbook -Image $Box.Mascot -Dir (Join-Path $PSScriptRoot '..\mascots\flag') -Loop
}
```

- [ ] **Step 5: Dot-source all four in `show-notification.ps1`**.

- [ ] **Step 6: Verify DryRun** — Run the DryRun command. Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
git add lib/mascot-jump-prep.ps1 lib/mascot-jump.ps1 lib/mascot-confetti.ps1 lib/mascot-flag-waver.ps1 show-notification.ps1
git commit -m "Add mascot phase libs: prep, jump, confetti, flag"
```

---

## Task 5: Wire the sequencer and remove dead code

**Files:**
- Modify: `show-notification.ps1`

- [ ] **Step 1: Remove the old `Start-Mascot` and `Start-Fireworks` functions** and the old `$mascotFolder` / `Start-Mascot` call inside `Add_Loaded` (that logic now lives in the box + sequencer).

- [ ] **Step 2: Start the sequence from the box's `Loaded`** — positions need live layout, so add (in the orchestrator, after `$box = New-NotificationBox ...`):

```powershell
$win.Add_Loaded({
  Start-JumpPrep $box {
    Start-Jump $box {
      if ($box.Event -eq 'done') { Start-Confetti $box } else { Start-FlagWave $box }
    }
  }
}.GetNewClosure())
```

(The box's own `Add_Loaded` for clip/position/fade/rim still runs first; multiple `Loaded` handlers fire in order.)

- [ ] **Step 3: Verify DryRun** — Run the DryRun command. Expected: exit 0.

- [ ] **Step 4: Visual smoke — done**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File show-notification.ps1 -Event done -Seconds 12`
Expected: mascot looks around in the slot, jumps straight up onto the top-left edge, then loops confetti; closes after 12s.

- [ ] **Step 5: Visual smoke — needs-input**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File show-notification.ps1 -Event needs-input -Seconds 12`
Expected: same looking+jump, then flag wave on top edge; revealed Claude mark waves in the slot.

- [ ] **Step 6: Commit**

```bash
git add show-notification.ps1
git commit -m "Wire mascot choreography sequencer; drop old mascot/fireworks code"
```

---

## Task 6: Harden DryRun (frame-dir assertions)

**Files:**
- Modify: `show-notification.ps1`

- [ ] **Step 1: Extend the DryRun block** to assert frame dirs exist before printing screen info:

```powershell
if ($DryRun) {
  foreach ($d in 'looking','jump','confetti','flag') {
    $dir = Join-Path $PSScriptRoot "mascots\$d"
    if (-not (Test-Path $dir)) { Write-Error "missing mascot dir: $dir"; exit 1 }
  }
  Write-Output ("screen={0} wa={1},{2},{3}x{4}" -f $screen.DeviceName,$wa.Left,$wa.Top,$wa.Width,$wa.Height); return
}
```

- [ ] **Step 2: Verify DryRun passes**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File show-notification.ps1 -DryRun`
Expected: prints `screen=... wa=...`, exit 0.

- [ ] **Step 3: Verify bash hook tests still green**

Run: `bash ~/.claude/notify/tests/run.sh`
Expected: `5 passed, 0 failed`.

- [ ] **Step 4: Commit**

```bash
git add show-notification.ps1
git commit -m "Assert mascot frame dirs in DryRun"
```

---

## Self-Review

- **Spec coverage:** looking-in-slot (Task 4 prep), jump-to-top-edge vertical (Task 4 jump), confetti/flag loop (Task 4 + Task 5 sequencer), headroom + overlay canvas (Task 2), file split (Tasks 1-4), logo wave kept for needs-input (Task 2 keeps the orchestrator timer), drop fireworks fallback (Task 5), params unchanged (orchestrator untouched signature), DryRun load+frame-dir test (Tasks 1,6), bash tests green (Task 6). All covered.
- **Placeholders:** none — every code step has full code.
- **Type consistency:** `$box` keys (`Win/Card/Slot/Overlay/Mascot/Logo/Event` + computed `SlotLeft/SlotTop/TopLeft/TopTop`) consistent across `New-NotificationBox`, `Start-JumpPrep`, `Start-Jump`. `Start-Flipbook` signature matches all callers.
