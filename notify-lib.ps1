# Pure helpers for show-notification.ps1. No WPF — dot-sourceable and unit-testable.

# Read a property from either a hashtable or a (JSON-derived) PSCustomObject.
function Get-Prop($obj, [string]$name) {
  if ($null -eq $obj) { return $null }
  if ($obj -is [hashtable] -or $obj -is [System.Collections.IDictionary]) { return $obj[$name] }
  $p = $obj.PSObject.Properties[$name]
  if ($p) { return $p.Value } else { return $null }
}

# First argument that is neither $null nor an empty string.
function Coalesce {
  foreach ($v in $args) { if ($null -ne $v -and "$v" -ne '') { return $v } }
  return $null
}

# Built-in fallback config — identical to the pre-config hardcoded look.
function Get-NotifyDefaults {
  @{
    activeTheme = 'unicorn'
    events = @{
      'needs-input' = @{ label='Needs you'; accent='#FF7A18'; indicator='👋'; mascot='flag'; sound='exclamation';
        body=@(@{ text='{{folder}}'; style='sub' }) }
      'done' = @{ label='Done!'; accent='#22C55E'; indicator='fireworks'; mascot='confetti'; sound='asterisk';
        body=@(@{ text='{{folder}}'; style='sub' }) }
    }
    themes = @{
      unicorn = @{
        hero='🦄'
        gradient=@('#FF5F6D 0','#FFC371 0.28','#3CFFB0 0.5','#36D1DC 0.72','#A56BFF 1')
        rim=@('#7C3AED 0','#2563EB 0.17','#06B6D4 0.34','#22C55E 0.5','#EAB308 0.67','#F97316 0.84','#EC4899 1')
        card='#18181B'
        palette=@('#FF5F6D','#FFC371','#FFD93D','#3CFFB0','#36D1DC','#A56BFF','#EC4899')
      }
    }
  }
}
