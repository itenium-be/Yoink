param(
  [string]$SettingsPath = (Join-Path $PSScriptRoot 'settings.json'),
  [string]$Event = 'done',
  [switch]$DryRun,        # print the field list and exit (no WPF)
  [switch]$SelfTest,      # build the window + one synchronous rebuild, then exit (no message loop)
  [string]$SaveTo = ''    # with -DryRun: serialize the model to this path and exit
)

. (Join-Path $PSScriptRoot 'notify-lib.ps1')
. (Join-Path $PSScriptRoot 'lib\settings-model.ps1')

# --- Load model + derive the selected event and a concrete selected theme (even when
#     activeTheme is "random"). The event + theme dropdowns mutate these and rebuild the form. ---
$script:model = Read-SettingsModel $SettingsPath
$script:enums = Get-SchemaEnums (Join-Path $PSScriptRoot 'settings.schema.json')
# Wav files the theme sound pickers offer (leading '' = silent).
$script:soundsDir = Join-Path $PSScriptRoot 'sounds'
$script:enums['sound.files'] = @('') + @(if (Test-Path $script:soundsDir) { (Get-ChildItem $script:soundsDir -Filter *.wav | Sort-Object Name).Name })
$script:themeNames = @((Get-ModelValue $script:model @('themes')).Keys)
$script:selectedEvent = $Event
$active = [string](Get-ModelValue $script:model @('activeTheme'))
$script:selectedTheme = if ($active -and $active -ne 'random' -and ($script:themeNames -contains $active)) { $active } else { $script:themeNames[0] }
$fields = Get-EditorFields $script:model $script:enums $script:selectedEvent $script:selectedTheme

# --- Headless seam: print the field list (and optionally Save), then exit ---
if ($DryRun) {
  foreach ($f in $fields) { Write-Output ("{0} {1}" -f $f.kind, ($f.path -join '.')) }
  if ($SaveTo) { Set-Content -Path $SaveTo -Value (ConvertTo-SettingsJson $script:model) -Encoding UTF8 }
  return
}

# --- WPF + card renderer libs (only needed for the live window / self-test) ---
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing
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

$script:ctx = Get-SampleContext

# --- Shell window: scrollable controls on top, card host on the bottom ---
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Yoink settings" Width="680" Height="900" Background="#15151A">
  <DockPanel>
    <DockPanel DockPanel.Dock="Top" LastChildFill="False" Margin="10,8">
      <Button x:Name="save" Content="Save" Width="90" Height="28" DockPanel.Dock="Right" Margin="6,0,0,0"/>
      <Button x:Name="reload" Content="Reload" Width="90" Height="28" DockPanel.Dock="Right"/>
      <TextBlock x:Name="status" Foreground="#9CA3AF" VerticalAlignment="Center"/>
    </DockPanel>
    <Border DockPanel.Dock="Bottom" Height="461" Background="#0B0B10">
      <Grid x:Name="cardHost"/>
    </Border>
    <ScrollViewer VerticalScrollBarVisibility="Auto">
      <StackPanel x:Name="form" Margin="12"/>
    </ScrollViewer>
  </DockPanel>
</Window>
"@
$win = [Windows.Markup.XamlReader]::Parse($xaml)
$icoPath = Join-Path $PSScriptRoot 'favicon.ico'
if (Test-Path $icoPath) { $win.Icon = [Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri $icoPath)) }
$script:form = $win.FindName('form'); $script:cardHost = $win.FindName('cardHost'); $script:status = $win.FindName('status')

# --- Debounced full rebuild of the bottom card from the current model ---
$script:rebuildTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:rebuildTimer.Interval = [TimeSpan]::FromMilliseconds(150)
$script:rebuildTimer.Add_Tick({ $script:rebuildTimer.Stop(); Invoke-Rebuild })
function Request-Rebuild { $script:rebuildTimer.Stop(); $script:rebuildTimer.Start() }

