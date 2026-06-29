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

# --- New-HeroStops: plain colours -> hard-banded stops (no per-stop offsets) ---
Assert-Eq (New-HeroStops @('white')) `
  "<GradientStop Color=`"white`" Offset=`"0`"/>`n<GradientStop Color=`"white`" Offset=`"1`"/>" `
  "single hero colour -> solid (0..1)"
Assert-Eq (New-HeroStops @('#EF4444', '#3B82F6')) `
  "<GradientStop Color=`"#EF4444`" Offset=`"0`"/>`n<GradientStop Color=`"#EF4444`" Offset=`"0.5`"/>`n<GradientStop Color=`"#3B82F6`" Offset=`"0.5`"/>`n<GradientStop Color=`"#3B82F6`" Offset=`"1`"/>" `
  "two hero colours -> hard 50/50 split (red/blue pill)"
Assert-Eq (New-HeroStops @('#12', 'white')) `
  "<GradientStop Color=`"white`" Offset=`"0`"/>`n<GradientStop Color=`"white`" Offset=`"1`"/>" `
  "hero skips invalid colour token"

# --- Remove-JsonComments: JSONC support (// line + /* block */), string-aware ---
$jc = "{`n  // pick one`n  `"a`": 1,`n  `"b`": 2 /* inline */`n}"
Assert-Eq ((Remove-JsonComments $jc | ConvertFrom-Json).a) 1 "line + block comments stripped (a)"
Assert-Eq ((Remove-JsonComments $jc | ConvertFrom-Json).b) 2 "line + block comments stripped (b)"
# A // inside a string (e.g. a URL) must survive untouched.
Assert-Eq ((Remove-JsonComments '{ "u": "http://x//y" }' | ConvertFrom-Json).u) 'http://x//y' "// inside string preserved"
# An escaped quote must not prematurely end the string scan.
Assert-Eq ((Remove-JsonComments '{ "u": "a\"// b" }' | ConvertFrom-Json).u) 'a"// b' "escaped quote keeps string open"

# --- Resolution (inline fixture). The SHIPPED settings.json is validated structurally
# by tests/settings.Tests.sh; resolving against a fixture keeps these green no matter
# how a user edits their own settings.json. ---
$cfg = [pscustomobject]@{
  activeTheme = 'unicorn'
  themes = [pscustomobject]@{
    unicorn = [pscustomobject]@{ hero = '🦄'; gradient = @('#FF5F6D 0', '#A56BFF 1'); rim = @('#7C3AED 0', '#EC4899 1'); card = '#18181B' }
    ocean   = [pscustomobject]@{ hero = '🐳'; gradient = @('#0EA5E9 0', '#0891B2 1'); rim = @('#0C4A6E 0', '#14B8A6 1'); card = '#0A1620'; scene = [pscustomobject]@{ kind = 'waves' } }
    pill    = [pscustomobject]@{ hero = [pscustomobject]@{ emoji = '💊'; colors = @('#EF4444', '#3B82F6') }; gradient = @('#000000 0', '#111111 1'); rim = @('#000000 0', '#111111 1'); card = '#050505' }
    bunny   = [pscustomobject]@{ hero = [pscustomobject]@{ emoji = '🐇'; color = 'white' }; gradient = @('#000000 0', '#111111 1'); rim = @('#000000 0', '#111111 1'); card = '#050505' }
  }
  events = [pscustomobject]@{
    'needs-input' = [pscustomobject]@{
      label = 'Needs you'; accent = '#FF7A18'; indicator = '👋'; mascot = 'flag'; sound = 'exclamation'
      body = @(
        [pscustomobject]@{ text = '{{message}}'; style = 'headline' },
        [pscustomobject]@{ text = '{{folder}} · {{branch}}'; style = 'sub' },
        [pscustomobject]@{ text = '{{last_prompt}}'; style = 'muted' }
      )
    }
  }
}
Assert-Eq (Resolve-ThemeName $cfg) 'unicorn' "active theme name from config"

$theme = Resolve-Theme $cfg 'ocean'
Assert-Eq $theme.hero '🐳' "resolve named theme hero"
$missing = Resolve-Theme $cfg 'nope'
Assert-Eq $missing.hero '🦄' "unknown theme -> unicorn default"

