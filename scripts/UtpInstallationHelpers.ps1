function Get-UtpInstallationPaths {
    $root = Split-Path -Parent $PSScriptRoot
    $powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $updaterPath = Join-Path $root "src\Update-ClaudeUsageFromStatusline.ps1"
    $legacyUpdaterPath = Join-Path $root "Update-ClaudeUsageFromStatusline.ps1"
    $managedCommand = "`"$powershellPath`" -NoProfile -ExecutionPolicy Bypass -File `"$updaterPath`""

    [pscustomobject]@{
        Root = $root
        Launcher = Join-Path $root "src\Launch-UsageTrayPill.vbs"
        LegacyLauncher = Join-Path $root "Launch-UsageTrayPill.vbs"
        Assets = Join-Path $root "assets"
        Wscript = Join-Path $env:SystemRoot "System32\wscript.exe"
        PowerShell = $powershellPath
        Updater = $updaterPath
        ManagedCommand = $managedCommand
        ManagedCommands = @(
            $managedCommand
            "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$updaterPath`""
            "`"$powershellPath`" -NoProfile -ExecutionPolicy Bypass -File `"$legacyUpdaterPath`""
            "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$legacyUpdaterPath`""
        )
    }
}

function Test-UtpManagedShortcut {
    param($Shortcut, $Installation)

    # Exact paths only: a shortcut from another checkout is never ours.
    return ([string]$Shortcut.TargetPath -ieq $Installation.Wscript -and
        [string]$Shortcut.Arguments -in @("`"$($Installation.Launcher)`"", "`"$($Installation.LegacyLauncher)`""))
}

function Test-UtpManagedClaudeCommand {
    param([string]$Command, $Installation)

    return ($Command -in $Installation.ManagedCommands)
}

function Get-UtpShortcutIconPath {
    param($Installation, [string]$Theme = "Light")

    # The app icon works on light and dark backgrounds; the themed icons remain a fallback.
    $appIcon = Join-Path $Installation.Assets "app-icon.ico"
    if (Test-Path -LiteralPath $appIcon) { return $appIcon }
    return (Join-Path $Installation.Assets ("tray-icon-" + $Theme.ToLowerInvariant() + ".ico"))
}

function Set-UtpShortcutAppId {
    param([string]$ShortcutPath, $Installation)

    # Lets Windows show "Usage Tray Pill" with its icon in the taskbar and in notifications.
    $identitySource = Join-Path $Installation.Root "src\UtpShellIdentity.cs"
    if (-not (Test-Path -LiteralPath $identitySource)) { return $false }
    try {
        if (-not ('UtpShellIdentity' -as [type])) { Add-Type -Path $identitySource }
        return [UtpShellIdentity]::SetShortcutAppId($ShortcutPath, [UtpShellIdentity]::AppId)
    }
    catch { return $false }
}
