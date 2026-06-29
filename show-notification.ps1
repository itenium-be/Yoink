param(
  [long]$Hwnd = 0,
  [string]$Folder = "",
  [string]$Event = "done",
  [int]$Seconds = 0,   # 0 = stay until clicked or the target terminal is focused
  [string]$Context = "",
  [switch]$DryRun,
  [switch]$EmitXaml
)
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

. (Join-Path $PSScriptRoot 'lib\win-focus.ps1')
. (Join-Path $PSScriptRoot 'lib\notification-box.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-player.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-clip.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-jump-prep.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-jump.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-walk.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-hjump.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-gym.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-confetti.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-flag-waver.ps1')
. (Join-Path $PSScriptRoot 'lib\scene-waves.ps1')
. (Join-Path $PSScriptRoot 'lib\scene-space.ps1')
. (Join-Path $PSScriptRoot 'lib\scene-matrix.ps1')
. (Join-Path $PSScriptRoot 'lib\scene-sakura.ps1')
. (Join-Path $PSScriptRoot 'lib\scene-unicorn.ps1')
. (Join-Path $PSScriptRoot 'lib\scene-spooky.ps1')
. (Join-Path $PSScriptRoot 'lib\scene-vaporwave.ps1')
. (Join-Path $PSScriptRoot 'lib\scene-dragon.ps1')
. (Join-Path $PSScriptRoot 'lib\scene-robot.ps1')
. (Join-Path $PSScriptRoot 'lib\card-choreography.ps1')
. (Join-Path $PSScriptRoot 'notify-lib.ps1')

# --- Resolve the target monitor ---
$screen = $null
if ($Hwnd -ne 0) { try { $screen = [System.Windows.Forms.Screen]::FromHandle([IntPtr]$Hwnd) } catch {} }
if ($null -eq $screen) { $screen = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position) }
$wa = $screen.WorkingArea

if ($DryRun) {
  foreach ($d in 'looking','jump','walking','horizontal-jump','gym','confetti','flag') {
    $dir = Join-Path $PSScriptRoot "mascots\$d"
    if (-not (Test-Path $dir)) { Write-Error "missing mascot dir: $dir"; exit 1 }
  }
  if (-not (Test-Path (Join-Path $PSScriptRoot 'mascots\anchor.json'))) { Write-Error "missing anchor.json"; exit 1 }
  Write-Output ("screen={0} wa={1},{2},{3}x{4}" -f $screen.DeviceName,$wa.Left,$wa.Top,$wa.Width,$wa.Height); return
}

# --- Resolve themed config (theme + event + body) ---
$cfg   = Get-NotifyConfig $PSScriptRoot
$theme = Resolve-Theme $cfg (Resolve-ThemeName $cfg)
$ev    = Resolve-Event $cfg $Event
$ctx   = @{ folder = $Folder; event = $Event }
if ($Context -and (Test-Path $Context)) {
  try {
    $cj = Get-Content -Raw -Encoding UTF8 $Context | ConvertFrom-Json
    foreach ($p in $cj.PSObject.Properties) { $ctx[$p.Name] = [string]$p.Value }
  } catch {}
}
$bodyLines = @(Resolve-BodyLines $ev.body $ctx)
$footer    = @(Resolve-Footer $ev.footer $ctx)
if ($EmitXaml) {
  # Emoji come from settings.json as UTF8; force UTF8 stdout so they survive the pipe.
  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
  New-NotificationBox -Event $Event -Theme $theme -Ev $ev -BodyLines $bodyLines -Footer $footer -WorkArea $wa -EmitXaml; return
}

# --- Terminal already focused? You're looking right at it, so skip the card. The themed
# sound still plays unless play-sound-when-terminal-is-active is off. (Both checks live here,
# not in bash: the foreground test needs the live window, and "random" only resolves the
# theme — hence the wav — once we're this far.) ---
$terminalActive = ($Hwnd -ne 0) -and ([WinFocus]::GetForegroundWindow() -eq [IntPtr]$Hwnd)

