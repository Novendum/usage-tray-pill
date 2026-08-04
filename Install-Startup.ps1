param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$launcherPath = Join-Path $PSScriptRoot "Launch-UsageTrayPill.vbs"
if (-not (Test-Path -LiteralPath $launcherPath)) {
    throw "Hidden launcher not found: $launcherPath"
}

$startupFolder = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupFolder "Usage Tray Pill.lnk"
$wscriptPath = Join-Path $env:SystemRoot "System32\wscript.exe"
$iconPath = Join-Path $PSScriptRoot "assets\tray-icon-light.ico"
if (-not (Test-Path -LiteralPath $iconPath)) {
    throw "UTP icon not found: $iconPath"
}

$shell = New-Object -ComObject WScript.Shell
if (Test-Path -LiteralPath $shortcutPath) {
    $existing = $shell.CreateShortcut($shortcutPath)
    $isManaged = [string]$existing.TargetPath -ieq $wscriptPath -and [string]$existing.Arguments -eq "`"$launcherPath`""
    if (-not $isManaged -and -not $Force) {
        throw "A different startup shortcut named Usage Tray Pill already exists. Use -Force only when you intentionally want to replace it."
    }
}

$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $wscriptPath
$shortcut.Arguments = "`"$launcherPath`""
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.WindowStyle = 7
$shortcut.IconLocation = "$iconPath,0"
$shortcut.Description = "Start Usage Tray Pill at Windows sign-in"
$shortcut.Save()

$legacyShortcutPath = Join-Path $startupFolder "Codex Limit Tray.lnk"
if (Test-Path -LiteralPath $legacyShortcutPath) {
    $legacy = $shell.CreateShortcut($legacyShortcutPath)
    $isManagedLegacy = [string]$legacy.TargetPath -ieq $wscriptPath -and [string]$legacy.Arguments -eq "`"$launcherPath`""
    if ($isManagedLegacy) {
        Remove-Item -LiteralPath $legacyShortcutPath -Force
    }
}

Write-Host "Startup shortcut installed:"
Write-Host $shortcutPath
Write-Host ""
Write-Host "Start manually with:"
Write-Host (Join-Path $PSScriptRoot "Start-UsageTrayPill.cmd")
