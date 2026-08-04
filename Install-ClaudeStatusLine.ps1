param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "Update-ClaudeUsageFromStatusline.ps1"
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Claude statusline script not found: $scriptPath"
}
$powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
if (-not (Test-Path -LiteralPath $powershellPath)) {
    throw "Windows PowerShell not found: $powershellPath"
}

$claudeDir = Join-Path $env:USERPROFILE ".claude"
$settingsPath = Join-Path $claudeDir "settings.json"

if (-not (Test-Path -LiteralPath $claudeDir)) {
    New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null
}

try {
    if (Test-Path -LiteralPath $settingsPath) {
        $raw = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            $settings = [pscustomobject]@{}
        }
        else {
            $settings = $raw | ConvertFrom-Json -ErrorAction Stop
        }
    }
    else {
        $settings = [pscustomobject]@{}
    }
}
catch {
    throw "Could not read Claude settings: $($_.Exception.Message)"
}

$existingStatusLine = $settings.statusLine
$existingCommand = $(if ($null -ne $existingStatusLine) { [string]$existingStatusLine.command } else { "" })
$managedCommand = "`"$powershellPath`" -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
$legacyManagedCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
$isManagedStatusLine = $existingCommand -in @($managedCommand, $legacyManagedCommand)
if ($null -ne $existingStatusLine -and -not $isManagedStatusLine -and -not $Force) {
    throw "A different Claude statusline is already configured. Use -Force only when you intentionally want UTP to replace it."
}

if (Test-Path -LiteralPath $settingsPath) {
    $backupPath = "$settingsPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $settingsPath -Destination $backupPath -Force
}
else {
    $backupPath = ""
}

$statusLine = [pscustomobject]@{
    type = "command"
    command = $managedCommand
    refreshInterval = 5
}

$settings | Add-Member -MemberType NoteProperty -Name "statusLine" -Value $statusLine -Force

$json = $settings | ConvertTo-Json -Depth 12
$encoding = New-Object System.Text.UTF8Encoding($false)
$tempPath = "$settingsPath.tmp-$PID"
$replaceBackupPath = "$settingsPath.replace-backup-$PID"
try {
    [System.IO.File]::WriteAllText($tempPath, $json, $encoding)
    if (Test-Path -LiteralPath $settingsPath) {
        [System.IO.File]::Replace($tempPath, $settingsPath, $replaceBackupPath, $true)
        Remove-Item -LiteralPath $replaceBackupPath -Force -ErrorAction SilentlyContinue
    }
    else {
        Move-Item -LiteralPath $tempPath -Destination $settingsPath
    }
}
finally {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $replaceBackupPath -Force -ErrorAction SilentlyContinue
}

Write-Host "Claude Code statusLine configured:"
Write-Host $settingsPath
if (-not [string]::IsNullOrWhiteSpace($backupPath)) {
    Write-Host "Backup:"
    Write-Host $backupPath
}
Write-Host ""
Write-Host "Restart Claude Code or send a new message so the statusline starts writing data."
