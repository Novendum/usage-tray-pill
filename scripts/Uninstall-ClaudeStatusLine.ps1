$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "UtpInstallationHelpers.ps1")
$installation = Get-UtpInstallationPaths

$settingsPath = Join-Path (Join-Path $env:USERPROFILE ".claude") "settings.json"

if (-not (Test-Path -LiteralPath $settingsPath)) {
    Write-Host "No Claude settings found."
    exit 0
}

$raw = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop
$settings = $(if ([string]::IsNullOrWhiteSpace($raw)) { [pscustomobject]@{} } else { $raw | ConvertFrom-Json -ErrorAction Stop })
$statusLine = $settings.statusLine
if ($null -eq $statusLine -or -not (Test-UtpManagedClaudeCommand -Command ([string]$statusLine.command) -Installation $installation)) {
    Write-Host "No Claude statusline managed by this UTP installation was found."
    exit 0
}

$backupPath = "$settingsPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item -LiteralPath $settingsPath -Destination $backupPath -Force
$settings.PSObject.Properties.Remove("statusLine")

$json = $settings | ConvertTo-Json -Depth 12
$encoding = New-Object System.Text.UTF8Encoding($false)
$tempPath = "$settingsPath.tmp-$PID"
$replaceBackupPath = "$settingsPath.replace-backup-$PID"
try {
    [System.IO.File]::WriteAllText($tempPath, $json, $encoding)
    [System.IO.File]::Replace($tempPath, $settingsPath, $replaceBackupPath, $true)
    Remove-Item -LiteralPath $replaceBackupPath -Force -ErrorAction SilentlyContinue
}
finally {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $replaceBackupPath -Force -ErrorAction SilentlyContinue
}

Write-Host "Claude statusline removed."
Write-Host "Backup: $backupPath"
