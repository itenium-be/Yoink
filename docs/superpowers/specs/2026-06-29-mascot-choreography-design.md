# Mascot choreography + composable lib split

## Goal

Replace the single inline mascot flipbook with a three-phase choreography, and
break the monolithic `show-notification.ps1` into composable `lib/*.ps1` blocks.

## Choreography (both events)

1. **Looking** — mascot plays the `looking` frames *in place*, in the current
   inline slot left of the status text (where the mascot renders today).
2. **Jump** — mascot plays the `jump` frames while a **vertical** translate
   carries it straight up out of the slot onto the **top edge** of the box. It
   lands on the left side, directly above its slot — no horizontal movement.
3. **Celebrate** — at the top edge it loops `confetti` (event `done`) or `flag`
   (event `needs-input`) until dismissed.

Looking and jump play **once**; celebrate **loops** until the target terminal
gets focus or the popup is clicked.

Frame rates stay ~30fps (33ms tick), matching the source videos. Frame counts
today: looking 149, jump 64, confetti 127, flag 132.

## Layout

The mascot must render *outside* the rounded-clipped card to sit on the top
edge, so:

- The window grows taller with transparent **headroom** above the card. The
  card's visual size is unchanged; it gets a top margin equal to the headroom.
- The mascot lives in an **unclipped overlay `Canvas`** spanning the whole
  window, at the top z-index. During *looking* it is parked over the slot
  position; *jump* animates its `Canvas.Top` straight up to land on the card's
  top edge above the slot.
- The Claude ASCII mark stays in the slot underneath the mascot. It is revealed
  when the mascot leaps away. For `needs-input` the existing two-frame logo wave
  is **kept** and runs on the revealed mark.
- Mascot display size stays at the current slot size (~110px tall).
- The popup still anchors bottom-right of the target monitor; the extra height
  pushes the whole thing up slightly.

## Files

| File                       | Responsibility                                                                 |
|----------------------------|--------------------------------------------------------------------------------|
| `show-notification.ps1`    | Thin orchestrator: params, assemblies, screen resolve, dot-source libs, build box, play sound, run the phase sequence, wire flash/click/poll, `ShowDialog`. |
| `lib/win-focus.ps1`        | `WinFocus` `Add-Type` + `Flash` / foreground / `IsForeground` helpers.         |
| `lib/notification-box.ps1` | `New-NotificationBox` -> builds window + card XAML, fills logo/status/folder, rim spin, fade-in, headroom + overlay canvas + mascot `Image`. Returns the `$box` hashtable. |
| `lib/mascot-player.ps1`    | Shared flipbook engine: `Start-Flipbook -Image -Dir -Fps -Loop -OnDone`. Loads + freezes frames, drives a `DispatcherTimer`, loops or fires `OnDone` after the last frame. |
| `lib/mascot-jump-prep.ps1` | `Start-JumpPrep $box { }` -> `looking` flipbook in the slot, then `OnDone`.     |
| `lib/mascot-jump.ps1`      | `Start-Jump $box { }` -> `jump` flipbook + vertical `Canvas.Top` animation to the top edge, then `OnDone`. |
| `lib/mascot-confetti.ps1`  | `Start-Confetti $box` -> loop `confetti` at the top edge.                       |
| `lib/mascot-flag-waver.ps1`| `Start-FlagWave $box` -> loop `flag` at the top edge.                           |

Each per-phase lib is a thin wrapper over `mascot-player.ps1`. `$box` is a
hashtable carrying the window plus element refs (card, slot, overlay canvas,
mascot image, logo) and is passed through the chain.

## Interface / wiring

Dot-source once; phases compose via completion callbacks in a single live WPF
window (no process re-spawn). Sequencer in the orchestrator:

```powershell
Start-JumpPrep $box {
  Start-Jump $box {
    if ($Event -eq 'done') { Start-Confetti $box } else { Start-FlagWave $box }
  }
}
```

The sequence starts from the window's `Loaded` handler (positions are known
only after layout).

## Decisions

- **Drop** the WPF hand-drawn `Start-Fireworks` fallback — real frames are
  committed (YAGNI).
- **Sound** stays inline in the orchestrator (not worth a lib file).
- **Params unchanged** (`-Hwnd / -Folder / -Event / -Sound / -Seconds /
  -DryRun`) so the bash hooks and their tests stay green untouched.

## Testing / verification

WPF animation can't be unit-tested in the WSL harness (it stubs
`powershell.exe`), so:

- `-DryRun` is extended to **dot-source every lib** and assert each required
  mascot frame dir (`looking`, `jump`, `confetti`, `flag`) exists, then print
  the screen info as today. A parse/wiring error in any lib fails fast via
  `powershell -File show-notification.ps1 -DryRun`.
- The existing bash hook tests (`tests/run.sh`) stay green unchanged.
- Visual phases verified by running both events manually from PowerShell.

## Out of scope

- The unused `gym` mascot frames.
- Any change to the bash hooks or capture flow.
