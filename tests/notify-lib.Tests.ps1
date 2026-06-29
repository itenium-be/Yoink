. "$PSScriptRoot\..\notify-lib.ps1"

$script:fail = 0
function Assert-Eq($got, $exp, $msg) {
  if ("$got" -ne "$exp") { Write-Host "FAIL: $msg`n  exp=[$exp]`n  got=[$got]"; $script:fail++ }
  else { Write-Host "ok: $msg" }
}

# --- Get-Prop ---
$h = @{ a = 1 }
$o = [pscustomobject]@{ a = 2 }
Assert-Eq (Get-Prop $h 'a') 1 "Get-Prop hashtable"
Assert-Eq (Get-Prop $o 'a') 2 "Get-Prop pscustomobject"
Assert-Eq (Get-Prop $null 'a') '' "Get-Prop null -> empty"
Assert-Eq (Get-Prop $h 'missing') '' "Get-Prop missing -> empty"

# --- Coalesce ---
Assert-Eq (Coalesce '' $null 'x') 'x' "Coalesce skips empty/null"
Assert-Eq (Coalesce 'a' 'b') 'a' "Coalesce first non-empty"
Assert-Eq (Coalesce '' $null) '' "Coalesce all-empty -> null"

# --- Defaults ---
$d = Get-NotifyDefaults
Assert-Eq $d.activeTheme 'unicorn' "defaults activeTheme"
Assert-Eq $d.themes.unicorn.hero '🦄' "defaults unicorn hero"
Assert-Eq $d.events['needs-input'].body[0].text '{{folder}}' "defaults needs-input body is folder"

# --- New-GradientStops ---
Assert-Eq (New-GradientStops @('#FF0000 0','#00FF00 1')) `
  "<GradientStop Color=`"#FF0000`" Offset=`"0`"/>`n<GradientStop Color=`"#00FF00`" Offset=`"1`"/>" `
  "gradient stops -> xaml"
Assert-Eq (New-GradientStops @('bad','#0000FF 0.5')) `
  "<GradientStop Color=`"#0000FF`" Offset=`"0.5`"/>" `
  "gradient skips unparseable stop"
Assert-Eq (New-GradientStops @('#123456')) '' "stop without offset skipped"

# --- Get-NotifyConfig / resolution (uses repo settings.json one dir up) ---
$cfg = Get-NotifyConfig (Join-Path $PSScriptRoot '..')
Assert-Eq (Resolve-ThemeName $cfg) 'unicorn' "active theme name from settings.json"

$theme = Resolve-Theme $cfg 'ocean'
Assert-Eq $theme.hero '🐳' "resolve named theme hero"
$missing = Resolve-Theme $cfg 'nope'
Assert-Eq $missing.hero '🦄' "unknown theme -> unicorn default"

$ev = Resolve-Event $cfg 'needs-input'
Assert-Eq $ev.label 'Needs you' "resolve event label"
Assert-Eq $ev.indicator '👋' "resolve event indicator"
Assert-Eq $ev.body[1].text '{{folder}} · {{branch}}' "resolve event body line"

# Missing file -> defaults (today's look)
$dcfg = Get-NotifyConfig 'C:\does\not\exist'
Assert-Eq (Resolve-Theme $dcfg 'unicorn').card '#18181B' "missing config -> default theme"
Assert-Eq (Resolve-Event $dcfg 'done').body[0].text '{{folder}}' "missing config -> default body"

# random resolves to one of the configured names
$names = $cfg.themes.PSObject.Properties.Name
$r = Resolve-ThemeName ([pscustomobject]@{ activeTheme='random'; themes=$cfg.themes })
Assert-Eq ($names -contains $r) 'True' "random theme name is a configured theme"

# --- Resolve-BodyLines ---
$ctx = @{ folder='notify'; branch=''; message='Needs permission'; agents=''; last_prompt='fix flag' }

$body = @(
  @{ text='{{message}}';             style='headline' },
  @{ text='{{folder}} · {{branch}}';  style='sub' },
  @{ text='{{agents}} agents running'; style='muted' },
  @{ text='{{last_prompt}}';          style='weird' }
)
$lines = @(Resolve-BodyLines $body $ctx)
Assert-Eq $lines.Count 3 "all-empty 'agents' line dropped"
Assert-Eq $lines[0].text 'Needs permission' "headline resolved"
Assert-Eq $lines[0].style 'headline' "headline style kept"
Assert-Eq $lines[1].text 'notify' "empty branch -> dangling separator trimmed"
Assert-Eq $lines[2].text 'fix flag' "muted line resolved"
Assert-Eq $lines[2].style 'sub' "unknown style normalised to sub"

# both tokens empty -> whole line dropped
$lines2 = @(Resolve-BodyLines @(@{ text='{{folder}} · {{branch}}'; style='sub' }) @{ folder=''; branch='' })
Assert-Eq $lines2.Count 0 "line with all-empty tokens dropped"

# pure literal always kept
$lines3 = @(Resolve-BodyLines @(@{ text='hello'; style='sub' }) @{})
Assert-Eq $lines3.Count 1 "pure literal kept"
Assert-Eq $lines3[0].text 'hello' "pure literal text"

if ($script:fail -gt 0) { exit 1 } else { Write-Host "ALL PASS" }