# Total rebuild: build a fresh card from the model, steal its inner Grid, host it. Plain
# (script-scoped) so it and its dot-sourced callees stay visible; refs kept at script scope
# for the grid's Loaded handler (which runs after this returns).
function Invoke-Rebuild {
  # Stop the outgoing card's looping mascot frame-timers before discarding it; otherwise each
  # edit leaves a flipbook ticking on the shared Dispatcher and after a few switches they pile
  # up and visibly jank the live mascot. (Scene/rim animations are WPF clocks tied to the
  # detached grid, so they stop on their own once it's GC'd.)
  if ($script:box) { Stop-CardAnimations $script:box }
  $script:cardHost.Children.Clear()
  $themeName = [string](Get-ModelValue $script:model @('activeTheme'))
  if (-not $themeName -or $themeName -eq 'random' -or -not ($script:themeNames -contains $themeName)) { $themeName = $script:selectedTheme }
  $script:theme = Resolve-Theme $script:model $themeName
  $script:ev    = Resolve-Event $script:model $script:selectedEvent
  $bodyLines = @(Resolve-BodyLines $script:ev.body $script:ctx)
  $footer    = @(Resolve-Footer $script:ev.footer $script:ctx)
  $wa = New-Object System.Drawing.Rectangle 0, 0, 1920, 1080
  $script:box = New-NotificationBox -Event $script:selectedEvent -Theme $script:theme -Ev $script:ev -BodyLines $bodyLines -Footer $footer -WorkArea $wa
  $grid = $script:box.Win.Content; $script:box.Win.Content = $null   # steal the inner card Grid
  $grid.Opacity = 1                                                  # the unshown source Window starts at 0
  $grid.Tag = $script:box                                            # bind the grid to its own box
  # Run card setup + choreography once the stolen Grid lays out in its new host. Plain
  # scriptblock (script scope) so the dot-sourced Initialize-/Start- functions stay visible; the
  # box comes from the grid's .Tag (not $script:box, which a later rebuild may have replaced),
  # and Started makes it one-shot so a second Loaded can't stack a duplicate choreography.
  $grid.Add_Loaded({
    $b = $this.Tag
    if ($b.Started) { return }
    $b.Started = $true
    Initialize-NotificationCard $b
    Start-CardChoreography $b $b.Theme $b.Ev
  })
  $script:cardHost.Children.Add($grid) | Out-Null
}

