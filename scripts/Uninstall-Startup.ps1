param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "UtpInstallationHelpers.ps1")
$installation = Get-UtpInstallationPaths

$startupFolder = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupFolder "Usage Tray Pill.lnk"

if (Test-Path -LiteralPath $shortcutPath) {
    $shell = New-Object -ComObject WScript.Shell
    $existing = $shell.CreateShortcut($shortcutPath)
    $isManaged = Test-UtpManagedShortcut -Shortcut $existing -Installation $installation
    if (-not $isManaged -and -not $Force) {
        throw "The startup shortcut with this name is not managed by this UTP installation. Use -Force only when you intentionally want to remove it."
    }
    Remove-Item -LiteralPath $shortcutPath -Force
    Write-Host "Startup shortcut removed:"
    Write-Host $shortcutPath
}
else {
    Write-Host "No startup shortcut found."
}

Write-Host "If the tray app is still running, right-click its icon and choose Exit."