# Object-form hero: emoji + fill colours (split for the pill, single for the bunny);
# string-form heroes carry no heroColors (watermark falls back to the theme gradient).
$pill = Resolve-Theme $cfg 'pill'
Assert-Eq $pill.hero '💊' "object hero -> emoji"
Assert-Eq ($pill.heroColors -join ',') '#EF4444,#3B82F6' "object hero -> colours array"
$bunny = Resolve-Theme $cfg 'bunny'
Assert-Eq $bunny.hero '🐇' "object hero (single colour) -> emoji"
Assert-Eq ($bunny.heroColors -join ',') 'white' "single colour -> one-element heroColors"
Assert-Eq ([string]$theme.heroColors) '' "string hero -> no heroColors"

Assert-Eq (Resolve-Theme $cfg 'ocean').scene.kind 'waves' "resolve theme scene passthrough"
Assert-Eq ([string](Resolve-Theme $cfg 'unicorn').scene) '' "theme without scene -> null/empty"
Assert-Eq ([string](Resolve-Theme $cfg 'nope').scene) '' "unknown theme -> no scene"

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

# --- Get-StopColors ---
$cols = @(Get-StopColors @('#FF0000 0','#00FF00 0.5','#0000FF 1'))
Assert-Eq $cols.Count 3 "stop colors count"
Assert-Eq $cols[0] '#FF0000' "first stop color"
Assert-Eq $cols[2] '#0000FF' "last stop color"
Assert-Eq (@(Get-StopColors @('bad','#123456 0.4')).Count) 1 "unparseable stop skipped"

# --- indicator: explicit "" is honored (no badge); a MISSING key falls back to default ---
$cfgEmptyInd = [pscustomobject]@{ events = [pscustomobject]@{ 'needs-input' = [pscustomobject]@{ indicator = '' } } }
Assert-Eq (Resolve-Event $cfgEmptyInd 'needs-input').indicator '' "explicit empty indicator honored"
$cfgNoInd = [pscustomobject]@{ events = [pscustomobject]@{ 'needs-input' = [pscustomobject]@{ label = 'X' } } }
Assert-Eq (Resolve-Event $cfgNoInd 'needs-input').indicator '👋' "missing indicator falls back to default"

# --- sound: explicit "" is honored (silent); a MISSING key falls back to default ---
$cfgEmptySnd = [pscustomobject]@{ events = [pscustomobject]@{ 'done' = [pscustomobject]@{ sound = '' } } }
Assert-Eq (Resolve-Event $cfgEmptySnd 'done').sound '' "explicit empty sound honored"
$cfgNoSnd = [pscustomobject]@{ events = [pscustomobject]@{ 'done' = [pscustomobject]@{ label = 'Y' } } }
Assert-Eq (Resolve-Event $cfgNoSnd 'done').sound 'asterisk' "missing sound falls back to default"

# --- mascot: move/end resolve, each field falling back to the event default ---
Assert-Eq (Resolve-Event $cfg 'done').mascot.move 'walk' "resolve mascot move"
Assert-Eq (Resolve-Event $cfg 'done').mascot.end 'confetti' "resolve mascot end (done)"
$cfgPartialMascot = [pscustomobject]@{ events = [pscustomobject]@{ 'needs-input' = [pscustomobject]@{ mascot = [pscustomobject]@{ move = 'jump' } } } }
Assert-Eq (Resolve-Event $cfgPartialMascot 'needs-input').mascot.move 'jump' "explicit move honored"
Assert-Eq (Resolve-Event $cfgPartialMascot 'needs-input').mascot.end 'flag' "missing end falls back to default (needs-input)"

# --- Resolve-Footer: token expand, drop all-empty, pass through color/background ---
$fctx = @{ branch='main'; agents='2' }
$badges = @(Resolve-Footer @(
  @{ badge='{{branch}}'; color='#FFFFFF'; background='' },
  @{ badge='{{agents}} 🤖'; color=''; background='' }
) $fctx)
Assert-Eq $badges.Count 2 "both badges resolved"
Assert-Eq $badges[0].text 'main' "branch badge text"
Assert-Eq $badges[0].color '#FFFFFF' "badge color passed through"
Assert-Eq $badges[1].text '2 🤖' "agents badge text"
# agents empty -> the {{agents}} 🤖 badge drops (all its tokens empty)
$badges2 = @(Resolve-Footer @(@{ badge='{{agents}} 🤖' }) @{ agents='' })
Assert-Eq $badges2.Count 0 "badge with all-empty tokens dropped"

if ($script:fail -gt 0) { exit 1 } else { Write-Host "ALL PASS" }
