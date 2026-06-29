# Unicorn scene — design

## Problem

The scenery mechanism shipped with one renderer (`ocean → waves`). The `unicorn`
theme is still palette-only (rainbow gradient + 🦄 hero, no `scene`). We want a
second, richer scene that makes `unicorn` feel inhabited — and, because the right
unicorn "vibe" is subjective, we ship **all candidate motifs as independent
toggleable layers** so they can be evaluated live and pruned later.

## Goal

Add a `kind: "unicorn"` scene renderer (`lib/scene-unicorn.ps1`) wired into the
existing dispatch, with **8 flag-toggled layers** spanning four motifs. Reuse the
ocean scene's patterns (gradient backdrops, drifting elements, opacity pulses,
the WPF-free + unit-tested geometry helper). Keep the same subtle look: layers
stay translucent so the hero watermark and body text remain readable.

Hard constraint (unchanged): a theme with **no** `scene` renders byte-identically
to today — the default-equivalence golden test stays green, untouched.

## Model

The `unicorn` theme gains a `scene` object whose flags select layers:

```json
"unicorn": {
  "hero": "🦄",
  "gradient": ["#FF5F6D 0", "#FFC371 0.28", "#3CFFB0 0.5", "#36D1DC 0.72", "#A56BFF 1"],
  "rim": ["#7C3AED 0", "#2563EB 0.17", "#06B6D4 0.34", "#22C55E 0.5", "#EAB308 0.67", "#F97316 0.84", "#EC4899 1"],
  "card": "#18181B",
  "scene": { "kind": "unicorn", "sky": true, "rainbow": true, "clouds": true, "sparkles": true }
}
```

Shared `scene` fields behave exactly as for `waves` (sourced via the same dispatch):

| Field     | Meaning                             | Default                                  |
|-----------|-------------------------------------|------------------------------------------|
| `kind`    | registered renderer name            | (required; unknown/absent → no scenery)  |
| `colors`  | `#RRGGBB` array the scene draws from | `gradient` stop colours (`Get-StopColors`) |
| `opacity` | overall subtlety baseline (0..1)    | `0.22`                                   |
| `speed`   | animation speed multiplier          | `1.0`                                    |

Every layer is **off unless its flag is true** — there is no mandatory base layer
(unlike `waves`, where water always draws). An empty `{ "kind": "unicorn" }`
renders nothing.

## Layers (flags), drawn back-to-front

Draw order is fixed so combinations stack sanely: `sky → aurora → rainbow →
clouds → stars → glitter → sparkles → shootingStar`.

| Flag           | Layer                                                                                          | Technique (reuses)                                                                 |
|----------------|------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------|
| `sky`          | Pastel dawn gradient backdrop (lavender→peach→mint). Off → the dark `#18181B` card shows, which suits the night motifs. | `Rectangle` + `LinearGradientBrush`, `#AARRGGBB` stops (like `Add-OceanSky`)        |
| `aurora`       | 2–3 translucent ribbons high in the card, gentle horizontal drift + slow opacity sway.         | `New-WavePathData` (placed near top, taller amp, soft gradient fill) + `TranslateTransform` |
| `rainbow`      | Soft ROYGBIV arc curving across the top; concentric stroked arcs at low opacity; faint shimmer pulse. | new WPF-free `New-ArcPathData` (unit-tested) + `Path` per band                     |
| `clouds`       | Drifting puffy clouds, tinted pastel.                                                           | `New-CloudVisual` / `Add-OceanClouds` drift pattern (tint via brush colour)        |
| `stars`        | Field of tiny twinkling dots at fixed positions; staggered opacity pulses.                     | small `Ellipse`s + `DoubleAnimation` opacity (AutoReverse, staggered `BeginTime`)  |
| `glitter`      | Many tiny pastel particles slowly rising bottom→top while twinkling; negative phase spread.     | `Ellipse`s + Y `TranslateTransform` (cloud-drift pattern, vertical) + opacity pulse |
| `sparkles`     | Fewer, larger 4-point glints scattered mid-card; scale + opacity twinkle.                       | new `New-SparkleVisual` (4-point star `Path`) + `ScaleTransform`/opacity pulses    |
| `shootingStar` | Occasional diagonal streak (gradient-tailed) that crosses and fades, on a long repeat with idle gap. | `Path`/`Line` + gradient brush + `TranslateTransform` + opacity keyframes           |

