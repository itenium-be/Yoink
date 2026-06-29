# Spooky scene — design

## Problem

The scenery mechanism now has five renderers (`waves`, `space`, `matrix`,
`sakura`, `unicorn`). The `spooky` theme is still palette-only (🎃 hero,
orange→purple gradient, dark `#100A14` card, no `scene`). We want a Halloween /
haunted scene that makes `spooky` feel inhabited. As with `unicorn` and `sakura`,
the right "vibe" is subjective, so we ship **all candidate motifs as independent
toggleable layers** to be evaluated live and pruned later.

## Goal

Add a `kind: "spooky"` scene renderer (`lib/scene-spooky.ps1`) wired into the
existing dispatch, with **8 flag-toggled layers** mixing playful Halloween and
eerie-haunt motifs. Reuse existing scene idioms (gradient/sun backdrops, drifting
elements, opacity pulses, static silhouette paths, the WPF-free + unit-tested
geometry-helper contract). Keep the established look: layers stay translucent so
the 🎃 hero watermark and body text remain readable.

Hard constraint (unchanged): a theme with **no** `scene` renders byte-identically
to today — the default-equivalence golden test stays green, untouched.

## Model

The `spooky` theme gains a `scene` object whose flags select layers:

```json
"spooky": {
  "hero": "🎃",
  "gradient": ["#F97316 0", "#EA580C 0.3", "#7C2D12 0.55", "#6B21A8 0.8", "#4C1D95 1"],
  "rim": ["#7C2D12 0", "#9A3412 0.25", "#EA580C 0.5", "#6B21A8 0.75", "#4C1D95 1"],
  "card": "#100A14",
  "scene": { "kind": "spooky", "moon": true, "fog": true, "bats": true, "webs": true }
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
An empty `{ "kind": "spooky" }` renders nothing.

## Layers (flags), drawn back-to-front

Draw order is fixed so combinations stack sanely — atmospheric layers sit behind
moving silhouettes, and the flash sits above everything:
`moon → fog → gravestones → webs → ghosts → bats → eyes → lightning`.

| Flag          | Layer                                                                                   | Technique (reuses)                                                              |
|---------------|-----------------------------------------------------------------------------------------|--------------------------------------------------------------------------------|
| `moon`        | Glowing full moon with a soft halo, upper corner.                                        | `Add-OceanSun` glow pattern, recoloured pale yellow-white                      |
| `fog`         | Low translucent mist bands drifting along the bottom, gentle opacity sway.               | wave-ribbon / cloud-drift + `TranslateTransform` (placed low, soft fill)       |
| `gravestones` | Silhouette of tilted gravestones along the bottom edge.                                  | static `Path` (like `Add-SakuraBranch`), dark fill                             |
| `webs`        | Corner spiderweb: radial spokes + concentric arc threads, faint shimmer.                 | **new `New-WebPathData`** (WPF-free, unit-tested) + `Path` per thread          |
| `ghosts`      | Pale wisps rising bottom→top while fading; negative phase spread.                        | glitter vertical-drift (`Ellipse`/blob + Y `TranslateTransform`) + opacity pulse |
| `bats`        | Small bat silhouettes flapping diagonally across the card on a long repeat.              | **new `New-BatPathData`** wing path + `TranslateTransform` + wing-flap scale   |
| `eyes`        | Pairs of glowing eyes that blink in the dark at staggered intervals.                     | `Ellipse`s + `DoubleAnimation` opacity (AutoReverse, staggered `BeginTime`)     |
| `lightning`   | Occasional full-card flash with a long idle gap, quick rise + decay.                     | `Rectangle` opacity keyframes (like the unicorn `shootingStar` long-repeat)      |

Per-layer opacities are tuned against the `opacity` baseline (≈0.22) so any
combination stays a backdrop. Colours come from `$cfg.colors` (the theme's
orange→purple gradient) except where a motif needs fixed hues — moon (pale
yellow-white), eyes (green/amber), gravestones/bats (near-black) — which fall back
to built-in sets if `colors` is empty.

## Reuse vs. new code

- **Reused as-is** (already global at runtime; all `lib\*.ps1` are dot-sourced):
  `New-Brush`, `New-SceneStop`, the sun-glow, cloud/wave-drift, vertical-drift, and
  opacity-pulse idioms.
- **New shared helper:** none required. (If duplication appears, factor a
  `lib/scene-common.ps1` then — out of scope now.)
- **New WPF-free, unit-tested geometry** (mirrors `New-ArcPathData`'s testable,
  invariant-culture, `.`-decimal contract):
  - `New-WebPathData(cx, cy, r, spokes, rings)` — radial spokes + concentric arc
    threads for the corner web.
  - `New-BatPathData(w, h)` — a small two-wing bat silhouette path.

## Registration / dispatch (`show-notification.ps1`)

1. Dot-source the renderer next to the existing includes:
   `. (Join-Path $PSScriptRoot 'lib\scene-spooky.ps1')`
2. Add to the dispatch table:
   `spooky = { param($b, $c) Start-Spooky $b $c }`
3. Add the 8 flag reads to the `$sceneCfg` hashtable
   (`moon, fog, gravestones, webs, ghosts, bats, eyes, lightning`, all
   `[bool](Get-Prop $theme.scene '<flag>')`).

No other dispatch change — colour resolution, default merge, and the
try/catch-around-scene safety already exist and apply uniformly.

## Schema (`settings.schema.json`)

- Add `"spooky"` to the `scene.kind` enum.
- Add 8 boolean flag properties (`moon, fog, gravestones, webs, ghosts, bats,
  eyes, lightning`) with `spooky:`-prefixed descriptions, mirroring the
  unicorn/sakura flag definitions.

## Back-compat

Unchanged from the scenery design: the `scene` `Canvas` is emitted only when the
resolved theme has a `scene`. `spooky` previously had none, so this only adds a
scene to one theme; the default theme stays scene-less and the golden XAML stays
byte-identical. The `Resolve-Theme` passthrough and `$box.Scene` plumbing are
already in place.

## Error handling

- No `scene` → today's look, no error.
- Unknown `kind` → no scenery; warn to stderr; card still shows (existing path).
- `colors` empty/unresolvable → each layer falls back to its built-in set.
- Renderer throws → caught at dispatch; popup renders without scenery.
- `ActualWidth/Height ≤ 0` → `Start-Spooky` returns early (as `Start-Waves` does).

## Testing / verification

1. **Geometry unit tests** — `New-WebPathData` and `New-BatPathData`, WPF-free:
   monotonic/expected sampling, valid path string, `.`-decimal under an `nl-BE`
   culture (mirrors the wave-path / arc-path tests).
2. **Config parse smoke** — `settings.json` parses; `spooky.scene.kind == "spooky"`.
3. **Schema checks** (`tests/settings.Tests.sh`) — `scene.kind` enum allows
   `spooky`; the 8 flags are defined; full Draft-07 validation of `settings.json`
   stays at 0 errors.
4. **Default-equivalence** — no `settings.json` → built XAML byte-identical to
   `tests/golden/default.xaml` (still green, untouched).
5. **Scene XAML snapshot** — `-EmitXaml` for `spooky` contains the `scene` Canvas;
   a no-scene theme does not.
6. **Per-flag render** — for each of the 8 flags alone, and the default preset,
   the popup runs clean (exit 0, no stderr) via the acceptance command.
7. **Visual check** — render the presets (both events) and screenshot; confirm the
   🎃 hero and body text stay readable behind every layer.

## Default preset

Shipped enabled in `settings.json`: `moon + fog + bats + webs` — reads instantly
as spooky while staying subtle. The other four (`gravestones, ghosts, eyes,
lightning`) are off by default and available for the prune-later evaluation.

## Acceptance

```
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w /mnt/c/temp/notify/show-notification.ps1)" \
  -Hwnd 0 -Folder demo -Event done -Seconds 8
```

with `activeTheme: "spooky"` and a chosen flag-set shows the selected layers
drifting subtly behind the content; removing `settings.json` reproduces the
current default look exactly.

## Out of scope

- Choosing the final flag-set (that is the post-render evaluation this enables).
- Scenes for the remaining themes.
- Per-event scenery (scene stays theme-level).
- Factoring `lib/scene-common.ps1` (only if real duplication emerges).
