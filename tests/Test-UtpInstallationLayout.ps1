$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
# Windows runners may expose TEMP through an 8.3 alias; PSScriptRoot expands it.
$temporaryRoot = (Get-Item -LiteralPath $env:TEMP).FullName
$testRoot = Join-Path $temporaryRoot ("UTP install user's fixture " + [guid]::NewGuid().ToString('N'))
$fixtureRoot = Join-Path $testRoot 'installation'
$scriptsFolder = Join-Path $fixtureRoot 'scripts'
$savedProfile = $env:USERPROFILE
$encoding = New-Object Text.UTF8Encoding($false)

function Check([bool]$Value, [string]$Message) {
    if (-not $Value) { throw $Message }
}

function Invoke-FixtureScript([string]$Name, [switch]$Force) {
    $parameters = @{}
    if ($Force) { $parameters.Force = $true }
    & (Join-Path $scriptsFolder $Name) @parameters
}

function Write-FixtureShortcut([string]$Path, [string]$Target, [string]$Arguments) {
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = $Target
    $shortcut.Arguments = $Arguments
    $shortcut.Save()
}

function Write-ClaudeSettings([string]$Command) {
    $settings = [pscustomobject]@{ preserved = 'keep'; statusLine = @{ type = 'command'; command = $Command } }
    [IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 5), $encoding)
}

