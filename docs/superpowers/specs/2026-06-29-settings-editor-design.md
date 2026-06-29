# Settings editor — live notification preview

## Goal

A single PowerShell/WPF window for tuning `settings.json`: top half = form controls
(checkboxes, text fields, dropdowns), bottom half = the live notification card rendered
from the current form values, animations looping. Change a control → see it in the card
immediately. Edits are ephemeral; a **Save** button writes back to `settings.json`.

## Non-goals (v1)

- Editing the variable-length `body` / `footer` line lists.
- Editing `gradient` / `rim` colour-stop arrays or other per-theme colour internals beyond
  `hero` and `card`.
- Preserving JSONC comments on Save (Save serializes the in-memory model as plain JSON).
- Driving real notifications from the editor — it is a tuning tool, not the notifier.

## Renderer extraction

The card visual is today welded into a top-level `Window` inside `New-NotificationBox`
(`lib/notification-box.ps1`). Positioning/fade/Topmost are Window concerns; the *visual* is
the inner `<Grid>` (rim border, hero watermark, scene canvas, content StackPanel, mascot
overlay). Extract so the editor can host the card under its controls:

- **`New-NotificationCard`** — builds the inner `<Grid>` and returns the element bag
  (`Root, Card, Slot, Overlay, Mascot, Scene, Event`). Owns the body-line and footer-pill
  population currently in `New-NotificationBox`.
- **`Initialize-NotificationCard $box`** — the load-time work that is *not* window
  positioning: card corner-clip, rim-brush spin, fireworks, body-line marquee. Pulled out
  of `New-NotificationBox`'s `Add_Loaded`.
- **`Start-CardChoreography $box $theme $ev`** — the mascot phases + scene config/dispatch
  currently inlined in `show-notification.ps1` (≈ lines 99-173), extracted to a shared lib
  so both the notifier and the editor call it. Includes the anchor/geometry setup.
- **`New-NotificationBox`** — becomes a thin Window wrapper around `New-NotificationCard`:
  parses the same `<Window>…</Window>` XAML, keeps Window-only `Add_Loaded` work
  (positioning, fade-in), and calls `Initialize-NotificationCard`.

**Hard constraint:** `New-NotificationBox -EmitXaml` output must stay byte-identical so the
existing golden / default-equivalence tests pass unchanged. The extraction is a code move,
not a markup change.

`show-notification.ps1` shrinks to: resolve config → `New-NotificationBox` →
`Start-CardChoreography` → existing flash/sound/dismiss orchestration.

## Editor: `settings-editor.ps1`

A normal (titled, resizable) WPF Window.

```
┌─ Settings editor ──────────────────────────┐
│  [ Controls — scrollable ]                  │  top
│   Preview:  event ▾   (sample context)      │
│   activeTheme ▾                             │
│   Event ‹done›:  label □  accent □           │
│     indicator □  move ▾  end ▾  sound ▾      │
│   Theme ‹sakura›: hero □  card □             │
│     scene: ☑ petals  ☑ bloom  speed □ …      │
│   ───────────────────────────────────────   │
│   [ Save ]   [ Reload ]                      │
├─────────────────────────────────────────────┤
│  [ Live notification card — looping ]       │  bottom
│   (New-NotificationCard Root, hosted)       │
└─────────────────────────────────────────────┘
```

### State & data flow

```
settings.json ──load──▶ $model (mutable)
   control changed ──▶ apply to $model ──(150ms debounce)──▶ rebuild card ──▶ swap into host
   [Save] ──serialize $model──▶ settings.json
```

- Load `settings.json` once into a mutable `$model`.
- Each control writes its value into `$model` and requests a **rebuild**: dispose the old
  card (stop its DispatcherTimers / animations), build a fresh `New-NotificationCard` from
  `$model`, run `Initialize-NotificationCard` + `Start-CardChoreography`, swap the Root into
  the bottom container. Total rebuild — no partial-update bookkeeping.
- A 150 ms debounce coalesces rapid edits (typing) into one rebuild.
- **Save** serializes `$model` to `settings.json` (plain JSON, comments dropped).
- **Reload** re-reads the file, discarding unsaved edits.

### Controls (v1)

| Group   | Field                | Control   | Source of options                     |
|---------|----------------------|-----------|----------------------------------------|
| Preview | event                | dropdown  | `done`, `needs-input`                  |
| Root    | `activeTheme`        | dropdown  | `random` + every `themes` key          |
| Event   | `label`              | text      | —                                      |
| Event   | `accent`             | text      | `#RRGGBB`                              |
| Event   | `indicator`          | text      | emoji / `fireworks` / empty            |
| Event   | `mascot.move`        | dropdown  | schema enum: `walk`, `jump`            |
| Event   | `mascot.end`         | dropdown  | schema enum: `confetti`, `gym`, `flag` |
| Event   | `sound`              | dropdown  | schema enum: `asterisk`, `exclamation`, `` |
| Theme   | `hero`               | text      | — (string form only in v1)             |
| Theme   | `card`               | text      | `#RRGGBB`                              |
| Theme   | `scene.<bool>`       | checkbox  | per active theme's scene keys          |
| Theme   | `scene.glyphs`       | dropdown  | schema enum                            |
| Theme   | `scene.<number>`     | text      | `speed`, `opacity`, `count`, `density` |

The Event group edits `events.<selected event>`; the Theme group edits
`themes.<selected theme>`. Scene controls render only when the selected theme has a `scene`.
Enum option lists are sourced from `settings.schema.json` so they can't drift.

**Theme selection vs `random`:** the Theme group needs a concrete theme to edit and the
preview needs a concrete theme to draw, but `activeTheme` may be `random`. So the editor
keeps a separate **selected theme** (a concrete `themes` key) that drives both the Theme
group and the preview. When `activeTheme` is a concrete key, selected theme defaults to it;
when `activeTheme` is `random`, selected theme defaults to the first theme key. Changing
`activeTheme` to a concrete key syncs the selected theme to match.

### Token sample context

`body` / `footer` still render (just aren't editable yet), so `{{token}}`s resolve against a
fixed **sample context** baked into the editor (e.g. `folder=my-project`, `branch=main`,
`message=Waiting for your input`, `last_assistant=Done — all tests pass`, `agents=2`, …),
reusing the existing `Resolve-BodyLines` / `Resolve-Footer`. No live session required.

## Testing (Pester / sh, matching the existing suite)

- **Golden guard** — `New-NotificationBox -EmitXaml` byte-identical before/after extraction
  (existing equivalence tests stay green; add an explicit assertion if not already covered).
- **Model round-trip** — load → apply edits (`event.label`, `mascot.move`, a scene bool,
  `activeTheme`) → serialize: values land at the right paths; untouched keys preserved.
- **Schema-driven options** — dropdown option lists match `settings.schema.json` enums.
- **Sample context** — resolves body/footer to non-empty lines for both events.

WPF rendering, animation timing, and the editor window itself are not unit-tested
(consistent with the current suite, which exercises pure helpers + `-EmitXaml`/`-DryRun`).

## Launch

Run from PowerShell in the repo dir:

```powershell
.\settings-editor.ps1
```

(WSL: `powershell.exe -File settings-editor.ps1`.)
