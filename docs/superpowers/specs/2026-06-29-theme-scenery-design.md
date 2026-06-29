# Theme scenery — design

## Problem

A theme today is purely colours (`gradient`, `rim`, `card`) plus a `hero` emoji
watermark. Themes feel static and interchangeable — only the palette differs.
We want each theme to feel *inhabited*: a per-theme animated backdrop (waves for
ocean, drifting stars for cosmic, falling petals for sakura, …). This iteration
builds the general mechanism and ships the first scene — **ocean → waves**.

## Goal

Add a config-driven, animated **scenery layer** any theme can opt into via a new
optional `scene` field in `settings.json`. Ship one renderer (`waves`). The
mechanism mirrors the existing named effects (`fireworks` indicator, mascot
`end` clips): config selects a `kind`, a PowerShell renderer draws + animates it.

Hard constraint: a theme with **no** `scene` must render byte-identically to
today (the default-equivalence golden test stays green untouched).

## Model

A theme gains an optional `scene` object:

```json
"ocean": {
  "hero": "🐳",
  "gradient": ["#0EA5E9 0", "#22D3EE 0.3", "#2DD4BF 0.6", "#14B8A6 0.8", "#0891B2 1"],
  "rim": ["#0C4A6E 0", "#0369A1 0.25", "#0891B2 0.5", "#06B6D4 0.75", "#14B8A6 1"],
  "card": "#0A1620",
  "palette": ["#7DD3FC", "#22D3EE", "#2DD4BF", "#5EEAD4", "#38BDF8"],
  "scene": { "kind": "waves" }
}
```

`scene` fields (all optional except `kind`):

| Field     | Meaning                                  | Default                                        |
|-----------|------------------------------------------|------------------------------------------------|
| `kind`    | registered renderer name                 | (required; unknown/absent → no scenery)        |
| `colors`  | array of `#RRGGBB` the scene cycles      | `gradient` stop colours (via `Get-StopColors`) |
| `opacity` | overall scene layer opacity (0..1)       | `0.22`                                          |
| `speed`   | animation speed multiplier               | `1.0`                                           |

Minimal config `{ "kind": "waves" }` works: colours come from the theme's
`gradient` stop colours. (There is no `palette` field in this codebase; `fireworks`
already sources its colours the same way.)

## Layering

A new `scene` `Canvas` is added **inside the `card` Border** so the card's
rounded clip contains it. It is inserted as the **first child** of the card grid,
before the hero `Rectangle`. Both keep `Panel.ZIndex="0"`; among equal z-index,
WPF paints in document order, so the scene (declared first) renders **behind** the
hero, and the content `StackPanel` (`ZIndex="1"`) stays on top of both. The mascot
overlay (`ZIndex="10"`, window-level) is unchanged.

Crucially this means **no existing element's z-index changes** — the only XAML
delta for a scened theme is the inserted Canvas (see Back-compat).

Scenery sits behind both the hero watermark and the body text — a subtle
backdrop that never crowds content.

## Back-compat

The `scene` `Canvas` element is emitted **only when the resolved theme has a
`scene`** — the same conditional-fragment trick already used for
`$indicatorBlock`. A theme with no scene produces the exact XAML it does today,
so the default-equivalence golden test (`tests/golden/default.xaml`) stays
byte-identical and green.

## The waves renderer (`lib/scene-waves.ps1`)

`Start-Waves $box $cfg` is called from the orchestrator's `Loaded` handler (when
the card's `ActualWidth` is known), exactly as `Start-Fireworks` is invoked.

- Builds **3 layered sine-wave `Path`s**, each spanning ~2× the card width and
  closed to the card's bottom edge so it reads as filled water.
- Each layer is filled with a `$cfg.colors` colour at low opacity and stacked in
  the card's bottom band at slightly different heights for depth.
- Each layer gets a `TranslateTransform.X` `DoubleAnimation` looping
  `0 → -onePeriod`, `RepeatBehavior=Forever`, at staggered durations
  (~6s / 9s / 13s, divided by `speed`) → seamless, parallax drift.