try {
    foreach ($folder in @('scripts', 'src', 'assets', 'Desktop', 'Programs', 'Startup', 'profile\.claude')) {
        [void](New-Item -ItemType Directory -Path (Join-Path $fixtureRoot $folder) -Force)
    }
    $env:USERPROFILE = Join-Path $fixtureRoot 'profile'
    $settingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'scripts\UtpInstallationHelpers.ps1') -Destination $scriptsFolder
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'scripts') -Filter '*.ps1') {
        if ($file.Name -notmatch '^(Install|Uninstall)-') { continue }
        $text = [IO.File]::ReadAllText($file.FullName)
        # Redirect only known-folder lookups in disposable copies. Never run the
        # repository scripts against the real Desktop, Programs or Startup folder.
        foreach ($folder in @('Desktop', 'Programs', 'Startup')) {
            $lookup = '[Environment]::GetFolderPath("' + $folder + '")'
            $destination = "'" + (Join-Path $fixtureRoot $folder).Replace("'", "''") + "'"
            $text = $text.Replace($lookup, $destination)
        }
        Check ($text -notmatch '\[Environment\]::GetFolderPath') 'All known-folder lookups must be redirected before execution'
        [IO.File]::WriteAllText((Join-Path $scriptsFolder $file.Name), $text, $encoding)
    }
    # Installers validate presence; no runtime script or VBS is ever launched.
    foreach ($file in @('src\Launch-UsageTrayPill.vbs', 'src\Update-ClaudeUsageFromStatusline.ps1', 'assets\tray-icon-light.ico', 'assets\tray-icon-dark.ico')) {
        [IO.File]::WriteAllText((Join-Path $fixtureRoot $file), '', $encoding)
    }
    . (Join-Path $scriptsFolder 'UtpInstallationHelpers.ps1')
    $installation = Get-UtpInstallationPaths
    Check ($installation.Root -eq $fixtureRoot) 'Installation root must be the parent of scripts'
    $shell = New-Object -ComObject WScript.Shell
    $foreignLauncher = Join-Path $testRoot 'other-installation\src\Launch-UsageTrayPill.vbs'

    foreach ($kind in @(
        @{ Folder = 'Desktop'; Suffix = 'DesktopShortcut' },
        @{ Folder = 'Programs'; Suffix = 'StartMenuShortcut' },
        @{ Folder = 'Startup'; Suffix = 'Startup' }
    )) {
        $shortcutPath = Join-Path (Join-Path $fixtureRoot $kind.Folder) 'Usage Tray Pill.lnk'
        $installName = 'Install-' + $kind.Suffix + '.ps1'
        $uninstallName = 'Uninstall-' + $kind.Suffix + '.ps1'
        foreach ($launcher in @($installation.LegacyLauncher, $installation.Launcher)) {
            Write-FixtureShortcut $shortcutPath $installation.Wscript "`"$launcher`""
            Invoke-FixtureScript $installName
            $shortcut = $shell.CreateShortcut($shortcutPath)
            Check ($shortcut.TargetPath -ieq (Join-Path $env:SystemRoot 'System32\wscript.exe')) 'Shortcut must use the absolute Windows script host'
            Check ($shortcut.WindowStyle -eq 7) 'Shortcut must retain its hidden-launch window style'
            Check ($shortcut.Arguments -eq "`"$($installation.Launcher)`"") "$installName must migrate same-root shortcuts without Force"
            Check ($shortcut.WorkingDirectory -eq $fixtureRoot) 'Shortcut working directory must remain at repository root'
            Check ($shortcut.IconLocation -eq "$(Join-Path $fixtureRoot 'assets\tray-icon-light.ico'),0") 'Shortcut icon must remain in root assets'
            Write-FixtureShortcut $shortcutPath $installation.Wscript "`"$launcher`""
            Invoke-FixtureScript $uninstallName
            Check (-not (Test-Path -LiteralPath $shortcutPath)) "$uninstallName must remove either same-root layout"
        }
        foreach ($unrelated in @(
            @{ Target = $installation.Wscript; Arguments = "`"$foreignLauncher`"" },
            @{ Target = $installation.Wscript; Arguments = "`"$($installation.LegacyLauncher)`" --custom" },
            @{ Target = $installation.PowerShell; Arguments = "`"$($installation.Launcher)`"" }
        )) {
            Write-FixtureShortcut $shortcutPath $unrelated.Target $unrelated.Arguments
            $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($shortcutPath))
            foreach ($operation in @($installName, $uninstallName)) {
                $failed = $false
                try { Invoke-FixtureScript $operation } catch { $failed = $true }
                Check $failed "$operation must refuse unrelated shortcuts without Force"
                Check ([Convert]::ToBase64String([IO.File]::ReadAllBytes($shortcutPath)) -eq $before) 'Refused shortcuts must stay unchanged'
            }
        }
        Invoke-FixtureScript $installName -Force
        Check (Test-UtpManagedShortcut ($shell.CreateShortcut($shortcutPath)) $installation) 'Explicit Force must still allow replacement'
        Invoke-FixtureScript $uninstallName
        Invoke-FixtureScript $installName
        Invoke-FixtureScript $uninstallName
    }

    $legacyStartup = Join-Path $fixtureRoot 'Startup\Codex Limit Tray.lnk'
    Write-FixtureShortcut $legacyStartup $installation.Wscript "`"$($installation.LegacyLauncher)`""
    Invoke-FixtureScript 'Install-Startup.ps1'
    Check (-not (Test-Path -LiteralPath $legacyStartup)) 'Startup migration must remove its own old-named shortcut'
    Write-FixtureShortcut $legacyStartup $installation.Wscript "`"$foreignLauncher`""
    Invoke-FixtureScript 'Install-Startup.ps1'
    Check (Test-Path -LiteralPath $legacyStartup) 'Startup migration must preserve other installations under the legacy name'

    foreach ($command in $installation.ManagedCommands) {
        Write-ClaudeSettings $command
        $before = [IO.File]::ReadAllText($settingsPath)
        Invoke-FixtureScript 'Install-ClaudeStatusLine.ps1'
        $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        Check ($settings.statusLine.command -eq $installation.ManagedCommand) 'All exact legacy/current commands must migrate to absolute src updater without Force'
        Check ($settings.preserved -eq 'keep') 'Statusline install must preserve other settings'
        $backup = Get-ChildItem -LiteralPath (Split-Path $settingsPath) -Filter 'settings.json.bak-*' | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        Check ($null -ne $backup -and [IO.File]::ReadAllText($backup.FullName) -eq $before) 'Statusline migration must back up original settings'
        Write-ClaudeSettings $command
        Invoke-FixtureScript 'Uninstall-ClaudeStatusLine.ps1'
        $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        Check ($null -eq $settings.statusLine -and $settings.preserved -eq 'keep') 'Statusline uninstall must recognize all exact same-root commands'
    }
    foreach ($command in @(
        ($installation.ManagedCommand + ' --custom'),
        $installation.ManagedCommand.Replace($fixtureRoot, (Join-Path $testRoot 'other-installation')),
        'echo custom-statusline'
    )) {
        Write-ClaudeSettings $command
        $before = [IO.File]::ReadAllText($settingsPath)
        $failed = $false
        try { Invoke-FixtureScript 'Install-ClaudeStatusLine.ps1' } catch { $failed = $true }
        Check $failed 'Statusline install must refuse custom and other-installation commands'
        Check ([IO.File]::ReadAllText($settingsPath) -eq $before) 'Refused statusline install must not change settings'
        Invoke-FixtureScript 'Uninstall-ClaudeStatusLine.ps1'
        Check ([IO.File]::ReadAllText($settingsPath) -eq $before) 'Statusline uninstall must preserve custom and other-installation commands'
    }
    Invoke-FixtureScript 'Install-ClaudeStatusLine.ps1' -Force
    Check ((Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json).statusLine.command -eq $installation.ManagedCommand) 'Explicit Force must still replace custom statuslines'
    Remove-Item -LiteralPath $settingsPath
    Invoke-FixtureScript 'Install-ClaudeStatusLine.ps1'
    Check ((Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json).statusLine.command -eq $installation.ManagedCommand) 'Fresh statusline install must use the absolute src updater'
    Write-Host 'UTP installation layout tests passed (isolated shortcuts and Claude profile).'
}
finally {
    $env:USERPROFILE = $savedProfile
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    $resolvedTemp = [IO.Path]::GetFullPath($temporaryRoot).TrimEnd('\') + '\'
    if ($resolvedTestRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedTestRoot)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
