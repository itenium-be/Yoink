param(
  [long]$Hwnd = 0,
  [string]$Folder = "",
  [string]$Event = "done",
  [string]$Sound = "",
  [int]$Seconds = 0,   # 0 = stay until clicked or the target terminal is focused
  [switch]$DryRun
)
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

. (Join-Path $PSScriptRoot 'lib\win-focus.ps1')
. (Join-Path $PSScriptRoot 'lib\notification-box.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-player.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-jump-prep.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-jump.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-confetti.ps1')
. (Join-Path $PSScriptRoot 'lib\mascot-flag-waver.ps1')

# --- Resolve the target monitor ---
$screen = $null
if ($Hwnd -ne 0) { try { $screen = [System.Windows.Forms.Screen]::FromHandle([IntPtr]$Hwnd) } catch {} }
if ($null -eq $screen) { $screen = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position) }
$wa = $screen.WorkingArea

if ($DryRun) {
  foreach ($d in 'looking','jump','confetti','flag') {
    $dir = Join-Path $PSScriptRoot "mascots\$d"
    if (-not (Test-Path $dir)) { Write-Error "missing mascot dir: $dir"; exit 1 }
  }
  Write-Output ("screen={0} wa={1},{2},{3}x{4}" -f $screen.DeviceName,$wa.Left,$wa.Top,$wa.Width,$wa.Height); return
}

# Flash the originating terminal (taskbar + title bar) until it gets focus.
if ($Hwnd -ne 0) { try { [WinFocus]::Flash([IntPtr]$Hwnd) } catch {} }

# Without a target window we can't auto-close on focus, so fall back to a timeout.
if ($Hwnd -eq 0 -and $Seconds -le 0) { $Seconds = 15 }

# --- Sound ---
try {
  if ($Sound -and (Test-Path $Sound)) { (New-Object System.Media.SoundPlayer $Sound).Play() }
  elseif ($Event -eq 'needs-input') { [System.Media.SystemSounds]::Exclamation.Play() }
  else { [System.Media.SystemSounds]::Asterisk.Play() }
} catch {}

# --- Build the window ---
$box = New-NotificationBox -Event $Event -Folder $Folder -WorkArea $wa
$win = $box.Win

# --- Mascot choreography: look around -> jump onto the top edge -> celebrate ---
# Started from Loaded because slot/card positions are known only after layout.
$win.Add_Loaded({
  Start-JumpPrep $box {
    Start-Jump $box {
      if ($box.Event -eq 'done') { Start-Confetti $box } else { Start-FlagWave $box }
    }
  }
}.GetNewClosure())

# --- Click to focus the originating terminal window ---
$win.Add_MouseLeftButtonDown({
  if ($Hwnd -ne 0) {
    if ([WinFocus]::IsIconic([IntPtr]$Hwnd)) { [WinFocus]::ShowWindow([IntPtr]$Hwnd, [WinFocus]::SW_RESTORE) }
    [WinFocus]::SetForegroundWindow([IntPtr]$Hwnd)
  }
  $win.Close()
})

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
