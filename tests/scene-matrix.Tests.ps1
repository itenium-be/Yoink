. "$PSScriptRoot\..\lib\scene-matrix.ps1"

$script:fail = 0
function Assert-Eq($got, $exp, $msg) {
  if ("$got" -ne "$exp") { Write-Host "FAIL: $msg`n  exp=[$exp]`n  got=[$got]"; $script:fail++ }
  else { Write-Host "ok: $msg" }
}
function Assert-True($cond, $msg) { Assert-Eq ([bool]$cond) $true $msg }

# --- Get-MatrixGlyphs: each named set is non-empty and themed correctly ---
Assert-True ((Get-MatrixGlyphs 'digits') -eq '0123456789') "digits set is the ten digits"
Assert-True ((Get-MatrixGlyphs 'latin').Contains('A'))     "latin set contains A"
Assert-True ((Get-MatrixGlyphs 'katakana').Length -gt 0)   "katakana set is non-empty"
Assert-True ((Get-MatrixGlyphs 'mixed').Length -gt 0)      "mixed set is non-empty"

# Unknown / empty falls back to katakana (the iconic default), never empty.
Assert-Eq (Get-MatrixGlyphs 'nope') (Get-MatrixGlyphs 'katakana') "unknown style falls back to katakana"
Assert-Eq (Get-MatrixGlyphs '')     (Get-MatrixGlyphs 'katakana') "empty style falls back to katakana"

# --- Get-MatrixColumnCount: how many glyph columns fit the card width ---
Assert-Eq (Get-MatrixColumnCount 160 16) 10 "160/16 -> 10 columns"
Assert-Eq (Get-MatrixColumnCount 159 16) 9  "rounds down (no partial column)"
# A zero/negative cell width must not divide-by-zero; coerce + yield at least one.
Assert-True ((Get-MatrixColumnCount 100 0) -ge 1) "cellW<=0 still yields >=1 column"
Assert-True ((Get-MatrixColumnCount 1 16) -ge 1)  "tiny width still yields >=1 column"

if ($script:fail -gt 0) { exit 1 } else { Write-Host "ALL PASS" }
