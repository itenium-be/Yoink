# Yoink

Themed Windows (WSL) Claude notification hooks, whatever theme you fancy, be it 🦄, 🌸, 🐉
or The Matrix, we've got you covered. Fully configurable.

<video src="https://github.com/itenium-be/Yoink/raw/main/site/assets/yoink-unicorn.mp4" autoplay loop muted playsinline></video>


## Wire up

Point `~/.claude/settings.json` at this repo's hook scripts. If this repo lives at `~/.claude/yoink`:

```jsonc
"hooks": {
  "SessionStart": [
    { "hooks": [ { "type": "command", "command": "bash ~/.claude/yoink/hooks/notify-capture.sh" } ] }
  ],
  "Stop": [
    { "hooks": [ { "type": "command", "command": "bash ~/.claude/yoink/hooks/notify-fire.sh done" } ] }
  ],
  "Notification": [
    { "hooks": [ { "type": "command", "command": "bash ~/.claude/yoink/hooks/notify-fire.sh needs-input" } ] }
  ]
}
```

## Usage

- **Left click** — activate the originating terminal.
- **Right click** — close the notification without activating the terminal.


## Settings

Fully configurable by updating `settings.json`.
Use the editor if you want to test-drive the different themes and options.


```powershell
.\settings-editor.ps1
```

## Configuration

Possible replacements for the notification body text.

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

WSL with `jq` on `PATH`.

```sh
sudo apt install jq
```


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


## Tests

```bash
bash ~/.claude/yoink/tests/run.sh
```

## Credits

Thanks to [Wale-Durojaye Ayotomiwa](https://github.com/tomiwadoesux)
for the awesome [Claude mascot animations](https://tympanus.net/codrops/2026/05/05/reverse-engineering-claude-ais-mascot-animations-with-svg-and-gsap/)
