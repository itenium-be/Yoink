# Dev-only: render the active theme's notification CARD to a PNG via RenderTargetBitmap,
# in-process, so scenery can be reviewed deterministically. Because it renders this
# window's own visual tree (not the screen), any other popup on the desktop is irrelevant
# -- no monitor/cursor races. Reuses the real pipeline (New-NotificationBox + Start-*).
param([Parameter(Mandatory)][string]$Out, [int]$Wait = 1600)
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib\win-focus.ps1')
. (Join-Path $root 'lib\notification-box.ps1')
. (Join-Path $root 'lib\scene-waves.ps1')
. (Join-Path $root 'lib\scene-unicorn.ps1')
. (Join-Path $root 'notify-lib.ps1')

$cfg = Get-NotifyConfig $root
$theme = Resolve-Theme $cfg (Resolve-ThemeName $cfg)
$ev = Resolve-Event $cfg 'done'
$ctx = @{ folder = 'demo'; event = 'done' }
$bodyLines = @(Resolve-BodyLines $ev.body $ctx)
$footer = @(Resolve-Footer $ev.footer $ctx)
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

# Mirror show-notification.ps1's scene resolution + dispatch.
$sceneCfg = $null
if ($theme.scene -and (Get-Prop $theme.scene 'kind')) {
  $cols = @(Get-Prop $theme.scene 'colors')
  if (-not $cols -or $cols.Count -eq 0) { $cols = @(Get-StopColors $theme.gradient) }
  $sceneCfg = @{
    kind         = [string](Get-Prop $theme.scene 'kind')
    colors       = $cols
    opacity      = (Coalesce (Get-Prop $theme.scene 'opacity') 0.22)
    speed        = (Coalesce (Get-Prop $theme.scene 'speed') 1.0)
    sky          = [bool](Get-Prop $theme.scene 'sky')
    sun          = [bool](Get-Prop $theme.scene 'sun')
    clouds       = [bool](Get-Prop $theme.scene 'clouds')
    aurora       = [bool](Get-Prop $theme.scene 'aurora')
    rainbow      = [bool](Get-Prop $theme.scene 'rainbow')
    stars        = [bool](Get-Prop $theme.scene 'stars')
    glitter      = [bool](Get-Prop $theme.scene 'glitter')
    sparkles     = [bool](Get-Prop $theme.scene 'sparkles')
    shootingStar = [bool](Get-Prop $theme.scene 'shootingStar')
  }
}
$sceneKinds = @{
  waves   = { param($b, $c) Start-Waves $b $c }
  unicorn = { param($b, $c) Start-Unicorn $b $c }
}

$box = New-NotificationBox -Event 'done' -Theme $theme -Ev $ev -BodyLines $bodyLines -Footer $footer -WorkArea $wa
$win = $box.Win

$win.Add_Loaded({
  if ($sceneCfg) {
    $fn = $sceneKinds[$sceneCfg.kind]
    if ($fn) { try { & $fn $box $sceneCfg } catch { Write-Warning "scene failed: $_" } }
  }
  $t = New-Object System.Windows.Threading.DispatcherTimer
  $t.Interval = [TimeSpan]::FromMilliseconds($Wait)   # let animations advance to a representative frame
  $t.Add_Tick({
    $this.Stop()   # $this is the timer; the local $t isn't captured in this nested handler
    $card = $box.Card
    $w = [int][Math]::Ceiling($card.ActualWidth); $h = [int][Math]::Ceiling($card.ActualHeight)
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap ($w, $h, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($card)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [System.IO.File]::Create($Out); $enc.Save($fs); $fs.Close()
    $win.Close()
  })
  $t.Start()
})
$win.ShowDialog() | Out-Null
Write-Host "rendered $Out"