- Wave geometry is built in code by sampling `sin()` into a `PathFigure` with
  `LineSegment`s (smooth enough; avoids Bezier control-point math).

Optional scene flags layer scenery above the waterline (drawn back-to-front:
sky → sun → clouds → waves):

| Flag     | Effect                                                                 |
|----------|-----------------------------------------------------------------------|
| `sky`    | continuous sky-glow (top) + sea-tint (bottom) gradients that meet at the horizon — no transparent band exposing the dark card |
| `sun`    | soft radial sun with a slow opacity pulse (needs `sky`)                |
| `clouds` | drifting clouds, randomized in size/height/speed and spread across the width via a negative animation phase (needs `sky`) |

The `ocean` theme ships with all three enabled.

## Scene dispatch (`show-notification.ps1`)

A small `kind → scriptblock` table in the orchestrator's `Loaded` handler:

```powershell
$sceneKinds = @{ waves = { param($box, $cfg) Start-Waves $box $cfg } }
```

Dispatch resolves colours up front (`$cfg.colors`, else `Get-StopColors
$theme.gradient`) and merges defaults, then:

```powershell
if ($theme.scene) {
  $fn = $sceneKinds[$theme.scene.kind]
  if ($fn) { try { & $fn $box $resolvedSceneCfg } catch { Write-Warning "scene '$($theme.scene.kind)' failed: $_" } }
}
```

Dispatch lives in **script scope** (not inside `New-NotificationBox`'s
`.GetNewClosure()` `Loaded` handler) to avoid the closure-rebind scope trap
already documented in `show-notification.ps1`. The renderer libs are
dot-sourced alongside the existing `lib\*.ps1` includes. A broken scene is
caught so it can never kill the popup.

## Components

| Unit                       | Responsibility                                                   |
|----------------------------|-----------------------------------------------------------------|
| `settings.json`            | add `scene` to the `ocean` theme                                |
| `Resolve-Theme` (notify-lib.ps1) | pass `scene` through (default `$null`)                     |
| `New-NotificationBox`      | conditional `scene` Canvas (inserted first, behind hero); `$box.Scene` |
| `lib/scene-waves.ps1`      | `Start-Waves` — build + animate layered sine paths              |
| `show-notification.ps1`    | dot-source scene libs; resolve scene cfg; dispatch by `kind`     |

## Error handling

- No `scene` on the theme → nothing rendered (today's look). No error.
- Unknown `kind` → no scenery; warn to stderr; card still shows.
- `colors` unresolvable / empty → renderer falls back to a built-in ocean-blue set.
- Renderer throws → caught at dispatch; popup renders without scenery.

## Testing / verification

1. **Config parse smoke** — `settings.json` still parses; `ocean.scene.kind == "waves"`.
2. **Default-equivalence** — with no `settings.json`, the built XAML is still
   byte-identical to `tests/golden/default.xaml` (default theme has no scene).
3. **Scene XAML snapshot** — `-EmitXaml` for the `ocean` theme contains the
   `scene` Canvas element; a no-scene theme does not.
4. **Per-theme render** — `ocean` runs clean (exit 0, no stderr) through the
   acceptance command.
5. **Unknown kind** — a theme with `scene.kind = "nope"` renders with no scenery
   and no throw.
6. **Visual check** — render `ocean` (both events): waves roll subtly along the
   bottom, the whale watermark and body text stay readable.

## Acceptance

```
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w /mnt/c/temp/notify/show-notification.ps1)" \
  -Hwnd 0 -Folder demo -Event done -Seconds 8
```

with `activeTheme: "ocean"` shows subtly drifting waves behind the content;
removing `settings.json` reproduces the current look exactly.

## Out of scope

- Scenes for the other 8 themes (the mechanism supports them; only
  `ocean` → `waves` ships now).
- Per-event scenery (scene is theme-level).
- Geometry/timing changes beyond the optional `scene` `cfg` fields.
