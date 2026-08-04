param(
    [ValidateSet("Light", "Dark")]
    [string]$Theme = "Light",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$launcherPath = Join-Path $PSScriptRoot "Launch-UsageTrayPill.vbs"
if (-not (Test-Path -LiteralPath $launcherPath)) {
    throw "Hidden launcher not found: $launcherPath"
}

$assetsPath = Join-Path $PSScriptRoot "assets"
$iconPath = Join-Path $assetsPath ("tray-icon-" + $Theme.ToLowerInvariant() + ".ico")
if (-not (Test-Path -LiteralPath $iconPath)) {
    throw "Theme icon not found: $iconPath"
}

$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktopPath "Usage Tray Pill.lnk"
$wscriptPath = Join-Path $env:SystemRoot "System32\wscript.exe"

$shell = New-Object -ComObject WScript.Shell
if (Test-Path -LiteralPath $shortcutPath) {
    $existing = $shell.CreateShortcut($shortcutPath)
    $isManaged = [string]$existing.TargetPath -ieq $wscriptPath -and [string]$existing.Arguments -eq "`"$launcherPath`""
    if (-not $isManaged -and -not $Force) {
        throw "A different shortcut named Usage Tray Pill already exists. Use -Force only when you intentionally want to replace it."
    }
}

$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $wscriptPath
$shortcut.Arguments = "`"$launcherPath`""
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.WindowStyle = 7
$shortcut.Description = "Start Usage Tray Pill hidden"
$shortcut.IconLocation = "$iconPath,0"
$shortcut.Save()

Write-Host "Desktop shortcut installed:"
Write-Host $shortcutPath
Write-Host "Theme: $Theme"
