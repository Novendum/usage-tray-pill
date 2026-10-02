function Get-ProviderRetrySeconds {
    param([string]$ErrorCode,[int]$FailureCount,[int]$RetryAfterSeconds=0)
    if ($ErrorCode -in @('auth_expired','auth_required','unsupported_auth_context','unsupported_response','unexpected_model_activity','access_denied','subscription_required','api_key_required','credential_unreadable','setup_required')) { return -1 }
    if ($RetryAfterSeconds -gt 0) { return [Math]::Min(86400,[Math]::Max(30,$RetryAfterSeconds)) }
    return [int][Math]::Min(900,30*[Math]::Pow(2,[Math]::Min(5,[Math]::Max(0,$FailureCount-1))))
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
    return $dates|Sort-Object|Select-Object -First 1
}
