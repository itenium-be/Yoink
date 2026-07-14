# /yoink — DND (`off`/`on`), `doctor`, `attach`

Design for the first interactive surface of the Yoink plugin ([issue #6](https://github.com/itenium-be/Yoink/issues/6)).
Scope: `off`, `on`, `doctor`, `attach`. The `test` and `theme` subcommands from the issue are
separable — `theme` needs a comment-preserving JSONC write, which is its own problem — and are
not covered here.

## Two roots

Yoink already splits its state:

| Root                    | Holds                                          | Written by            |
|-------------------------|------------------------------------------------|-----------------------|
| `CLAUDE_PLUGIN_ROOT`    | scripts, bundled default `settings.json`       | plugin updates        |
| `$HOME/.claude/yoink`   | user `settings.json`, `sessions/`, `sounds/`   | the user, the hooks   |

`settings.json` is **JSONC** (`lib/settings-model.ps1` strips comments before parsing; the bundled
default ships with `//` comments in it). `jq` cannot read it, and a sed-based comment stripper would
mangle the `"$schema": "https://…"` line. Today only the PowerShell side reads settings, and
`notify-fire.sh` stays a pure-`jq` hot path. This design keeps it that way.

## Channels

A notification fires on up to three channels:

| Channel | What it is                                          | Rendered by                          |
|---------|-----------------------------------------------------|--------------------------------------|
| `bell`  | `\a` to the session's tty                           | the terminal, per its own bell style |
| `card`  | the popup window                                    | `show-notification.ps1`              |
| `sound` | the theme `.wav`                                    | `show-notification.ps1`              |

`bell` is a single ASCII BEL: whether it becomes a tab flash, a taskbar flash, or an audible ding is
the terminal's `bellStyle`, not something Yoink can split.

## DND state: `~/.claude/yoink/dnd.json`

Runtime state, deliberately **not** a key in `settings.json` — that file is declarative config the
user hand-writes and comments, and every `/yoink off` would have to rewrite it.

```json
{
  "all":      { "until": 0, "allow": ["bell"] },
  "sessions": { "6f3a…":                  { "until": 1752600000, "allow": [] } },
  "projects": { "/mnt/c/temp/notify":      { "until": 0,         "allow": ["bell", "sound"] } }
}
```

- `until` is an epoch in seconds; `0` means indefinite. An absent key is not muted.
- `allow` lists the channels that still fire while muted. `card` is never in it — a card *is* the
  notification. Domain: `[]`, `["bell"]`, `["sound"]`, `["bell","sound"]`.
- Expired keys are pruned on any write. No reaper.

## `off-behavior` in `settings.json`

```json
"off-behavior": ["bell"]
```

The **default** `allow` list, nothing more. `/yoink off` runs interactively, so it can afford to read
it through the existing PS settings-model and copy the resolved value into `dnd.json`. The hook never
parses JSONC.

The cost: editing `off-behavior` does not retroactively change an already-active DND. Re-run
`/yoink off`.

## Commands

| Command                                                | Effect                                                                                    |
|--------------------------------------------------------|--------------------------------------------------------------------------------------------|
| `/yoink off [all\|session\|project] [30m\|2h\|1d] [--allow bell,sound]` | Mute. Scope defaults to `all`, duration to indefinite, `allow` to `off-behavior`. |
| `/yoink on [all\|session\|project]`                     | Unmute. Bare `on` clears `all` **and** this session **and** this project.                   |
| `/yoink attach [--force]`                              | Bind the foreground window to this session. `--force` skips the trusted-terminal allowlist. |
| `/yoink doctor`                                        | Pass/fail report on the install, including active DND.                                      |

`session` keys off `$CLAUDE_CODE_SESSION_ID` (present in the environment — a slash command does not
get the hook's stdin). `project` keys off the session cwd.

Bare `/yoink on` clearing all three scopes is deliberate: otherwise `/yoink off session` followed by
`/yoink on` leaves the user muted and convinced Yoink is broken.

## The gate in `notify-fire.sh`

At the top, **before the bell**. Any matching scope suppresses the card; `bell` and `sound` survive
only if present in the **intersection** of every matching scope's `allow` list — most restrictive
wins, so a blanket `off` is never loosened by a per-project one.

Fails open: a missing or unparseable `dnd.json` yields empty output, which is not a match, so the
notification fires.

`needs-input` is exempt from the multi-agent coalescing that already lives in this hook. It is **not**
exempt from DND.

`["sound"]` implies the wav plays with no window, so `show-notification.ps1` grows a `-SoundOnly`
switch.

## `attach`

`notify-capture.sh` records the HWND at SessionStart and only trusts it when the foreground window's
process is on an allowlist (`WindowsTerminal wt alacritty wezterm-gui Hyper Tabby`). It writes nothing
when the terminal wasn't focused at launch, the host isn't on the list (VS Code integrated terminal,
conhost), or the plugin was installed mid-session. `notify-fire.sh` then falls back to `HWND=0` and
click-to-focus is lost.

When the user types `/yoink attach`, the terminal *is* the foreground window by construction. So
attach is a more reliable capture path than the hook, not merely a repair tool. `--force` bypasses the
allowlist for users who accept that a host-based console hands back a child window rather than the
top-level handle.

The trust check moves out of `notify-capture.sh` into a shared script that both the hook and `attach`
call.

## `doctor`

Checks: `jq` on PATH; `powershell.exe` reachable; HWND record exists for this session; user
`settings.json` parses as JSONC; sounds dir resolves; **active DND** (a silently-muted Yoink is the
most likely reason someone runs doctor at all). A missing HWND record reports "run `/yoink attach`".

## Seam

`commands/yoink.md` is a thin wrapper whose `!` bash calls a single `bin/yoink.sh <subcommand>`. All
logic lives in that script so `tests/run.sh` can drive it against the existing `powershell.exe` stub;
the command markdown carries none.

## Tests

Extend `tests/run.sh`:

- each scope (`all`, `session`, `project`) gates `notify-fire.sh`
- an expired `until` does not gate
- `allow` intersection: blanket `[]` beats a project-level `["bell"]`
- bare `/yoink on` clears all three scopes
- duration parsing: `30m`, `2h`, `1d`
- `attach` writes the record for `$CLAUDE_CODE_SESSION_ID`; `--force` bypasses the allowlist
- `doctor` fails correctly on missing `jq`, missing HWND record, unparseable settings

Plus PS-side: `-SoundOnly` plays the wav and creates no window (`show-notification.Tests.sh`).

## Docs

README gains a `/yoink` section with the subcommand table and the `off-behavior` setting.
