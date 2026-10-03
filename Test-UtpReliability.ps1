$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Start-UsageTrayPill.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Runtime parse failed' }
$definitions = @{}
foreach ($node in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    $definitions[$node.Name] = $node.Extent.Text
    . ([scriptblock]::Create($node.Extent.Text))
}
. (Join-Path $PSScriptRoot 'OpenCodeGo.ps1')
. (Join-Path $PSScriptRoot 'QwenTokenPlan.ps1')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('UtpReliability-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testRoot)
$script:DataDir = $testRoot
$script:DataPath = Join-Path $testRoot 'data.json'
$script:ClaudeUsagePath = Join-Path $testRoot 'claude.json'
$script:CodexUsagePath = Join-Path $testRoot 'codex.json'
$script:OpenCodeGoUsagePath = Join-Path $testRoot 'opencode.json'
$script:QwenUsagePath = Join-Path $testRoot 'qwen.json'
$script:State = New-DefaultState
$script:ProviderRefreshes = @{}
$script:Failures = @()
function Check { param([bool]$Condition, [string]$Message) if (-not $Condition) { $script:Failures += $Message; Write-Output "FAIL: $Message" } }
try {
    $b = Convert-LiveBucket ([pscustomobject]@{ primary = [pscustomobject]@{ windowDurationMins = 10080 } })
    Check ($null -eq $b.primaryRemainingPercent) 'Missing usage must remain unknown'
    $b = Convert-LiveBucket ([pscustomobject]@{ primary = [pscustomobject]@{ usedPercent = -1 } })
    Check ($null -eq $b.primaryRemainingPercent) 'Out-of-range usage must remain unknown'
    $b = [pscustomobject]@{primaryRemainingPercent=61; primaryWindowDurationMins=300; secondaryRemainingPercent=$null}
    Check ($null -eq (Get-WeeklyBucketRemainingPercent $b)) 'Five-hour window must never be labelled weekly'
    $script:State.liveUsage.buckets = @([pscustomobject]@{limitId='codex';primaryRemainingPercent=42;primaryWindowDurationMins=10080;primaryResetsAt='2001-01-08';secondaryRemainingPercent=$null})
    $script:State.liveUsage.lastCheckedAt = '2001-01-01'
    Check ($null -eq (Get-MainLiveBucket).primaryRemainingPercent) 'Expired Codex data must be hidden'

    function Get-ClaudeDesktopUsageSnapshot { return $null }
    @{lastCheckedAt='2001-01-01';lastError='';fiveHourRemainingPercent=80;sevenDayRemainingPercent=70;fiveHourResetsAt='';sevenDayResetsAt='';limits=@()} | ConvertTo-Json | Set-Content $script:ClaudeUsagePath
    Check ($null -eq (Get-ClaudeUsageSnapshot).fiveHourRemainingPercent) 'Stale Claude without fallback must be hidden'
    @{lastCheckedAt=(Get-Date).ToString('o');lastError='';fiveHourRemainingPercent=80;sevenDayRemainingPercent=70;fiveHourResetsAt=(Get-Date).AddMinutes(-1).ToString('o');sevenDayResetsAt=(Get-Date).AddDays(1).ToString('o');limits=@()} | ConvertTo-Json | Set-Content $script:ClaudeUsagePath
    $claude=Get-ClaudeUsageSnapshot
    Check ($null -eq $claude.fiveHourRemainingPercent -and $claude.sevenDayRemainingPercent -eq 70) 'One expired Claude window must not clear a still-valid weekly window'
    foreach ($provider in @('OpenCodeGo','Qwen')) {
        $path = if ($provider -eq 'Qwen') { $script:QwenUsagePath } else { $script:OpenCodeGoUsagePath }
        $revision=Get-UtpCredentialRevision $(if($provider -eq 'Qwen'){'qwen'}else{'opencodego'})
        @{credentialRevision=$revision;available=$true;stale=$true;lastSuccessAt=(Get-Date).AddHours(-1).ToString('o');items=@(@{key='five_hour';remainingPercent=7;resetsAt=(Get-Date).AddMinutes(-30).ToString('o')})} | ConvertTo-Json -Depth 6 | Set-Content $path
        $snapshot = & "Get-$($provider)UsageSnapshot"
        Check ($null -eq $snapshot.items[0].remainingPercent) "$provider must hide expired windows even inside the cache TTL"
        @{credentialRevision=$revision;available=$true;stale=$false;lastSuccessAt=(Get-Date).AddMinutes(-30).ToString('o');items=@(@{key='five_hour';remainingPercent=50;resetsAt=(Get-Date).AddHours(1).ToString('o')})} | ConvertTo-Json -Depth 6 | Set-Content $path
        $snapshot = & "Get-$($provider)UsageSnapshot"
        Check ([bool]$snapshot.stale -and [bool]$snapshot.available) "$provider must distinguish old cached success from current data"
    }

    # Real WinForms events after the factory returns, with external side effects stubbed.
    function Save-State {}
    function Hide-TaskbarBadge {}
    function Refresh-TaskbarBadge {}
    function Refresh-Tray {}
    function Clear-ClaudeKeeperCooldown {}
    function Ensure-ClaudeUsageKeeper {}
    $script:State = New-DefaultState
    $menu = New-TrayMenu
    try {
        $badge = $menu.Items | Where-Object Text -eq 'Show status badge'
        $badge.PerformClick()
        Check ($script:State.settings.showTaskbarBadge -eq $false) 'Badge can be disabled'
        $badge.PerformClick()
        Check ($script:State.settings.showTaskbarBadge -eq $true) 'Badge can be re-enabled'
        $keeper = $menu.Items | Where-Object Text -eq 'Keep Claude active'
        $keeper.PerformClick()
        Check ($script:State.settings.keepClaudeCodeAlive -eq $true) 'Keeper checkbox persists its checked state'
    } finally { $menu.Dispose() }

    $script:State = New-DefaultState
    $script:State.planName = 'Preserve me'
    $script:State | ConvertTo-Json -Depth 8 | Set-Content $script:DataPath
    $before = [IO.File]::ReadAllText($script:DataPath)
    function Save-State { throw 'Simulated write failure' }
    $loadFailed = $false
    try { [void](Load-State) } catch { $loadFailed = $true }
    Check (-not $loadFailed -and $script:State.planName -eq 'Preserve me') 'Reading state must not require a successful write'
    Check ([IO.File]::ReadAllText($script:DataPath) -eq $before) 'Loading must never replace valid state'

    $childCode = '[Console]::WriteLine(''{"id":0,"result":{}}''); [Console]::WriteLine(''{"id":1,"result":{"ok":true}}''); Start-Sleep -Seconds 8'
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $psi.Arguments = '-NoProfile -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCode))
    $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true; $psi.RedirectStandardOutput=$true
    $process = New-Object Diagnostics.Process
    $process.StartInfo=$psi
    try {
        [void]$process.Start()
        [void](Get-JsonLineResponse -Process $process -ExpectedId 0 -TimeoutSeconds 3)
        $readSucceeded=$false
        try { $reply=Get-JsonLineResponse -Process $process -ExpectedId 1 -TimeoutSeconds 1; $readSucceeded=($reply.id -eq 1) } catch {}
        Check $readSucceeded 'Sequential JSON responses must not be lost'
    } finally { if (-not $process.HasExited) { $process.Kill(); [void]$process.WaitForExit(2000) }; $process.Dispose() }

    $runtimeText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Start-UsageTrayPill.ps1'))
    $uiText = $definitions['Start-TrayApp'] + $definitions['Show-MainWindow']
    Check ($uiText -notmatch '\[void\]\(Update-(Live|Antigravity)Usage\)') 'UI handlers must never poll providers synchronously'
    Check ($definitions.ContainsKey('Start-ProviderUsageRefresh')) 'Providers must share a bounded background refresh lifecycle'
    if ($definitions.ContainsKey('Start-ProviderUsageRefresh')) {
        $inFlight = [pscustomobject]@{HasExited=$false}
        $script:ProviderRefreshes.codex = [pscustomobject]@{Process=$inFlight;StartedAt=Get-Date}
        Start-ProviderUsageRefresh -Source codex
        Check ([object]::ReferenceEquals($inFlight,$script:ProviderRefreshes.codex.Process)) 'Repeated refresh must not start overlapping workers'
        $script:ProviderRefreshes.Clear()
    }
    # Collector lifecycle/failure policy is exercised by Test-UtpCollector.ps1.
    $script:BadgeAnimating=$true
    $script:BadgeDisplayedSource='codex'
    $script:BadgeAnimationTargetSource='claude'
    $script:BadgeAnimationStartedAt=(Get-Date).AddMilliseconds(-100)
    $started=$script:BadgeAnimationStartedAt
    $script:BadgePendingSource=''
    $script:State=New-DefaultState
    try {
        Start-BadgeSlideToSource -Source antigravity
        Check ($script:BadgeAnimationStartedAt -eq $started -and $script:BadgePendingSource -eq 'antigravity') 'Rapid clicking must queue the latest choice without restarting a running transition'
    } catch { Check $false 'Rapid clicking must queue without touching animation controls' }
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if ($resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'UtpReliability-*') { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
if ($script:Failures.Count) { throw "$($script:Failures.Count) reliability regressions failed" }
Write-Output 'Reliability tests OK'
