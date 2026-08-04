$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "Start-UsageTrayPill.ps1"
$usageUpdaterPath = Join-Path $PSScriptRoot "Update-ClaudeUsageFromStatusline.ps1"
$silentLauncherPath = Join-Path $PSScriptRoot "Launch-UsageTrayPill.vbs"
$cmdLauncherPath = Join-Path $PSScriptRoot "Start-UsageTrayPill.cmd"
$keeperPath = Join-Path $PSScriptRoot "Start-ClaudeUsageKeeper.ps1"
$startupInstallerPath = Join-Path $PSScriptRoot "Install-Startup.ps1"
$desktopUninstallerPath = Join-Path $PSScriptRoot "Uninstall-DesktopShortcut.ps1"
$startMenuInstallerPath = Join-Path $PSScriptRoot "Install-StartMenuShortcut.ps1"
$startMenuUninstallerPath = Join-Path $PSScriptRoot "Uninstall-StartMenuShortcut.ps1"
$statusLineInstallerPath = Join-Path $PSScriptRoot "Install-ClaudeStatusLine.ps1"
$statusLineUninstallerPath = Join-Path $PSScriptRoot "Uninstall-ClaudeStatusLine.ps1"
$openCodeAdapterPath = Join-Path $PSScriptRoot "OpenCodeGo.ps1"
$qwenAdapterPath = Join-Path $PSScriptRoot "QwenTokenPlan.ps1"
$windowsPowerShellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

foreach ($powerShellFile in @(Get-ChildItem -LiteralPath $PSScriptRoot -File -Filter "*.ps1")) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $powerShellFile.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        $messages = @($parseErrors | ForEach-Object { $_.Message }) -join " | "
        throw "PowerShell syntax error in $($powerShellFile.Name): $messages"
    }
}

if (-not (Test-Path -LiteralPath $silentLauncherPath)) {
    throw "Silent tray launcher is missing."
}

$silentLauncher = Get-Content -LiteralPath $silentLauncherPath -Raw
if ($silentLauncher -notmatch "shell\.Run command, 0, False") {
    throw "Silent tray launcher does not start hidden."
}
if ($silentLauncher -match "-OpenEditor") {
    throw "Silent tray launcher must not open the editor."
}

$cmdLauncher = Get-Content -LiteralPath $cmdLauncherPath -Raw
if ($cmdLauncher -notmatch '%SystemRoot%\\System32\\wscript\.exe') {
    throw "CMD launcher must use the hidden VBS launcher through an absolute Windows path."
}

$startupInstaller = Get-Content -LiteralPath $startupInstallerPath -Raw
if ($startupInstaller -notmatch 'Launch-UsageTrayPill\.vbs' -or $startupInstaller -notmatch 'wscript\.exe') {
    throw "Startup installer must use the hidden UTP launcher."
}
if ($startupInstaller -notmatch '\[switch\]\$Force' -or $startupInstaller -notmatch '\$isManaged') {
    throw "Startup installer must protect a same-named shortcut not owned by UTP."
}
if ($startupInstaller -notmatch 'tray-icon-light\.ico') {
    throw "Startup installer must use the light UTP icon by default."
}
if (-not (Test-Path -LiteralPath $desktopUninstallerPath)) {
    throw "Desktop shortcut uninstaller is missing."
}
$desktopUninstaller = Get-Content -LiteralPath $desktopUninstallerPath -Raw
if ($desktopUninstaller -notmatch '\[switch\]\$Force' -or $desktopUninstaller -notmatch '\$isManaged') {
    throw "Desktop uninstaller must not remove a same-named shortcut not owned by UTP without -Force."
}
if (-not (Test-Path -LiteralPath $startMenuInstallerPath) -or -not (Test-Path -LiteralPath $startMenuUninstallerPath)) {
    throw "Start menu shortcut install/uninstall scripts are missing."
}
$startMenuInstaller = Get-Content -LiteralPath $startMenuInstallerPath -Raw
$startMenuUninstaller = Get-Content -LiteralPath $startMenuUninstallerPath -Raw
if ($startMenuInstaller -notmatch 'Usage Tray Pill\.lnk' -or
    $startMenuInstaller -notmatch '\[switch\]\$Force' -or
    $startMenuInstaller -notmatch '\$isManaged' -or
    $startMenuInstaller -notmatch 'tray-icon-') {
    throw "Start menu installer must correctly manage the name, ownership, and theme icon."
}
if ($startMenuUninstaller -notmatch '\[switch\]\$Force' -or $startMenuUninstaller -notmatch '\$isManaged') {
    throw "Start menu uninstaller must not remove a same-named shortcut not owned by UTP without -Force."
}
$startupUninstaller = Get-Content -LiteralPath (Join-Path $PSScriptRoot "Uninstall-Startup.ps1") -Raw
if ($startupUninstaller -notmatch '\[switch\]\$Force' -or $startupUninstaller -notmatch '\$isManaged') {
    throw "Startup uninstaller must not remove a same-named shortcut not owned by UTP without -Force."
}