# --- Sound --- theme picks the wav; the event toggle gates it. Toggle off, no file, or
# missing file => silent.
if ([bool]$ev.sound -and (-not $terminalActive -or (Get-PlaySoundWhenTerminalActive $cfg))) {
  $sndFile = if ($theme.sound) { [string](Get-Prop $theme.sound $Event) } else { '' }
  if ($sndFile) {
    $sndPath = Join-Path $PSScriptRoot "sounds\$sndFile"
    if (Test-Path $sndPath) { try { (New-Object System.Media.SoundPlayer $sndPath).Play() } catch {} }
  }
}

if ($terminalActive) { return }

# --- One card per monitor: evict any predecessor still showing on this screen ---
# Keyed by DeviceName (e.g. \\.\DISPLAY1). Guard on process name: a card that crashed
# (e.g. the PostMessage quota crash) leaves a stale PID that may have been reused.
$screenKey = ($screen.DeviceName -replace '[^A-Za-z0-9]', '_')
$screenDir = Join-Path $PSScriptRoot 'screens'
New-Item -ItemType Directory -Force -Path $screenDir | Out-Null
$marker = Join-Path $screenDir "$screenKey.pid"
if (Test-Path $marker) {
  $old = (Get-Content $marker -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ($old -match '^\d+$' -and [int]$old -ne $PID) {
    $op = Get-Process -Id ([int]$old) -ErrorAction SilentlyContinue
    if ($op -and $op.ProcessName -in @('powershell', 'pwsh')) { Stop-Process -InputObject $op -Force -ErrorAction SilentlyContinue }
  }
}
Set-Content -Path $marker -Value $PID

# Flash the originating terminal (taskbar + title bar) until it gets focus.
if ($Hwnd -ne 0) { try { [WinFocus]::Flash([IntPtr]$Hwnd) } catch {} }

# Without a target window we can't auto-close on focus, so fall back to a timeout.
if ($Hwnd -eq 0 -and $Seconds -le 0) { $Seconds = 15 }

# --- Build the window ---
$box = New-NotificationBox -Event $Event -Theme $theme -Ev $ev -BodyLines $bodyLines -Footer $footer -WorkArea $wa
$win = $box.Win

# Mascot + scene choreography, started once the card has laid out.
# NB: plain scriptblock, not .GetNewClosure() - the closure form rebinds to a module
# scope that can't see the script-scoped phase/scene functions when this script is
# launched via the call operator (.\show-notification.ps1) rather than -File.
$win.Add_Loaded({ Start-CardChoreography $box $theme $ev })

# --- Click to focus the originating terminal window ---
$win.Add_MouseLeftButtonDown({
  if ($Hwnd -ne 0) {
    if ([WinFocus]::IsIconic([IntPtr]$Hwnd)) { [WinFocus]::ShowWindow([IntPtr]$Hwnd, [WinFocus]::SW_RESTORE) }
    [WinFocus]::SetForegroundWindow([IntPtr]$Hwnd)
  }
  $win.Close()
})

# --- Right-click dismisses the card without touching the terminal's focus ---
$win.Add_MouseRightButtonDown({ $win.Close() })

# --- Dismiss: close when the target terminal gains focus; optional timeout ---
$script:elapsed = 0.0
$poll = New-Object System.Windows.Threading.DispatcherTimer
$poll.Interval = [TimeSpan]::FromMilliseconds(400)
$poll.Add_Tick({
  if ($Hwnd -ne 0 -and [WinFocus]::GetForegroundWindow() -eq [IntPtr]$Hwnd) { $poll.Stop(); $win.Close(); return }
  if ($Seconds -gt 0) {
    $script:elapsed += 0.4
    if ($script:elapsed -ge $Seconds) { $poll.Stop(); $win.Close() }
  }
})
$poll.Start()
$win.ShowDialog() | Out-Null

# Release this monitor's slot if we still own it (a successor may have overwritten it).
if ((Test-Path $marker) -and ((Get-Content $marker -ErrorAction SilentlyContinue | Select-Object -First 1) -eq "$PID")) {
  Remove-Item $marker -ErrorAction SilentlyContinue
}
