# claude-notify

Pops a custom notification on the monitor where *that* Claude session's terminal lives — bell + window flash + rainbow popup (waving hand when it needs you, fireworks when it's done) — and closes when you focus that terminal or click it.

## Wire up

Install the hooks (this repo is assumed to live at `~/.claude/notify`):

```bash
cp ~/.claude/notify/hooks/*.sh ~/.claude/hooks/
```

Then add to `~/.claude/settings.json` (merge into an existing `hooks` block if you have one):

```jsonc
"hooks": {
  "SessionStart": [
    { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/notify-capture.sh" } ] }
  ],
  "Stop": [
    { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/notify-fire.sh done" } ] }
  ],
  "Notification": [
    { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/notify-fire.sh needs-input" } ] }
  ]
}
```

Restart Claude Code (the `SessionStart` capture runs on next launch).

## Usage

- **Left click** — activate the originating terminal.
- **Right click** — close the notification without activating the terminal.

## Requirements

WSL + Windows Terminal, `powershell.exe` and `jq` on `PATH`.

## Custom sounds (optional)

Drop `done.wav` / `needs-input.wav` into `~/.claude/notify/sounds/`. Falls back to Windows system sounds.

## Tests

```bash
bash ~/.claude/notify/tests/run.sh
```
