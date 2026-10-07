$sourceRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$source = Join-Path $sourceRoot 'BadgeVisibility.cs'
if (-not (Test-Path -LiteralPath $source)) { throw 'Badge visibility detector is missing.' }
Add-Type -Path $source -ReferencedAssemblies System.Drawing
function Check { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw $Message } }
function Sample { param([string]$Kind,[Drawing.Rectangle]$Bounds) New-Object UtpTaskbarSample ([UtpTaskbarHit]::$Kind),$Bounds }
$monitor = New-Object Drawing.Rectangle 0,0,3440,1440
$taskbar = New-Object Drawing.Rectangle 0,1392,3440,48
$full = Sample Application $monitor
$shell = Sample Taskbar $taskbar
$desktop = Sample Desktop $monitor
$own = Sample OwnWindow (New-Object Drawing.Rectangle 2911,1402,265,28)
$unknown = Sample Unknown ([Drawing.Rectangle]::Empty)
$small = Sample Application (New-Object Drawing.Rectangle 500,300,600,400)
$other = Sample Application (New-Object Drawing.Rectangle 3440,0,1920,1080)
function Classify { param([object[]]$Samples,[bool]$AutoHide=$false,[Drawing.Rectangle]$Bar=$taskbar) [UtpBadgeVisibility]::Classify($monitor,$Bar,$AutoHide,[UtpTaskbarSample[]]$Samples) }
Check ((Classify @($full,$full)) -eq $true) 'A proven fullscreen occluder over the primary taskbar must hide the pill'
Check ((Classify @($full,$shell)) -eq $false) 'An exposed taskbar must win over fullscreen geometry'
Check ((Classify @($desktop,$desktop)) -eq $false) 'The desktop must never be mistaken for a fullscreen application'
Check ((Classify @($own,$shell)) -eq $false) 'Our own window must not hide the pill'
Check ((Classify @($other,$other)) -eq $false) 'Fullscreen on another monitor must not hide the primary pill'
Check ((Classify @($small,$small)) -eq $false) 'Ordinary windows must not count as fullscreen'
Check ((Classify @($small,$full)) -eq $true) 'A small modal at one probe must not obscure fullscreen evidence at the other'
Check ($null -eq (Classify @($unknown,$full))) 'Incomplete ownership evidence must remain unknown'
Check ($null -eq (Classify @())) 'Missing taskbar observations must remain unknown'
Check ((Classify @($unknown,$shell)) -eq $false) 'Known taskbar exposure is enough to show the pill'
$collapsed = New-Object Drawing.Rectangle 0,1438,3440,48
Check ((Classify @($shell,$shell) $true $collapsed) -eq $true) 'An auto-hidden two-pixel strip is not an exposed taskbar'
Check ((Classify @($shell,$shell) $true $taskbar) -eq $false) 'A revealed auto-hide taskbar must show the pill'
$verticalStrip = New-Object Drawing.Rectangle -46,0,48,1440
Check ((Classify @($shell,$shell) $true $verticalStrip) -eq $true) 'A collapsed vertical taskbar must also remain hidden'
Check ($null -eq (Classify @($full,$full) $false ([Drawing.Rectangle]::Empty))) 'Invalid geometry must remain unknown'
$gap = Sample Application (New-Object Drawing.Rectangle 0,0,3437,1440)
Check ((Classify @($gap,$gap)) -eq $false) 'A gap larger than two pixels must not count as fullscreen'
$gate = New-Object UtpBadgeVisibility
Check (-not $gate.Update($true)) 'One hide candidate must not hide the pill'
Check ($gate.Update($true)) 'Two consecutive hide candidates must hide the pill'
Check ($gate.Update($false)) 'One show candidate must not flash the pill'
Check (-not $gate.Update($false)) 'Two consecutive show candidates must restore the pill'
[void]$gate.Update($true)
Check (-not $gate.Update($null)) 'Unknown observations must preserve current visibility'
Check (-not $gate.Update($true)) 'Unknown observations must break consecutive agreement'
Check ($gate.Update($true)) 'Stable readings after uncertainty must still converge'
Check ($gate.Update($null)) 'An unknown sample must not make a hidden pill appear'
Check ($gate.Update((Classify @($gap,$gap)))) 'One boundary fluctuation must not reveal the pill'
Check ($gate.Update((Classify @($full,$full)))) 'Returning fullscreen evidence must cancel that fluctuation'
1..100 | ForEach-Object { Check ($gate.Update($true)) 'Stable hidden samples must remain hidden' }
$gate.Reset($false)
Check (-not $gate.Hidden) 'Disabling fullscreen hiding must reset the gate to visible'
Write-Output 'Taskbar ownership, desktop, monitor, auto-hide and debounce tests OK'
