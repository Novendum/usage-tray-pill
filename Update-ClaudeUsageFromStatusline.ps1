param(
    [switch]$SelfTest,
    [string]$DataDir = (Join-Path $env:APPDATA "UsageTrayPill")
)

$ErrorActionPreference = "Stop"

$dataPath = Join-Path $DataDir "claude-usage.json"

function Format-DateForStorage {
    param([datetime]$Date)
    return $Date.ToString("yyyy-MM-dd HH:mm:ss")
}

function Format-UnixDateForStorage {
    param($Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return ""
    }

    try {
        return [DateTimeOffset]::FromUnixTimeSeconds([int64][double]$Value).LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss")
    }
    catch {
        return ""
    }
}

function Get-NumberOrNull {
    param($Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    try {
        return [double]$Value
    }
    catch {
        return $null
    }
}

function Get-RemainingPercent {
    param($UsedPercent)

    if ($null -eq $UsedPercent) {
        return $null
    }

    return [int][Math]::Max(0, [Math]::Min(100, [Math]::Round(100 - [double]$UsedPercent)))
}

function Save-ClaudeUsage {
    param([object]$Snapshot)

    if (-not (Test-Path -LiteralPath $DataDir)) {
        New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
    }

    $json = $Snapshot | ConvertTo-Json -Depth 8
    $tempPath = "$dataPath.tmp-$PID"
    $replaceBackupPath = "$dataPath.replace-backup-$PID"
    $encoding = New-Object System.Text.UTF8Encoding($false)
    $writeMutex = New-Object System.Threading.Mutex($false, "UsageTrayPillClaudeUsageWrite")
    $hasWriteLock = $false
    try {
        try {
            $hasWriteLock = $writeMutex.WaitOne([TimeSpan]::FromSeconds(15))
        }
        catch [System.Threading.AbandonedMutexException] {
            $hasWriteLock = $true
        }
        if (-not $hasWriteLock) {
            throw "Timed out while locking Claude usage."
        }

        [System.IO.File]::WriteAllText($tempPath, $json, $encoding)
        if (Test-Path -LiteralPath $dataPath) {
            [System.IO.File]::Replace($tempPath, $dataPath, $replaceBackupPath, $true)
            Remove-Item -LiteralPath $replaceBackupPath -Force -ErrorAction SilentlyContinue
        }
        else {
            Move-Item -LiteralPath $tempPath -Destination $dataPath
        }
    }
    finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $replaceBackupPath -Force -ErrorAction SilentlyContinue
        if ($hasWriteLock) {
            try { $writeMutex.ReleaseMutex() } catch {
            }
        }
        $writeMutex.Dispose()
    }
}

function New-EmptySnapshot {
    param([string]$ErrorMessage)

    return [pscustomobject]@{
        source = "claude-code"
        lastCheckedAt = Format-DateForStorage (Get-Date)
        lastError = $ErrorMessage
        modelName = ""
        version = ""
        fiveHourUsedPercent = $null
        fiveHourRemainingPercent = $null
        fiveHourResetsAt = ""
        sevenDayUsedPercent = $null
        sevenDayRemainingPercent = $null
        sevenDayResetsAt = ""
        limits = @()
    }
}

function Get-RateLimitLabel {
    param([string]$Key, [object]$RateLimit)

    if ($Key -eq "five_hour") { return "5h" }
    if ($Key -eq "seven_day") { return "weekly" }
    return $Key
}

function Test-StatuslinePayloadHasRateLimits {
    param([object]$Payload)

    return $null -ne $Payload -and $null -ne $Payload.rate_limits -and @($Payload.rate_limits.PSObject.Properties).Count -gt 0
}

