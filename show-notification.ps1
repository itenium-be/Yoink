param(
  [long]$Hwnd = 0,
  [string]$Folder = "",
  [string]$Event = "done",
  [string]$Sound = "",
  [int]$Seconds = 0,   # 0 = stay until clicked or the target terminal is focused
  [switch]$DryRun
)
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

Add-Type @"
using System; using System.Runtime.InteropServices;
public class WinFocus {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  public const int SW_RESTORE = 9;

  [StructLayout(LayoutKind.Sequential)]
  public struct FLASHWINFO { public uint cbSize; public IntPtr hwnd; public uint dwFlags; public uint uCount; public uint dwTimeout; }
  [DllImport("user32.dll")] public static extern bool FlashWindowEx(ref FLASHWINFO pwfi);
  // FLASHW_ALL (taskbar + caption) | FLASHW_TIMERNOFG (flash until the window comes to the foreground)
  public const uint FLASHW_ALL = 3, FLASHW_TIMERNOFG = 12;

  public static void Flash(IntPtr h) {
    FLASHWINFO fi = new FLASHWINFO();
    fi.cbSize = (uint)Marshal.SizeOf(fi);
    fi.hwnd = h; fi.dwFlags = FLASHW_ALL | FLASHW_TIMERNOFG; fi.uCount = uint.MaxValue; fi.dwTimeout = 0;
    FlashWindowEx(ref fi);
  }
}
"@

# --- Resolve the target monitor ---
$screen = $null
if ($Hwnd -ne 0) { try { $screen = [System.Windows.Forms.Screen]::FromHandle([IntPtr]$Hwnd) } catch {} }
if ($null -eq $screen) { $screen = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position) }
$wa = $screen.WorkingArea

if ($DryRun) { Write-Output ("screen={0} wa={1},{2},{3}x{4}" -f $screen.DeviceName,$wa.Left,$wa.Top,$wa.Width,$wa.Height); return }

# Flash the originating terminal (taskbar + title bar) until it gets focus.
if ($Hwnd -ne 0) { try { [WinFocus]::Flash([IntPtr]$Hwnd) } catch {} }

# Without a target window we can't auto-close on focus, so fall back to a timeout.
if ($Hwnd -eq 0 -and $Seconds -le 0) { $Seconds = 15 }

# --- Per-event styling ---
if ($Event -eq 'needs-input') {
  $statusText = 'Needs you'; $accent = '#FF7A18'
  $indicator = @"
<Rectangle Width="58" Height="58" HorizontalAlignment="Center" VerticalAlignment="Center" RenderTransformOrigin="0.5,0.85">
  <Rectangle.Fill>
    <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
      <GradientStop Color="#FF5F6D" Offset="0"/><GradientStop Color="#FFD93D" Offset="0.3"/>
      <GradientStop Color="#3CFFB0" Offset="0.55"/><GradientStop Color="#36D1DC" Offset="0.78"/>
      <GradientStop Color="#A56BFF" Offset="1"/>
    </LinearGradientBrush>
  </Rectangle.Fill>
  <Rectangle.OpacityMask>
    <VisualBrush Stretch="Uniform"><VisualBrush.Visual>
      <TextBlock Text="&#x1F44B;" FontSize="60" FontFamily="Segoe UI Emoji"/>
    </VisualBrush.Visual></VisualBrush>
  </Rectangle.OpacityMask>
  <Rectangle.RenderTransform><RotateTransform Angle="0"/></Rectangle.RenderTransform>
  <Rectangle.Triggers>
    <EventTrigger RoutedEvent="FrameworkElement.Loaded">
      <BeginStoryboard><Storyboard RepeatBehavior="Forever" AutoReverse="True">
        <DoubleAnimation Storyboard.TargetProperty="(UIElement.RenderTransform).(RotateTransform.Angle)" From="-25" To="25" Duration="0:0:0.28"/>
      </Storyboard></BeginStoryboard>
    </EventTrigger>
  </Rectangle.Triggers>
</Rectangle>
"@
} else {
  $statusText = 'Done!'; $accent = '#22C55E'
  $indicator = '<Canvas x:Name="fx" Width="64" Height="64" HorizontalAlignment="Center" VerticalAlignment="Center"/>'
}