$statusLineInstaller = Get-Content -LiteralPath $statusLineInstallerPath -Raw
if ($statusLineInstaller -notmatch 'System32\\WindowsPowerShell\\v1\.0\\powershell\.exe' -or
    $statusLineInstaller -notmatch '\$managedCommand = "`"\$powershellPath`" .* -File `"\$scriptPath`""' -or
    $statusLineInstaller -notmatch '\$existingCommand -in @\(\$managedCommand, \$legacyManagedCommand\)') {
    throw "Claude statusline installer must use absolute, quoted PowerShell and script paths."
}
if ($statusLineInstaller -notmatch '\[System\.IO\.File\]::Replace') {
    throw "Claude statusline installer must replace settings atomically."
}
if (-not (Test-Path -LiteralPath $statusLineUninstallerPath)) {
    throw "Claude statusline uninstaller is missing."
}
$statusLineUninstaller = Get-Content -LiteralPath $statusLineUninstallerPath -Raw
if ($statusLineUninstaller -notmatch '\$statusLine\.command -notin @\(\$managedCommand, \$legacyManagedCommand\)') {
    throw "Claude statusline uninstaller must remove only exact current or legacy UTP commands."
}
if ($statusLineInstaller -notmatch '\[switch\]\$Force' -or $statusLineInstaller -notmatch 'A different Claude statusline is already configured') {
    throw "Claude statusline installer must protect an existing integration behind explicit -Force."
}

