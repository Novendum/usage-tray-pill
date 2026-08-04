param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$launcherPath = Join-Path $PSScriptRoot "Launch-UsageTrayPill.vbs"
$programsFolder = [Environment]::GetFolderPath("Programs")
$shortcutPath = Join-Path $programsFolder "Usage Tray Pill.lnk"
$wscriptPath = Join-Path $env:SystemRoot "System32\wscript.exe"

if (-not (Test-Path -LiteralPath $shortcutPath)) {
    Write-Host "The Start menu shortcut has already been removed."
    exit 0
}

$shell = New-Object -ComObject WScript.Shell
$existing = $shell.CreateShortcut($shortcutPath)
$isManaged = [string]$existing.TargetPath -ieq $wscriptPath -and [string]$existing.Arguments -eq "`"$launcherPath`""
if (-not $isManaged -and -not $Force) {
    throw "The shortcut named Usage Tray Pill does not belong to this checkout. Use -Force only when you intentionally want to remove it."
}

Remove-Item -LiteralPath $shortcutPath -Force
Write-Host "Start menu shortcut removed:"
Write-Host $shortcutPath
