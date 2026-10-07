$sourceRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Test-ProcessHelpers.ps1')
$repo=$sourceRoot
$root=Join-Path $env:TEMP ('UtpProviderRecovery-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root)
$failures=@()
function Check([bool]$Value,[string]$Message){if(-not $Value){$script:failures+=$Message;Write-Output "FAIL: $Message"}}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'Start-UsageTrayPill.ps1'),[ref]$tokens,[ref]$errors)
foreach($node in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($node.Extent.Text))}
. (Join-Path $repo 'OpenCodeGo.ps1')
. (Join-Path $repo 'QwenTokenPlan.ps1')
. (Join-Path $repo 'CollectorPolicy.ps1')
$oldGo=$env:OPENCODE_GO_API_KEY;$oldQwen=$env:QWEN_TOKEN_PLAN_COOKIE
$env:OPENCODE_GO_API_KEY='';$env:QWEN_TOKEN_PLAN_COOKIE=''
$script:DataDir=$root
$script:OpenCodeGoCredentialPath=Join-Path $root 'go-key.json'
$script:QwenCredentialPath=Join-Path $root 'qwen-key.json'
$script:OpenCodeGoUsagePath=Join-Path $root 'go-usage.json'
$script:QwenUsagePath=Join-Path $root 'qwen-usage.json'
$process=$null
try {
    foreach($provider in @('OpenCodeGo','Qwen')){
        if($provider -eq 'OpenCodeGo'){Save-OpenCodeGoCredentials 'synthetic-account-A'}else{Save-QwenCredentials 'login_fixture=accountA'}
        $usage=[pscustomobject]@{available=$true;stale=$false;lastSuccessAt=(Get-Date).ToString('o');items=@([pscustomobject]@{key='five_hour';remainingPercent=87;resetsAt=(Get-Date).AddHours(2).ToString('o')})}
        & "Write-${provider}UsageSnapshot" $usage
        if($provider -eq 'OpenCodeGo'){Save-OpenCodeGoCredentials 'synthetic-account-B'}else{Save-QwenCredentials 'login_fixture=accountB'}
        $changed=& "Get-${provider}UsageSnapshot"
        Check ($null -eq $changed -or -not $changed.available) "$provider must hide previous-account quotas immediately after replacing credentials"
        & "Set-${provider}FailureSnapshot" -Code network_error -Message 'Synthetic failure'
        $changed=& "Get-${provider}UsageSnapshot"
        Check (-not $changed.available) "$provider must not retain previous-account quotas after a failed new-account request"
        $usage.PSObject.Properties.Remove('credentialRevision')
        & "Write-${provider}UsageSnapshot" $usage
        Check ((& "Get-${provider}UsageSnapshot").available) "$provider must retain a snapshot bound to the current credentials"
        if($provider -eq 'OpenCodeGo'){$env:OPENCODE_GO_API_KEY='synthetic-env-account-C'}else{$env:QWEN_TOKEN_PLAN_COOKIE='login_fixture=accountC'}
        $changed=& "Get-${provider}UsageSnapshot"
        Check ($null -eq $changed -or -not $changed.available) "$provider must hide quotas when effective environment credentials change"
        $env:OPENCODE_GO_API_KEY='';$env:QWEN_TOKEN_PLAN_COOKIE=''
    }
    # Simulate a credential replacement between the preservation check and cache write.
    $revisionFunction=${function:Get-UtpCredentialRevision}
    try {
        foreach($provider in @('OpenCodeGo','Qwen')){
            $script:revisionReads=0
            function Get-UtpCredentialRevision {param($Source) $script:revisionReads++;if($script:revisionReads -eq 1){'account-A'}else{'account-B'}}
            $cache=if($provider -eq 'OpenCodeGo'){$script:OpenCodeGoUsagePath}else{$script:QwenUsagePath}
            @{credentialRevision='account-A';lastSuccessAt=(Get-Date).ToString('o');items=@(@{remainingPercent=87})}|ConvertTo-Json -Depth 5|Set-Content $cache
            & "Set-${provider}FailureSnapshot" -Code network_error -Message 'Synthetic interrupted refresh'
            $saved=Get-Content $cache -Raw|ConvertFrom-Json
            Check ($saved.credentialRevision -eq 'account-A') "$provider must not stamp preserved account-A quotas with concurrently changed account-B credentials"
        }
    } finally {${function:Get-UtpCredentialRevision}=$revisionFunction}
    foreach($provider in @('opencodego','qwen')){
        $credentialPath=if($provider -eq 'opencodego'){$script:OpenCodeGoCredentialPath}else{$script:QwenCredentialPath}
        $beforeLock=Get-UtpCredentialRevision $provider
        $locked=[IO.File]::Open($credentialPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try{
            $blockedRevision=$null;$escaped=$false
            try{$blockedRevision=Get-UtpCredentialRevision $provider}catch{$escaped=$true}
            Check (-not $escaped -and $blockedRevision -eq 'unreadable') "$provider credential locks must return a stable unavailable revision without throwing out of a worker"
            Check ($blockedRevision -ne $beforeLock) "$provider must not trust old cache while the credential is unreadable"
        } finally {$locked.Dispose()}
        Check ((Get-UtpCredentialRevision $provider) -eq $beforeLock) "$provider must recover its original revision after the credential lock is released"
    }

    $statusRoot=Join-Path $root 'statusline';[void](New-Item -ItemType Directory $statusRoot)
    @{lastCheckedAt=(Get-Date).AddDays(-2).ToString('o');modelName='';version='';fiveHourRemainingPercent=87;fiveHourResetsAt=(Get-Date).AddDays(-1).ToString('o');sevenDayRemainingPercent=$null;limits=@(@{key='five_hour';remainingPercent=87;observedAt=(Get-Date).AddDays(-2).ToString('o');resetsAt=(Get-Date).AddDays(-1).ToString('o')})}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $statusRoot 'claude-usage.json')
    $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $output='{"model":{"display_name":"fixture"}}'|& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'Update-ClaudeUsageFromStatusline.ps1') -DataDir $statusRoot
    Check ($output -notmatch '87%') 'Claude statusline must not display expired cache when current input has no quotas'
    $scheduleTest=Join-Path $root 'malformed-schedule.json'
    $hardPause=[pscustomobject]@{errorCode='auth_expired';lastCheckedAt=(Get-Date).ToString('o');credentialRevision='old-key'}
    $migrated=Read-UtpCollectorSchedule -Path $scheduleTest -CredentialRevision 'new-key' -Snapshot $hardPause
    Check ($migrated.Next -le (Get-Date)) 'A legacy snapshot from another credential must not pause the new account'
    @{nextAttemptAt=(Get-Date).AddMinutes(-1).ToString('o');failures=0;credentialRevision='old-key'}|ConvertTo-Json|Set-Content $scheduleTest
    $interrupted=Read-UtpCollectorSchedule -Path $scheduleTest -CredentialRevision 'old-key' -Snapshot $hardPause
    Check ($interrupted.Next -eq [datetime]::MaxValue) 'A newer hard-failure snapshot must preserve the pause if shutdown interrupted schedule persistence'
    foreach($invalid in @('{','{"nextAttemptAt":"invalid","failures":1,"credentialRevision":"same"}')){
        Set-Content $scheduleTest $invalid
        $contained=$null
        try{$contained=Read-UtpCollectorSchedule -Path $scheduleTest -CredentialRevision 'same' -Snapshot $hardPause}catch{}
        Check ($null -ne $contained -and $contained.Next -gt (Get-Date)) 'Corrupt schedule must stay paused per source without terminating the collector'
    }

    # Actual collector and policy, isolated from all installed providers.
    $fixture=Join-Path $root 'collector';[void](New-Item -ItemType Directory $fixture)
    foreach($file in @('Start-UsageCollector.ps1','CollectorPolicy.ps1','OpenCodeGo.ps1','QwenTokenPlan.ps1','RequestDeadline.cs')){Copy-Item (Join-Path $repo $file) (Join-Path $fixture $file)}
    @'