$originalUserProfile = $env:USERPROFILE
$statusLineTestProfile = Join-Path ([System.IO.Path]::GetTempPath()) ("utp-statusline-test-" + [Guid]::NewGuid().ToString("N"))
try {
    $env:USERPROFILE = $statusLineTestProfile
    $testClaudeDir = Join-Path $statusLineTestProfile ".claude"
    $testSettingsPath = Join-Path $testClaudeDir "settings.json"
    New-Item -ItemType Directory -Force -Path $testClaudeDir | Out-Null
    $deceptiveCommand = "custom-statusline.exe --note `"$usageUpdaterPath`""
    [System.IO.File]::WriteAllText(
        $testSettingsPath,
        ([pscustomobject]@{
            statusLine = [pscustomobject]@{ type = "command"; command = $deceptiveCommand }
            theme = "dark"
        } | ConvertTo-Json -Depth 4),
        (New-Object System.Text.UTF8Encoding($false))
    )

    $blockedExistingStatusLine = $false
    try {
        & $statusLineInstallerPath *> $null
    }
    catch {
        $blockedExistingStatusLine = $true
    }
    if (-not $blockedExistingStatusLine) {
        throw "Claude statusline installer must reject an existing integration without -Force."
    }
    $preservedSettings = Get-Content -LiteralPath $testSettingsPath -Raw | ConvertFrom-Json
    if ([string]$preservedSettings.statusLine.command -ne $deceptiveCommand) {
        throw "A rejected installation must not change existing Claude settings."
    }

    & $statusLineUninstallerPath *> $null
    $preservedAfterUninstall = Get-Content -LiteralPath $testSettingsPath -Raw | ConvertFrom-Json
    if ([string]$preservedAfterUninstall.statusLine.command -ne $deceptiveCommand) {
        throw "Claude statusline uninstaller must not remove an unrelated command that only mentions a UTP path."
    }

    & $statusLineInstallerPath -Force *> $null
    $installedSettings = Get-Content -LiteralPath $testSettingsPath -Raw | ConvertFrom-Json
    if ([string]$installedSettings.statusLine.command -notmatch [regex]::Escape($usageUpdaterPath)) {
        throw "Claude statusline installer must configure the UTP updater when -Force is used."
    }
    if ([string]$installedSettings.theme -ne "dark") {
        throw "Claude statusline installer must preserve all other settings."
    }

    & $statusLineUninstallerPath *> $null
    $uninstalledSettings = Get-Content -LiteralPath $testSettingsPath -Raw | ConvertFrom-Json
    if ($null -ne $uninstalledSettings.statusLine) {
        throw "Claude statusline uninstaller must remove only the managed UTP statusline."
    }
    if ([string]$uninstalledSettings.theme -ne "dark") {
        throw "Claude statusline uninstaller must preserve all other settings."
    }
}
finally {
    $env:USERPROFILE = $originalUserProfile
    Remove-Item -LiteralPath $statusLineTestProfile -Recurse -Force -ErrorAction SilentlyContinue
}

$trayScript = Get-Content -LiteralPath $scriptPath -Raw
$usageUpdater = Get-Content -LiteralPath $usageUpdaterPath -Raw
$openCodeAdapter = Get-Content -LiteralPath $openCodeAdapterPath -Raw
$qwenAdapter = Get-Content -LiteralPath $qwenAdapterPath -Raw
$gitIgnore = Get-Content -LiteralPath (Join-Path $PSScriptRoot ".gitignore") -Raw
if ($openCodeAdapter -notmatch 'reads usage from the OpenCode Go dashboard' -or
    $openCodeAdapter -notmatch 'session is encrypted for your Windows account only') {
    throw "OpenCode Go setup must describe its experimental dashboard source and encrypted session storage."
}
if ($qwenAdapter -notmatch 'reads usage from QwenCloud dashboard interfaces every two minutes' -or
    $qwenAdapter -notmatch 'session is encrypted for your Windows account only') {
    throw "Qwen setup must describe its experimental dashboard source, poll interval, and encrypted session storage."
}
if ($gitIgnore -notmatch 'assets/\*-source\.png') {
    throw "Local high-resolution source images must remain outside the release."
}
$qwenLogoPath = Join-Path $PSScriptRoot "assets\qwen-logo.png"
$blockedProviderAssets = @(
    (Join-Path $PSScriptRoot "assets\openai-logo.png"),
    (Join-Path $PSScriptRoot "assets\claude-logo.png")
)
foreach ($blockedProviderAsset in $blockedProviderAssets) {
    if (Test-Path -LiteralPath $blockedProviderAsset) {
        throw "Bundled provider logo must not be included in the open-source distribution: $blockedProviderAsset"
    }
}
if ($trayScript -match 'openai-logo\.png|claude-logo\.png') {
    throw "Tray code must not depend on bundled OpenAI or Claude logos."
}
if (-not (Test-Path -LiteralPath $qwenLogoPath)) {
    throw "The official Qwen Code provider logo is missing."
}
$qwenLogoHash = (Get-FileHash -LiteralPath $qwenLogoPath -Algorithm SHA256).Hash
if ($qwenLogoHash -ne "02DAC7AE657DDD32793B55CB63C00497807D1B6CF55343CEA2B97120D048839A") {
    throw "The Qwen provider logo differs from the documented official Qwen Code icon."
}
if ($trayScript -notmatch 'assets\\qwen-logo\.png' -or $trayScript -notmatch 'official:qwen') {
    throw "The Qwen pill must use only the official Qwen Code provider logo."
}
if ($trayScript -notmatch 'Get-ClaudeIconCandidatePaths' -or
    $trayScript -notmatch 'Get-ClaudeIconPath' -or
    $trayScript -notmatch 'Get-CodexIconPath') {
    throw "ChatGPT and Claude indicators must be loaded from locally installed apps."
}
if ($trayScript -notmatch 'Get-AntigravityLanguageServerContext' -or
    $trayScript -notmatch 'LanguageServerService/GetUserStatus' -or
    $trayScript -notmatch 'Get-TaskbarBadgeSources') {
    throw "The tray must include the local Antigravity adapter and dynamic provider cycle."
}
if ($trayScript -notmatch 'Read-AntigravityLimitedUtf8Stream' -or
    $trayScript -match '(?s)Invoke-AntigravityUserStatusRequest.+?ReadToEnd\(') {
    throw "Antigravity responses must be strictly bounded while reading."
}
if ($trayScript -match 'fetchAvailableModels|oauth2\.googleapis\.com') {
    throw "The Antigravity integration must not include a cloud or OAuth fallback."
}
if ($trayScript -match 'Fable 5|function Update-ClaudeUsage|RefreshFromOAuth') {
    throw "The tray must not contain Fable or experimental Claude OAuth logic."
}
if ($usageUpdater -match 'Fable 5|RefreshFromOAuth|Invoke-RestMethod|Authorization|accessToken|\.credentials\.json') {
    throw "The Claude statusline updater must not contain Fable, OAuth, network, or credential logic."
}
if ($usageUpdater -notmatch 'Read-LimitedStatuslineInput' -or $usageUpdater -match '\[Console\]::In\.ReadToEnd\(') {
    throw "The Claude statusline updater must stream provider input with a strict bound."
}
if ($trayScript -notmatch 'UsageTrayPillStateWrite' -or $usageUpdater -notmatch 'UsageTrayPillClaudeUsageWrite') {
    throw "UTP state and Claude snapshots must use cross-process write locks."
}
if ($trayScript -notmatch '\[System\.IO\.File\]::Replace\(\$tempPath, \$script:DataPath, \$replaceBackupPath, \$true\)' -or $usageUpdater -notmatch '\[System\.IO\.File\]::Replace\(\$tempPath, \$dataPath, \$replaceBackupPath, \$true\)') {
    throw "UTP state and Claude snapshots must be replaced atomically."
}
if ($trayScript -match 'Start-BadgeHoverCarousel|Stop-BadgeHoverCarouselIfOutside|Step-BadgeHoverCarousel|badgeCarouselTimer') {
    throw "Provider switching must not be triggered by hover or a carousel timer."
}
if ($trayScript -notmatch '\$badgeKeepAliveTimer\.Interval\s*=\s*500') {
    throw "Fullscreen badge visibility must refresh within 500 milliseconds."
}
if ($trayScript -notmatch 'Invoke-TaskbarBadgeMouseUp -EventArgs \$eventData' -or
    $trayScript -notmatch 'MouseButtons\]::Right' -or
    $trayScript -notmatch 'ContextMenuStrip\.Show') {
    throw "The pill must switch providers on left-click and open the stable UTP menu on right-click."
}
if ($trayScript -match '\.FileName = "cmd\.exe"|/c codex app-server') {
    throw "Codex must not be launched through an unresolved cmd or PATH command."
}
if ($trayScript -notmatch 'function Resolve-CodexCommandPath' -or $trayScript -notmatch 'function New-CodexAppServerStartInfo') {
    throw "The Codex app-server must start through a validated absolute command path."
}
if ($trayScript -notmatch 'StandardError\.BaseStream\.CopyToAsync\(\[System\.IO\.Stream\]::Null\)' -or
    $trayScript -notmatch 'WaitForExit\(2000\)') {
    throw "Codex app-server stderr must be drained without unbounded memory growth and shut down cleanly."
}
if ($trayScript -notmatch 'if \(\$widthChanged -or \$null -eq \$script:BadgeForm\.Region\)') {
    throw "Dynamic badge width must also refresh the rounded window region."
}

$openCodeGoAdapterPath = Join-Path $PSScriptRoot "OpenCodeGo.ps1"
if (-not (Test-Path -LiteralPath $openCodeGoAdapterPath)) {
    throw "OpenCode Go adapter is missing."
}
$openCodeGoAdapter = Get-Content -LiteralPath $openCodeGoAdapterPath -Raw
if ($trayScript -notmatch 'RefreshOpenCodeGoOnce' -or
    $trayScript -notmatch 'openCodeGoEnabled' -or
    $trayScript -notmatch 'Show-OpenCodeGoSetupDialog') {
    throw "The tray must offer OpenCode Go as a configurable fourth provider."
}
if ($openCodeGoAdapter -notmatch 'rollingUsage' -or
    $openCodeGoAdapter -notmatch 'weeklyUsage' -or
    $openCodeGoAdapter -notmatch 'monthlyUsage') {
    throw "The OpenCode Go adapter must process 5-hour, weekly, and monthly quotas."
}
if ($openCodeGoAdapter -notmatch 'ProtectedData.*Protect' -or
    $openCodeGoAdapter -notmatch 'DataProtectionScope.*CurrentUser') {
    throw "OpenCode Go authentication must be encrypted with Windows DPAPI for the current user."
}
if ($openCodeGoAdapter -match '(?i)auth\.json|WebView2.*Cookies|Network\\Cookies') {
    throw "The OpenCode Go adapter must not automatically read provider or browser credentials."
}
if ($openCodeGoAdapter -notmatch 'https://opencode\.ai' -or
    $openCodeGoAdapter -match 'Invoke-RestMethod') {
    throw "OpenCode Go network traffic must be explicitly restricted to the dashboard."
}
if ($openCodeGoAdapter -notmatch 'Read-OpenCodeGoLimitedUtf8Stream' -or $openCodeGoAdapter -match 'ReadToEnd\(') {
    throw "OpenCode Go responses must be strictly bounded while reading."
}

if (-not (Test-Path -LiteralPath $qwenAdapterPath)) {
    throw "The Qwen Token Plan adapter is missing."
}
$qwenAdapter = Get-Content -LiteralPath $qwenAdapterPath -Raw
if ($trayScript -notmatch 'RefreshQwenOnce' -or
    $trayScript -notmatch 'qwenTokenPlanEnabled' -or
    $trayScript -notmatch 'Show-QwenSetupDialog' -or
    $trayScript -notmatch 'Start-QwenUsageRefresh') {
    throw "The tray must offer Qwen Token Plan as a configurable provider."
}
if ($qwenAdapter -notmatch 'per5HourPercentage' -or
    $qwenAdapter -notmatch 'per1WeekPercentage' -or
    $qwenAdapter -notmatch '/tokenplan/personal/api/v2/usage') {
    throw "The Qwen adapter must process the 5h and weekly quotas through the fixed Token Plan endpoint."
}
if ($qwenAdapter -notmatch 'ProtectedData.*Protect' -or
    $qwenAdapter -notmatch 'DataProtectionScope.*CurrentUser') {
    throw "Qwen authentication must be encrypted with Windows DPAPI for the current user."
}
if ($qwenAdapter -match '(?i)[/\\]\.qwen|settings\.json|WebView2.*Cookies|Network\\Cookies|Invoke-RestMethod') {
    throw "The Qwen adapter must not automatically read provider, CLI, or browser credentials."
}
if ($qwenAdapter -notmatch 'https://home\.qwencloud\.com' -or
    $qwenAdapter -notmatch 'https://cs-data\.qwencloud\.com' -or
    $qwenAdapter -match 'sk-sp-') {
    throw "Qwen network traffic and configuration must remain limited to the dashboard session."
}
if ($qwenAdapter -notmatch 'AllowAutoRedirect = \$false' -or
    $qwenAdapter -notmatch 'response_too_large' -or
    $qwenAdapter -notmatch 'UsageTrayPillQwenPoll') {
    throw "Qwen traffic must be bounded, redirect-free, and locked across processes."
}
if ($qwenAdapter -notmatch 'Read-QwenLimitedUtf8Stream' -or $qwenAdapter -match 'ReadToEnd\(') {
    throw "Qwen responses must be strictly bounded while reading."
}

$keeperScript = Get-Content -LiteralPath $keeperPath -Raw
if ($keeperScript -notmatch 'Get-ChildItem -LiteralPath \$desktopRoot -Directory') {
    throw "The Claude keeper must discover Desktop version directories dynamically."
}
if ($keeperScript -notmatch 'Sort-Object Version -Descending') {
    throw "The Claude keeper must select the newest valid Desktop version."
}
if ($keeperScript -notmatch 'CommandType Application' -or
    $keeperScript -notmatch '\$extension -in @\("\.exe", "\.cmd", "\.bat"\)' -or
    $keeperScript -notmatch 'Test-Path -LiteralPath \$resolvedPath -PathType Leaf') {
    throw "The Claude keeper may only start an existing executable Claude file, not an alias or function."
}
if ($trayScript -match 'return "5h \$primary\s+weekly \$secondary"') {
    throw "The status badge must no longer show a 5h value."
}
if ($trayScript -notmatch 'return "weekly \$secondary"') {
    throw "The status badge must show the weekly value."
}
if ($trayScript -match 'PrimaryPrefix = "5h"') {
    throw "The status badge must not use the 5h bucket as its primary field."
}
if ($trayScript -match 'SourceText = "(Codex|Claude)"') {
    throw "The status badge must not show a Codex or Claude name."
}
if ($trayScript -notmatch 'SourceText = ""') {
    throw "The status badge must leave the source name empty so only the logo is visible."
}
if ($trayScript -notmatch '\$script:BadgeMinimumWidth = 176') {
    throw "The status badge must retain a compact minimum width for weekly usage."
}
if ($trayScript -notmatch 'function Get-BadgeLabelWidth' -or $trayScript -notmatch 'function Get-BadgeContentWidth') {
    throw "The status badge must measure labels and total content dynamically."
}
if ($trayScript -notmatch '\$script:BadgeLabelValueGap = 4' -or $trayScript -notmatch '\$script:BadgeItemGap = 8') {
    throw "The status badge must use provider-independent spacing."
}
if ($trayScript -notmatch '\$script:BadgeLabelFontSize = 12' -or $trayScript -notmatch '\$script:BadgeValueFontSize = 12') {
    throw "The status badge must format labels and values consistently."
}
if ($trayScript -notmatch 'function Get-BadgeTransitionEase' -or $trayScript -notmatch 'function Set-TaskbarBadgeWidth') {
    throw "The status badge must animate text, logo, and width with a shared transition."
}
if ($trayScript -notmatch '\$logoViewport\.Visible = \$true' -or $trayScript -notmatch 'Set-BadgePictureBoxImage -PictureBox \$script:BadgeLogoNext') {
    throw "The provider logo must visibly move with the provider content."
}
if ($trayScript -notmatch 'function Enable-ControlDoubleBuffering') {
    throw "The status badge must use double buffering to prevent flicker during animations."
}
if ($trayScript -notmatch '\$script:BadgeForm\.Invalidate\(\$true\)' -or $trayScript -notmatch '\$script:BadgeForm\.Update\(\)') {
    throw "The status badge must refresh all child controls during the transition without leaving trails."
}
if ($trayScript -notmatch 'if \(\$script:BadgeAnimating\) \{\s*\$rect = \$script:BadgeForm\.Bounds') {
    throw "Keep-alive must not overwrite the animated badge width during a transition."
}
if ($trayScript -notmatch '\$script:TrayIconSignature -ne \$iconSignature' -or
    $trayScript -notmatch '\$script:BadgeRenderSignature -ne \$targetSignature') {
    throw "The tray and pill must only rerender after an actual state change."
}
if ($trayScript -notmatch 'Refresh-TaskbarBadge -GeometryOnly' -or
    $trayScript -notmatch 'if \(-not \$geometryOnlyMode\) \{\s*\$targetSource = Get-TaskbarBadgeDefaultSource') {
    throw "Keep-alive must not reread provider files or quotas."
}
if ($trayScript -notmatch 'if \(-not \$wasVisible -or \$boundsChanged -or \$restoreOccludedBadge\) \{\s*Set-BadgeTopMostNoActivate') {
    throw "The pill may only be moved to topmost after being shown again, a geometry change, or proven occlusion."
}
if ($trayScript -notmatch 'function Test-TaskbarBadgeOccluded' -or
    $trayScript -notmatch 'WindowFromPoint' -or
    $trayScript -notmatch 'BadgeLastOcclusionRestoreAt' -or
    $trayScript -notmatch 'TotalSeconds -ge 5') {
    throw "A pill covered by Explorer must be restored conditionally and with a cooldown."
}
if ($trayScript -match '\$script:BadgeForm\.TopMost = \$true' -or
    $trayScript -match '\$script:BadgeLogoViewport\.BringToFront\(\)') {
    throw "Keep-alive must not perform repeated z-order changes."
}
if ($trayScript -notmatch '\$script:TrayMenuOpen = \$true' -or
    $trayScript -notmatch '\$script:TrayMenuOpen = \$false') {
    throw "Tray updates must be paused while the context menu is open."
}
if ($trayScript -notmatch '(?s)function Start-TrayApp.+?try \{.+?\[System\.Windows\.Forms\.Application\]::Run\(\).+?finally \{' -or
    $trayScript -notmatch '\$script:Mutex\.Dispose\(\)\s*\$script:Mutex = \$null\s*return') {
    throw "The tray runtime must clean up all resources after partial initialization and for a second instance."
}
if ($trayScript -match 'Next: \$\(Format-TimeLeft') {
    throw "The tray tooltip must not change on every refresh solely because the remaining minutes decrease."
}

$desktopInstallerPath = Join-Path $PSScriptRoot "Install-DesktopShortcut.ps1"
$desktopInstaller = Get-Content -LiteralPath $desktopInstallerPath -Raw
if ($desktopInstaller -notmatch 'ValidateSet\("Light", "Dark"\)') {
    throw "The desktop installer must support light and dark themes."
}
if ($desktopInstaller -notmatch '\$Theme = "Light"') {
    throw "The desktop installer must use the light theme by default."
}
if ($desktopInstaller -notmatch '\[switch\]\$Force' -or $desktopInstaller -notmatch '\$isManaged') {
    throw "The desktop installer must protect a same-named shortcut that is not managed by UTP."
}
if ($desktopInstaller -notmatch 'tray-icon-') {
    throw "The desktop installer must use UTP's own themed icons."
}

function Stop-ProcessTree {
    param([int]$RootProcessId)

    $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $ids = @($RootProcessId)
    $frontier = @($RootProcessId)

    while ($frontier.Count -gt 0) {
        $children = @(
            $all |
                Where-Object { $frontier -contains [int]$_.ParentProcessId } |
                ForEach-Object { [int]$_.ProcessId }
        )
        $newIds = @($children | Where-Object { $ids -notcontains $_ })
        if ($newIds.Count -eq 0) {
            break
        }

        $ids += $newIds
        $frontier = $newIds
    }

    foreach ($processId in @($ids | Sort-Object -Descending | Select-Object -Unique)) {
        if ($processId -eq $PID) {
            continue
        }

        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }
}

$selfTestTimeoutMilliseconds = 30000

$process = Start-Process -FilePath $windowsPowerShellPath -ArgumentList @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    ("`"" + $scriptPath + "`""),
    "-SelfTest"
) -PassThru

