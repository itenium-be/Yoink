# WPF object construction needs STA; powershell.exe (5.1) is STA by default.
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing
. "$PSScriptRoot\..\notify-lib.ps1"
. "$PSScriptRoot\..\lib\notification-box.ps1"

$script:fail = 0
function Assert-True($cond, $msg) {
  if ([bool]$cond) { Write-Host "ok: $msg" } else { Write-Host "FAIL: $msg"; $script:fail++ }
}

$theme = @{ gradient = @('#FF5F6D 0', '#A56BFF 1'); rim = @('#7C3AED 0', '#EC4899 1'); card = '#18181B'; hero = '🦄' }
$ev    = @{ label = 'Done!'; accent = '#22C55E'; indicator = '' }
$body  = @([pscustomobject]@{ text = 'focus probe'; style = 'headline' })
# Off-screen work area: the card is shown for real, but never lands on a monitor.
$wa  = New-Object System.Drawing.Rectangle -10000, -10000, 100, 100
$box = New-NotificationBox -Event 'done' -Theme $theme -Ev $ev -BodyLines $body -WorkArea $wa
$win = $box.Win

# --- The card must never become the active window: it pops up while you're typing elsewhere,
# and an activated card takes the keyboard focus with it. (Asserted on IsActive, not on
# GetForegroundWindow: Windows' foreground lock can deny the steal, so a focused card still
# sometimes leaves the foreground window in place - IsActive catches it either way.) ---
$script:active = $true
$t = New-Object System.Windows.Threading.DispatcherTimer
$t.Interval = [TimeSpan]::FromMilliseconds(700)
$t.Add_Tick({ $t.Stop(); $script:active = $win.IsActive; $win.Close() })
$t.Start()
$win.ShowDialog() | Out-Null

Assert-True (-not $script:active) "showing the card does not activate it"

if ($script:fail -gt 0) { exit 1 } else { Write-Host "ALL PASS" }
