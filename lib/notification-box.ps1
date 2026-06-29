# Builds the notification window + card and returns the $box element bag.
# The mascot lives in an unclipped window-level overlay canvas (top z-index) so
# it can sit on the card's top edge; the card itself keeps its rounded clip.
# Sound, flash, click-to-focus, logo-wave and dismissal stay in the orchestrator.
function New-Brush([string]$hex) { New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex)) }

# Radial confetti burst on a 64x64 canvas; colours come from the theme gradient.
function Start-Fireworks($canvas, $colors) {
  if ($null -eq $canvas) { return }
  $colors = @($colors); if ($colors.Count -eq 0) { $colors = @('#FF5F6D','#FFD93D','#3CFFB0','#36D1DC','#A56BFF') }
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

function New-NotificationBox {
  param(
    [string]$Event = 'done',
    [hashtable]$Theme,
    [hashtable]$Ev,
    [object[]]$BodyLines = @(),
    [System.Drawing.Rectangle]$WorkArea,
    [switch]$EmitXaml
  )

  $statusText = $Ev.label
  $accent     = $Ev.accent
  $heroStops  = New-GradientStops $Theme.gradient
  $rimStops   = New-GradientStops $Theme.rim

  if ($Ev.indicator -eq 'fireworks') {
    $indicator = '<Canvas x:Name="fx" Width="64" Height="64" HorizontalAlignment="Center" VerticalAlignment="Center"/>'
  } else {
    $indicator = @"
<Rectangle Width="58" Height="58" HorizontalAlignment="Center" VerticalAlignment="Center" RenderTransformOrigin="0.5,0.85">
  <Rectangle.Fill><LinearGradientBrush StartPoint="0,0" EndPoint="1,1">$heroStops</LinearGradientBrush></Rectangle.Fill>
  <Rectangle.OpacityMask>
    <VisualBrush Stretch="Uniform"><VisualBrush.Visual>
      <TextBlock Text="$($Ev.indicator)" FontSize="60" FontFamily="Segoe UI Emoji"/>
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
  }

  $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        Width="620" Height="330" Opacity="0">
  <Grid>
    <!-- Card sits below a transparent headroom strip so the mascot can land on its top edge. -->
    <Border CornerRadius="24" Margin="14,104,14,14">
      <Border.Background>
        <LinearGradientBrush x:Name="rimBrush" StartPoint="0,0" EndPoint="1,1">$rimStops</LinearGradientBrush>
      </Border.Background>
      <Border.Effect><DropShadowEffect BlurRadius="30" ShadowDepth="5" Opacity="0.55"/></Border.Effect>
      <Border x:Name="card" CornerRadius="21" Margin="3" Background="$($Theme.card)" ClipToBounds="True">
        <Grid>
          <!-- Big rainbow unicorn background, bleeding to the card edges (rounded clip
               on the card keeps it from spilling onto the rim).
               VerticalAlignment must stay Stretch: a Rectangle with no Height collapses otherwise. -->
          <Rectangle x:Name="unicorn" Panel.ZIndex="0" Width="210" HorizontalAlignment="Right" VerticalAlignment="Stretch" Margin="0" Opacity="0.92">
            <Rectangle.Fill>
              <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">$heroStops</LinearGradientBrush>
            </Rectangle.Fill>
            <Rectangle.OpacityMask>
              <VisualBrush Stretch="Uniform">
                <VisualBrush.Visual>
                  <TextBlock Text="$($Theme.hero)" FontSize="190" FontFamily="Segoe UI Emoji"/>
                </VisualBrush.Visual>
              </VisualBrush>
            </Rectangle.OpacityMask>
          </Rectangle>

          <!-- Content layer, always above the unicorn -->
          <StackPanel Panel.ZIndex="1" HorizontalAlignment="Left" VerticalAlignment="Center" Margin="26,0,0,0">
            <StackPanel Orientation="Horizontal">
              <!-- Empty spacer: reserves the mascot's resting spot during the looking phase. -->
              <Grid x:Name="slot" Width="128" Height="110" VerticalAlignment="Center"/>
              <TextBlock x:Name="status" FontSize="34" FontWeight="Bold" Margin="16,0,0,0" VerticalAlignment="Center"/>
              <Grid Width="64" Height="64" Margin="14,0,0,0" VerticalAlignment="Center">$indicator</Grid>
            </StackPanel>
            <StackPanel x:Name="bodyPanel" Margin="2,10,0,0"/>
            <TextBlock Text="click to focus" FontSize="13" Foreground="#999999" Margin="2,8,0,2"/>
          </StackPanel>
        </Grid>
      </Border>
    </Border>

    <!-- Unclipped overlay: the mascot animates here, free to sit on the card's top edge. -->
    <Canvas x:Name="overlay" Panel.ZIndex="10" IsHitTestVisible="False">
      <!-- Height-driven: each phase sets Height so the character matches across
           phases (frame canvases differ in padding/effects). Width auto-follows. -->
      <Image x:Name="mascot" Stretch="Uniform" Visibility="Collapsed"
             RenderOptions.BitmapScalingMode="HighQuality"/>
    </Canvas>
  </Grid>
</Window>
"@

  if ($EmitXaml) { return $xaml }

  $win = [Windows.Markup.XamlReader]::Parse($xaml)

  $st = $win.FindName('status'); $st.Text = $statusText
  $st.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($accent))
  $bodyPanel = $win.FindName('bodyPanel')
  foreach ($ln in $BodyLines) {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = [string]$ln.text
    $tb.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    switch ($ln.style) {
      'headline' { $tb.FontSize = 22; $tb.FontWeight = [System.Windows.FontWeights]::SemiBold; $tb.Foreground = (New-Brush '#FFFFFF'); $tb.Margin = (New-Object System.Windows.Thickness 0,4,0,0) }
      'muted'    { $tb.FontSize = 13; $tb.Foreground = (New-Brush '#999999'); $tb.Margin = (New-Object System.Windows.Thickness 0,4,0,0) }
      default    { $tb.FontSize = 19; $tb.Foreground = (New-Brush '#FFFFFF'); $tb.Margin = (New-Object System.Windows.Thickness 0,4,0,0) }
    }
    $bodyPanel.Children.Add($tb) | Out-Null
  }

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
    $win.Left = ($WorkArea.Right  - $wpx - $pad) / $sx
    $win.Top  = ($WorkArea.Bottom - $hpx - $pad) / $sy
    $fade = New-Object System.Windows.Media.Animation.DoubleAnimation 0, 1, ([System.Windows.Duration][TimeSpan]::FromMilliseconds(250))
    $win.BeginAnimation([System.Windows.Window]::OpacityProperty, $fade)

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
    if ($Ev.indicator -eq 'fireworks') { Start-Fireworks ($win.FindName('fx')) (@(Get-StopColors $Theme.gradient)) }
  }.GetNewClosure())

  return @{
    Win = $win; Card = $win.FindName('card'); Slot = $win.FindName('slot')
    Overlay = $win.FindName('overlay'); Mascot = $win.FindName('mascot')
    Event = $Event
  }
}