# --- Per-control handlers: plain (script scope); per-control state via .Tag, never closures ---
$onCheck = { $f = $this.Tag; Set-ModelValue $script:model $f.path ([bool]$this.IsChecked); Request-Rebuild }
$onCombo = { $f = $this.Tag; Set-ModelValue $script:model $f.path ([string]$this.SelectedItem); Request-Rebuild }
# Preview a theme sound: play the combo's selected wav (a blank selection is a no-op).
$onPlaySound = {
  $sel = [string]$this.Tag.combo.SelectedItem
  if ($sel) { try { (New-Object System.Media.SoundPlayer (Join-Path $script:soundsDir $sel)).Play() } catch {} }
}
$onText  = { $f = $this.Tag; Set-ModelValue $script:model $f.path (ConvertTo-ModelValue $f.kind $this.Text); Request-Rebuild }
# WPF has no built-in colour picker; reuse the WinForms ColorDialog (already loaded). The
# button's .Tag is its hex TextBox: writing .Text fires TextChanged -> model update + rebuild.
$onPick = {
  $tb = $this.Tag
  $dlg = New-Object System.Windows.Forms.ColorDialog
  $dlg.FullOpen = $true
  if ($tb.Text -match '^#([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})$') {
    $dlg.Color = [System.Drawing.Color]::FromArgb([Convert]::ToInt32($matches[1], 16), [Convert]::ToInt32($matches[2], 16), [Convert]::ToInt32($matches[3], 16))
  }
  if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $hex = '#{0:X2}{1:X2}{2:X2}' -f $dlg.Color.R, $dlg.Color.G, $dlg.Color.B
    $tb.Text = $hex
    $this.Background = New-Brush $hex
  }
}
# The event + theme dropdowns are reactive: they change which fields exist (event group /
# theme group), so changing either re-derives the field list and rebuilds the whole form.
# Picking a concrete theme also makes it the active theme. The other handlers only mutate a
# value and re-render the preview.
$onEvent = { $script:selectedEvent = [string]$this.SelectedItem; Build-Form; Request-Rebuild }
$onTheme = {
  $sel = [string]$this.SelectedItem
  Set-ModelValue $script:model @('activeTheme') $sel
  if ($sel -ne 'random' -and ($script:themeNames -contains $sel)) { $script:selectedTheme = $sel }
  Build-Form; Request-Rebuild
}
# Hero is edited by three textboxes (emoji + two colour swatches) sharing a context via
# .Tag; any edit reassembles the whole value (bare string when no colours, else
# { emoji, colors }).
$onHero = {
  $h = $this.Tag
  Set-ModelValue $script:model $h.path (Build-HeroValue $h.emoji.Text @($h.col1.Text, $h.col2.Text))
  Request-Rebuild
}
# Preset writes a full curated hero value, then rebuilds the form so the emoji/colour
# controls re-seed from it (a plain rebuild would leave their text stale).
$onPreset = {
  $t = $this.Tag
  $p = $t.presets | Where-Object { $_.label -eq [string]$this.SelectedItem } | Select-Object -First 1
  if ($p) { Set-ModelValue $script:model $t.path (Build-HeroValue $p.emoji $p.colors); Build-Form; Request-Rebuild }
}
# Emoji picker: a button toggles a popup of emoji buttons; picking one writes the target
# textbox's .Text (firing its TextChanged -> model update) and closes the popup.
$onEmojiToggle = { $this.Tag.IsOpen = -not $this.Tag.IsOpen }
$onEmojiPick   = { $t = $this.Tag; $t.tb.Text = [string]$this.Content; $t.pop.IsOpen = $false }
# Greyed placeholder hint that hides as soon as the textbox has text. Finds its sibling
# in the wrapping Grid so it needs no .Tag (the textbox's .Tag is its field descriptor).
$onPlaceholderText = {
  foreach ($c in $this.Parent.Children) {
    if ($c -is [System.Windows.Controls.TextBlock]) { $c.Visibility = if ($this.Text) { 'Collapsed' } else { 'Visible' } }
  }
}
# Curated emoji offered by the picker: theme heroes plus common celebration glyphs. Code
# points, not literals — see Get-Emoji (a .ps1 without a BOM is read as ANSI under Windows
# PowerShell 5.1, which mangles raw emoji bytes).
$script:emojiSet = @(
  0x1F984, 0x1F680, 0x1F433, 0x1F338, 0x1F48A, 0x1F407, 0x1F409, 0x1F334, 0x1F916,
  0x1F383, 0x1F47B, 0x1F480, 0x1F389, 0x1F386, 0x2728, 0x26A1, 0x1F525, 0x2705,
  0x2B50, 0x1F4A5, 0x1F3C6, 0x1F308
) | ForEach-Object { Get-Emoji $_ }

function Add-Row($labelText, $control) {
  $row = New-Object System.Windows.Controls.DockPanel
  $row.Margin = New-Object System.Windows.Thickness 0, 0, 0, 6
  $lbl = New-Object System.Windows.Controls.TextBlock
  $lbl.Text = $labelText; $lbl.Width = 130; $lbl.Foreground = (New-Brush '#D1D5DB'); $lbl.VerticalAlignment = 'Center'
  [System.Windows.Controls.DockPanel]::SetDock($lbl, 'Left')
  $row.Children.Add($lbl) | Out-Null
  $row.Children.Add($control) | Out-Null
  $script:form.Children.Add($row) | Out-Null
}

