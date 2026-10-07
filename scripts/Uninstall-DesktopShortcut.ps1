param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "UtpInstallationHelpers.ps1")
$installation = Get-UtpInstallationPaths

$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktopPath "Usage Tray Pill.lnk"

if (Test-Path -LiteralPath $shortcutPath) {
    $shell = New-Object -ComObject WScript.Shell
    $existing = $shell.CreateShortcut($shortcutPath)
    $isManaged = Test-UtpManagedShortcut -Shortcut $existing -Installation $installation
    if (-not $isManaged -and -not $Force) {
        throw "The desktop shortcut with this name is not managed by this UTP installation. Use -Force only when you intentionally want to remove it."
    }
    Remove-Item -LiteralPath $shortcutPath -Force
    Write-Host "Desktop shortcut removed:"
    Write-Host $shortcutPath
}
else {
    Write-Host "No UTP desktop shortcut found."
}