if (-not $process.WaitForExit($selfTestTimeoutMilliseconds)) {
    Stop-ProcessTree -RootProcessId $process.Id
    throw "Usage Tray Pill selftest timed out."
}

Stop-ProcessTree -RootProcessId $process.Id

if ($process.ExitCode -ne 0) {
    throw "Usage Tray Pill selftest failed with exit code $($process.ExitCode)"
}

$relocatedRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("Usage Tray Pill relocation " + [Guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Path $relocatedRoot | Out-Null
    foreach ($runtimeFile in @(
        "Start-UsageTrayPill.ps1",
        "Start-ClaudeUsageKeeper.ps1",
        "Update-ClaudeUsageFromStatusline.ps1",
        "OpenCodeGo.ps1",
        "QwenTokenPlan.ps1"
    )) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $runtimeFile) -Destination $relocatedRoot
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "assets") -Destination $relocatedRoot -Recurse

    $relocatedProcess = Start-Process -FilePath $windowsPowerShellPath -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        ("`"" + (Join-Path $relocatedRoot "Start-UsageTrayPill.ps1") + "`""),
        "-SelfTest"
    ) -PassThru

    if (-not $relocatedProcess.WaitForExit($selfTestTimeoutMilliseconds)) {
        Stop-ProcessTree -RootProcessId $relocatedProcess.Id
        throw "Usage Tray Pill relocated selftest timed out."
    }
    Stop-ProcessTree -RootProcessId $relocatedProcess.Id
    if ($relocatedProcess.ExitCode -ne 0) {
        throw "Usage Tray Pill relocated selftest failed with exit code $($relocatedProcess.ExitCode)"
    }
}
finally {
    Remove-Item -LiteralPath $relocatedRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$usageOutput = & $windowsPowerShellPath -NoProfile -ExecutionPolicy Bypass -File $usageUpdaterPath -SelfTest
if ($LASTEXITCODE -ne 0 -or ($usageOutput -notcontains "Selftest OK")) {
    throw "Claude usage updater selftest failed."
}
