param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "UtpInstallationHelpers.ps1")
$installation = Get-UtpInstallationPaths

$launcherPath = $installation.Launcher
if (-not (Test-Path -LiteralPath $launcherPath)) {
    throw "Hidden launcher not found: $launcherPath"
}

$startupFolder = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupFolder "Usage Tray Pill.lnk"
$wscriptPath = $installation.Wscript
$iconPath = Join-Path $installation.Assets "tray-icon-light.ico"
if (-not (Test-Path -LiteralPath $iconPath)) {
    throw "UTP icon not found: $iconPath"
}

$shell = New-Object -ComObject WScript.Shell
if (Test-Path -LiteralPath $shortcutPath) {
    $existing = $shell.CreateShortcut($shortcutPath)
    $isManaged = Test-UtpManagedShortcut -Shortcut $existing -Installation $installation
    if (-not $isManaged -and -not $Force) {
        throw "A different startup shortcut named Usage Tray Pill already exists. Use -Force only when you intentionally want to replace it."
    }
}

$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $wscriptPath
$shortcut.Arguments = "`"$launcherPath`""
$shortcut.WorkingDirectory = $installation.Root
$shortcut.WindowStyle = 7
$shortcut.IconLocation = "$iconPath,0"
$shortcut.Description = "Start Usage Tray Pill at Windows sign-in"
$shortcut.Save()

$legacyShortcutPath = Join-Path $startupFolder "Codex Limit Tray.lnk"
if (Test-Path -LiteralPath $legacyShortcutPath) {
    $legacy = $shell.CreateShortcut($legacyShortcutPath)
    $isManagedLegacy = Test-UtpManagedShortcut -Shortcut $legacy -Installation $installation
    if ($isManagedLegacy) {
        Remove-Item -LiteralPath $legacyShortcutPath -Force
    }
}

Write-Host "Startup shortcut installed:"
Write-Host $shortcutPath
Write-Host ""
Write-Host "Start manually with:"
Write-Host (Join-Path $installation.Root "Start-UsageTrayPill.cmd")
