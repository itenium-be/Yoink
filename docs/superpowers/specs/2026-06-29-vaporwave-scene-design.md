# Vaporwave scene — design

## Problem

The scenery mechanism has six renderers (`waves`, `space`, `matrix`, `sakura`,
`unicorn`, `spooky`). The `vaporwave` theme is still palette-only (🌴 hero,
pink→purple→cyan gradient, dark `#160F1F` card, no `scene`). We want an 80s/90s
"outrun" vaporwave scene that makes `vaporwave` feel inhabited. As with the other
recent scenes, the right "vibe" is subjective, so we ship **all candidate motifs
as independent toggleable layers** to be evaluated live and pruned later.

## Goal

Add a `kind: "vaporwave"` scene renderer (`lib/scene-vaporwave.ps1`) wired into the
existing dispatch, with **8 flag-toggled layers** spanning the canonical vaporwave
motifs (sunset sky, banded retro sun, neon perspective grid, VHS scanlines, neon
mountains, stars, palms, horizon glow). Reuse existing scene idioms (gradient
backdrops, sun-glow pulse, twinkle, drift, the WPF-free + unit-tested geometry-helper
contract). Keep the established look: layers stay translucent so the 🌴 hero
watermark and body text remain readable.

Hard constraint (unchanged): a theme with **no** `scene` renders byte-identically
to today — the default-equivalence golden test stays green, untouched.

## Model

The `vaporwave` theme gains a `scene` object whose flags select layers:

```json
"vaporwave": {
  "hero": "🌴",
  "gradient": ["#FF6AD5 0", "#C774E8 0.3", "#AD8CFF 0.55", "#8795E8 0.8", "#94D0FF 1"],
  "rim": ["#FF71CE 0", "#B967FF 0.25", "#01CDFE 0.5", "#05FFA1 0.75", "#FFFB96 1"],
  "card": "#160F1F",
  "scene": { "kind": "vaporwave", "haze": true, "sun": true, "grid": true, "scanlines": true }
}
```

Shared `scene` fields behave exactly as for the other scenes (sourced via the same
dispatch):

| Field     | Meaning                              | Default                                    |
|-----------|--------------------------------------|--------------------------------------------|
| `kind`    | registered renderer name             | (required; unknown/absent → no scenery)    |
| `colors`  | `#RRGGBB` array the scene draws from  | `gradient` stop colours (`Get-StopColors`) |
| `opacity` | overall subtlety baseline (0..1)     | `0.22`                                     |
| `speed`   | animation speed multiplier           | `1.0`                                      |

Every layer is **off unless its flag is true** — there is no mandatory base layer.
An empty `{ "kind": "vaporwave" }` renders nothing.

## Layers (flags), drawn back-to-front

Draw order is fixed so combinations stack sanely — atmospheric layers behind, the
grid floor over the sky, the VHS overlay and horizon bloom on top:
`haze → sun → stars → mountains → grid → palms → scanlines → glow`.

The scene is organised around a **horizon line** at `y = h * 0.52`: the sun and
stars sit above it (the sky), the grid recedes below it (the floor), mountains rest
on it, and the glow blooms along it.

| Flag        | Layer                                                                                  | Technique (reuses)                                                                |
|-------------|----------------------------------------------------------------------------------------|----------------------------------------------------------------------------------|
| `haze`      | Sunset sky wash: pink→purple→cyan vertical gradient backdrop, translucent.              | `Rectangle` + `LinearGradientBrush` (like `Add-UnicornSky`)                       |
| `sun`       | Banded retro sun above the horizon: a circle whose lower half is sliced into widening horizontal bands; gentle opacity pulse. | `Ellipse`-clipped `Canvas` of gradient bars (gaps reveal haze) + `Add-OceanSun` pulse idiom |
| `stars`     | Twinkling dots scattered in the upper sky only.                                          | `Add-UnicornStars` pattern (`Ellipse` + `Add-Twinkle`)                            |
| `mountains` | Distant neon-rimmed wireframe ridge resting on the horizon.                              | **new `New-MountainPathData`** (WPF-free, unit-tested) + filled `Path` + neon stroke |
| `grid`      | Receding neon perspective grid from horizon to bottom, scrolling toward the viewer.      | **new `New-GridPathData`** (WPF-free, unit-tested) + stroked `Path` + `TranslateTransform` |
| `palms`     | Angular palm silhouettes framing the bottom corners.                                     | static inline `Path` (straight-segment fronds — no curves, so no helper)          |
| `scanlines` | VHS horizontal scanlines across the whole card with a slow vertical roll.                | thin `Rectangle`s in a `Canvas` + `TranslateTransform` Y loop                     |
| `glow`      | Neon bloom band along the horizon, subtle flicker.                                        | `Rectangle` + vertical `LinearGradientBrush` (transparent→neon→transparent) + `Add-Twinkle` |

Per-layer opacities are tuned against the `opacity` baseline (≈0.22) so any
combination stays a backdrop. Colours come from `$cfg.colors` (the theme's
pink→purple→cyan gradient) except where a motif needs fixed hues — scanlines
(near-black), palms/mountains fill (near-black silhouette) — which fall back to
built-in sets if `colors` is empty.

## Reuse vs. new code

