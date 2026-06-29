. "$PSScriptRoot\..\lib\settings-model.ps1"

$script:fail = 0
function Assert-Eq($got, $exp, $msg) {
  if ("$got" -ne "$exp") { Write-Host "FAIL: $msg`n  exp=[$exp]`n  got=[$got]"; $script:fail++ }
  else { Write-Host "ok: $msg" }
}

# --- ConvertTo-HashtableDeep ---
$o = [pscustomobject]@{ a = 1; b = [pscustomobject]@{ c = 2 }; d = @(1,2) }
$h = ConvertTo-HashtableDeep $o
Assert-Eq ($h -is [System.Collections.IDictionary]) 'True' "deep convert -> dictionary"
Assert-Eq $h['b']['c'] 2 "deep convert nested"
Assert-Eq $h['d'].Count 2 "deep convert array"

# --- Get/Set-ModelValue ---
$m = [ordered]@{ events = [ordered]@{ done = [ordered]@{ label = 'Done!' } } }
Assert-Eq (Get-ModelValue $m @('events','done','label')) 'Done!' "get nested"
Assert-Eq (Get-ModelValue $m @('events','nope','label')) '' "get missing -> null"
Set-ModelValue $m @('events','done','label') 'Hi'
Assert-Eq (Get-ModelValue $m @('events','done','label')) 'Hi' "set existing"
Set-ModelValue $m @('themes','sakura','card') '#000000'
Assert-Eq (Get-ModelValue $m @('themes','sakura','card')) '#000000' "set creates intermediate"

# --- ConvertTo-SettingsJson round-trips through ConvertFrom-Json ---
$json = ConvertTo-SettingsJson $m
$back = $json | ConvertFrom-Json
Assert-Eq $back.events.done.label 'Hi' "serialize round-trips label"
Assert-Eq $back.themes.sakura.card '#000000' "serialize round-trips new key"

# --- ConvertTo-ModelValue coercion ---
Assert-Eq (ConvertTo-ModelValue 'checkbox' $true) 'True' "checkbox -> bool"
Assert-Eq (ConvertTo-ModelValue 'number' '22') 22 "number int"
Assert-Eq (ConvertTo-ModelValue 'number' '1.5') 1.5 "number double"
Assert-Eq (ConvertTo-ModelValue 'text' 42) '42' "text -> string"

# --- number parse is locale-independent (nl-BE uses ',' as decimal separator) ---
$prev = [System.Threading.Thread]::CurrentThread.CurrentCulture
try {
  [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]'nl-BE'
  Assert-Eq (ConvertTo-ModelValue 'number' '1.5') 1.5 "number double under nl-BE culture"
} finally {
  [System.Threading.Thread]::CurrentThread.CurrentCulture = $prev
}

# --- Get-SchemaEnums (reads the real schema) ---
$enums = Get-SchemaEnums "$PSScriptRoot\..\settings.schema.json"
Assert-Eq ($enums['mascot.move'] -join ',') 'walk,jump' "schema mascot.move enum"
Assert-Eq ($enums['mascot.end'] -join ',')  'confetti,gym,flag' "schema mascot.end enum"
Assert-Eq ($enums['scene.glyphs'] -join ',') 'katakana,latin,digits,binary,mixed' "schema glyphs enum"
Assert-Eq ($enums['scene.bottom'] -join ',') 'lava,treasure,none' "schema bottom enum"
Assert-Eq ($enums['scene.base'] -join ',') 'circuit,none' "schema base enum"