# A half of a 50/50 paired row: a narrow label docked left, the control filling the rest.
function New-PairHalf($labelText, $control) {
  $dock = New-Object System.Windows.Controls.DockPanel
  $lbl = New-Object System.Windows.Controls.TextBlock
  $lbl.Text = $labelText; $lbl.Width = 78; $lbl.Foreground = (New-Brush '#D1D5DB'); $lbl.VerticalAlignment = 'Center'
  [System.Windows.Controls.DockPanel]::SetDock($lbl, 'Left')
  $dock.Children.Add($lbl) | Out-Null
  $dock.Children.Add($control) | Out-Null
  $dock
}

# Two labelled controls side by side, each in a 50%-width column.
function Add-PairRow($lbl1, $ctrl1, $lbl2, $ctrl2) {
  $grid = New-Object System.Windows.Controls.Grid
  $grid.Margin = New-Object System.Windows.Thickness 0, 0, 0, 6
  foreach ($i in 0, 1) {
    $cd = New-Object System.Windows.Controls.ColumnDefinition
    $cd.Width = New-Object System.Windows.GridLength 1, ([System.Windows.GridUnitType]::Star)
    $grid.ColumnDefinitions.Add($cd)
  }
  $h1 = New-PairHalf $lbl1 $ctrl1; $h1.Margin = New-Object System.Windows.Thickness 0, 0, 6, 0
  $h2 = New-PairHalf $lbl2 $ctrl2; $h2.Margin = New-Object System.Windows.Thickness 6, 0, 0, 0
  [System.Windows.Controls.Grid]::SetColumn($h1, 0); [System.Windows.Controls.Grid]::SetColumn($h2, 1)
  $grid.Children.Add($h1) | Out-Null; $grid.Children.Add($h2) | Out-Null
  $script:form.Children.Add($grid) | Out-Null
}

# A section divider: a centred bold title flanked by hairlines.
function Add-Separator($title) {
  $grid = New-Object System.Windows.Controls.Grid
  $grid.Margin = New-Object System.Windows.Thickness 0, 16, 0, 8
  foreach ($w in 'Star', 'Auto', 'Star') {
    $cd = New-Object System.Windows.Controls.ColumnDefinition
    $cd.Width = if ($w -eq 'Auto') { [System.Windows.GridLength]::Auto } else { New-Object System.Windows.GridLength 1, ([System.Windows.GridUnitType]::Star) }
    $grid.ColumnDefinitions.Add($cd)
  }
  foreach ($col in 0, 2) {
    $line = New-Object System.Windows.Controls.Border
    $line.Height = 1; $line.Background = New-Brush '#3A3A44'; $line.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($line, $col); $grid.Children.Add($line) | Out-Null
  }
  $txt = New-Object System.Windows.Controls.TextBlock
  $txt.Text = $title; $txt.Foreground = New-Brush '#9CA3AF'; $txt.FontWeight = 'Bold'
  $txt.Margin = New-Object System.Windows.Thickness 10, 0, 10, 0
  [System.Windows.Controls.Grid]::SetColumn($txt, 1); $grid.Children.Add($txt) | Out-Null
  $script:form.Children.Add($grid) | Out-Null
}

# A hex TextBox + a square swatch button that opens the colour dialog. The textbox keeps
# whatever TextChanged handler it was given (generic field value, or the hero assembler).
function New-SwatchControl($tb) {
  $tb.HorizontalAlignment = 'Stretch'; $tb.VerticalAlignment = 'Center'
  $pick = New-Object System.Windows.Controls.Button
  $pick.Content = ([char]0x25A2); $pick.Width = 28; $pick.Margin = New-Object System.Windows.Thickness 6, 0, 0, 0
  if ($tb.Text -match '^#[0-9A-Fa-f]{6}$') { $pick.Background = New-Brush $tb.Text }
  $pick.Tag = $tb; $pick.Add_Click($onPick)
  $dock = New-Object System.Windows.Controls.DockPanel
  [System.Windows.Controls.DockPanel]::SetDock($pick, 'Right')
  $dock.Children.Add($pick) | Out-Null
  $dock.Children.Add($tb) | Out-Null
  $dock
}

