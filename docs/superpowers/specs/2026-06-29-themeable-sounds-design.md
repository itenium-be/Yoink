# Themeable Notification Sounds — Design

## Goal

Each theme owns a pair of notification sounds (done / needs-input), selectable and
previewable in the settings-editor, persisted to `settings.json`, and played on the live
notification.

## Model

Two responsibilities, split:

- **Theme decides *which* sound.** `themes.<theme>.sound = { done, "needs-input" }` naming a
  wav file (relative to `sounds/`). `""` = no sound for that event.
- **Event decides *whether* to play.** `events.<event>.sound` is a boolean master toggle
  (was the `asterisk`/`exclamation`/`""` enum).

Resolution: `play = events[event].sound (bool) AND theme.sound[event] (non-empty) AND file exists`.
Anything missing → **silent**. No system-sound fallback.

All audio is **wav** (`SoundPlayer` is wav-only). Existing non-wav downloads in `sounds/`
are converted to wav up front via ffmpeg.

### settings.json

```jsonc
"events": {
  "done":        { ..., "sound": true },
  "needs-input": { ..., "sound": true }
},
"themes": {
  "unicorn": { "hero": "🦄", ..., "sound": { "done": "", "needs-input": "" } }
  // all 9 themes get a sound block; filenames start "" until assigned via the editor
}
```

### settings.schema.json

- `definitions.event.properties.sound`: `{ "type": "boolean", "description": "Master toggle:
  play this event's themed sound." }` (replaces the enum).
- `definitions.theme`: add `sound` (optional, not in `required`):
  ```jsonc
  "sound": {
    "type": "object", "additionalProperties": false,
    "description": "Wav filenames (relative to sounds/) per event. Empty = silent.",
    "properties": { "done": { "type": "string" }, "needs-input": { "type": "string" } }
  }
  ```

## Playback (`show-notification.ps1`)

Resolution moves fully into PowerShell — bash cannot know the file when
`activeTheme: "random"` (the theme is chosen at display time). Replace the sound block
(current lines 92-99):

```powershell
# Theme picks the wav; the event toggle gates it. Toggle off, no file, or missing file => silent.
if ([bool]$ev.sound) {
  $sndFile = if ($theme.sound) { [string](Get-Prop $theme.sound $Event) } else { '' }
  if ($sndFile) {
    $p = Join-Path $PSScriptRoot "sounds\$sndFile"
    if (Test-Path $p) { try { (New-Object System.Media.SoundPlayer $p).Play() } catch {} }
  }
}
```

Remove the now-unused `-Sound` parameter (line 5).

## notify-lib.ps1

- Event defaults: `sound='asterisk'`/`'exclamation'` → `sound=$true` for both events.
- `Resolve-Event`: stop coercing `sound` to string — `[string]$true` is `"True"` and
  `[bool]"False"` is `$true` (any non-empty string is truthy). Return `sound = $snd` (the
  raw boolean). An explicit `""` (legacy) coerces via `[bool]""` = `$false` → silent.
- `Resolve-Theme`: add `sound = (Get-Prop $t 'sound')` to the returned hashtable so
  `$theme.sound` is available downstream. A theme without `sound` yields `$null` → silent.

## Hook (`notify-fire.sh`)

Drop the `SND`/`WSND` computation (current lines 37-38, 41-42) and the `-Sound "$WSND"`
argument. `$PSScriptRoot/sounds/` is resolved directly in PowerShell.

## Editor (`settings-model.ps1` + `settings-editor.ps1`)

- **Event group:** the `sound` field kind changes `dropdown` → `checkbox`.
- **Theme group:** always show **both** sound pickers (regardless of selected event):
  `themes.<theme>.sound.done` and `themes.<theme>.sound.needs-input`, each a new `'sound'`
  field kind = a wav dropdown + a **▶ Play** button that previews the selection in-process.
- **Wav list:** the editor enumerates `sounds/*.wav` at startup and injects the filenames
  (with a leading `""`) as `$enums['sound.files']`. `Get-EditorFields` reads that for the
  theme sound options. `Get-SchemaEnums` drops the now-unused `sound` enum.
- **`Get-EditorFields`:** emits the event `sound` as `checkbox` and two theme
  `sound.<event>` fields as `'sound'` kind with options `@($enums['sound.files'])`.
- **`New-FieldControl`:** new `'sound'` case → a `ComboBox` (options = wavs) plus a Play
  `Button`; the handler plays `Join-Path $soundsDir <selected>` via `SoundPlayer`. A `""`
  selection no-ops.

## Tests (TDD)

- `settings.Tests.sh`: `events.*.sound` is boolean; every theme has a `sound` object with
  `done` + `needs-input` keys; schema declares `event.sound` boolean and `theme.sound`.
- `settings-model.Tests.ps1`: event `sound` field is `checkbox`; both theme `sound.<event>`
  fields are `'sound'` kind carrying the injected wav options.
- `settings-editor.Tests.sh`: `-DryRun` lists `checkbox events.<e>.sound` + the two
  `sound themes.<t>.sound.*` rows; `-SaveTo` round-trips the boolean + theme sound object;
  `-SelfTest` still builds (covers the new control + Play handler wiring).

## Docs

Update `SOUNDS.md`: model is event-toggle + per-theme wav files + silent fallback. The
system asterisk/exclamation sounds are reference-only, not a runtime fallback.

## Out of scope

- Choosing which wav each theme uses (user assigns via the editor).
- Non-wav playback, per-theme subfolders, volume control.
