function Get-ProviderRetrySeconds {
    param([string]$ErrorCode,[int]$FailureCount,[int]$RetryAfterSeconds=0)
    if ($ErrorCode -in @('auth_expired','auth_required','unsupported_auth_context','unsupported_response','unexpected_model_activity','unexpected_transcript_activity','access_denied','subscription_required','api_key_required','credential_unreadable','setup_required')) { return -1 }
    if ($RetryAfterSeconds -gt 0) { return [Math]::Min(86400,[Math]::Max(30,$RetryAfterSeconds)) }
    if ($ErrorCode -eq 'quota_fetch_unavailable') { return [int][Math]::Min(900,[Math]::Max(300,30*[Math]::Pow(2,[Math]::Min(5,[Math]::Max(0,$FailureCount-1))))) }
    return [int][Math]::Min(900,30*[Math]::Pow(2,[Math]::Min(5,[Math]::Max(0,$FailureCount-1))))
}

function Get-UtpCredentialRevision {
    param([string]$Source)
    $path='';$value=''
    switch($Source){
        'opencodego' {$path=$script:OpenCodeGoCredentialPath;$value=[string]$env:OPENCODE_GO_API_KEY}
        'qwen' {$path=$script:QwenCredentialPath;$value=[string]$env:QWEN_TOKEN_PLAN_COOKIE}
        default {return ''}
    }
    $bytes=$null
    if(-not [string]::IsNullOrWhiteSpace($value)){$bytes=[Text.Encoding]::UTF8.GetBytes('environment:'+ $value)}
    elseif($path -and (Test-Path -LiteralPath $path)){
        try{$bytes=[IO.File]::ReadAllBytes($path)}
        catch{return 'unreadable'} # A locked credential pauses only its provider; it is never an identity match.
    }
    else{return 'none'}
    $hash=[Security.Cryptography.SHA256]::Create()
    try{return [Convert]::ToBase64String($hash.ComputeHash($bytes))}
    finally{$hash.Dispose();[Array]::Clear($bytes,0,$bytes.Length)}
}

function Read-UtpCollectorSchedule {
    param([string]$Path,[string]$CredentialRevision,[object]$Snapshot)
    $next=[datetime]::MinValue;$failures=0
    if(Test-Path -LiteralPath $Path){
        try {
            $saved=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json -ErrorAction Stop
            if($saved.PSObject.Properties.Name -notcontains 'credentialRevision'){throw 'Invalid schedule'}
            $savedNext=[datetime]::Parse([string]$saved.nextAttemptAt,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
            if([string]$saved.credentialRevision -eq $CredentialRevision){
                $next=$savedNext
                $failures=[Math]::Max(0,[int]$saved.failures)
            }
        } catch {
            # An unreadable source schedule must not restart every provider or bypass a pause.
            # Explicit refresh or changed credentials can resume this worker and replace the file.
            $next=[datetime]::MaxValue
        }
    }
    if($null -ne $Snapshot -and [string]$Snapshot.credentialRevision -eq $CredentialRevision) {
        # The cache is written before the schedule. Honor newer failures even if shutdown
        # interrupted schedule persistence, and retain older-version safety pauses.
        $code=if($Snapshot.errorCode){[string]$Snapshot.errorCode}else{[string]$Snapshot.lastError}
        if($code){
            $failures=[Math]::Max(1,$failures)
            $seconds=Get-ProviderRetrySeconds $code $failures ([int]$Snapshot.retryAfterSeconds)
            $checked=Get-DateOrNull ([string]$Snapshot.lastCheckedAt)
            if($seconds -lt 0){$next=[datetime]::MaxValue}
            elseif($null -ne $checked -and $checked.AddSeconds($seconds) -gt $next){$next=$checked.AddSeconds($seconds)}
        }
    }
    [pscustomobject]@{Next=$next;Failures=$failures}
}

function Get-ProviderPollSeconds {
    param([string]$Source)
    switch($Source){'claude'{return 180} 'qwen'{return 120} default{return 60}}
}

function Get-HttpRetryAfterSeconds {
    param([string]$Value)
    $seconds=0
    if([int]::TryParse($Value,[ref]$seconds)){return [Math]::Min(86400,[Math]::Max(0,$seconds))}
    $date=[DateTimeOffset]::MinValue
    if([DateTimeOffset]::TryParse($Value,[ref]$date)){return [int][Math]::Min(86400,[Math]::Max(0,($date-[DateTimeOffset]::UtcNow).TotalSeconds))}
    return 0
}

function Test-ProviderEnabled {
    param([string]$Source,[object]$Settings)
    switch ($Source) {
        'codex' { return [bool]$Settings.autoPollLiveUsage }
        'claude' { return [bool]$Settings.claudeControlEnabled }
        'opencodego' { return [bool]$Settings.openCodeGoEnabled }
        'qwen' { return [bool]$Settings.qwenTokenPlanEnabled }
        default { return $true }
    }
}

function Get-NextQuotaReset {
    param([object]$Snapshot,[datetime]$Now=(Get-Date))
    $values=@($Snapshot.items | ForEach-Object {$_.resetsAt})
    foreach($bucket in @($Snapshot.buckets)){$values+=@($bucket.primaryResetsAt,$bucket.secondaryResetsAt)}
    $dates=@(foreach($value in $values){$date=Get-DateOrNull ([string]$value);if($null -ne $date -and $date -gt $Now){$date}})
    return $dates|Sort-Object|Select-Object -First 1 -Wait
}