Per-layer opacities are tuned against the `opacity` baseline (≈0.22) so any
combination stays a backdrop. Colours come from `$cfg.colors` (the theme's rainbow
gradient) except where a motif needs fixed hues (sky pastels, aurora green/teal/
violet), which fall back to built-in sets if `colors` is empty.

## Reuse vs. new code

- **Reused as-is (already global at runtime, all `lib\*.ps1` are dot-sourced):**
  `New-Brush`, `New-SceneStop`, `New-CloudVisual`, and the cloud-drift /
  opacity-pulse idioms.
- **New shared helper:** none required; `New-SceneStop`/`New-Brush` are reused
  directly. (If duplication appears, factor a `lib/scene-common.ps1` then — out of
  scope now.)
- **New WPF-free, unit-tested geometry:** `New-ArcPathData` (rainbow arc bands) —
  mirrors `New-WavePathData`'s testable, invariant-culture, `.`-decimal contract.

## Registration / dispatch (`show-notification.ps1`)

1. Dot-source the renderer next to the existing include:
   `. (Join-Path $PSScriptRoot 'lib\scene-unicorn.ps1')`
2. Add to the dispatch table:
   `$sceneKinds = @{ waves = {...}; unicorn = { param($b, $c) Start-Unicorn $b $c } }`

No other dispatch change — colour resolution, default merge, and the
try/catch-around-scene safety all already exist and apply uniformly.

## Back-compat

Unchanged from the scenery design: the `scene` `Canvas` is emitted only when the
resolved theme has a `scene`. `unicorn` previously had none, so this only adds a
scene to one theme; the default theme stays scene-less and the golden XAML stays
byte-identical. The `Resolve-Theme` passthrough and `$box.Scene` plumbing are
already in place.

## Error handling

- No `scene` → today's look, no error.
- Unknown `kind` → no scenery; warn to stderr; card still shows (existing path).
- `colors` empty/unresolvable → each layer falls back to its built-in pastel set.
- Renderer throws → caught at dispatch; popup renders without scenery.
- `ActualWidth/Height ≤ 0` → `Start-Unicorn` returns early (as `Start-Waves` does).

## Testing / verification

1. **`New-ArcPathData` unit test** — WPF-free: monotonic sampling, closed/valid
   path string, `.`-decimal under an `nl-BE` culture (mirrors the wave-path test).
2. **Config parse smoke** — `settings.json` parses; `unicorn.scene.kind == "unicorn"`.
3. **Default-equivalence** — no `settings.json` → built XAML byte-identical to
   `tests/golden/default.xaml` (still green, untouched).
4. **Scene XAML snapshot** — `-EmitXaml` for `unicorn` contains the `scene` Canvas;
   a no-scene theme does not.
5. **Per-flag render** — for each of the 8 flags alone, and for the 4 evaluation
   presets below, the popup runs clean (exit 0, no stderr) via the acceptance command.
6. **Unknown kind** — `scene.kind = "nope"` → no scenery, no throw.
7. **Visual check** — render each preset (both events) and screenshot; confirm the
   hero 🦄 and body text stay readable behind every layer.

## Evaluation presets

Rendered + screenshotted for side-by-side comparison; the user keeps any subset
(they are just flags):

| Preset       | Flags                                    |
|--------------|------------------------------------------|
| Rainbow      | `sky + rainbow + clouds + sparkles`      |
| Aurora night | `aurora + stars + shootingStar`          |
| Glitter      | `glitter` (+ faint `stars`)              |
| Pastel       | `sky + clouds + stars`                   |

## Acceptance

```
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w /mnt/c/temp/notify/show-notification.ps1)" \
  -Hwnd 0 -Folder demo -Event done -Seconds 8
```

with `activeTheme: "unicorn"` and a chosen flag-set shows the selected layers
drifting subtly behind the content; removing `settings.json` reproduces the
current default look exactly.

## Out of scope

- Choosing the final flag-set (that is the post-render evaluation this enables).
- Scenes for the remaining themes.
- Per-event scenery (scene stays theme-level).
- Factoring `lib/scene-common.ps1` (only if real duplication emerges).
