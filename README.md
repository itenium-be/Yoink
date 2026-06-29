# claude-notify

Pops a custom notification on the monitor where *that* Claude session's terminal lives — bell + window flash + rainbow popup (waving hand when it needs you, fireworks when it's done) — and closes when you focus that terminal or click it.

## Wire up

Point `~/.claude/settings.json` at this repo's hook scripts. If this repo lives at `~/.claude/notify`:

```jsonc
"hooks": {
  "SessionStart": [
    { "hooks": [ { "type": "command", "command": "bash ~/.claude/notify/hooks/notify-capture.sh" } ] }
  ],
  "Stop": [
    { "hooks": [ { "type": "command", "command": "bash ~/.claude/notify/hooks/notify-fire.sh done" } ] }
  ],
  "Notification": [
    { "hooks": [ { "type": "command", "command": "bash ~/.claude/notify/hooks/notify-fire.sh needs-input" } ] }
  ]
}
```

Restart Claude Code (the `SessionStart` capture runs on next launch).

## Usage

- **Left click** — activate the originating terminal.
- **Right click** — close the notification without activating the terminal.

## Trigger manually

From a PowerShell prompt, in the repo directory:

```powershell
.\show-notification.ps1 -Event done -Folder Notify
.\show-notification.ps1 -Event needs-input -Folder Notify
```

| Switch         | Effect                                                            |
|----------------|-------------------------------------------------------------------|
| `-Event`       | `done` (default) or `needs-input`                                 |
| `-Seconds <n>` | Auto-close after n seconds (default: stay until focused/clicked)  |
| `-Folder <s>`  | Folder name shown in the card body                                |
| `-Hwnd <n>`    | Terminal to flash + auto-close once it regains focus              |

Flash and auto-close on *this* terminal:

```powershell
.\show-notification.ps1 -Event done -Hwnd ([int64](Get-Process -Id $PID).MainWindowHandle)
```

## Settings editor

A live editor for `settings.json` — controls on top, the notification card looping below.
Edits are in-memory until you press **Save**.

```powershell
.\settings-editor.ps1
```

Pick the event, theme, mascot moves, sounds and the active theme's scene toggles; the card
re-renders as you change them. Body/footer text and gradient colours aren't editable yet —
edit those in `settings.json` directly. The preview spawns a fresh animated card per edit, so
after many tweaks it can get sluggish — restart the editor if so.

## Configuration

Each event's body is a list of templated lines in `settings.json` (`events.<event>.body`). Lines use `{{token}}` replacements; a line whose tokens all resolve empty is dropped.

| Token                 | Resolves to                                                        |
|-----------------------|--------------------------------------------------------------------|
| `{{folder}}`          | Basename of the working directory                                  |
| `{{cwd}}`             | Full working-directory path                                        |
| `{{repo}}`            | Git repository name (top-level dir), empty outside a repo          |
| `{{branch}}`          | Current git branch                                                 |
| `{{dirty}}`           | `●` when the working tree has uncommitted changes, else empty      |
| `{{message}}`         | Claude Code's notification reason (needs-input only)               |
| `{{last_prompt}}`     | Your most recent prompt (truncated to ~120 chars)                  |
| `{{last_assistant}}`  | Claude's last message (truncated to ~120 chars)                    |
| `{{model}}`           | Active model id                                                    |
| `{{agents}}`          | Background agents still running (empty when none)                  |
| `{{pending_tool}}`    | Name of the most recent tool call                                  |
| `{{permission_mode}}` | `auto` / `default` / `plan` / `acceptEdits`                        |
| `{{event}}`           | `done` or `needs-input`                                            |

## Requirements

WSL + Windows Terminal, `powershell.exe` and `jq` on `PATH`.

## Custom sounds (optional)

Drop `done.wav` / `needs-input.wav` into `~/.claude/notify/sounds/`. Falls back to Windows system sounds.

## Tests

```bash
bash ~/.claude/notify/tests/run.sh
```
