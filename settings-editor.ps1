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
. (Join-Path $PSScriptRoot 'lib\scene-dragon.ps1')
. (Join-Path $PSScriptRoot 'lib\card-choreography.ps1')

$script:ctx = Get-SampleContext

# --- Shell window: scrollable controls on top, card host on the bottom ---
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="claude-notify settings" Width="680" Height="900" Background="#15151A">
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

# Build one labelled control for a field descriptor, using the generic value handlers.
function Add-FieldRow($f) {
  switch ($f.kind) {
    'checkbox' {
      $c = New-Object System.Windows.Controls.CheckBox
      $c.IsChecked = [bool](Get-ModelValue $script:model $f.path); $c.VerticalAlignment = 'Center'
      $c.Tag = $f; $c.Add_Click($onCheck)
      Add-Row $f.label $c
    }
    'dropdown' {
      $c = New-Object System.Windows.Controls.ComboBox
      foreach ($o in $f.options) { $c.Items.Add([string]$o) | Out-Null }
      $c.SelectedItem = [string](Get-ModelValue $script:model $f.path)
      $c.Tag = $f; $c.Add_SelectionChanged($onCombo)
      Add-Row $f.label $c
    }
    default {   # 'text' and 'number'; hex-colour text fields also get a swatch picker
      $c = New-Object System.Windows.Controls.TextBox
      $c.Text = [string](Get-ModelValue $script:model $f.path); $c.HorizontalAlignment = 'Left'
      $c.Tag = $f; $c.Add_TextChanged($onText)
      if ($f.kind -eq 'text' -and $c.Text -match '^#[0-9A-Fa-f]{6}$') {
        $c.Width = 100
        $pick = New-Object System.Windows.Controls.Button
        $pick.Content = 'Pick'; $pick.Width = 56; $pick.Margin = New-Object System.Windows.Thickness 6, 0, 0, 0
        $pick.Background = New-Brush $c.Text; $pick.Tag = $c; $pick.Add_Click($onPick)
        $wrap = New-Object System.Windows.Controls.StackPanel; $wrap.Orientation = 'Horizontal'
        $wrap.Children.Add($c) | Out-Null; $wrap.Children.Add($pick) | Out-Null
        Add-Row $f.label $wrap
      } else {
        $c.Width = 360
        Add-Row $f.label $c
      }
    }
  }
}

# A reactive dropdown: seed SelectedItem BEFORE attaching the handler so seeding can't fire
# a spurious rebuild.
function Add-SelectorRow($labelText, $options, $selected, $handler) {
  $c = New-Object System.Windows.Controls.ComboBox
  foreach ($o in $options) { $c.Items.Add([string]$o) | Out-Null }
  $c.SelectedItem = [string]$selected
  $c.Add_SelectionChanged($handler)
  Add-Row $labelText $c
}

# (Re)populate the form: event selector + event group, then theme selector + theme group.
# Called on startup and whenever the event/theme selection changes (which changes the fields).
function Build-Form {
  $script:form.Children.Clear()
  $fields = Get-EditorFields $script:model $script:enums $script:selectedEvent $script:selectedTheme
  Add-SelectorRow 'event' @('done', 'needs-input') $script:selectedEvent $onEvent
  foreach ($f in $fields | Where-Object { $_.path[0] -eq 'events' }) { Add-FieldRow $f }
  $themeField = $fields | Where-Object { ($_.path -join '.') -eq 'activeTheme' } | Select-Object -First 1
  if ($themeField) { Add-SelectorRow $themeField.label $themeField.options (Get-ModelValue $script:model @('activeTheme')) $onTheme }
  foreach ($f in $fields | Where-Object { $_.path[0] -eq 'themes' }) { Add-FieldRow $f }
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
  Write-Output 'selftest ok'; return
}

$win.Add_Loaded({ Request-Rebuild })
$win.ShowDialog() | Out-Null
