# Phase 2: play the jump frames while translating straight up onto the top edge.
# The sprite bakes a full hop (arms-up apex ~frame 16, settled ~frame 48). The baseline
# translate must track that hop, not outrun it: a linear 700ms move parks the body on the
# edge while the arms are still rising, which reads as the hands lifting too late. So we
# sync the translate to the airborne span and ease it Out — fast lift, then settle.
function Start-Jump {
  param([hashtable]$Box, [scriptblock]$OnDone)
  $m = $Box.Mascot
  $a = Set-MascotClip $Box 'jump' $Box.FxLeft $Box.FyRest   # start feet in the slot
  $restTop = $Box.FyRest - $a.Ay
  $landTop = $Box.FyLand - $a.Ay
  $fps = 30
  $frameCount = @(Get-ChildItem (Join-Path $PSScriptRoot '..\mascots\jump') -Filter 'frame_*.png').Count
  $airborneFrac = 0.55   # sprite has touched back down by ~frame 35/64; stop translating there
  $dur = [System.Windows.Duration][TimeSpan]::FromMilliseconds([int]($frameCount / $fps * 1000 * $airborneFrac))
  $up = New-Object System.Windows.Media.Animation.DoubleAnimation $restTop, $landTop, $dur
  $ease = New-Object System.Windows.Media.Animation.QuadraticEase
  $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
  $up.EasingFunction = $ease
  $m.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty, $up)
  Start-Flipbook -Image $m -Dir (Join-Path $PSScriptRoot '..\mascots\jump') -Fps $fps -OnDone {
    # Pin the final position so the next phase starts from the edge.
    $m.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty, $null)
    [System.Windows.Controls.Canvas]::SetTop($m, $landTop)
    if ($OnDone) { & $OnDone }
  }.GetNewClosure()
}
