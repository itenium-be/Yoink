# Frame-by-frame flipbook player for an Image element.
# -Loop plays forever; otherwise -OnDone fires once after the last frame.
function Start-Flipbook {
  param(
    [System.Windows.Controls.Image]$Image,
    [string]$Dir,
    [int]$Fps = 30,
    [double]$Size = 0,   # rendered height in px; 0 = leave the Image's current size
    [switch]$Loop,
    [scriptblock]$OnDone
  )
  $files = @(Get-ChildItem -Path $Dir -Filter 'frame_*.png' -ErrorAction SilentlyContinue | Sort-Object Name)
  if ($files.Count -eq 0) { if ($OnDone) { & $OnDone }; return }
  if ($Size -gt 0) { $Image.Width = [double]::NaN; $Image.Height = $Size }
  $frames = foreach ($f in $files) {
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bi.UriSource = New-Object System.Uri($f.FullName)
    $bi.EndInit(); $bi.Freeze(); $bi
  }
  $Image.Source = $frames[0]
  $Image.Visibility = [System.Windows.Visibility]::Visible
  $state = [pscustomobject]@{ Idx = 0 }
  $timer = New-Object System.Windows.Threading.DispatcherTimer
  $timer.Interval = [TimeSpan]::FromMilliseconds([int](1000 / $Fps))
  $timer.Add_Tick({
    $state.Idx++
    if ($state.Idx -ge $frames.Count) {
      if ($Loop) { $state.Idx = 0 }
      else { $timer.Stop(); if ($OnDone) { & $OnDone }; return }
    }
    $Image.Source = $frames[$state.Idx]
  }.GetNewClosure())
  $timer.Start()
}
