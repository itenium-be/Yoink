# Phase 2.5 (experimental, replaces walk): one big horizontal leap from the slot
# side to the right end. The arc is baked into the frames; we translate Canvas.Left
# across, synced to the clip length, then hand off to the celebrate phase.
function Start-HJump {
  param([hashtable]$Box, [scriptblock]$OnDone)
  $m = $Box.Mascot
  $a = Set-MascotClip $Box 'horizontal-jump' $Box.FxLeft $Box.FyLand
  $startLeft = $Box.FxLeft - $a.Ax
  $endLeft = $Box.FxRight - $a.Ax
  [System.Windows.Controls.Canvas]::SetLeft($m, $startLeft)
  $fps = 30
  $n = @(Get-ChildItem (Join-Path $PSScriptRoot '..\mascots\horizontal-jump') -Filter 'frame_*.png').Count
  $dur = [System.Windows.Duration][TimeSpan]::FromMilliseconds([int]($n / $fps * 1000))
  $move = New-Object System.Windows.Media.Animation.DoubleAnimation $startLeft, $endLeft, $dur
  $m.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, $move)
  Start-Flipbook -Image $m -Dir (Join-Path $PSScriptRoot '..\mascots\horizontal-jump') -Fps $fps -OnDone {
    $m.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, $null)
    [System.Windows.Controls.Canvas]::SetLeft($m, $endLeft)
    if ($OnDone) { & $OnDone }
  }.GetNewClosure()
}