# --- Layout (XAML) ---
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        Width="620" Height="240" Opacity="0">
  <Border CornerRadius="24" Margin="14">
    <Border.Background>
      <LinearGradientBrush x:Name="rimBrush" StartPoint="0,0" EndPoint="1,1">
        <GradientStop Color="#7C3AED" Offset="0"/><GradientStop Color="#2563EB" Offset="0.17"/>
        <GradientStop Color="#06B6D4" Offset="0.34"/><GradientStop Color="#22C55E" Offset="0.5"/>
        <GradientStop Color="#EAB308" Offset="0.67"/><GradientStop Color="#F97316" Offset="0.84"/>
        <GradientStop Color="#EC4899" Offset="1"/>
      </LinearGradientBrush>
    </Border.Background>
    <Border.Effect><DropShadowEffect BlurRadius="30" ShadowDepth="5" Opacity="0.55"/></Border.Effect>
    <Border x:Name="card" CornerRadius="21" Margin="3" Background="#18181B" ClipToBounds="True">
      <Grid>
        <!-- Big rainbow unicorn background, bleeding to the card edges (rounded clip
             on the card keeps it from spilling onto the rim).
             VerticalAlignment must stay Stretch: a Rectangle with no Height collapses otherwise. -->
        <Rectangle x:Name="unicorn" Panel.ZIndex="0" Width="210" HorizontalAlignment="Right" VerticalAlignment="Stretch" Margin="0" Opacity="0.92">
          <Rectangle.Fill>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
              <GradientStop Color="#FF5F6D" Offset="0"/><GradientStop Color="#FFC371" Offset="0.28"/>
              <GradientStop Color="#3CFFB0" Offset="0.5"/><GradientStop Color="#36D1DC" Offset="0.72"/>
              <GradientStop Color="#A56BFF" Offset="1"/>
            </LinearGradientBrush>
          </Rectangle.Fill>
          <Rectangle.OpacityMask>
            <VisualBrush Stretch="Uniform">
              <VisualBrush.Visual>
                <TextBlock Text="&#x1F984;" FontSize="190" FontFamily="Segoe UI Emoji"/>
              </VisualBrush.Visual>
            </VisualBrush>
          </Rectangle.OpacityMask>
        </Rectangle>

        <!-- Content layer, always above the unicorn -->
        <StackPanel Panel.ZIndex="1" HorizontalAlignment="Left" VerticalAlignment="Center" Margin="26,0,0,0">
          <StackPanel Orientation="Horizontal">
            <Grid VerticalAlignment="Center">
              <TextBlock x:Name="logo" FontFamily="Cascadia Mono, Consolas, Courier New" FontSize="16"
                         Foreground="#D97757" LineHeight="16" LineStackingStrategy="BlockLineHeight"
                         TextAlignment="Center" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              <Image x:Name="mascot" Height="108" Stretch="Uniform" Visibility="Collapsed"
                     RenderOptions.BitmapScalingMode="HighQuality"/>
            </Grid>
            <TextBlock x:Name="status" FontSize="34" FontWeight="Bold" Margin="16,0,0,0" VerticalAlignment="Center"/>
            <Grid Margin="14,0,0,0" Width="64" Height="64" VerticalAlignment="Center">$indicator</Grid>
          </StackPanel>
          <TextBlock x:Name="folder" FontSize="19" Foreground="White" Margin="2,14,0,0" TextTrimming="CharacterEllipsis"/>
          <TextBlock Text="click to focus" FontSize="13" Foreground="#999999" Margin="2,8,0,2"/>
        </StackPanel>
      </Grid>
    </Border>
  </Border>
</Window>
"@

$win = [Windows.Markup.XamlReader]::Parse($xaml)

