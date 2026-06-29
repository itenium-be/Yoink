# Mascot + scene choreography for an already-laid-out card. $box is the bag from
# New-NotificationBox (or a card hosted elsewhere). $Root is the repo root (for mascot art).
# Requires the mascot-*, scene-* libs to be dot-sourced by the caller.
function Start-CardChoreography($box, $theme, $ev, [string]$Root) {
  # Normalized frames share one canvas; the creature sits at a fixed anchor inside it
  # (torso-centre x, feet-baseline y). One display height drives every phase.
  $anchor = Get-Content (Join-Path $Root 'mascots\anchor.json') -Raw | ConvertFrom-Json
  $box.MascotH = 243.0
  $box.DisplayScale = $box.MascotH / $anchor.canvasH   # on-screen px per canvas px (shared by all clips)

  # Per-clip canvas geometry. Core clips share the main anchor; spare clips (gym,
  # horizontal-jump) each carry their own anchor.json so a wide pose isn't clipped.
  $core = @{ W = $anchor.canvasW; H = $anchor.canvasH; AX = [double]$anchor.anchorX; AY = [double]$anchor.anchorY }
  $box.Geom = @{ looking = $core; jump = $core; walking = $core; confetti = $core; flag = $core }
  foreach ($e in 'gym', 'horizontal-jump') {
    $ea = Get-Content (Join-Path $Root "mascots\$e\anchor.json") -Raw | ConvertFrom-Json
    $box.Geom[$e] = @{ W = $ea.canvasW; H = $ea.canvasH; AX = [double]$ea.anchorX; AY = [double]$ea.anchorY }
  }

  # --- Mascot choreography: look around -> jump onto the top edge -> move -> celebrate ---
  # The look + jump onto the edge are always played; only the move and end are configurable.
  $box.Move = $ev.mascot.move   # walk | jump (horizontal hop)
  $box.End  = $ev.mascot.end    # confetti | gym | flag
  Start-JumpPrep $box {
    Start-Jump $box {
      $celebrate = {
        if     ($box.End -eq 'gym')  { Start-Gym $box }
        elseif ($box.End -eq 'flag') { Start-FlagWave $box }
        else                         { Start-Confetti $box }
      }
      if ($box.Move -eq 'jump') { Start-HJump $box $celebrate } else { Start-Walk $box $celebrate }
    }
  }

  # --- Scenery: resolve the scene config and dispatch by kind. ---
  $sceneCfg = $null
  if ($theme.scene -and (Get-Prop $theme.scene 'kind')) {
    $sceneCols = @(Get-Prop $theme.scene 'colors')
    if (-not $sceneCols -or $sceneCols.Count -eq 0) { $sceneCols = @(Get-StopColors $theme.gradient) }
    $sceneCfg = @{
      kind    = [string](Get-Prop $theme.scene 'kind')
      colors  = $sceneCols
      opacity = (Coalesce (Get-Prop $theme.scene 'opacity') 0.22)
      speed   = (Coalesce (Get-Prop $theme.scene 'speed')   1.0)
      sky          = [bool](Get-Prop $theme.scene 'sky')
      sun          = [bool](Get-Prop $theme.scene 'sun')
      clouds       = [bool](Get-Prop $theme.scene 'clouds')
      stars        = [bool](Get-Prop $theme.scene 'stars')
      nebula       = [bool](Get-Prop $theme.scene 'nebula')
      comets       = [bool](Get-Prop $theme.scene 'comets')
      streaks      = [bool](Get-Prop $theme.scene 'streaks')
      density      = (Coalesce (Get-Prop $theme.scene 'density') 0.85)
      glyphs       = [string](Coalesce (Get-Prop $theme.scene 'glyphs') 'katakana')
      petals       = [bool](Coalesce (Get-Prop $theme.scene 'petals') $true)
      count        = [int](Coalesce (Get-Prop $theme.scene 'count') 22)
      bloom        = [bool](Get-Prop $theme.scene 'bloom')
      branch       = [bool](Get-Prop $theme.scene 'branch')
      parallax     = [bool](Get-Prop $theme.scene 'parallax')
      aurora       = [bool](Get-Prop $theme.scene 'aurora')
      rainbow      = [bool](Get-Prop $theme.scene 'rainbow')
      glitter      = [bool](Get-Prop $theme.scene 'glitter')
      sparkles     = [bool](Get-Prop $theme.scene 'sparkles')
      shootingStar = [bool](Get-Prop $theme.scene 'shootingStar')
    }
  }
  $sceneKinds = @{
    waves   = { param($b, $c) Start-Waves $b $c }
    space   = { param($b, $c) Start-Space $b $c }
    matrix  = { param($b, $c) Start-Matrix $b $c }
    sakura  = { param($b, $c) Start-Sakura $b $c }
    unicorn = { param($b, $c) Start-Unicorn $b $c }
  }
  if ($sceneCfg) {
    $fn = $sceneKinds[$sceneCfg.kind]
    if ($fn) { try { & $fn $box $sceneCfg } catch { Write-Warning "scene '$($sceneCfg.kind)' failed: $_" } }
  }
}
