param(
  [long]$Hwnd = 0,
  [string]$Folder = "",
  [string]$Event = "done",
  [string]$Sound = "",
  [int]$Seconds = 8,
  [switch]$DryRun
)
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

Add-Type @"
using System; using System.Runtime.InteropServices;
public class WinFocus {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
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

# --- Per-event styling ---
if ($Event -eq 'needs-input') {
  $statusText = 'Needs you'; $accent = '#FF7A18'
  $indicator = @"
<TextBlock Text="&#x1F44B;" FontSize="46" HorizontalAlignment="Center" VerticalAlignment="Center" RenderTransformOrigin="0.5,0.85">
  <TextBlock.RenderTransform><RotateTransform Angle="0"/></TextBlock.RenderTransform>
  <TextBlock.Triggers>
    <EventTrigger RoutedEvent="FrameworkElement.Loaded">
      <BeginStoryboard><Storyboard RepeatBehavior="Forever" AutoReverse="True">
        <DoubleAnimation Storyboard.TargetProperty="(UIElement.RenderTransform).(RotateTransform.Angle)" From="-25" To="25" Duration="0:0:0.28"/>
      </Storyboard></BeginStoryboard>
    </EventTrigger>
  </TextBlock.Triggers>
</TextBlock>
"@
} else {
  $statusText = 'Done!'; $accent = '#22C55E'
  $indicator = '<Canvas x:Name="fx" Width="64" Height="64"/>'
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
      <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
        <GradientStop Color="#7C3AED" Offset="0"/><GradientStop Color="#2563EB" Offset="0.17"/>
        <GradientStop Color="#06B6D4" Offset="0.34"/><GradientStop Color="#22C55E" Offset="0.5"/>
        <GradientStop Color="#EAB308" Offset="0.67"/><GradientStop Color="#F97316" Offset="0.84"/>
        <GradientStop Color="#EC4899" Offset="1"/>
      </LinearGradientBrush>
    </Border.Background>
    <Border.Effect><DropShadowEffect BlurRadius="30" ShadowDepth="5" Opacity="0.55"/></Border.Effect>
    <Border CornerRadius="21" Margin="3" Background="#18181B" ClipToBounds="True">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>

        <!-- Big rainbow unicorn, masked as a background image on the right -->
        <Rectangle Grid.Column="1" Width="220" Margin="0,0,4,-10" Opacity="0.92">
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

        <!-- Left content -->
        <StackPanel Grid.Column="0" VerticalAlignment="Center" Margin="26,0,0,0">
          <StackPanel Orientation="Horizontal">
            <TextBlock x:Name="logo" FontFamily="Cascadia Mono, Consolas, Courier New" FontSize="16"
                       Foreground="#D97757" LineHeight="16" LineStackingStrategy="BlockLineHeight"
                       VerticalAlignment="Center"/>
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
# Claude mark, drawn from block-element glyphs (all BMP, so [char] is encoding-safe)
$b = @{ FB=[char]0x2590; TL=[char]0x259B; FU=[char]0x2588; TR=[char]0x259C; HL=[char]0x258C; QTR=[char]0x259D; QTL=[char]0x2598 }
$win.FindName('logo').Text = " $($b.FB)$($b.TL)$($b.FU)$($b.FU)$($b.FU)$($b.TR)$($b.HL)`n$($b.QTR)$($b.TR)$($b.FU)$($b.FU)$($b.FU)$($b.FU)$($b.FU)$($b.TL)$($b.QTL)`n  $($b.QTL)$($b.QTL) $($b.QTR)$($b.QTR)"
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

# --- Position on the target monitor (DPI-correct), fade in, kick off fireworks ---
$win.Add_Loaded({
  $src = [System.Windows.PresentationSource]::FromVisual($win)
  $sx = $src.CompositionTarget.TransformToDevice.M11
  $sy = $src.CompositionTarget.TransformToDevice.M22
  $wpx = $win.ActualWidth * $sx; $hpx = $win.ActualHeight * $sy; $pad = 12 * $sx
  $win.Left = ($wa.Right  - $wpx - $pad) / $sx
  $win.Top  = ($wa.Bottom - $hpx - $pad) / $sy
  $fade = New-Object System.Windows.Media.Animation.DoubleAnimation 0, 1, ([System.Windows.Duration][TimeSpan]::FromMilliseconds(250))
  $win.BeginAnimation([System.Windows.Window]::OpacityProperty, $fade)
  if ($Event -eq 'done') { Start-Fireworks ($win.FindName('fx')) }
})

# --- Click to focus the originating terminal window ---
$win.Add_MouseLeftButtonDown({
  if ($Hwnd -ne 0) {
    if ([WinFocus]::IsIconic([IntPtr]$Hwnd)) { [WinFocus]::ShowWindow([IntPtr]$Hwnd, [WinFocus]::SW_RESTORE) }
    [WinFocus]::SetForegroundWindow([IntPtr]$Hwnd)
  }
  $win.Close()
})

# --- Auto-dismiss ---
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds($Seconds)
$timer.Add_Tick({ $timer.Stop(); $win.Close() })
$timer.Start()
$win.ShowDialog() | Out-Null
