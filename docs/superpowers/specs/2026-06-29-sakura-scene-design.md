# Sakura scenery — design

Add a `sakura` scene to the config-driven, animated scenery layer used by theme
notification cards, alongside the existing `waves` (ocean), `space` (cosmic) and
`matrix` (digital rain) scenes. The sakura theme today: `hero "🌸"`, pastel
pink→rose→lilac gradient, card `#1A1620`.

Card canvas is ~586×206 px (`$box.Card.ActualWidth/Height`); the scene draws into
`$box.Scene`, a `Canvas` behind the hero watermark.

## Composition

- **Falling petals (always on)** — cherry-blossom petals drifting down: linear
  vertical fall + sinusoidal horizontal sway + continuous tumble.
- **bloom** (toggle) — soft drifting radial pink/rose/lilac bokeh glows behind the
  petals for dreamy depth.
- **branch** (toggle) — a dark blossom branch in the top-left corner with a few
  five-petal blossoms, gently swaying.
- **parallax** (toggle) — a second petal class: a few large, faint, fast foreground
  petals over the small, slow background petals, for depth.

Density: **gentle drift** — ~22 background petals, slow lazy fall, wide soft sway.

## Module: `lib/scene-sakura.ps1`

Mirrors `lib/scene-space.ps1`. Dot-sourced by `show-notification.ps1`; `New-Brush`
comes from `notification-box.ps1`.

### Pure helpers (unit-tested in `tests/scene-sakura.Tests.ps1`)

- `New-PetalPathData([double]$w, [double]$h)` → XAML geometry mini-language string
  for one cherry-blossom petal: a rounded body with a small notch at the tip, built
  from Bézier segments. All numbers formatted with the invariant culture (XAML needs
  `.` decimals; the nl-BE machine locale would emit `,` and `Geometry.Parse` would
  choke — see `New-WavePathData`).
  - Tests: starts with `M`; parses via `[System.Windows.Media.Geometry]::Parse`
    without throwing; contains no `,`-decimal artifact under a comma-decimal culture.
- `New-SakuraStop([string]$hex6, [double]$alpha, [double]$offset)` → a `GradientStop`
  whose colour bakes the `0..1` alpha into `#AARRGGBB` (mirrors `New-SpaceStop`),
  so bloom gradients fade to transparent without a per-stop opacity.
  - Tests: alpha→`AA` mapping (0→`00`, 1→`FF`, 0.5→`80`).

### WPF builders (verified by rendering, not unit tests)

- `Add-SakuraBloom $canvas $w $h` — 3 soft radial pink/rose/lilac glows, slow
  `TranslateTransform.X` AutoReverse drift. Mirrors `Add-SpaceNebula`.
- `Add-SakuraPetals $canvas $w $h $count $speed $class` — spawns `$count` petals of
  one `$class`:
  - `background`: small, slow, faint, many (default 22).
  - `foreground`: large, fast, bolder, few (the parallax layer).
  - Each petal is a `Path` of petal geometry, tinted from the light-pink palette,
    with `RenderTransform = TransformGroup{ RotateTransform(tumble), TranslateTransform }`.
  - Motion (all RenderTransform — never Opacity; a plain Opacity `BeginAnimation`
    does not repaint reliably for scene children here):
    - linear `Y` fall from `-size` to `h+size`, Forever;
    - sinusoidal `X` sway via AutoReverse `DoubleAnimation`;
    - continuous `RotateTransform` tumble.
  - Desynced by varied start `Left`/`Top` + varied durations (no negative
    `BeginTime` — unreliable). Petals fade in/out at edges simply by translating
    fully off-card; per-petal `Opacity` is static.
- `Add-SakuraBranch $canvas $w $h` — a dark limb (`Path` stroke) in the top-left
  corner with 3–4 five-petal blossoms (each blossom = 5 petals rotated 72° around a
  tiny center), gentle whole-group `RotateTransform` sway anchored at the corner.

### Entry point

- `Start-Sakura($box, $cfg)` — guards on `$box.Scene` and a positive card size, sets
  `$canvas.Width/Height`, then dispatches by flag. `$cfg`: `petals` (default on),
  `bloom`, `branch`, `parallax`, `count` (default 22), `speed` (default 1.0).
  Draw order back→front: `bloom` → `branch` → background petals → foreground petals.

## Wiring

Stage only the hunks below explicitly when committing (concurrent sessions edit this
checkout — never `git add -A`).

- `show-notification.ps1`:
  - dot-source `lib\scene-sakura.ps1`;
  - add `petals` / `bloom` / `branch` / `parallax` bools to the `$sceneCfg` hashtable;
  - add `sakura = { param($b, $c) Start-Sakura $b $c }` to `$sceneKinds`.
- `settings.json` `themes.sakura`: add
  `"scene": { "kind": "sakura", "petals": true, "count": 22, "speed": 1.0, "bloom": true, "branch": true, "parallax": true }`.
- `settings.schema.json`: add `"sakura"` to the `scene.kind` enum and document
  `petals` / `bloom` / `branch` / `parallax`.
- `notify-lib.ps1` `Resolve-Theme` already passes `scene` through — no change.
- `New-NotificationBox` already emits the `scene` Canvas only when `theme.scene`
  exists, so themes without a scene stay byte-identical — must not break this.

## Verification

- `tests/scene-sakura.Tests.ps1` for the pure helpers.
- `bash tests/show-notification.Tests.sh` — default look stays byte-identical.
- Live render with `activeTheme=sakura` (already the active theme), eyeball, tune.

## Out of scope (YAGNI)

- No new sound, mascot, or layout behaviour.
- No changes to other themes/scenes.