# An emoji-picker button + its popup grid, bound to write $targetTb. Returned as a
# zero-footprint Grid so the popup lives in the visual tree without taking layout space.
function New-EmojiPicker($targetTb) {
  $btn = New-Object System.Windows.Controls.Button
  $btn.Content = (Get-Emoji 0x1F600); $btn.Width = 30; $btn.Margin = New-Object System.Windows.Thickness 6, 0, 0, 0
  $pop = New-Object System.Windows.Controls.Primitives.Popup
  $pop.PlacementTarget = $btn; $pop.Placement = 'Bottom'; $pop.StaysOpen = $false
  $border = New-Object System.Windows.Controls.Border
  $border.Background = New-Brush '#1F1F27'; $border.BorderBrush = New-Brush '#3A3A44'
  $border.BorderThickness = New-Object System.Windows.Thickness 1; $border.Padding = New-Object System.Windows.Thickness 4
  $wrap = New-Object System.Windows.Controls.WrapPanel; $wrap.Width = 232
  foreach ($em in $script:emojiSet) {
    $eb = New-Object System.Windows.Controls.Button
    $eb.Content = $em; $eb.FontFamily = 'Segoe UI Emoji'; $eb.FontSize = 18
    $eb.Width = 34; $eb.Height = 34; $eb.Margin = New-Object System.Windows.Thickness 2
    $eb.Tag = @{ tb = $targetTb; pop = $pop }; $eb.Add_Click($onEmojiPick)
    $wrap.Children.Add($eb) | Out-Null
  }
  $border.Child = $wrap; $pop.Child = $border
  $btn.Tag = $pop; $btn.Add_Click($onEmojiToggle)
  $container = New-Object System.Windows.Controls.Grid
  $container.Children.Add($btn) | Out-Null; $container.Children.Add($pop) | Out-Null
  $container
}

# A fill element + an emoji-picker button (writing $targetTb) docked to its right.
function New-EmojiField($fillElement, $targetTb) {
  $picker = New-EmojiPicker $targetTb
  $dock = New-Object System.Windows.Controls.DockPanel
  [System.Windows.Controls.DockPanel]::SetDock($picker, 'Right')
  $dock.Children.Add($picker) | Out-Null
  $dock.Children.Add($fillElement) | Out-Null
  $dock
}

# Overlay a greyed hint over an (otherwise stretched) textbox, shown only while empty.
function New-PlaceholderBox($tb, $hint) {
  $tb.HorizontalAlignment = 'Stretch'; $tb.VerticalAlignment = 'Center'
  $tb.Add_TextChanged($onPlaceholderText)
  $grid = New-Object System.Windows.Controls.Grid
  $grid.Children.Add($tb) | Out-Null
  $ph = New-Object System.Windows.Controls.TextBlock
  $ph.Text = $hint; $ph.Foreground = New-Brush '#6B7280'; $ph.IsHitTestVisible = $false
  $ph.VerticalAlignment = 'Center'; $ph.Margin = New-Object System.Windows.Thickness 5, 0, 0, 0
  $ph.Visibility = if ($tb.Text) { 'Collapsed' } else { 'Visible' }
  $grid.Children.Add($ph) | Out-Null
  $grid
}

