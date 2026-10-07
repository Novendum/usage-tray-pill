param(
    [string]$WorkingDirectory = $env:USERPROFILE,
    [int]$MaxConsecutiveFastFailures = 3,
    [int]$FastFailureSeconds = 10,
    [int]$CooldownMinutes = 15
)

$ErrorActionPreference = "Continue"

$dataDir = Join-Path $env:APPDATA "UsageTrayPill"
$logPath = Join-Path $dataDir "claude-keeper.log"
$cooldownPath = Join-Path $dataDir "claude-keeper-cooldown.json"

function Write-KeeperLog {
    param([string]$Message)

    try {
        if (-not (Test-Path -LiteralPath $dataDir)) {
            New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
        }

        $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
    }
    catch {
    }
}

function Set-KeeperCooldown {
    param([string]$Reason)

    try {
        if (-not (Test-Path -LiteralPath $dataDir)) {
            New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
        }

        $payload = [pscustomobject]@{
            disabledUntil = (Get-Date).AddMinutes([Math]::Max(1, $CooldownMinutes)).ToString("o")
            reason = $Reason
            writtenAt = (Get-Date).ToString("o")
        } | ConvertTo-Json -Depth 4
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($cooldownPath, $payload, $encoding)
    }
    catch {
    }
}

. (Join-Path $PSScriptRoot "ExternalUsageAdapters.ps1")

function Get-ClaudeExecutablePath { return Resolve-UtpClaudeUsageCli }

try {
    [Console]::Title = "Usage Tray Pill - Claude Keeper"
}
catch {
}

$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, "UsageTrayPillClaudeUsageKeeper", [ref]$createdNew)
if (-not $createdNew) {
    Write-KeeperLog "keeper already running; exiting"
    exit 0
}

try {
    $env:CODEX_LIMIT_TRAY_CLAUDE_KEEPER = "1"
    Write-KeeperLog "keeper started"
    $consecutiveFastFailures = 0
    $claudePath = Get-ClaudeExecutablePath
    if ([string]::IsNullOrWhiteSpace($claudePath)) {
        Write-KeeperLog "claude executable not found; cooldown started"
        Set-KeeperCooldown "claude executable not found"
        exit 1
    }
    Write-KeeperLog "using claude executable: $claudePath"

    while ($true) {
        $startedAt = Get-Date
        $exitCode = 0

        try {
            if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory) -and (Test-Path -LiteralPath $WorkingDirectory)) {
                Set-Location -LiteralPath $WorkingDirectory
            }

            Write-KeeperLog "starting claude"
            & $claudePath
            $exitCode = [int]$LASTEXITCODE
            Write-KeeperLog "claude exited with code $exitCode"
        }
        catch {
            $exitCode = 1
            Write-KeeperLog "claude failed: $($_.Exception.Message)"
        }

        $elapsedSeconds = ((Get-Date) - $startedAt).TotalSeconds
        if ($exitCode -ne 0 -and $elapsedSeconds -lt [Math]::Max(1, $FastFailureSeconds)) {
            $consecutiveFastFailures++
        }
        else {
            $consecutiveFastFailures = 0
        }

        if ($consecutiveFastFailures -ge [Math]::Max(1, $MaxConsecutiveFastFailures)) {
            $reason = "claude failed quickly $consecutiveFastFailures times; last exit code $exitCode"
            Write-KeeperLog "$reason; cooldown started"
            Set-KeeperCooldown $reason
            exit ([Math]::Min(255, [Math]::Max(1, $exitCode)))
        }

        Start-Sleep -Seconds 30
    }
}
finally {
    if ($null -ne $mutex) {
        try {
            $mutex.ReleaseMutex()
        }
        catch {
        }

        $mutex.Dispose()
    }
}