# --- Fill dynamic content ---
# Claude mark, drawn from block-element glyphs (all BMP, so [char] is encoding-safe).
# Two frames: alternating them rocks the mark left/right so it "waves".
$b = @{ FB=[char]0x2590; TL=[char]0x259B; FU=[char]0x2588; TR=[char]0x259C; HL=[char]0x258C; QTR=[char]0x259D; QTL=[char]0x2598 }
$logoFrame1 = " $($b.FB)$($b.TL)$($b.FU)$($b.FU)$($b.FU)$($b.TR)$($b.HL)`n$($b.QTR)$($b.TR)$($b.FU)$($b.FU)$($b.FU)$($b.FU)$($b.FU)$($b.TL)$($b.QTL)`n  $($b.QTL)$($b.QTL) $($b.QTR)$($b.QTR)"
$logoFrame2 = "$($b.QTR)$($b.FB)$($b.TL)$($b.FU)$($b.FU)$($b.FU)$($b.TR)$($b.HL)$($b.QTL)`n $($b.TR)$($b.FU)$($b.FU)$($b.FU)$($b.FU)$($b.FU)$($b.TL)`n  $($b.QTL)$($b.QTL) $($b.QTR)$($b.QTR)"
$logo = $win.FindName('logo'); $logo.Text = $logoFrame1
$st = $win.FindName('status'); $st.Text = $statusText
$st.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($accent))
$win.FindName('folder').Text = $Folder

# --- Sound ---
try {
  if ($Sound -and (Test-Path $Sound)) { (New-Object System.Media.SoundPlayer $Sound).Play() }
  elseif ($Event -eq 'needs-input') { [System.Media.SystemSounds]::Exclamation.Play() }
  else { [System.Media.SystemSounds]::Asterisk.Play() }
} catch {}

function New-Brush([string]$hex) { New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex)) }

function Start-Fireworks($canvas) {
  if ($null -eq $canvas) { return }
  $colors = '#FF5F6D','#FFC371','#FFD93D','#3CFFB0','#36D1DC','#A56BFF','#EC4899'
  $cx = 30; $cy = 30; $n = 16
  for ($i = 0; $i -lt $n; $i++) {
    $ang = $i * (360.0 / $n) * [Math]::PI / 180.0
    $dx = [Math]::Cos($ang) * 24; $dy = [Math]::Sin($ang) * 24
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = 7; $e.Height = 7; $e.Fill = New-Brush ($colors[$i % $colors.Count])
    [System.Windows.Controls.Canvas]::SetLeft($e, $cx); [System.Windows.Controls.Canvas]::SetTop($e, $cy)
    $tt = New-Object System.Windows.Media.TranslateTransform; $e.RenderTransform = $tt
    $canvas.Children.Add($e) | Out-Null
    $dur = [System.Windows.Duration][TimeSpan]::FromSeconds(1.2)
    $ax = New-Object System.Windows.Media.Animation.DoubleAnimation 0, $dx, $dur
    $ay = New-Object System.Windows.Media.Animation.DoubleAnimation 0, $dy, $dur
    $ao = New-Object System.Windows.Media.Animation.DoubleAnimation 1, 0, $dur
    $begin = [TimeSpan]::FromMilliseconds(($i % 4) * 140)
    foreach ($a in @($ax, $ay, $ao)) { $a.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever; $a.BeginTime = $begin }
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $ax)
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $ay)
    $e.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $ao)
  }
}