# Build (but don't place) the wired control for a field descriptor. Returns a stretchable
# element so it fits both full-width and 50/50 rows.
function New-FieldControl($f) {
  switch ($f.kind) {
    'checkbox' {
      $c = New-Object System.Windows.Controls.CheckBox
      $c.IsChecked = [bool](Get-ModelValue $script:model $f.path); $c.VerticalAlignment = 'Center'
      $c.Tag = $f; $c.Add_Click($onCheck); return $c
    }
    'dropdown' {
      $c = New-Object System.Windows.Controls.ComboBox
      foreach ($o in $f.options) { $c.Items.Add([string]$o) | Out-Null }
      $c.SelectedItem = [string](Get-ModelValue $script:model $f.path)
      $c.HorizontalAlignment = 'Stretch'; $c.VerticalAlignment = 'Center'
      $c.Tag = $f; $c.Add_SelectionChanged($onCombo); return $c
    }
    'sound' {
      $c = New-Object System.Windows.Controls.ComboBox
      foreach ($o in $f.options) { $c.Items.Add([string]$o) | Out-Null }
      $c.SelectedItem = [string](Get-ModelValue $script:model $f.path)
      $c.HorizontalAlignment = 'Stretch'; $c.VerticalAlignment = 'Center'
      $c.Tag = $f; $c.Add_SelectionChanged($onCombo)
      $play = New-Object System.Windows.Controls.Button
      $play.Content = ([char]0x25B6); $play.Width = 28; $play.Margin = New-Object System.Windows.Thickness 6, 0, 0, 0
      $play.Tag = @{ combo = $c }; $play.Add_Click($onPlaySound)
      $dock = New-Object System.Windows.Controls.DockPanel
      [System.Windows.Controls.DockPanel]::SetDock($play, 'Right')
      $dock.Children.Add($play) | Out-Null; $dock.Children.Add($c) | Out-Null
      return $dock
    }
    default {   # 'text' and 'number'; hex-colour text fields also get a swatch picker
      $c = New-Object System.Windows.Controls.TextBox
      $c.Text = [string](Get-ModelValue $script:model $f.path); $c.VerticalAlignment = 'Center'
      $c.Tag = $f; $c.Add_TextChanged($onText)
      if ($f.kind -eq 'text' -and $c.Text -match '^#[0-9A-Fa-f]{6}$') { return (New-SwatchControl $c) }
      $c.HorizontalAlignment = 'Stretch'; return $c
    }
  }
}
function Add-FieldRow($f) { Add-Row $f.label (New-FieldControl $f) }

# A reactive selector ComboBox: seed SelectedItem BEFORE attaching the handler so seeding
# can't fire a spurious rebuild.
function New-SelectorCombo($options, $selected, $handler) {
  $c = New-Object System.Windows.Controls.ComboBox
  foreach ($o in $options) { $c.Items.Add([string]$o) | Out-Null }
  $c.SelectedItem = [string]$selected
  $c.HorizontalAlignment = 'Stretch'; $c.VerticalAlignment = 'Center'
  $c.Add_SelectionChanged($handler)
  $c
}

# A bare textbox wired to the generic value handler (for composite rows that wrap it).
function New-TextBox($f) {
  $c = New-Object System.Windows.Controls.TextBox
  $c.Text = [string](Get-ModelValue $script:model $f.path); $c.VerticalAlignment = 'Center'
  $c.Tag = $f; $c.Add_TextChanged($onText); $c
}

