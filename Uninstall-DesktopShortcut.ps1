param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktopPath "Usage Tray Pill.lnk"

if (Test-Path -LiteralPath $shortcutPath) {
    $launcherPath = Join-Path $PSScriptRoot "Launch-UsageTrayPill.vbs"
    $wscriptPath = Join-Path $env:SystemRoot "System32\wscript.exe"
    $shell = New-Object -ComObject WScript.Shell
    $existing = $shell.CreateShortcut($shortcutPath)
    $isManaged = [string]$existing.TargetPath -ieq $wscriptPath -and [string]$existing.Arguments -eq "`"$launcherPath`""
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
