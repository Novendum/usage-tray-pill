param([Parameter(Mandatory=$true)][int]$OwnerProcessId,[Parameter(Mandatory=$true)][long]$OwnerStartTicks,[Parameter(Mandatory=$true)][string]$DataDirectory,[ValidateSet('codex','claude','antigravity','opencodego','qwen')][string[]]$Sources=@('codex','claude','antigravity','opencodego','qwen'))
$ErrorActionPreference='Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'RequestDeadline.cs')
$jobs=@()
$stop=[hashtable]::Synchronized(@{Requested=$false})
$worker={
    param($Repo,$Source,$DataDirectory,$Stop)
    $ErrorActionPreference='Stop'
    Add-Type -AssemblyName System.Windows.Forms
    $script:DataDir=$DataDirectory
    $script:DataPath=Join-Path $DataDirectory 'data.json'
    $script:ClaudeControlUsagePath=Join-Path $DataDirectory 'claude-control-usage.json'
    foreach($pair in @(@('CodexUsagePath','codex-usage.json'),@('ClaudeUsagePath','claude-usage.json'),@('AntigravityUsagePath','antigravity-usage.json'),@('OpenCodeGoUsagePath','opencode-go-usage.json'),@('QwenUsagePath','qwen-token-plan-usage.json'),@('OpenCodeGoCredentialPath','opencode-go-credentials.json'),@('QwenCredentialPath','qwen-token-plan-credentials.json'))) {
        Set-Variable -Scope Script -Name $pair[0] -Value (Join-Path $DataDirectory $pair[1])
    }
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Repo 'Start-UsageTrayPill.ps1'),[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'Collector source cannot be parsed.'}
    foreach($node in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) { . ([scriptblock]::Create($node.Extent.Text)) }
    . (Join-Path $Repo 'OpenCodeGo.ps1')
    . (Join-Path $Repo 'QwenTokenPlan.ps1')
    . (Join-Path $Repo 'ExternalUsageAdapters.ps1')
    . (Join-Path $Repo 'CollectorPolicy.ps1')
    $script:CollectorMode=$true
    $script:CollectorRepo=$Repo
    $script:ProviderRefreshErrors=@{}
    $script:CodexConnection=$null
    $script:State=Load-State
    $requestsPath=Join-Path $DataDirectory 'refresh-requests.json'
    $requestVersion=0L;$stateVersion=0L;$credentialVersion=0L;$lastToken='';$next=[datetime]::MinValue;$failures=0;$wasEnabled=$false
    $consumedPath=Join-Path $DataDirectory ("refresh-consumed-$Source.json")
    try {if(Test-Path $consumedPath){$lastToken=[string](Get-Content $consumedPath -Raw|ConvertFrom-Json).token}} catch {}
    $cache=Get-ProviderCachePath -Source $Source
    $credential=if($Source -eq 'opencodego'){$script:OpenCodeGoCredentialPath}elseif($Source -eq 'qwen'){$script:QwenCredentialPath}else{''}
    try {
        while(-not $Stop.Requested) {
            $file=Get-Item -LiteralPath $script:DataPath -ErrorAction SilentlyContinue
            if($null -ne $file -and $file.LastWriteTimeUtc.Ticks -ne $stateVersion) {
                try {$script:State=Load-State;$stateVersion=$file.LastWriteTimeUtc.Ticks} catch {Start-Sleep -Milliseconds 500;continue}
            }
            $manual=$false
            $file=Get-Item -LiteralPath $requestsPath -ErrorAction SilentlyContinue
            if($null -ne $file -and $file.LastWriteTimeUtc.Ticks -ne $requestVersion) {
                try {
                    $requests=Get-Content -LiteralPath $requestsPath -Raw|ConvertFrom-Json
                    $requestVersion=$file.LastWriteTimeUtc.Ticks
                    $token=[string]$requests.$Source
                    if($token -and $token -ne $lastToken){$manual=$true;$lastToken=$token}
                } catch {}
            }
            $enabled=Test-ProviderEnabled -Source $Source -Settings $script:State.settings
            if($Source -eq 'codex' -and $manual){$enabled=$true}
            if(-not $enabled) {$wasEnabled=$false;Start-Sleep -Milliseconds 500;continue}
            if(-not $wasEnabled){$next=[datetime]::MinValue;$wasEnabled=$true}
            if($credential) {
                $file=Get-Item -LiteralPath $credential -ErrorAction SilentlyContinue
                $version=if($null -ne $file){$file.LastWriteTimeUtc.Ticks}else{0L}
                if($version -ne $credentialVersion){$credentialVersion=$version;$next=[datetime]::MinValue}
            }
            if($manual){$next=[datetime]::MinValue}
            if((Get-Date) -lt $next){Start-Sleep -Milliseconds 500;continue}
            if($lastToken){Write-OpenCodeGoJsonAtomically -Path $consumedPath -Value ([pscustomobject]@{token=$lastToken}) -MutexName "UsageTrayPillConsumed-$Source"}
            $ok=$false
            try {
                switch($Source) {
                    'codex' {$ok=Update-LiveUsage}
                    'claude' {$ok=Update-ClaudeControlUsage}
                    'antigravity' {$ok=Update-AntigravityCliUsage}
                    'opencodego' {$ok=Update-OpenCodeGoUsage}
                    'qwen' {$ok=Update-QwenUsage}
                }
            } catch {
                # Never send raw provider/process errors to the UI or logs.
                Set-ProviderRefreshFailure -Source $Source -Message 'Usage could not be refreshed.'
            }
            $snapshot=$null
            try {$snapshot=Get-Content -LiteralPath $cache -Raw|ConvertFrom-Json} catch {}
            if($ok) {$failures=0;$seconds=if($Source -eq 'qwen'){120}else{60}}
            else {
                $failures++
                $code=if($snapshot.errorCode){[string]$snapshot.errorCode}else{[string]$snapshot.lastError}
                $seconds=Get-ProviderRetrySeconds -ErrorCode $code -FailureCount $failures -RetryAfterSeconds ([int]$snapshot.retryAfterSeconds)
            }
            $next=if($seconds -lt 0){[datetime]::MaxValue}else{(Get-Date).AddSeconds($seconds)}
            if($ok){$reset=Get-NextQuotaReset -Snapshot $snapshot;if($null -ne $reset -and $reset.AddSeconds(1) -lt $next){$next=$reset.AddSeconds(1)}}
        }
    } finally { Close-CodexConnection }
}
try {
    $owner=Get-Process -Id $OwnerProcessId -ErrorAction Stop
    if($owner.StartTime.ToUniversalTime().Ticks -ne $OwnerStartTicks){throw 'Collector owner changed.'}
    foreach($source in $Sources) {
        $runspace=[runspacefactory]::CreateRunspace();$runspace.Open()
        $ps=[powershell]::Create();$ps.Runspace=$runspace
        [void]$ps.AddScript($worker.ToString()).AddArgument($PSScriptRoot).AddArgument($source).AddArgument($DataDirectory).AddArgument($stop)
        $jobs+= [pscustomobject]@{Shell=$ps;Runspace=$runspace;Result=$ps.BeginInvoke()}
    }
    while(-not $owner.HasExited) {
        if(@($jobs|Where-Object {$_.Result.IsCompleted}).Count -gt 0){throw 'A collector worker stopped.'}
        Start-Sleep -Milliseconds 500
    }
} finally {
    $stop.Requested=$true
    foreach($job in $jobs) {
        try {[void]$job.Result.AsyncWaitHandle.WaitOne(1000);$job.Shell.Stop()} catch {}
        $job.Shell.Dispose();$job.Runspace.Dispose()
    }
}