# Play the "done" mascot as a frame-by-frame flipbook from PNGs in mascots\done.
# Returns $true if it started, $false if no frames were found (caller can fall back).
function Start-Mascot($win, $folder) {
  $dir = Join-Path $PSScriptRoot ('mascots\' + $folder)
  if (-not (Test-Path $dir)) { return $false }
  $files = @(Get-ChildItem -Path $dir -Filter 'frame_*.png' -ErrorAction SilentlyContinue | Sort-Object Name)
  if ($files.Count -eq 0) { return $false }
  $script:mFrames = foreach ($f in $files) {
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bi.UriSource = New-Object System.Uri($f.FullName)
    $bi.EndInit(); $bi.Freeze(); $bi
  }
  $script:mImg = $win.FindName('mascot')
  $win.FindName('logo').Visibility = [System.Windows.Visibility]::Collapsed
  $script:mImg.Source = $script:mFrames[0]
  $script:mImg.Visibility = [System.Windows.Visibility]::Visible
  $script:mIdx = 0
  $mt = New-Object System.Windows.Threading.DispatcherTimer
  $mt.Interval = [TimeSpan]::FromMilliseconds(33)   # ~30fps, matches the source video
  $mt.Add_Tick({ $script:mIdx = ($script:mIdx + 1) % $script:mFrames.Count; $script:mImg.Source = $script:mFrames[$script:mIdx] })
  $mt.Start()
  return $true
}

# --- Position on the target monitor (DPI-correct), fade in, kick off fireworks ---
$win.Add_Loaded({
  # Round-clip the card so edge-bleeding content follows the corner radius (a Border
  # with CornerRadius does NOT clip its children to the rounded shape on its own).
  $card = $win.FindName('card')
  if ($card) {
    $cg = New-Object System.Windows.Media.RectangleGeometry
    $cg.Rect = New-Object System.Windows.Rect 0, 0, $card.ActualWidth, $card.ActualHeight
    $cg.RadiusX = 21; $cg.RadiusY = 21
    $card.Clip = $cg
  }
  $src = [System.Windows.PresentationSource]::FromVisual($win)
  $sx = $src.CompositionTarget.TransformToDevice.M11
  $sy = $src.CompositionTarget.TransformToDevice.M22
  $wpx = $win.ActualWidth * $sx; $hpx = $win.ActualHeight * $sy; $pad = 12 * $sx
  $win.Left = ($wa.Right  - $wpx - $pad) / $sx
  $win.Top  = ($wa.Bottom - $hpx - $pad) / $sy
  $fade = New-Object System.Windows.Media.Animation.DoubleAnimation 0, 1, ([System.Windows.Duration][TimeSpan]::FromMilliseconds(250))
  $win.BeginAnimation([System.Windows.Window]::OpacityProperty, $fade)
  # Per-event mascot: done celebrates with confetti, needs-input waves a flag.
  $mascotFolder = @{ 'done' = 'confetti'; 'needs-input' = 'flag' }[$Event]
  if ($mascotFolder) {
    if (-not (Start-Mascot $win $mascotFolder)) { if ($Event -eq 'done') { Start-Fireworks ($win.FindName('fx')) } }
  }

  # Continuously rotate the rainbow rim so the colours travel around the border.
  $rimBrush = $win.FindName('rimBrush')
  if ($rimBrush) {
    $rot = New-Object System.Windows.Media.RotateTransform
    $rot.CenterX = 0.5; $rot.CenterY = 0.5
    $rimBrush.RelativeTransform = $rot
    $spin = New-Object System.Windows.Media.Animation.DoubleAnimation 0, 360, ([System.Windows.Duration][TimeSpan]::FromSeconds(4))
    $spin.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $rot.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $spin)
  }
})

# --- Click to focus the originating terminal window ---
$win.Add_MouseLeftButtonDown({
  if ($Hwnd -ne 0) {
    if ([WinFocus]::IsIconic([IntPtr]$Hwnd)) { [WinFocus]::ShowWindow([IntPtr]$Hwnd, [WinFocus]::SW_RESTORE) }
    [WinFocus]::SetForegroundWindow([IntPtr]$Hwnd)
  }
  $win.Close()
})

# --- Wave the Claude mark (needs-input only) by toggling its two frames ---
if ($Event -eq 'needs-input') {
  $script:logoOn = $false
  $logoTimer = New-Object System.Windows.Threading.DispatcherTimer
  $logoTimer.Interval = [TimeSpan]::FromMilliseconds(280)
  $logoTimer.Add_Tick({ $script:logoOn = -not $script:logoOn; $logo.Text = $(if ($script:logoOn) { $logoFrame2 } else { $logoFrame1 }) })
  $logoTimer.Start()
}

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