function Get-SavedClaudeUsage {
    if (-not (Test-Path -LiteralPath $dataPath)) { return $null }
    try {
        return Get-Content -LiteralPath $dataPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch { return $null }
}

function Read-LimitedStatuslineInput {
    param(
        [Parameter(Mandatory = $true)] [System.IO.TextReader]$Reader,
        [int]$MaximumCharacters = 1048576
    )

    $builder = New-Object System.Text.StringBuilder
    $buffer = New-Object char[] 4096
    try {
        while (($read = $Reader.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if (($builder.Length + $read) -gt $MaximumCharacters) {
                throw "Claude statusline JSON is unexpectedly large."
            }
            [void]$builder.Append($buffer, 0, $read)
        }
        return $builder.ToString()
    }
    finally {
        [Array]::Clear($buffer, 0, $buffer.Length)
    }
}

function New-StatuslineSnapshot {
    param([object]$Payload)

    $fiveUsed = Get-NumberOrNull $Payload.rate_limits.five_hour.used_percentage
    $sevenUsed = Get-NumberOrNull $Payload.rate_limits.seven_day.used_percentage
    $limits = @()
    if ($null -ne $Payload.rate_limits) {
        foreach ($property in @($Payload.rate_limits.PSObject.Properties)) {
            if ([string]$property.Name -notin @("five_hour", "seven_day")) { continue }
            $rateLimit = $property.Value
            $used = Get-NumberOrNull $rateLimit.used_percentage
            $limits += [pscustomobject]@{
                key = [string]$property.Name
                label = Get-RateLimitLabel -Key ([string]$property.Name) -RateLimit $rateLimit
                usedPercent = $(if ($null -ne $used) { [int][Math]::Round($used) } else { $null })
                remainingPercent = Get-RemainingPercent $used
                resetsAt = Format-UnixDateForStorage $rateLimit.resets_at
            }
        }
    }

    return [pscustomobject]@{
        source = "claude-code-statusline"
        lastCheckedAt = Format-DateForStorage (Get-Date)
        lastError = ""
        modelName = [string]$Payload.model.display_name
        version = [string]$Payload.version
        fiveHourUsedPercent = $(if ($null -ne $fiveUsed) { [int][Math]::Round($fiveUsed) } else { $null })
        fiveHourRemainingPercent = Get-RemainingPercent $fiveUsed
        fiveHourResetsAt = Format-UnixDateForStorage $Payload.rate_limits.five_hour.resets_at
        sevenDayUsedPercent = $(if ($null -ne $sevenUsed) { [int][Math]::Round($sevenUsed) } else { $null })
        sevenDayRemainingPercent = Get-RemainingPercent $sevenUsed
        sevenDayResetsAt = Format-UnixDateForStorage $Payload.rate_limits.seven_day.resets_at
        limits = @($limits)
    }
}

function Merge-StatuslineSnapshot {
    param([object]$Current, [object]$Previous)

    if ($null -eq $Previous) { return $Current }
    $merged = @{}
    foreach ($limit in @($Previous.limits | Where-Object { [string]$_.key -in @("five_hour", "seven_day") })) { $merged[[string]$limit.key] = $limit }
    foreach ($limit in @($Current.limits)) { $merged[[string]$limit.key] = $limit }
    $Current.limits = @($merged.Values)

    foreach ($name in @("fiveHourUsedPercent", "fiveHourRemainingPercent", "fiveHourResetsAt", "sevenDayUsedPercent", "sevenDayRemainingPercent", "sevenDayResetsAt")) {
        $value = $Current.$name
        if (($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) -and $null -ne $Previous.$name) {
            $Current.$name = $Previous.$name
        }
    }
    return $Current
}

function Write-StatuslineOutput {
    param([object]$Snapshot)

    $parts = @("Claude")
    if (-not [string]::IsNullOrWhiteSpace([string]$Snapshot.modelName)) {
        $parts += $Snapshot.modelName
    }
    if ($null -ne $Snapshot.fiveHourRemainingPercent) {
        $parts += "5h $($Snapshot.fiveHourRemainingPercent)%"
    }
    if ($null -ne $Snapshot.sevenDayRemainingPercent) {
        $parts += "7d $($Snapshot.sevenDayRemainingPercent)%"
    }
    Write-Output ($parts -join " ")
}

function Assert-SelfTest {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw "Self-test failed: $Message"
    }
}

function Invoke-SelfTest {
    $statuslinePayload = @{
        version = "2.1.202"
        model = @{ display_name = "Sonnet 4.6" }
        rate_limits = @{
            five_hour = @{ used_percentage = 51.2; resets_at = 1783526400 }
            seven_day = @{ used_percentage = 58.4; resets_at = 1783551600 }
        }
    } | ConvertTo-Json -Depth 8 | ConvertFrom-Json

    $statusline = New-StatuslineSnapshot $statuslinePayload
    Assert-SelfTest ($statusline.fiveHourUsedPercent -eq 51) "statusline five-hour used"
    Assert-SelfTest ($statusline.fiveHourRemainingPercent -eq 49) "statusline five-hour remaining"
    Assert-SelfTest ($statusline.sevenDayUsedPercent -eq 58) "statusline seven-day used"
    Assert-SelfTest ($statusline.sevenDayRemainingPercent -eq 42) "statusline seven-day remaining"
    Assert-SelfTest (-not [string]::IsNullOrWhiteSpace($statusline.fiveHourResetsAt)) "statusline reset parsing"
    Assert-SelfTest (@($statusline.limits).Count -eq 2) "statusline must normalize 5-hour and weekly usage"
    Assert-SelfTest (Test-StatuslinePayloadHasRateLimits $statuslinePayload) "payload with rate limits must be recognized"
    $payloadWithoutLimits = @{ version = "2.1.215"; model = @{ display_name = "Sonnet" } } | ConvertTo-Json -Depth 4 | ConvertFrom-Json
    Assert-SelfTest (-not (Test-StatuslinePayloadHasRateLimits $payloadWithoutLimits)) "payload without rate limits must be recognized"

    $exactReader = New-Object System.IO.StringReader ("x" * 32)
    try {
        Assert-SelfTest ((Read-LimitedStatuslineInput -Reader $exactReader -MaximumCharacters 32).Length -eq 32) "statusline input at the limit must be accepted"
    }
    finally {
        $exactReader.Dispose()
    }

    $oversizedRejected = $false
    $oversizedReader = New-Object System.IO.StringReader ("x" * 33)
    try {
        try { [void](Read-LimitedStatuslineInput -Reader $oversizedReader -MaximumCharacters 32) }
        catch { $oversizedRejected = $true }
    }
    finally {
        $oversizedReader.Dispose()
    }
    Assert-SelfTest $oversizedRejected "oversized statusline input must be rejected"

    Write-Host "Selftest OK"
}

if ($SelfTest) {
    Invoke-SelfTest
    exit 0
}

try {
    $raw = Read-LimitedStatuslineInput -Reader ([Console]::In) -MaximumCharacters 1048576
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "No Claude statusline JSON received."
    }

    $payload = $raw | ConvertFrom-Json -ErrorAction Stop
    $previous = Get-SavedClaudeUsage
    if (-not (Test-StatuslinePayloadHasRateLimits $payload)) {
        if ($null -ne $previous -and @($previous.limits).Count -gt 0) {
            $previous.lastCheckedAt = Format-DateForStorage (Get-Date)
            $previous.lastError = ""
            if (-not [string]::IsNullOrWhiteSpace([string]$payload.model.display_name)) { $previous.modelName = [string]$payload.model.display_name }
            if (-not [string]::IsNullOrWhiteSpace([string]$payload.version)) { $previous.version = [string]$payload.version }
            Save-ClaudeUsage $previous
            Write-StatuslineOutput $previous
            exit 0
        }
        Write-Output "Claude usage --"
        exit 0
    }
    $snapshot = New-StatuslineSnapshot $payload
    $snapshot = Merge-StatuslineSnapshot -Current $snapshot -Previous $previous
    Save-ClaudeUsage $snapshot
    Write-StatuslineOutput $snapshot
    exit 0
}
catch {
    $snapshot = New-EmptySnapshot $_.Exception.Message

    if ($null -eq (Get-SavedClaudeUsage)) {
        try { Save-ClaudeUsage $snapshot } catch {
        }
    }

    Write-Output "Claude usage --"
    exit 0
}
