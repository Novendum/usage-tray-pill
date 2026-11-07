$sourceRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
$ErrorActionPreference = 'Stop'
. (Join-Path $sourceRoot 'Start-UsageTrayPill.ps1') -LibraryOnly
function Check { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }

# Asking Windows for every process's command line takes about half a second with many processes,
# and it runs on the UI thread: refreshes must not do it, and the keeper may not repeat it while off.
$script:State = New-DefaultState
$script:CodeChecks = 0
$script:KeeperChecks = 0
$realCodeCheck = ${function:Test-ClaudeCodeRunning}
function Test-ClaudeCodeRunning { $script:CodeChecks++; return $false }
function Test-ClaudeKeeperRunning { $script:KeeperChecks++; return $false }
function Test-CodexRunning { return $false }
[void](Get-StatusSnapshot)
Check ($script:CodeChecks -eq 0 -and $script:KeeperChecks -eq 0) 'A refresh must not search the process list for Claude'
$menu = Get-StatusSnapshot -IncludeClaudeProcesses
Check ($script:CodeChecks -eq 1 -and $script:KeeperChecks -eq 0 -and $menu.ClaudeCodeRunning -eq $false) 'Only the tray menu may ask whether Claude Code runs'

# Claude Code is recognised from the fast process list, never from a WMI query.
Set-Item Function:Test-ClaudeCodeRunning -Value $realCodeCheck
function Get-CimInstance { throw 'WMI process query' }
Check (-not (Test-ClaudeCodeRunning)) 'Claude Code detection must not use WMI'

# With the keeper off, leftover keepers are searched once, again only after it was on.
$script:Stops = 0
$script:Starts = 0
function Stop-ClaudeUsageKeeper { $script:Stops++ }
function Start-ClaudeUsageKeeper { $script:Starts++; return $true }
$script:ClaudeKeeperStopChecked = $false
1..3 | ForEach-Object { Ensure-ClaudeUsageKeeper }
Check ($script:Stops -eq 1) 'With the keeper off the process search must run once'
$script:State.settings.keepClaudeCodeAlive = $true
Ensure-ClaudeUsageKeeper
$script:State.settings.keepClaudeCodeAlive = $false
1..2 | ForEach-Object { Ensure-ClaudeUsageKeeper }
Check ($script:Starts -eq 1 -and $script:Stops -eq 2) 'Switching the keeper off must search once more'

# Callers that just refreshed the tray tell the overview to skip it.
$source = Get-Content -LiteralPath (Join-Path $sourceRoot 'Start-UsageTrayPill.ps1') -Raw
Check ($source -match '(?s)\$timer\.Add_Tick\(\{\s*Refresh-Tray\s*if \(\$null -ne \$script:RefreshMainWindow\) \{\s*& \$script:RefreshMainWindow -SkipTray') 'The minute timer must not refresh the tray twice'
Check ($source -match '(?s)Sync-CodexUsageSnapshot\s*Refresh-Tray\s*if \(\$null -ne \$script:RefreshMainWindow\) \{ & \$script:RefreshMainWindow -SkipTray \}') 'A cache change must not refresh the tray twice'
Write-Output 'Responsiveness tests OK (no process scan per refresh, keeper search once while off, single tray refresh)'
