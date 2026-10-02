$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Start-UsageTrayPill.ps1') -LibraryOnly
function Check {param([bool]$Value,[string]$Message) if(-not $Value){throw $Message}}
Check ((Format-RemainingPercent 0.4) -eq '<1%') 'Fractional allowance must not be displayed as exhausted'
Check ((Format-RemainingPercent 0) -eq '0%') 'Zero must remain zero'
Check ((Format-RemainingPercent $null) -eq '--') 'Unknown must stay unknown'
Check ((Get-ProviderRetrySeconds auth_expired 10) -eq -1) 'Expired authentication must pause polling'
Check ((Get-ProviderRetrySeconds auth_required 10) -eq -1) 'CLI sign-in requirements must also pause polling'
Check ((Get-ProviderRetrySeconds unexpected_model_activity 1) -eq -1) 'Unexpected model activity must never be retried automatically'
Check ((Get-ProviderRetrySeconds rate_limited 1 240) -eq 240) 'Honor provider Retry-After'
Check ((Get-ProviderRetrySeconds network_error 5) -gt (Get-ProviderRetrySeconds network_error 1)) 'Network failures must back off'
$resetTime=(Get-Date).AddSeconds(20)
Check ((Get-NextQuotaReset ([pscustomobject]@{items=@([pscustomobject]@{resetsAt=$resetTime.ToString('o')})})) -eq $resetTime) 'Schedule an early refresh at the actual quota reset'
Add-Type @'
public sealed class UtpDeadlineProbe : System.Net.WebRequest {
 public readonly System.Threading.ManualResetEvent Aborted=new System.Threading.ManualResetEvent(false);
 public override void Abort(){Aborted.Set();}
}
'@
$probe=New-Object UtpDeadlineProbe
$deadlineGuard=New-Object UtpRequestDeadline $probe,50
try {Check ($probe.Aborted.WaitOne(1000)) 'The absolute deadline must abort a request independently of stream progress'} finally {$deadlineGuard.Dispose();$probe.Aborted.Dispose()}
$root=Join-Path $env:TEMP ('UtpCollectorTest-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root)
$oldPath=$env:PATH
$process=$null;$monitor=$null
try {
    $script:DataDir=$root;$script:DataPath=Join-Path $root 'data.json'
    $script:QwenCredentialPath=Join-Path $root 'qwen-token-plan-credentials.json'
    $script:State=New-DefaultState
    $script:State.planName='Preserve this note'
    Save-State
    $before=(Get-FileHash $script:DataPath).Hash
    if(-not ('UtpUsageFileMonitor' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'UsageFileMonitor.cs')}
    $monitor=New-Object UtpUsageFileMonitor $root
    [void]$monitor.ConsumeChanges()
    $mock=@'
$ErrorActionPreference='Stop'
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'server-pid.txt'),[string]$PID)
while($null -ne ($line=[Console]::ReadLine())) {
 $request=$line|ConvertFrom-Json
 if($request.method -eq 'initialize'){[Console]::WriteLine((@{id=$request.id;result=@{}}|ConvertTo-Json -Compress))}
 if($request.method -eq 'account/rateLimits/read'){
  Add-Content -LiteralPath (Join-Path $PSScriptRoot 'reads.txt') -Value $request.id
  $reply=@{id=$request.id;result=@{rateLimits=@{limitId='codex';primary=@{usedPercent=99.6;windowDurationMins=10080;resetsAt=[DateTimeOffset]::UtcNow.AddDays(1).ToUnixTimeSeconds()}}}}
  [Console]::WriteLine(($reply|ConvertTo-Json -Depth 8 -Compress))
 }
}
'@
    [IO.File]::WriteAllText((Join-Path $root 'mock.ps1'),$mock)
    [IO.File]::WriteAllText((Join-Path $root 'codex.cmd'),"@echo off`r`n`"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`" -NoProfile -ExecutionPolicy Bypass -File `"%~dp0mock.ps1`"`r`n")
    $env:PATH="$root;$oldPath"
    $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $ownerTicks=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks
    $collector=Join-Path $PSScriptRoot 'Start-UsageCollector.ps1'
    $process=Start-Process -FilePath $exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$collector+'"'),'-OwnerProcessId',$PID,'-OwnerStartTicks',$ownerTicks,'-DataDirectory',('"'+$root+'"'),'-Sources','codex') -WindowStyle Hidden -PassThru -RedirectStandardError (Join-Path $root 'stderr.txt')
    $cache=Join-Path $root 'codex-usage.json'
    $deadline=(Get-Date).AddSeconds(20)
    while(-not (Test-Path $cache) -and -not $process.HasExited -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 100}
    if(-not (Test-Path $cache)){throw ('Collector did not produce a snapshot: '+(Get-Content (Join-Path $root 'stderr.txt') -Raw))}
    $snapshot=Get-Content $cache -Raw|ConvertFrom-Json
    Check ([Math]::Abs($snapshot.buckets[0].primaryRemainingPercent-0.4) -lt 0.001) 'Collector must preserve provider precision'
    Check ($monitor.ConsumeChanges()) 'Atomic provider writes must wake the UI watcher'
    $serverId=[IO.File]::ReadAllText((Join-Path $root 'server-pid.txt'))
    @{codex=[guid]::NewGuid().ToString('N')}|ConvertTo-Json|Set-Content (Join-Path $root 'refresh-requests.json')
    $deadline=(Get-Date).AddSeconds(8)
    while(@(Get-Content (Join-Path $root 'reads.txt')).Count -lt 2 -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 100}
    Check (@(Get-Content (Join-Path $root 'reads.txt')).Count -ge 2) 'A manual request must reach the collector'
    Check ([IO.File]::ReadAllText((Join-Path $root 'server-pid.txt')) -eq $serverId) 'Codex process must be reused across reads'
    Check ((Get-FileHash $script:DataPath).Hash -eq $before) 'Collector must not modify settings or notes'
    Check (-not $process.HasExited) 'Collector must stay alive after a completed request'
    Stop-OwnedRefreshProcess $process;$process=$null
    $script:State.settings.autoPollLiveUsage=$false
    Save-State
    $readCount=@(Get-Content (Join-Path $root 'reads.txt')).Count
    $process=Start-Process -FilePath $exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$collector+'"'),'-OwnerProcessId',$PID,'-OwnerStartTicks',$ownerTicks,'-DataDirectory',('"'+$root+'"'),'-Sources','codex') -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 2
    Check (@(Get-Content (Join-Path $root 'reads.txt')).Count -eq $readCount) 'Restart must not replay an already consumed refresh when automatic polling is disabled'
    Stop-OwnedRefreshProcess $process;$process=$null
    function Refresh-Tray {}
    function Start-QwenUsageRefresh {}
    function Stop-QwenUsageRefresh {}
    $script:State.settings.taskbarBadgeDefaultSource='qwen'
    [IO.File]::WriteAllText($script:QwenCredentialPath,'test encrypted credential marker')
    Set-QwenEnabled $false
    Check (-not $script:State.settings.qwenTokenPlanEnabled -and (Get-TaskbarBadgeSources) -notcontains 'qwen') 'Disabled Qwen must disappear from provider cycling'
    Check (Test-Path $script:QwenCredentialPath) 'Disabling must preserve the saved Qwen connection'
    Set-QwenEnabled $true
    Check ((Get-TaskbarBadgeSources) -contains 'qwen') 'Qwen can be enabled again'
    $script:ClaudeControlUsagePath=Join-Path $root 'claude-control-usage.json'
    $script:State.settings.claudeControlEnabled=$true
    @{source='claude-code-control';available=$true;lastError='';lastCheckedAt=(Get-Date).ToString('o');items=@(@{key='five_hour';label='5h';remainingPercent=0.4;resetsAt=(Get-Date).AddHours(1).ToString('o')},@{key='seven_day';label='weekly';remainingPercent=72;resetsAt=(Get-Date).AddDays(1).ToString('o')})}|ConvertTo-Json -Depth 6|Set-Content $script:ClaudeControlUsagePath
    $claude=Get-ClaudeUsageSnapshot
    Check ($claude.source -eq 'claude-code-control' -and $claude.fiveHourRemainingPercent -eq 0.4 -and $claude.sevenDayRemainingPercent -eq 72) 'Selected CLI source must feed the existing Claude display without losing precision'
    $grouped=@(Get-AntigravityDisplayItems ([pscustomobject]@{items=@([pscustomobject]@{key='gemini-5h';family='Gemini';remainingPercent=90},[pscustomobject]@{key='gemini-weekly';family='Gemini';remainingPercent=40})}))
    Check ($grouped.Count -eq 1 -and $grouped[0].key -eq 'gemini-weekly') 'Compact Antigravity view must select the most restrictive window without discarding raw buckets'
    Write-Output 'Collector, precision, pause and watcher tests OK'
} finally {
    if($null -ne $process){Stop-OwnedRefreshProcess $process}
    if($null -ne $monitor){$monitor.Dispose()}
    $env:PATH=$oldPath
    $resolved=[IO.Path]::GetFullPath($root)
    if($resolved.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'UtpCollectorTest-*'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