- **Reused as-is** (already global at runtime; all `lib\*.ps1` are dot-sourced):
  `New-Brush`, `New-SceneStop`, `Add-Twinkle`, the `Add-OceanSun` glow-pulse idiom,
  the `Add-UnicornStars` twinkle-field idiom, and the `TranslateTransform` drift idiom.
- **New shared helper:** none required. (If duplication appears, factor a
  `lib/scene-common.ps1` then — out of scope now.)
- **New WPF-free, unit-tested geometry** (mirrors `New-ArcPathData`/`New-WebPathData`'s
  testable, invariant-culture, `.`-decimal contract):
  - `New-GridPathData(w, horizonY, bottomY, cols, rows, vanishX)` — vertical lines
    fanning from the vanishing point `(vanishX, horizonY)` to `cols+1` evenly-spaced
    points along the bottom edge, plus `rows` full-width horizontal lines whose
    spacing tightens toward the horizon (perspective: `y = horizonY + (bottomY -
    horizonY) * (j/rows)^2`). One combined stroked Path-data string.
  - `New-MountainPathData(w, baseY, peakY, peaks)` — a closed jagged ridge silhouette:
    `M 0,baseY`, alternating peak (`peakY`) / valley points across `peaks` peaks,
    `L w,baseY Z`.

Palms deliberately use **straight-segment** fronds drawn inline (like the spooky
gravestone rects), introducing **no** third geometry helper — keeping the
curved/parametric-goes-in-a-tested-helper rule satisfied with exactly the two
helpers above.

## Registration / dispatch (`show-notification.ps1`)

1. Dot-source the renderer next to the existing includes:
   `. (Join-Path $PSScriptRoot 'lib\scene-vaporwave.ps1')`
2. Add to the dispatch table:
   `vaporwave = { param($b, $c) Start-Vaporwave $b $c }`
3. Add the 8 flag reads to the `$sceneCfg` hashtable
   (`haze, sun, stars, mountains, grid, palms, scanlines, glow`, all
   `[bool](Get-Prop $theme.scene '<flag>')`).

No other dispatch change — colour resolution, default merge, and the
try/catch-around-scene safety already exist and apply uniformly.

## Schema (`settings.schema.json`)

- Add `"vaporwave"` to the `scene.kind` enum (after `spooky`).
- Add 8 boolean flag properties (`haze, sun, stars, mountains, grid, palms,
  scanlines, glow`) with `vaporwave:`-prefixed descriptions, mirroring the
  unicorn/spooky flag definitions. `additionalProperties: false` stays.

## Back-compat

Unchanged from the scenery design: the `scene` `Canvas` is emitted only when the
resolved theme has a `scene`. `vaporwave` previously had none, so this only adds a
scene to one theme; the default theme stays scene-less and the golden XAML stays
byte-identical. The `Resolve-Theme` passthrough and `$box.Scene` plumbing are
already in place.

## Error handling

- No `scene` → today's look, no error.
- Unknown `kind` → no scenery; warn to stderr; card still shows (existing path).
- `colors` empty/unresolvable → each layer falls back to its built-in set.
- Renderer throws → caught at dispatch; popup renders without scenery.
- `ActualWidth/Height ≤ 0` → `Start-Vaporwave` returns early (as `Start-Waves` does).

## Testing / verification

1. **Geometry unit tests** — `New-GridPathData` and `New-MountainPathData`, WPF-free
   (`tests/scene-vaporwave.Tests.ps1`): expected sampling (vanishing point, bottom
   corners, peak/valley Y), valid path string (`M`-start; mountain `Z`-close),
   `.`-decimal under an `nl-BE` culture, degenerate inputs coerced (mirrors the
   web-path / bat-path tests).
2. **Config parse smoke** — `settings.json` parses; `vaporwave.scene.kind == "vaporwave"`.
3. **Schema checks** (`tests/settings.Tests.sh`) — `scene.kind` enum allows
   `vaporwave`; the 8 flags are defined; full Draft-07 validation of `settings.json`
   stays at 0 errors.
4. **Default-equivalence** — no `settings.json` → built XAML byte-identical to the
   golden default (`tests/scene.Tests.sh`, still green, untouched).
5. **Scene XAML snapshot** — `-EmitXaml` for `vaporwave` contains the `scene` Canvas;
   a no-scene theme does not.
6. **Per-flag render** — for each of the 8 flags alone, and the default preset, the
   popup runs clean (exit 0, no stderr) via the `-EmitXaml` smoke loop.
7. **Visual check** — render the presets (both events) and screenshot; confirm the
   🌴 hero and body text stay readable behind every layer.

## Default preset

Shipped enabled in `settings.json`: `haze + sun + grid + scanlines` — the
instantly-recognizable outrun look while staying subtle. The other four (`stars,
mountains, palms, glow`) are off by default and available for the prune-later
evaluation. (`palms` is off because the 🌴 hero already occupies the palm motif.)

## Acceptance

```
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w /mnt/c/temp/notify/show-notification.ps1)" \
  -Hwnd 0 -Folder demo -Event done -Seconds 8
```

with `activeTheme: "vaporwave"` and a chosen flag-set shows the selected layers
drifting subtly behind the content; removing `settings.json` reproduces the
current default look exactly.

## Out of scope

- Choosing the final flag-set (that is the post-render evaluation this enables).
- Changing `activeTheme` or any other theme.
- Scenes for the remaining themes.
- Per-event scenery (scene stays theme-level).
- Factoring `lib/scene-common.ps1` (only if real duplication emerges).
```