# --- Get-EditorFields ---
$model = [ordered]@{
  activeTheme = 'sakura'
  events = [ordered]@{ done = [ordered]@{ label='Done!'; mascot=[ordered]@{ move='walk'; end='confetti' } } }
  themes = [ordered]@{
    sakura = [ordered]@{ hero='🌸'; card='#1A1620'; scene=[ordered]@{ kind='sakura'; petals=$true; count=22; glyphs='katakana' } }
    dragon = [ordered]@{ hero='🐉'; card='#1A0F0A'; scene=[ordered]@{ kind='dragon'; bottom='lava'; volcano=$false; embers=$true } }
  }
}
$fields = Get-EditorFields $model $enums 'done' 'sakura'
$byLabel = @{}; foreach ($f in $fields) { $byLabel[$f.label] = $f }
Assert-Eq ($byLabel['activeTheme'].options -join ',') 'sakura,dragon,random' "activeTheme options = themes + random"
Assert-Eq $byLabel['activeTheme'].kind 'dropdown' "activeTheme is dropdown"
Assert-Eq ($byLabel['label'].path -join '.') 'events.done.label' "event label path"
Assert-Eq ($byLabel['mascot.move'].path -join '.') 'events.done.mascot.move' "mascot.move path"
Assert-Eq $byLabel['mascot.move'].kind 'dropdown' "mascot.move dropdown"
Assert-Eq ($byLabel['hero'].path -join '.') 'themes.sakura.hero' "theme hero path"
Assert-Eq $byLabel['hero'].kind 'hero' "theme hero is hero kind"

$dfields = Get-EditorFields $model $enums 'done' 'dragon'
$dByLabel = @{}; foreach ($f in $dfields) { $dByLabel[$f.label] = $f }
Assert-Eq $dByLabel['scene.bottom'].kind 'dropdown' "scene enum string -> dropdown"
Assert-Eq ($dByLabel['scene.bottom'].options -join ',') 'lava,treasure,none' "scene.bottom options"
Assert-Eq $dByLabel['scene.volcano'].kind 'checkbox' "scene bool -> checkbox (volcano)"
Assert-Eq $byLabel['scene.petals'].kind 'checkbox' "scene bool -> checkbox"
Assert-Eq $byLabel['scene.count'].kind 'number' "scene number -> number"
Assert-Eq $byLabel['scene.glyphs'].kind 'dropdown' "scene glyphs -> dropdown"
Assert-Eq ($fields | Where-Object { $_.label -eq 'scene.kind' }).Count 0 "scene.kind not exposed"

# --- Hero parts: normalize string / {emoji,colors} / {emoji,color} ---
$uni = Get-Emoji 0x1F984; $pill = Get-Emoji 0x1F48A; $rab = Get-Emoji 0x1F407
$hpStr = Get-HeroParts $uni
Assert-Eq $hpStr.emoji $uni "hero string -> emoji"
Assert-Eq $hpStr.colors.Count 0 "hero string -> no colors"
$hpObj = Get-HeroParts ([ordered]@{ emoji=$pill; colors=@('#EF4444','#3B82F6') })
Assert-Eq $hpObj.emoji $pill "hero object -> emoji"
Assert-Eq ($hpObj.colors -join ',') '#EF4444,#3B82F6' "hero object colors"
$hpOne = Get-HeroParts ([ordered]@{ emoji=$rab; color='white' })
Assert-Eq ($hpOne.colors -join ',') 'white' "hero single color -> colors[1]"

# --- Build hero value: no colors -> bare string; colors -> object ---
Assert-Eq (Build-HeroValue $uni @()) $uni "build hero no colors -> string"
Assert-Eq (Build-HeroValue $uni @('','  ')) $uni "build hero blank colors -> string"
$bv = Build-HeroValue $pill @('#EF4444','#3B82F6')
Assert-Eq ($bv -is [System.Collections.IDictionary]) 'True' "build hero colors -> object"
Assert-Eq $bv.emoji $pill "build hero object emoji"
Assert-Eq ($bv.colors -join ',') '#EF4444,#3B82F6' "build hero object colors"

# --- Hero presets: curated per theme; unknown -> empty ---
$mp = Get-HeroPresets 'matrix'
Assert-Eq ($mp.label -join ',') 'rabbit,pill' "matrix presets"
Assert-Eq (($mp | Where-Object label -eq 'pill').colors -join ',') '#EF4444,#3B82F6' "pill preset colors"
Assert-Eq (Get-HeroPresets 'unicorn').Count 0 "no presets -> empty"

# --- Sample context resolves body/footer non-empty ---
$ctx = Get-SampleContext
$lines = @(Resolve-BodyLines @(@{ text='{{folder}}'; style='sub' }) $ctx)
Assert-Eq $lines.Count 1 "sample context resolves folder line"
Assert-Eq $lines[0].text 'my-project' "sample folder value"

if ($script:fail -gt 0) { exit 1 } else { Write-Host "ALL PASS" }
