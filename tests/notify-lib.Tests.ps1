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

if ($script:fail -gt 0) { exit 1 } else { Write-Host "ALL PASS" }
