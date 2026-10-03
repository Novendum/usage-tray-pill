$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Start-UsageTrayPill.ps1') -LibraryOnly
function Check([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
$now=[DateTimeOffset]::UtcNow
$previous=[pscustomobject]@{source='claude-code-control';available=$true;lastSuccessAt=$now.AddMinutes(-3).ToString('o');lastCheckedAt=$now.AddMinutes(-3).ToString('o');items=@(
    [pscustomobject]@{key='five_hour';label='5h';remainingPercent=67.5;resetsAt=$now.AddMinutes(1).ToString('o')},
    [pscustomobject]@{key='seven_day';label='weekly';remainingPercent=48;resetsAt=$now.AddDays(1).ToString('o')}
)}
$empty=ConvertFrom-UtpClaudeControlUsageJson '{"session":{"total_cost_usd":0,"model_usage":{}},"rate_limits_available":true,"rate_limits":null,"behaviors":null}'
Check ($empty.errorCode -eq 'quota_fetch_unavailable') 'An eligible account with no fetched quotas is temporarily unavailable, not an unsupported schema.'
Check ((Get-ProviderPollSeconds claude) -eq 180) 'Claude healthy reads should use a conservative three-minute interval.'
Check ((Get-ProviderRetrySeconds $empty.errorCode 1) -eq 300) 'A temporary quota fetch failure must wait at least five minutes.'
Check ((Get-ProviderRetrySeconds $empty.errorCode 20) -eq 900) 'Temporary quota retry delay must remain bounded.'
$cached=Merge-UtpClaudeUsageSnapshot $empty $previous $now
Check ($cached.available -and $cached.stale -and $cached.items[0].remainingPercent -eq 67.5) 'Retain the last known verified quotas after a temporary fetch failure.'
Check ($cached.lastSuccessAt -eq $previous.lastSuccessAt) 'A failed fetch must never refresh the observation timestamp.'
$partial=Merge-UtpClaudeUsageSnapshot $empty $cached ($now.AddMinutes(2))
Check ($null -eq $partial.items[0].remainingPercent -and $partial.items[1].remainingPercent -eq 48) 'Each cached window must expire at its own reset time.'
$expired=Merge-UtpClaudeUsageSnapshot $empty $cached ($now.AddMinutes(8))
Check (-not $expired.available -and @($expired.items).Count -eq 0) 'Failed attempts must not extend cached values beyond ten minutes.'
foreach($code in @('auth_required','unsupported_auth_context','setup_required','unexpected_model_activity','unexpected_transcript_activity')){
    $failure=New-UtpExternalUsageFailure 'claude-code-control' $code 'Synthetic failure'
    Check (-not (Merge-UtpClaudeUsageSnapshot $failure $previous $now).available) 'Identity, setup and safety errors must clear cached values.'
}
$recovered=[pscustomobject]@{source='claude-code-control';available=$true;lastCheckedAt=$now.ToString('o');lastSuccessAt=$now.ToString('o');items=$previous.items;lastError='';errorCode=''}
Check (-not (Merge-UtpClaudeUsageSnapshot $recovered $cached $now).stale) 'A successful read must remove the cache indication.'
$root=Join-Path $env:TEMP ('UtpClaudeCache-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root|Out-Null
try {
    $script:DataDir=$root
    $script:ClaudeControlUsagePath=Join-Path $root 'claude-control-usage.json'
    $script:State=New-DefaultState
    $script:State.settings.claudeControlEnabled=$true
    $cached|ConvertTo-Json -Depth 8|Set-Content $script:ClaudeControlUsagePath
    $display=Get-ClaudeUsageSnapshot
    Check ($display.stale -and $display.fiveHourRemainingPercent -eq 67.5) 'The UI must accept explicitly cached values without hiding them on lastError.'
    $pill=Get-TaskbarBadgeData claude
    Check ($pill.Cached -and $pill.Items[-1].Label -eq 'cache' -and $pill.StatusText -like 'Cached *') 'Cached values need a visible pill marker and an observation time in the overview.'
    # Run the actual writer with a fixture: a retained snapshot must not signal success to the scheduler.
    function Get-UtpClaudeControlUsage { return $empty }
    Check (-not (Update-ClaudeControlUsage)) 'A retained snapshot must preserve retry backoff instead of looking like a successful fetch.'
    $saved=Get-Content $script:ClaudeControlUsagePath -Raw|ConvertFrom-Json
    Check ($saved.lastSuccessAt -eq $previous.lastSuccessAt) 'The on-disk observation time must survive a retry.'
    $saved.lastSuccessAt=$now.AddMinutes(-11).ToString('o')
    $saved|ConvertTo-Json -Depth 8|Set-Content $script:ClaudeControlUsagePath
    $pill=Get-TaskbarBadgeData claude
    Check (-not $pill.Cached -and $pill.PrimaryText -eq '--' -and $pill.SecondaryText -eq '--') 'The renderer must drop cached values after their lifetime even without another cache write.'
    Write-Output 'Claude temporary-fetch and truthful-cache tests OK'
} finally {
    $resolved=[IO.Path]::GetFullPath($root)
    if($resolved.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'UtpClaudeCache-*'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