function Load-State { [pscustomobject]@{settings=[pscustomobject]@{qwenTokenPlanEnabled=$true}} }
function Ensure-DataDirectory {}
function Close-CodexConnection {}
function Get-ProviderCachePath {param($Source) Join-Path $script:DataDir 'qwen-token-plan-usage.json'}
function Get-DateOrNull {param($Value) if($Value){[datetime]::Parse($Value)}}
function Set-ProviderRefreshFailure {throw 'Unexpected fixture failure'}
'@|Set-Content (Join-Path $fixture 'Start-UsageTrayPill.ps1')
    @'
function Update-QwenUsage {
 Add-Content (Join-Path $script:DataDir 'attempts.txt') 'fixture'
 $scenario=Get-Content (Join-Path $script:DataDir 'scenario.json') -Raw|ConvertFrom-Json
 Write-OpenCodeGoJsonAtomically -Path $script:QwenUsagePath -Value ([pscustomobject]@{lastCheckedAt=(Get-Date).ToString('o');errorCode=$scenario.errorCode;retryAfterSeconds=$scenario.retryAfterSeconds;available=$false;items=@()}) -MutexName ('Audit-'+$PID)
 return $false
}
'@|Set-Content (Join-Path $fixture 'ExternalUsageAdapters.ps1')
    $attempts=Join-Path $fixture 'attempts.txt'
    @{errorCode='unexpected_model_activity';retryAfterSeconds=0}|ConvertTo-Json|Set-Content (Join-Path $fixture 'scenario.json')
    $ownerTicks=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks
    function Start-FixtureCollector {
        Start-UtpHiddenTestProcess -FilePath $exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $fixture 'Start-UsageCollector.ps1')+'"'),'-OwnerProcessId',$PID,'-OwnerStartTicks',$ownerTicks,'-DataDirectory',('"'+$fixture+'"'),'-Sources','qwen')
    }
    function Read-Attempts {if(Test-Path $attempts){@(Get-Content $attempts).Count}else{0}}
    function Wait-Attempts([int]$Count){$until=(Get-Date).AddSeconds(8);while((Read-Attempts) -lt $Count -and (Get-Date) -lt $until -and -not $process.HasExited){Start-Sleep -Milliseconds 100};Start-Sleep -Milliseconds 400}
    $process=Start-FixtureCollector;Wait-Attempts 1
    Check ((Read-Attempts) -eq 1) 'Initial collection must occur'
    Stop-OwnedRefreshProcess $process;$process=$null
    $process=Start-FixtureCollector;Start-Sleep -Seconds 2
    Check ((Read-Attempts) -eq 1) 'Restart must preserve an unexpected-model-activity pause'
    $before=Read-Attempts
    @{qwen=[guid]::NewGuid().ToString('N')}|ConvertTo-Json|Set-Content (Join-Path $fixture 'refresh-requests.json')
    Wait-Attempts ($before+1)
    Check ((Read-Attempts) -eq ($before+1)) 'Explicit refresh must resume a paused provider once'
    $before=Read-Attempts
    [IO.File]::WriteAllText((Join-Path $fixture 'qwen-token-plan-credentials.json'),'synthetic credential revision')
    Wait-Attempts ($before+1)
    Check ((Read-Attempts) -eq ($before+1)) 'Changed credentials must resume a paused provider'
    @{errorCode='rate_limited';retryAfterSeconds=600}|ConvertTo-Json|Set-Content (Join-Path $fixture 'scenario.json')
    $before=Read-Attempts
    @{qwen=[guid]::NewGuid().ToString('N')}|ConvertTo-Json|Set-Content (Join-Path $fixture 'refresh-requests.json')
    Wait-Attempts ($before+1)
    Stop-OwnedRefreshProcess $process;$process=$null
    $before=Read-Attempts
    $process=Start-FixtureCollector;Start-Sleep -Seconds 2
    Check ((Read-Attempts) -eq $before) 'Restart must preserve provider Retry-After'
    Check (-not $process.HasExited) 'The paused collector must remain alive'
    Stop-OwnedRefreshProcess $process;$process=$null
    Set-Content (Join-Path $fixture 'collector-schedule-qwen.json') '{'
    $process=Start-FixtureCollector;Start-Sleep -Seconds 2
    Check (-not $process.HasExited -and (Read-Attempts) -eq $before) 'A corrupt source schedule must neither crash the collector nor bypass its pause'
    @{qwen=[guid]::NewGuid().ToString('N')}|ConvertTo-Json|Set-Content (Join-Path $fixture 'refresh-requests.json')
    Wait-Attempts ($before+1)
    Check ((Read-Attempts) -eq ($before+1)) 'Explicit refresh must recover from a corrupt source schedule'
} finally {
    if($null -ne $process){Stop-OwnedRefreshProcess $process}
    $env:OPENCODE_GO_API_KEY=$oldGo;$env:QWEN_TOKEN_PLAN_COOKIE=$oldQwen
    $resolved=[IO.Path]::GetFullPath($root)
    if($resolved.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'UtpProviderRecovery-*'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
if($failures.Count){throw "$($failures.Count) provider recovery checks failed"}
'Provider recovery, credential isolation and statusline expiry tests OK'
