$sourceRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
$ErrorActionPreference='Stop'
. (Join-Path $sourceRoot 'Start-UsageTrayPill.ps1') -LibraryOnly
$root=Join-Path $env:TEMP ('UtpRefreshRecovery-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root)
$script:DataDir=$root
$script:CodexUsagePath=Join-Path $root 'codex-usage.json'
$script:ClaudeControlUsagePath=Join-Path $root 'claude-control-usage.json'
$script:State=New-DefaultState
$script:State.settings.claudeControlEnabled=$true
$script:Failures=@()
function Check([bool]$Value,[string]$Message){if(-not $Value){$script:Failures+=$Message}}
function Refresh-Tray {}
function Start-UsageCollection {}
try {
    $snapshot=[pscustomobject]@{source='claude-code-control';available=$true;stale=$false;lastCheckedAt=[DateTimeOffset]::UtcNow.ToString('o');lastSuccessAt=[DateTimeOffset]::UtcNow.ToString('o');lastError='';errorCode='';items=@([pscustomobject]@{key='five_hour';label='5h';remainingPercent=81;resetsAt=[DateTimeOffset]::UtcNow.AddHours(2).ToString('o')})}
    $snapshot|ConvertTo-Json -Depth 8|Set-Content $script:ClaudeControlUsagePath
    $script:CollectorProcess=$null
    $script:ProviderRefreshes=@{claude=[pscustomobject]@{StartedAt=(Get-Date).AddSeconds(-46);CacheVersion=Get-ProviderCacheVersion claude};codex=[pscustomobject]@{StartedAt=Get-Date;CacheVersion=Get-ProviderCacheVersion codex}}
    Update-ProviderRefreshProcessState
    Check ($script:ProviderRefreshes.ContainsKey('codex')) 'A Claude timeout must not cancel a pending Codex refresh'
    Check (-not $script:ProviderRefreshes.ContainsKey('claude')) 'The timed-out request must stop showing progress'
    $saved=Get-Content $script:ClaudeControlUsagePath -Raw|ConvertFrom-Json
    Check ($saved.available -and $saved.stale -and $saved.items[0].remainingPercent -eq 81) 'A UI timeout must preserve and label eligible Claude cache'
    Check ($saved.lastSuccessAt -eq $snapshot.lastSuccessAt) 'A UI timeout must preserve the observation time'
    Check ((Get-TaskbarBadgeData claude).Cached) 'The pill must visibly mark the retained quota as cached'
    @{source='codex-app-server';lastCheckedAt=(Get-Date).ToString('o');lastError='';buckets=@()}|ConvertTo-Json|Set-Content $script:CodexUsagePath
    Update-ProviderRefreshProcessState
    Check (-not $script:ProviderRefreshes.ContainsKey('codex')) 'The independent Codex refresh must still complete normally'

    $script:State.settings.keepClaudeCodeAlive=$true
    $script:KeeperCalls=0
    function Test-ClaudeCodeRunning {return $false}
    function Test-ClaudeKeeperRunning {$script:KeeperCalls++;return $true}
    function Test-ClaudeKeeperCooldownActive {throw 'Existing keeper was not checked'}
    $keeperResult=$false
    try {$keeperResult=Start-ClaudeUsageKeeper} catch {}
    Check ($keeperResult -and $script:KeeperCalls -eq 1) 'An existing keeper must prevent another helper launch'
    if($script:Failures.Count){throw ($script:Failures -join '; ')}
    Write-Output 'Independent refresh, Claude timeout cache and keeper recovery tests OK'
} finally {
    $resolved=[IO.Path]::GetFullPath($root)
    if($resolved.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'UtpRefreshRecovery-*'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