# (Re)populate the form. Called on startup and whenever the event/theme selection changes
# (which changes the field set). Layout: paired 50/50 rows, an emoji picker on the emoji
# fields, and a Theme separator splitting the event group from the theme group.
function Build-Form {
  $script:form.Children.Clear()
  $fields = Get-EditorFields $script:model $script:enums $script:selectedEvent $script:selectedTheme
  $find = { param($lbl) $fields | Where-Object { $_.label -eq $lbl } | Select-Object -First 1 }

  # --- Event section ---
  $evCombo = New-SelectorCombo @('done', 'needs-input') $script:selectedEvent $onEvent
  $evCombo.Width = 180; $evCombo.HorizontalAlignment = 'Left'
  Add-Row 'event' $evCombo
  Add-PairRow 'label'  (New-FieldControl (& $find 'label')) `
              'accent' (New-FieldControl (& $find 'accent'))
  $indTb = New-TextBox (& $find 'indicator')
  Add-Row 'indicator' (New-EmojiField (New-PlaceholderBox $indTb 'fireworks  or an emoji') $indTb)
  Add-PairRow 'mascot.move' (New-FieldControl (& $find 'mascot.move')) `
              'mascot.end'  (New-FieldControl (& $find 'mascot.end'))
  Add-Row 'sound' (New-FieldControl (& $find 'sound'))

  # --- Theme section ---
  Add-Separator 'Theme'
  $thCombo = New-SelectorCombo (& $find 'activeTheme').options (Get-ModelValue $script:model @('activeTheme')) $onTheme

  $heroPath = @('themes', $script:selectedTheme, 'hero')
  $hp = Get-HeroParts (Get-ModelValue $script:model $heroPath)
  $heroCtx = @{ path = $heroPath }
  $tbEmoji = New-Object System.Windows.Controls.TextBox; $tbEmoji.Text = [string]$hp.emoji; $tbEmoji.HorizontalAlignment = 'Stretch'; $tbEmoji.VerticalAlignment = 'Center'
  $tbC1 = New-Object System.Windows.Controls.TextBox; $tbC1.Text = [string]($hp.colors[0]); $tbC1.VerticalAlignment = 'Center'
  $tbC2 = New-Object System.Windows.Controls.TextBox; $tbC2.Text = [string]($hp.colors[1]); $tbC2.VerticalAlignment = 'Center'
  $heroCtx.emoji = $tbEmoji; $heroCtx.col1 = $tbC1; $heroCtx.col2 = $tbC2
  foreach ($tb in $tbEmoji, $tbC1, $tbC2) { $tb.Tag = $heroCtx; $tb.Add_TextChanged($onHero) }

  Add-PairRow 'activeTheme' $thCombo 'hero' (New-EmojiField $tbEmoji $tbEmoji)

  $presets = @(Get-HeroPresets $script:selectedTheme)
  if ($presets.Count) {
    $pc = New-Object System.Windows.Controls.ComboBox
    foreach ($p in $presets) { $pc.Items.Add([string]$p.label) | Out-Null }
    $pc.HorizontalAlignment = 'Left'; $pc.Width = 200
    $pc.Tag = @{ path = $heroPath; presets = $presets }
    $pc.Add_SelectionChanged($onPreset)
    Add-Row 'preset' $pc
  }

  Add-PairRow 'hero color1' (New-SwatchControl $tbC1) `
              'hero color2' (New-SwatchControl $tbC2)
  Add-Row 'card' (New-FieldControl (& $find 'card'))
  Add-Row 'sound done'  (New-FieldControl (& $find 'sound.done'))
  Add-Row 'sound input' (New-FieldControl (& $find 'sound.needs-input'))
  foreach ($f in $fields | Where-Object { $_.label -like 'scene.*' }) { Add-FieldRow $f }
}
Build-Form

$win.FindName('save').Add_Click({
  Set-Content -Path $SettingsPath -Value (ConvertTo-SettingsJson $script:model) -Encoding UTF8
  $script:status.Text = "Saved $([DateTime]::Now.ToString('HH:mm:ss'))"
})
$win.FindName('reload').Add_Click({
  $script:model = Read-SettingsModel $SettingsPath
  $script:themeNames = @((Get-ModelValue $script:model @('themes')).Keys)
  $a = [string](Get-ModelValue $script:model @('activeTheme'))
  $script:selectedTheme = if ($a -and $a -ne 'random' -and ($script:themeNames -contains $a)) { $a } else { $script:themeNames[0] }
  Build-Form
  $script:status.Text = "Reloaded $([DateTime]::Now.ToString('HH:mm:ss'))"; Request-Rebuild
})

# --- Headless self-test: one synchronous rebuild + confirm the card functions are loaded ---
if ($SelfTest) {
  Invoke-Rebuild
  foreach ($fn in 'Initialize-NotificationCard', 'Start-CardChoreography', 'New-NotificationBox') {
    if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) { Write-Error "missing $fn"; exit 1 }
  }
  if ($null -eq $script:box -or $null -eq $script:box.Card) { Write-Error 'rebuild produced no card'; exit 1 }
  if ($null -eq $win.Icon) { Write-Error 'window icon not set'; exit 1 }
  Write-Output 'selftest ok'; Write-Output 'icon ok'; return
}

$win.Add_Loaded({ Request-Rebuild })
$win.ShowDialog() | Out-Null
