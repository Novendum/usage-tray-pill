param(
    [switch]$Validate,
    [switch]$RefreshLiveOnce,
    [switch]$RefreshAntigravityOnce,
    [switch]$RefreshOpenCodeGoOnce,
    [switch]$RefreshQwenOnce,
    [switch]$OpenEditor,
    [switch]$SelfTest,
    [switch]$LibraryOnly
)

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class UsageTrayPillNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);

    [DllImport("shcore.dll")]
    public static extern int SetProcessDpiAwareness(int awareness);

    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    [DllImport("user32.dll")]
    public static extern uint GetDpiForSystem();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindow(string className, string windowName);

    [DllImport("user32.dll")]
    public static extern uint GetDpiForWindow(IntPtr window);

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromPoint(POINT point, uint flags);

    [DllImport("user32.dll")]
    public static extern IntPtr WindowFromPoint(POINT point);

    [DllImport("user32.dll")]
    public static extern IntPtr GetAncestor(IntPtr hWnd, uint gaFlags);

    [DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(IntPtr monitor, int dpiType, out uint dpiX, out uint dpiY);

    public static uint GetPrimaryMonitorDpi() {
        IntPtr taskbar = FindWindow("Shell_TrayWnd", null);
        if (taskbar != IntPtr.Zero) {
            uint taskbarDpi = GetDpiForWindow(taskbar);
            if (taskbarDpi > 0) {
                return taskbarDpi;
            }
        }
        POINT origin = new POINT { X = 0, Y = 0 };
        IntPtr monitor = MonitorFromPoint(origin, 2);
        uint dpiX;
        uint dpiY;
        if (monitor != IntPtr.Zero && GetDpiForMonitor(monitor, 0, out dpiX, out dpiY) == 0 && dpiX > 0) {
            return dpiX;
        }
        return GetDpiForSystem();
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool DestroyIcon(IntPtr hIcon);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool IsZoomed(IntPtr hWnd);

    [DllImport("user32.dll", EntryPoint = "GetWindowLong", SetLastError = true)]
    private static extern int GetWindowLong32(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint = "SetWindowLong", SetLastError = true)]
    private static extern int SetWindowLong32(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr", SetLastError = true)]
    private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr", SetLastError = true)]
    private static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

    public static IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex) {
        if (IntPtr.Size == 8) {
            return GetWindowLongPtr64(hWnd, nIndex);
        }
        return new IntPtr(GetWindowLong32(hWnd, nIndex));
    }

    public static IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong) {
        if (IntPtr.Size == 8) {
            return SetWindowLongPtr64(hWnd, nIndex, dwNewLong);
        }
        return new IntPtr(SetWindowLong32(hWnd, nIndex, dwNewLong.ToInt32()));
    }
}
"@

$dpiConfigured = $false
try { $dpiConfigured = [UsageTrayPillNative]::SetProcessDpiAwarenessContext([IntPtr](-4)) } catch {
}
if (-not $dpiConfigured) {
    try { $dpiConfigured = ([UsageTrayPillNative]::SetProcessDpiAwareness(2) -ge 0) } catch {
    }
}
if (-not $dpiConfigured) {
    try { $dpiConfigured = [UsageTrayPillNative]::SetProcessDPIAware() } catch {
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Path (Join-Path $PSScriptRoot 'RequestDeadline.cs')
if (-not ($RefreshLiveOnce -or $RefreshAntigravityOnce -or $RefreshOpenCodeGoOnce -or $RefreshQwenOnce)) {
    Add-Type -Path (Join-Path $PSScriptRoot 'PillRenderer.cs') -ReferencedAssemblies System.Windows.Forms,System.Drawing
    Add-Type -Path (Join-Path $PSScriptRoot 'BadgeVisibility.cs') -ReferencedAssemblies System.Drawing
}

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:AppName = "Usage Tray Pill"
$script:DataDir = Join-Path $env:APPDATA "UsageTrayPill"
$script:DataPath = Join-Path $script:DataDir "data.json"
$script:CodexUsagePath = Join-Path $script:DataDir "codex-usage.json"
$script:ClaudeUsagePath = Join-Path $script:DataDir "claude-usage.json"
$script:ClaudeControlUsagePath = Join-Path $script:DataDir "claude-control-usage.json"
$script:AntigravityUsagePath = Join-Path $script:DataDir "antigravity-usage.json"
$script:OpenCodeGoUsagePath = Join-Path $script:DataDir "opencode-go-usage.json"
$script:OpenCodeGoCredentialPath = Join-Path $script:DataDir "opencode-go-credentials.json"
$script:QwenUsagePath = Join-Path $script:DataDir "qwen-token-plan-usage.json"
$script:QwenCredentialPath = Join-Path $script:DataDir "qwen-token-plan-credentials.json"
$script:ClaudeKeeperScriptPath = Join-Path $PSScriptRoot "Start-ClaudeUsageKeeper.ps1"
$script:ClaudeKeeperCooldownPath = Join-Path $script:DataDir "claude-keeper-cooldown.json"
$script:ClaudeUsageUpdaterPath = Join-Path $PSScriptRoot "Update-ClaudeUsageFromStatusline.ps1"
$script:NotifyIcon = $null
$script:TrayIconSignature = ""
$script:TrayTooltipText = ""
$script:TrayMenuOpen = $false
$script:MainForm = $null
$script:State = $null
$script:Mutex = $null
$script:ExitRequested = $false
$script:UsagePollInProgress = $false
$script:AntigravityUsagePollInProgress = $false
$script:OpenCodeGoUsagePollInProgress = $false
$script:OpenCodeGoRefreshProcess = $null
$script:QwenUsagePollInProgress = $false
$script:QwenRefreshProcess = $null
$script:QwenRefreshIntervalMilliseconds = 120000
$script:ProviderRefreshes = @{}
$script:ProviderRefreshErrors = @{}
$script:CollectorProcess = $null
$script:CollectorRestartAt = [datetime]::MinValue
$script:UsageMonitor = $null
$script:CodexConnection = $null
$script:BadgeToolTip = $null
$script:BadgeTheme = 'Light'
$script:PendingStateSave = $false
$script:RefreshMainWindow = $null
$script:BadgeForm = $null
$script:BadgeVisibility = $null
$script:BadgeLogoViewport = $null
$script:BadgeLogo = $null
$script:BadgeLogoNext = $null
$script:BadgeLogoPaintSource = ""
$script:BadgeTextViewport = $null
$script:BadgeCurrentRow = $null
$script:BadgeNextRow = $null
$script:BadgeSourceLabel = $null
$script:BadgePrimaryPrefix = $null
$script:BadgePrimaryValue = $null
$script:BadgeSeparator = $null
$script:BadgeSecondaryPrefix = $null
$script:BadgeSecondaryValue = $null
$script:BadgeNextSourceLabel = $null
$script:BadgeNextPrimaryPrefix = $null
$script:BadgeNextPrimaryValue = $null
$script:BadgeNextSeparator = $null
$script:BadgeNextSecondaryPrefix = $null
$script:BadgeNextSecondaryValue = $null
$script:BadgeDisplayedSource = ""
$script:BadgeRenderSignature = ""
$script:BadgeLastOcclusionRestoreAt = $null
$script:BadgeHovering = $false
$script:BadgeAnimating = $false
$script:BadgeAnimationTimer = $null
$script:BadgeAnimationStartedAt = $null
$script:BadgeAnimationTargetSource = ""
$script:BadgeAnimationHalfUpdated = $false
$script:BadgeAnimationDurationMs = 220
$script:BadgePendingSource = ""
$script:BadgeAnimationStartWidth = 0
$script:BadgeAnimationTargetWidth = 0
$script:BadgeLabelFontSize = 12
$script:BadgeValueFontSize = 12
$script:BadgeValueWidth = 54
$script:BadgeLabelValueGap = 4
$script:BadgeItemGap = 8
$script:BadgeMinimumWidth = 176
$script:BadgeTextLeft = 38
$script:BadgeHorizontalChrome = 44
$script:BadgeDpiScale = 1.0
try { $script:BadgeDpiScale = [Math]::Max(0.75, [Math]::Min(3.0, [UsageTrayPillNative]::GetPrimaryMonitorDpi() / 96.0)) } catch {
}

function ConvertTo-BadgePixels {
    param([double]$Value)
    return [int][Math]::Round($Value * $script:BadgeDpiScale, 0)
}

function ConvertTo-BadgeFontPixels {
    param([double]$PointSize)
    return [float]($PointSize * (96.0 / 72.0) * $script:BadgeDpiScale)
}

function Get-HiddenBadgeLogoLocation {
    return New-Object System.Drawing.Point 0, (-(ConvertTo-BadgePixels 22))
}

function Get-BadgeLogoViewportLocation {
    param([int]$BadgeHeight)

    $logoSize = ConvertTo-BadgePixels 22
    $top = [Math]::Max(1, [int][Math]::Round(($BadgeHeight - $logoSize) / 2.0, 0)) -1
    return New-Object System.Drawing.Point (ConvertTo-BadgePixels 13), $top
}

function New-BadgeFont {
    param(
        [float]$PointSize,
        [bool]$Bold
    )

    $style = if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    return New-Object System.Drawing.Font "Segoe UI", (ConvertTo-BadgeFontPixels $PointSize), $style, ([System.Drawing.GraphicsUnit]::Pixel)
}

function Enable-ControlDoubleBuffering {
    param([System.Windows.Forms.Control]$Control)

    if ($null -eq $Control) {
        return
    }

    try {
        $bindingFlags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
        $property = $Control.GetType().GetProperty("DoubleBuffered", $bindingFlags)
        if ($null -ne $property) {
            $property.SetValue($Control, $true, $null)
        }
    }
    catch {
    }
}

function Get-BadgeTransitionEase {
    param([double]$Progress)

    $progress = [Math]::Min(1.0, [Math]::Max(0.0, $Progress))
    return $progress * $progress * $progress * (($progress * (($progress * 6.0) - 15.0)) + 10.0)
}

function Get-BadgeLabelWidth {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return 0
    }

    $font = New-BadgeFont -PointSize $script:BadgeLabelFontSize -Bold $true
    try {
        $measuredWidth = [System.Windows.Forms.TextRenderer]::MeasureText(
            $Text,
            $font,
            (New-Object System.Drawing.Size 1000, (ConvertTo-BadgePixels 28)),
            ([System.Windows.Forms.TextFormatFlags]::SingleLine -bor [System.Windows.Forms.TextFormatFlags]::NoPadding)
        ).Width
        return [int][Math]::Ceiling(($measuredWidth / $script:BadgeDpiScale) + 2)
    }
    finally {
        $font.Dispose()
    }
}

function Get-BadgeContentWidth {
    param([object[]]$Items)

    $visibleItems = @($Items)
    $width = 0
    for ($index = 0; $index -lt $visibleItems.Count; $index++) {
        if ($index -gt 0) {
            $width += $script:BadgeItemGap
        }
        $width += (Get-BadgeLabelWidth -Text ([string]$visibleItems[$index].Label))
        $width += $script:BadgeLabelValueGap + $script:BadgeValueWidth
    }
    return $width
}

function Set-BadgeDpiScaleFromWindow {
    param([System.Windows.Forms.Form]$Form)
    if ($null -eq $Form -or $Form.IsDisposed) { return $false }
    try {
        [void]$Form.Handle
        $dpi = [UsageTrayPillNative]::GetDpiForWindow($Form.Handle)
        if ($dpi -le 0) { return $false }
        $nextScale = [Math]::Max(0.75, [Math]::Min(3.0, $dpi / 96.0))
        if ([Math]::Abs($nextScale - $script:BadgeDpiScale) -lt 0.01) { return $false }
        $script:BadgeDpiScale = $nextScale
        return $true
    }
    catch { return $false }
}

function New-Id {
    return [Guid]::NewGuid().ToString("N")
}

function Get-SilentTrayLaunchCommand {
    param(
        [string]$ScriptPath = (Join-Path $PSScriptRoot "Start-UsageTrayPill.ps1")
    )

    $powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    return "`"$powershellPath`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
}

function New-DefaultState {
    return [pscustomobject]@{
        planName = "ChatGPT Pro"
        limits = @(
            [pscustomobject]@{
                id = New-Id
                name = "ChatGPT/Codex usage"
                allowance = "Live via Codex app-server"
                remaining = "Automatic refresh"
                resetAt = ""
                notes = "Manual fallback entry; live values appear under Live usage."
            }
        )
        resets = @()
        settings = [pscustomobject]@{
            showOnlyWhenCodexRuns = $false
            autoPollLiveUsage = $true
            liveUsagePollIntervalMinutes = 5
            showTaskbarBadge = $true
            hideTaskbarBadgeInFullscreen = $true
            taskbarBadgeDefaultSource = "codex"
            codexLimitId = "codex"
            keepClaudeCodeAlive = $false
            claudeControlEnabled = $false
            openCodeGoEnabled = $false
            qwenTokenPlanEnabled = $false
        }
        liveUsage = [pscustomobject]@{
            source = "codex-app-server"
            lastCheckedAt = ""
            lastSuccessAt = ""
            lastError = ""
            planType = ""
            resetCreditsAvailable = $null
            creditsBalance = ""
            buckets = @()
        }
    }
}

function Ensure-DataDirectory {
    if (-not (Test-Path -LiteralPath $script:DataDir)) {
        New-Item -ItemType Directory -Force -Path $script:DataDir | Out-Null
    }
}

function Ensure-Property {
    param(
        [Parameter(Mandatory = $true)] [object]$Target,
        [Parameter(Mandatory = $true)] [string]$Name,
        $Value
    )

    if ($Target.PSObject.Properties.Name -notcontains $Name) {
        $Target | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function As-Array {
    param($Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [System.Array]) {
        return @($Value)
    }

    return @($Value)
}

function Normalize-State {
    param([object]$State)

    if ($null -eq $State) {
        $State = New-DefaultState
    }

    Ensure-Property -Target $State -Name "planName" -Value "ChatGPT Pro"
    if ([string]::IsNullOrWhiteSpace([string]$State.planName)) {
        $State.planName = "ChatGPT Pro"
    }
    Ensure-Property -Target $State -Name "limits" -Value @()
    Ensure-Property -Target $State -Name "resets" -Value @()
    Ensure-Property -Target $State -Name "settings" -Value ([pscustomobject]@{})
    Ensure-Property -Target $State -Name "liveUsage" -Value ([pscustomobject]@{})

    $State.limits = @(As-Array $State.limits)
    $State.resets = @(As-Array $State.resets)

    Ensure-Property -Target $State.settings -Name "showOnlyWhenCodexRuns" -Value $false
    Ensure-Property -Target $State.settings -Name "autoPollLiveUsage" -Value $true
    Ensure-Property -Target $State.settings -Name "liveUsagePollIntervalMinutes" -Value 5
    Ensure-Property -Target $State.settings -Name "showTaskbarBadge" -Value $true
    Ensure-Property -Target $State.settings -Name "taskbarBadgeDefaultSource" -Value "codex"
    Ensure-Property -Target $State.settings -Name "hideTaskbarBadgeInFullscreen" -Value $true
    Ensure-Property -Target $State.settings -Name "codexLimitId" -Value "codex"
    Ensure-Property -Target $State.settings -Name "claudeControlEnabled" -Value $false
    Ensure-Property -Target $State.settings -Name "keepClaudeCodeAlive" -Value $false
    Ensure-Property -Target $State.settings -Name "openCodeGoEnabled" -Value $false
    Ensure-Property -Target $State.settings -Name "qwenTokenPlanEnabled" -Value $false
    $State.settings.PSObject.Properties.Remove("enableExperimentalClaudeUsageApi")
    if ($null -eq $State.settings.showOnlyWhenCodexRuns) {
        $State.settings.showOnlyWhenCodexRuns = $false
    }
    if ($null -eq $State.settings.autoPollLiveUsage) {
        $State.settings.autoPollLiveUsage = $true
    }
    if ($null -eq $State.settings.liveUsagePollIntervalMinutes -or [int]$State.settings.liveUsagePollIntervalMinutes -lt 1) {
        $State.settings.liveUsagePollIntervalMinutes = 5
    }
    if ($null -eq $State.settings.showTaskbarBadge) {
        $State.settings.showTaskbarBadge = $true
    }
    if ([string]$State.settings.taskbarBadgeDefaultSource -notin @("codex", "claude", "antigravity", "opencodego", "qwen")) {
        $State.settings.taskbarBadgeDefaultSource = "codex"
    }
    if ($null -eq $State.settings.keepClaudeCodeAlive) {
        $State.settings.keepClaudeCodeAlive = $false
    }
    if ($null -eq $State.settings.openCodeGoEnabled) {
        $State.settings.openCodeGoEnabled = $false
    }
    if ($null -eq $State.settings.qwenTokenPlanEnabled) {
        $State.settings.qwenTokenPlanEnabled = $false
    }
    Ensure-Property -Target $State.liveUsage -Name "source" -Value "codex-app-server"
    Ensure-Property -Target $State.liveUsage -Name "lastCheckedAt" -Value ""
    Ensure-Property -Target $State.liveUsage -Name "lastSuccessAt" -Value ""
    Ensure-Property -Target $State.liveUsage -Name "lastError" -Value ""
    Ensure-Property -Target $State.liveUsage -Name "planType" -Value ""
    Ensure-Property -Target $State.liveUsage -Name "resetCreditsAvailable" -Value $null
    Ensure-Property -Target $State.liveUsage -Name "creditsBalance" -Value ""
    Ensure-Property -Target $State.liveUsage -Name "buckets" -Value @()
    $State.liveUsage.buckets = @(As-Array $State.liveUsage.buckets)

    foreach ($limit in $State.limits) {
        Ensure-Property -Target $limit -Name "id" -Value (New-Id)
        Ensure-Property -Target $limit -Name "name" -Value "Limit"
        Ensure-Property -Target $limit -Name "allowance" -Value ""
        Ensure-Property -Target $limit -Name "remaining" -Value ""
        Ensure-Property -Target $limit -Name "resetAt" -Value ""
        Ensure-Property -Target $limit -Name "notes" -Value ""
        if ([string]$limit.name -eq "ChatGPT/Codex usage" -and [string]$limit.allowance -eq "Live via Codex app-server") {
            if ([string]$limit.remaining -eq "Automatisch verversen") {
                $limit.remaining = "Automatic refresh"
            }
            if ([string]$limit.notes -eq "Fallback handmatige regel; live waarden staan op Live gebruik.") {
                $limit.notes = "Manual fallback entry; live values appear under Live usage."
            }
        }
    }

    foreach ($reset in $State.resets) {
        Ensure-Property -Target $reset -Name "id" -Value (New-Id)
        Ensure-Property -Target $reset -Name "label" -Value "Banked reset"
        Ensure-Property -Target $reset -Name "expiresAt" -Value ""
        Ensure-Property -Target $reset -Name "used" -Value $false
        Ensure-Property -Target $reset -Name "notes" -Value ""
    }

    return $State
}

function Save-State {
    Ensure-DataDirectory
    $json = $script:State | ConvertTo-Json -Depth 8
    $tempPath = "$($script:DataPath).tmp-$PID"
    $replaceBackupPath = "$($script:DataPath).replace-backup-$PID"
    $encoding = New-Object System.Text.UTF8Encoding($false)
    $lastError = $null
    $writeMutex = New-Object System.Threading.Mutex($false, "UsageTrayPillStateWrite")
    $hasWriteLock = $false

    try {
        try {
            $hasWriteLock = $writeMutex.WaitOne([TimeSpan]::FromSeconds(15))
        }
        catch [System.Threading.AbandonedMutexException] {
            $hasWriteLock = $true
        }
        if (-not $hasWriteLock) {
            throw "Timed out while locking UTP state."
        }

        for ($attempt = 1; $attempt -le 8; $attempt++) {
            try {
                [System.IO.File]::WriteAllText($tempPath, $json, $encoding)
                if (Test-Path -LiteralPath $script:DataPath) {
                    [System.IO.File]::Replace($tempPath, $script:DataPath, $replaceBackupPath, $true)
                    Remove-Item -LiteralPath $replaceBackupPath -Force -ErrorAction SilentlyContinue
                }
                else {
                    Move-Item -LiteralPath $tempPath -Destination $script:DataPath
                }
                return
            }
            catch {
                $lastError = $_
                Start-Sleep -Milliseconds (80 * $attempt)
            }
        }

        if ($null -ne $lastError) {
            throw $lastError
        }
    }
    finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $replaceBackupPath -Force -ErrorAction SilentlyContinue
        if ($hasWriteLock) {
            try { $writeMutex.ReleaseMutex() } catch {
            }
        }
        $writeMutex.Dispose()
    }
}

function Load-State {
    Ensure-DataDirectory

    if (-not (Test-Path -LiteralPath $script:DataPath)) {
        $state = New-DefaultState
        $script:State = Normalize-State $state
        return $script:State
    }

    try {
        $raw = Get-Content -LiteralPath $script:DataPath -Raw -ErrorAction Stop
        $state = $raw | ConvertFrom-Json -ErrorAction Stop
        $script:State = Normalize-State $state
        return $script:State
    }
    catch {
        # A read or validation failure must never overwrite the user's data.
        throw "UTP could not read its saved settings. The original file was preserved."
    }
}

function Get-DateOrNull {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $styles = [System.Globalization.DateTimeStyles]::AssumeLocal
    $culture = [System.Globalization.CultureInfo]::GetCultureInfo("nl-NL")
    $date = [DateTime]::MinValue

    if ([DateTime]::TryParse($Value, $culture, $styles, [ref]$date)) {
        return $date
    }

    if ([DateTime]::TryParse($Value, [ref]$date)) {
        return $date
    }

    return $null
}

function Format-DateForStorage {
    param([DateTime]$Value)
    return $Value.ToString("yyyy-MM-ddTHH:mm:ss")
}

function Format-UnixDateForStorage {
    param($UnixSeconds)

    if ($null -eq $UnixSeconds) {
        return ""
    }

    try {
        $date = [DateTimeOffset]::FromUnixTimeSeconds([int64]$UnixSeconds).LocalDateTime
        return Format-DateForStorage $date
    }
    catch {
        return ""
    }
}

function Format-DisplayDate {
    param($Value)

    $date = Get-DateOrNull ([string]$Value)
    if ($null -eq $date) {
        return "-"
    }

    return $date.ToString("dd-MM-yyyy HH:mm")
}

function Format-ShortDisplayDate {
    param($Value)

    $date = Get-DateOrNull ([string]$Value)
    if ($null -eq $date) {
        return "-"
    }

    if ($date.Date -eq (Get-Date).Date) {
        return $date.ToString("HH:mm")
    }

    return $date.ToString("d-M HH:mm")
}

function Format-TimeLeft {
    param($Value)

    $date = Get-DateOrNull ([string]$Value)
    if ($null -eq $date) {
        return "-"
    }

    $span = $date - (Get-Date)

    if ($span.TotalSeconds -le 0) {
        return "expired"
    }

    if ($span.TotalDays -ge 1) {
        return ("{0}d {1}h" -f [Math]::Floor($span.TotalDays), $span.Hours)
    }

    if ($span.TotalHours -ge 1) {
        return ("{0}h {1}m" -f [Math]::Floor($span.TotalHours), $span.Minutes)
    }

    return ("{0}m" -f [Math]::Max(1, [Math]::Floor($span.TotalMinutes)))
}

. (Join-Path $PSScriptRoot "OpenCodeGo.ps1")
. (Join-Path $PSScriptRoot "QwenTokenPlan.ps1")
. (Join-Path $PSScriptRoot "CollectorPolicy.ps1")
. (Join-Path $PSScriptRoot "ExternalUsageAdapters.ps1")

function Get-ResetStatus {
    param($Reset)

    if ([bool]$Reset.used) {
        return "used"
    }

    $date = Get-DateOrNull ([string]$Reset.expiresAt)
    if ($null -eq $date) {
        return "no date"
    }

    $span = $date - (Get-Date)
    if ($span.TotalSeconds -le 0) {
        return "expired"
    }

    if ($span.TotalDays -lt 3) {
        return "expiring soon"
    }

    return "active"
}

function Get-ActiveResets {
    $now = Get-Date
    return @(
        foreach ($reset in $script:State.resets) {
            $date = Get-DateOrNull ([string]$reset.expiresAt)
            if (-not [bool]$reset.used -and $null -ne $date -and $date -gt $now) {
                $reset
            }
        }
    )
}

function Get-NextReset {
    $now = Get-Date
    $active = @(
        foreach ($reset in $script:State.resets) {
            $date = Get-DateOrNull ([string]$reset.expiresAt)
            if (-not [bool]$reset.used -and $null -ne $date -and $date -gt $now) {
                [pscustomobject]@{
                    Reset = $reset
                    Date = $date
                }
            }
        }
    )

    if ($active.Count -eq 0) {
        return $null
    }

    return ($active | Sort-Object Date | Select-Object -First 1 -Wait)
}

function Get-NextLimit {
    $now = Get-Date
    $items = @(
        foreach ($limit in $script:State.limits) {
            $date = Get-DateOrNull ([string]$limit.resetAt)
            if ($null -ne $date -and $date -gt $now) {
                [pscustomobject]@{
                    Limit = $limit
                    Date = $date
                }
            }
        }
    )

    if ($items.Count -eq 0) {
        return $null
    }

    return ($items | Sort-Object Date | Select-Object -First 1 -Wait)
}

function Test-CodexAppProcess {
    param([object]$Process)

    if ($null -eq $Process) {
        return $false
    }

    $processName = ""
    if ($Process.PSObject.Properties.Name -contains "ProcessName") {
        $processName = [string]$Process.ProcessName
    }
    elseif ($Process.PSObject.Properties.Name -contains "Name") {
        $processName = [string]$Process.Name
    }

    return $processName -in @("Codex", "ChatGPT")
}

function Test-CodexRunning {
    try {
        return $null -ne (
            Get-Process -Name "Codex", "ChatGPT" -ErrorAction SilentlyContinue |
                Where-Object { Test-CodexAppProcess $_ } |
                Select-Object -First 1 -Wait
        )
    }
    catch {
        return $false
    }
}

function Get-NormalizedKeeperScriptPath {
    try {
        return [System.IO.Path]::GetFullPath([string]$script:ClaudeKeeperScriptPath).Replace("/", "\")
    }
    catch {
        return ([string]$script:ClaudeKeeperScriptPath).Replace("/", "\")
    }
}

function Test-ClaudeKeeperProcess {
    param([object]$Process)

    if ($null -eq $Process -or [string]$Process.Name -notmatch "^(powershell|pwsh)(\.exe)?$") {
        return $false
    }

    $commandLine = ([string]$Process.CommandLine).Replace("/", "\")
    if ([string]::IsNullOrWhiteSpace($commandLine)) {
        return $false
    }

    $lowerCommandLine = $commandLine.ToLowerInvariant()
    $fileIndex = $lowerCommandLine.IndexOf("-file")
    if ($fileIndex -lt 0) {
        return $false
    }

    foreach ($commandOption in @("-command", "-encodedcommand", "-enc")) {
        $commandIndex = $lowerCommandLine.IndexOf($commandOption)
        if ($commandIndex -ge 0 -and $commandIndex -lt $fileIndex) {
            return $false
        }
    }

    $escapedPath = [regex]::Escape((Get-NormalizedKeeperScriptPath))
    $tail = $commandLine.Substring($fileIndex)
    $filePattern = '(?i)^-file\s+("' + $escapedPath + '"|''' + $escapedPath + '''|' + $escapedPath + ')(?=\s|$)'
    return $tail -match $filePattern
}

function Get-ClaudeCodeProcesses {
    try {
        return @(
            Get-CimInstance Win32_Process -ErrorAction Stop |
                Where-Object {
                    $_.Name -ieq "claude.exe" -and
                    [string]$_.CommandLine -match "@anthropic-ai[\\/]+claude-code"
                }
        )
    }
    catch {
        return @()
    }
}

function Get-ClaudeKeeperProcesses {
    if ([string]::IsNullOrWhiteSpace((Get-NormalizedKeeperScriptPath))) {
        return @()
    }

    try {
        return @(
            Get-CimInstance Win32_Process -ErrorAction Stop |
                Where-Object {
                    $_.ProcessId -ne $PID -and
                    (Test-ClaudeKeeperProcess $_)
                }
        )
    }
    catch {
        return @()
    }
}

function Test-ClaudeCodeRunning {
    return @(Get-ClaudeCodeProcesses).Count -gt 0
}

function Test-ClaudeKeeperRunning {
    return @(Get-ClaudeKeeperProcesses).Count -gt 0
}

function Get-ClaudeKeeperCooldown {
    if (-not (Test-Path -LiteralPath $script:ClaudeKeeperCooldownPath)) {
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $script:ClaudeKeeperCooldownPath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            Remove-Item -LiteralPath $script:ClaudeKeeperCooldownPath -Force -ErrorAction SilentlyContinue
            return $null
        }

        $cooldown = $raw | ConvertFrom-Json -ErrorAction Stop
        $disabledUntil = [DateTime]::MinValue
        if (-not [DateTime]::TryParse([string]$cooldown.disabledUntil, [ref]$disabledUntil)) {
            Remove-Item -LiteralPath $script:ClaudeKeeperCooldownPath -Force -ErrorAction SilentlyContinue
            return $null
        }

        if ($disabledUntil -gt (Get-Date)) {
            return $cooldown
        }

        Remove-Item -LiteralPath $script:ClaudeKeeperCooldownPath -Force -ErrorAction SilentlyContinue
        return $null
    }
    catch {
        Remove-Item -LiteralPath $script:ClaudeKeeperCooldownPath -Force -ErrorAction SilentlyContinue
        return $null
    }
}

function Test-ClaudeKeeperCooldownActive {
    return $null -ne (Get-ClaudeKeeperCooldown)
}

function Clear-ClaudeKeeperCooldown {
    Remove-Item -LiteralPath $script:ClaudeKeeperCooldownPath -Force -ErrorAction SilentlyContinue
}

function Get-DescendantProcessIds {
    param([int[]]$ParentProcessIds)

    if ($null -eq $ParentProcessIds -or $ParentProcessIds.Count -eq 0) {
        return @()
    }

    try {
        $allProcesses = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    }
    catch {
        return @()
    }

    $result = @()
    $frontier = @($ParentProcessIds)
    while ($frontier.Count -gt 0) {
        $children = @($allProcesses | Where-Object { $frontier -contains [int]$_.ParentProcessId })
        $childIds = @($children | ForEach-Object { [int]$_.ProcessId })
        $newIds = @($childIds | Where-Object { $result -notcontains $_ -and $ParentProcessIds -notcontains $_ })
        if ($newIds.Count -eq 0) {
            break
        }

        $result += $newIds
        $frontier = @($newIds)
    }

    return @($result)
}

function Start-ClaudeUsageKeeper {
    if (-not [bool]$script:State.settings.keepClaudeCodeAlive) {
        return $false
    }

    if (-not (Test-Path -LiteralPath $script:ClaudeKeeperScriptPath)) {
        return $false
    }

    if ((Test-ClaudeCodeRunning) -or (Test-ClaudeKeeperRunning)) {
        return $true
    }

    if (Test-ClaudeKeeperCooldownActive) {
        return $false
    }

    try {
        if ($null -eq (Get-Command claude -ErrorAction SilentlyContinue)) {
            return $false
        }

        $powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
        $arguments = @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-WindowStyle",
            "Hidden",
            "-File",
            "`"$script:ClaudeKeeperScriptPath`"",
            "-WorkingDirectory",
            "`"$env:USERPROFILE`""
        )

        Start-Process -FilePath $powershellPath -WindowStyle Hidden -ArgumentList $arguments | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Stop-ClaudeUsageKeeper {
    $keepers = @(Get-ClaudeKeeperProcesses)
    if ($keepers.Count -eq 0) {
        return
    }

    $keeperIds = @($keepers | ForEach-Object { [int]$_.ProcessId })
    $childIds = @(Get-DescendantProcessIds -ParentProcessIds $keeperIds)
    foreach ($processId in @($childIds + $keeperIds)) {
        if ($processId -eq $PID) {
            continue
        }

        try {
            Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
        }
        catch {
        }
    }
}

function Ensure-ClaudeUsageKeeper {
    if ([bool]$script:State.settings.keepClaudeCodeAlive) {
        [void](Start-ClaudeUsageKeeper)
    }
    else {
        Stop-ClaudeUsageKeeper
    }
}

function Get-JsonLineResponse {
    param(
        [System.Diagnostics.Process]$Process,
        [int]$ExpectedId,
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $task = $Process.StandardOutput.ReadLineAsync()

    while ((Get-Date) -lt $deadline) {
        if ($Process.HasExited -and $Process.StandardOutput.EndOfStream) {
            break
        }

        $remainingMs = [Math]::Max(100, [int](($deadline - (Get-Date)).TotalMilliseconds))
        if (-not $task.Wait([Math]::Min(500, $remainingMs))) {
            continue
        }

        $line = $task.Result
        if ([string]::IsNullOrWhiteSpace($line)) {
            $task = $Process.StandardOutput.ReadLineAsync()
            continue
        }

        try {
            $message = $line | ConvertFrom-Json -ErrorAction Stop
            if ($message.PSObject.Properties.Name -contains "id" -and [int]$message.id -eq $ExpectedId) {
                return $message
            }
        }
        catch {
        }
        $task = $Process.StandardOutput.ReadLineAsync()
    }

    throw "No app-server response for request ID $ExpectedId within $TimeoutSeconds seconds."
}

function Resolve-CodexCommandPath {
    $commands = @(Get-Command -Name "codex" -All -CommandType Application -ErrorAction SilentlyContinue)
    $command = $commands | Where-Object { [System.IO.Path]::GetExtension([string]$_.Source) -in @(".cmd", ".bat") } | Select-Object -First 1 -Wait
    if ($null -eq $command) {
        $command = $commands | Where-Object { [System.IO.Path]::GetExtension([string]$_.Source) -ieq ".exe" } | Select-Object -First 1 -Wait
    }

    if ($null -eq $command -or [string]::IsNullOrWhiteSpace([string]$command.Source)) {
        throw "Neither codex.exe nor a Codex command shim was found in PATH."
    }

    $path = [System.IO.Path]::GetFullPath([string]$command.Source)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Codex command does not exist: $path"
    }
    if ($path -match '"') {
        throw "The Codex command path contains an invalid quotation mark."
    }

    return $path
}

function New-CodexAppServerStartInfo {
    param([Parameter(Mandatory = $true)][string]$CodexPath)

    $extension = [System.IO.Path]::GetExtension($CodexPath).ToLowerInvariant()
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    if ($extension -eq ".exe") {
        $psi.FileName = $CodexPath
        $psi.Arguments = "app-server --stdio"
    }
    elseif ($extension -in @(".cmd", ".bat")) {
        if ($CodexPath -match '[&|<>^%!]') {
            throw "The Codex command shim contains unsafe cmd metacharacters."
        }
        $cmdPath = Join-Path $env:SystemRoot "System32\cmd.exe"
        if (-not (Test-Path -LiteralPath $cmdPath -PathType Leaf)) {
            throw "System cmd.exe was not found."
        }
        $psi.FileName = $cmdPath
        $psi.Arguments = "/d /s /c `"`"$CodexPath`" app-server --stdio`""
    }
    else {
        throw "Unsupported Codex command type: $extension"
    }

    $psi.WorkingDirectory = $(if ($script:CollectorRepo) { $script:CollectorRepo } else { $PSScriptRoot })
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    return $psi
}

function Close-CodexConnection {
    if ($null -eq $script:CodexConnection) { return }
    $connection=$script:CodexConnection
    $script:CodexConnection=$null
    try { if(-not $connection.Process.HasExited){$connection.Process.StandardInput.Close();[void]$connection.Process.WaitForExit(200)} } catch {}
    Stop-OwnedRefreshProcess -Process $connection.Process
    try { [void]$connection.Stderr.Wait(500) } catch {}
}

function Invoke-CodexRateLimitsRead {
    try {
        if ($null -eq $script:CodexConnection -or $script:CodexConnection.Process.HasExited) {
            Close-CodexConnection
            $process=New-Object System.Diagnostics.Process
            $process.StartInfo=New-CodexAppServerStartInfo -CodexPath (Resolve-CodexCommandPath)
            if(-not (Start-UtpUsageProcess -Process $process)){throw 'Could not start Codex.'}
            $stderrDrainTask = $process.StandardError.BaseStream.CopyToAsync([System.IO.Stream]::Null)
            $script:CodexConnection=[pscustomobject]@{Process=$process;Stderr=$stderrDrainTask;NextId=1}
            $initialize=@{method='initialize';id=0;params=@{clientInfo=@{name='usage-tray-pill';version='0.3.0'}}}|ConvertTo-Json -Depth 5 -Compress
            $process.StandardInput.WriteLine($initialize)
            $process.StandardInput.Flush()
            $reply=Get-JsonLineResponse -Process $process -ExpectedId 0 -TimeoutSeconds 15
            if($null -ne $reply.error){throw 'Codex initialization failed.'}
            $process.StandardInput.WriteLine('{"method":"initialized"}')
        }
        $process=$script:CodexConnection.Process
        $id=$script:CodexConnection.NextId++
        $process.StandardInput.WriteLine((@{method='account/rateLimits/read';id=$id}|ConvertTo-Json -Compress))
        $process.StandardInput.Flush()
        $response=Get-JsonLineResponse -Process $process -ExpectedId $id -TimeoutSeconds 20
        if($null -ne $response.error){
            $usageFailure=New-Object InvalidOperationException 'Codex could not provide usage. Check your Codex sign-in.'
            $usageFailure.Data['UtpCode']=if([string]$response.error.message -match '(?i)auth|sign.in|log.in'){'auth_expired'}else{'network_error'}
            throw $usageFailure
        }
        if($null -eq $response.result){throw 'Codex returned no usage.'}
        return $response.result
    } catch { Close-CodexConnection; throw }
    finally { if(-not $script:CollectorMode){Close-CodexConnection} }
}

function Convert-LiveBucket {
    param($Bucket)

    if ($null -eq $Bucket) {
        return $null
    }

    $primary = $Bucket.primary
    $secondary = $Bucket.secondary
    $credits = $Bucket.credits
    $primaryUsed = Get-ValidUsagePercent $primary.usedPercent
    $secondaryUsed = Get-ValidUsagePercent $secondary.usedPercent

    return [pscustomobject]@{
        limitId = [string]$Bucket.limitId
        limitName = [string]$Bucket.limitName
        planType = [string]$Bucket.planType
        primaryUsedPercent = $(if ($null -ne $primaryUsed) { $primaryUsed } else { $null })
        primaryRemainingPercent = $(if ($null -ne $primaryUsed) { (100 - $primaryUsed) } else { $null })
        primaryWindowDurationMins = $(if ($null -ne $primary) { $primary.windowDurationMins } else { $null })
        primaryResetsAt = $(if ($null -ne $primary) { Format-UnixDateForStorage $primary.resetsAt } else { "" })
        secondaryUsedPercent = $(if ($null -ne $secondaryUsed) { $secondaryUsed } else { $null })
        secondaryRemainingPercent = $(if ($null -ne $secondaryUsed) { (100 - $secondaryUsed) } else { $null })
        secondaryWindowDurationMins = $(if ($null -ne $secondary) { $secondary.windowDurationMins } else { $null })
        secondaryResetsAt = $(if ($null -ne $secondary) { Format-UnixDateForStorage $secondary.resetsAt } else { "" })
        creditsBalance = $(if ($null -ne $credits -and $credits.PSObject.Properties.Name -contains "balance") { [string]$credits.balance } else { "" })
        rateLimitReachedType = [string]$Bucket.rateLimitReachedType
    }
}

function Get-ValidUsagePercent {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    try {
        $number = [double]$Value
        if ([double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt 0 -or $number -gt 100) { return $null }
        return $number
    } catch { return $null }
}

function Format-RemainingPercent {
    param($Value)
    $number=Get-ValidUsagePercent $Value
    if($null -eq $number){return '--'}
    if($number -gt 0 -and $number -lt 1){return '<1%'}
    return ('{0}%' -f [int][Math]::Floor($number))
}

function Set-QwenEnabled {
    param([bool]$Enabled)
    $script:State.settings.qwenTokenPlanEnabled=$Enabled
    if(-not $Enabled -and $script:State.settings.taskbarBadgeDefaultSource -eq 'qwen'){$script:State.settings.taskbarBadgeDefaultSource='codex'}
    Save-State
    if(-not $Enabled){Stop-QwenUsageRefresh}else{Start-QwenUsageRefresh}
    Refresh-Tray
    if($null -ne $script:RefreshMainWindow){& $script:RefreshMainWindow}
}

function Update-CodexBucketChoices {
    $box=$script:MainWindowControls.CodexBucket
    if($null -eq $box){return}
    $buckets=@($script:State.liveUsage.buckets)
    $signature=($buckets|ForEach-Object{"$($_.limitId):$($_.limitName)"}) -join '|'
    if($box.Tag -eq $signature){return}
    $box.Tag=$signature;$box.Items.Clear()
    foreach($bucket in $buckets){
        $name=if([string]::IsNullOrWhiteSpace($bucket.limitName)){$bucket.limitId}else{$bucket.limitName}
        $entry=[pscustomobject]@{Id=$bucket.limitId;Label=$name}
        [void]$box.Items.Add($entry)
        if($bucket.limitId -eq $script:State.settings.codexLimitId){$box.SelectedItem=$entry}
    }
}

function Get-LiveUsageBuckets {
    $usage = $script:State.liveUsage
    $checked = Get-DateOrNull ([string]$usage.lastCheckedAt)
    $fresh = $null -ne $checked -and ((Get-Date) - $checked).TotalMinutes -le 15 -and $checked -le (Get-Date).AddMinutes(1) -and [string]::IsNullOrWhiteSpace([string]$usage.lastError)
    foreach ($bucket in @(As-Array $usage.buckets)) {
        $copy = $bucket | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        foreach ($window in @('primary','secondary')) {
            Ensure-Property -Target $copy -Name "${window}RemainingPercent" -Value $null
            $reset = Get-DateOrNull ([string]$copy.("${window}ResetsAt"))
            if (-not $fresh -or ($null -ne $reset -and $reset -le (Get-Date))) {
                $copy.("${window}RemainingPercent") = $null
            }
        }
        $copy
    }
}

function Update-LiveUsage {
    if ($script:UsagePollInProgress) {
        return $false
    }

    $script:UsagePollInProgress = $true
    try {
        $result = Invoke-CodexRateLimitsRead
        $buckets = @()

        if ($null -ne $result.rateLimitsByLimitId) {
            foreach ($property in $result.rateLimitsByLimitId.PSObject.Properties) {
                $bucket = Convert-LiveBucket $property.Value
                if ($null -ne $bucket) {
                    $buckets += $bucket
                }
            }
        }

        if ($buckets.Count -eq 0 -and $null -ne $result.rateLimits) {
            $bucket = Convert-LiveBucket $result.rateLimits
            if ($null -ne $bucket) {
                $buckets += $bucket
            }
        }

        $mainBucket = $buckets | Where-Object { $_.limitId -eq "codex" } | Select-Object -First 1 -Wait
        if ($null -eq $mainBucket -and $buckets.Count -gt 0) {
            $mainBucket = $buckets[0]
        }

        $resetCredits = $null
        if ($null -ne $result.rateLimitResetCredits -and $result.rateLimitResetCredits.PSObject.Properties.Name -contains "availableCount") {
            $resetCredits = [int]$result.rateLimitResetCredits.availableCount
        }

        $script:State.liveUsage.source = "codex-app-server"
        $script:State.liveUsage.lastCheckedAt = Format-DateForStorage (Get-Date)
        $script:State.liveUsage.lastError = ""
        $script:State.liveUsage.lastSuccessAt = Format-DateForStorage (Get-Date)
        $script:State.liveUsage.resetCreditsAvailable = $resetCredits
        $script:State.liveUsage.buckets = @($buckets)
        $script:State.liveUsage.planType = $(if ($null -ne $mainBucket) { [string]$mainBucket.planType } else { "" })
        $script:State.liveUsage.creditsBalance = $(if ($null -ne $mainBucket) { [string]$mainBucket.creditsBalance } else { "" })
        Write-OpenCodeGoJsonAtomically -Path $script:CodexUsagePath -Value $script:State.liveUsage -MutexName 'UsageTrayPillCodexUsageWrite'
        return $true
    }
    catch {
        $script:State.liveUsage.lastCheckedAt = Format-DateForStorage (Get-Date)
        $script:State.liveUsage.lastError = $(if($_.Exception.Data['UtpCode']){[string]$_.Exception.Data['UtpCode']}else{'network_error'})
        Write-OpenCodeGoJsonAtomically -Path $script:CodexUsagePath -Value $script:State.liveUsage -MutexName 'UsageTrayPillCodexUsageWrite'
        return $false
    }
    finally {
        $script:UsagePollInProgress = $false
    }
}

function Get-MainLiveBucket {
    if ($null -eq $script:State.liveUsage -or $null -eq $script:State.liveUsage.buckets) {
        return $null
    }

    $buckets = @(Get-LiveUsageBuckets)
    $selected = [string]$script:State.settings.codexLimitId
    if ([string]::IsNullOrWhiteSpace($selected)) { $selected='codex' }
    $bucket = $buckets | Where-Object { $_.limitId -eq $selected } | Select-Object -First 1 -Wait
    if ($null -ne $bucket) {
        return $bucket
    }

    return $null
}

function Get-LiveBucketWindow {
    param([object]$Bucket, [int]$Minutes)
    if ($null -eq $Bucket) { return $null }
    foreach ($window in @('primary','secondary')) {
        if ($Bucket.("${window}WindowDurationMins") -eq $Minutes) {
            return [pscustomobject]@{remainingPercent=$Bucket.("${window}RemainingPercent");resetsAt=$Bucket.("${window}ResetsAt")}
        }
    }
    return $null
}

function Get-WeeklyBucketRemainingPercent {
    param([object]$Bucket = (Get-MainLiveBucket))
    return (Get-LiveBucketWindow -Bucket $Bucket -Minutes 10080).remainingPercent
}

function Get-EffectiveResetCount {
    if ($null -ne $script:State.liveUsage -and $null -ne $script:State.liveUsage.resetCreditsAvailable) {
        return [int]$script:State.liveUsage.resetCreditsAvailable
    }

    return @(Get-ActiveResets).Count
}

function Test-ClaudeUsageSnapshotFresh {
    param([object]$Usage)

    if ($null -eq $Usage) {
        return $false
    }

    $lastChecked = Get-DateOrNull ([string]$Usage.lastCheckedAt)
    if ($null -eq $lastChecked) {
        return $false
    }

    $maxAgeMinutes = 15
    try {
        $maxAgeMinutes = [Math]::Max(3, [int]$script:State.settings.liveUsagePollIntervalMinutes * 3)
    }
    catch {
        $maxAgeMinutes = 15
    }

    if ($lastChecked -gt (Get-Date).AddMinutes(1) -or ((Get-Date) - $lastChecked).TotalMinutes -gt $maxAgeMinutes) {
        return $false
    }

    foreach ($resetValue in @($Usage.fiveHourResetsAt, $Usage.sevenDayResetsAt)) {
        $resetDate = Get-DateOrNull ([string]$resetValue)
        if ($null -ne $resetDate -and $resetDate -lt (Get-Date).AddMinutes(-1)) {
            return $false
        }
    }

    return $true
}

function Test-ClaudeUsageNeedsDesktopFallback {
    param([object]$Usage)

    if ($null -eq $Usage) {
        return $true
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Usage.lastError)) {
        return $true
    }

    return -not (Test-ClaudeUsageSnapshotFresh $Usage)
}

function Convert-ClaudeDesktopUsageHistory {
    param([object]$History)

    $samples = @($History.samples | Sort-Object { [int64]$_.t })
    if ($samples.Count -eq 0) { return $null }
    $latest = $samples[-1]
    $checkedAt = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$latest.t).LocalDateTime
    if (((Get-Date) - $checkedAt).TotalMinutes -gt 20) { return $null }

    $limits = @()
    foreach ($definition in @(
        @{ Key = "fh"; SourceKey = "five_hour"; Label = "5h" },
        @{ Key = "sd"; SourceKey = "seven_day"; Label = "weekly" }
    )) {
        $sample = $samples | Where-Object { $_.u.PSObject.Properties.Name -contains $definition.Key -and ([DateTimeOffset]::FromUnixTimeMilliseconds([int64]$_.t).LocalDateTime -ge $checkedAt.AddMinutes(-20)) } | Select-Object -Last 1
        if ($null -eq $sample) { continue }
        $used = Get-ValidUsagePercent $sample.u.($definition.Key)
        if($null -eq $used){continue}
        $limits += [pscustomobject]@{
            key = $definition.SourceKey
            label = $definition.Label
            usedPercent = $used
            remainingPercent = 100 - $used
            resetsAt = ""
            observedAt = Format-DateForStorage ([DateTimeOffset]::FromUnixTimeMilliseconds([int64]$sample.t).LocalDateTime)
        }
    }

    $five = $limits | Where-Object { $_.key -eq "five_hour" } | Select-Object -First 1 -Wait
    $seven = $limits | Where-Object { $_.key -eq "seven_day" } | Select-Object -First 1 -Wait
    return [pscustomobject]@{
        source = "claude-desktop-plan-history"
        lastCheckedAt = Format-DateForStorage $checkedAt
        lastError = ""
        modelName = ""
        version = ""
        fiveHourUsedPercent = $(if ($five) { $five.usedPercent } else { $null })
        fiveHourRemainingPercent = $(if ($five) { $five.remainingPercent } else { $null })
        fiveHourResetsAt = ""
        sevenDayUsedPercent = $(if ($seven) { $seven.usedPercent } else { $null })
        sevenDayRemainingPercent = $(if ($seven) { $seven.remainingPercent } else { $null })
        sevenDayResetsAt = ""
        limits = @($limits)
    }
}

function Get-ClaudeDesktopUsageSnapshot {
    $packagesRoot = Join-Path $env:LOCALAPPDATA "Packages"
    $historyPath = Get-ChildItem -LiteralPath $packagesRoot -Directory -Filter "Claude_*" -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName "LocalCache\Roaming\Claude\plan-usage-history.json" } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Sort-Object { (Get-Item -LiteralPath $_).LastWriteTime } -Descending |
        Select-Object -First 1 -Wait
    if ([string]::IsNullOrWhiteSpace([string]$historyPath)) { return $null }
    try {
        $history = Get-Content -LiteralPath $historyPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        return Convert-ClaudeDesktopUsageHistory -History $history
    }
    catch { return $null }
}

function Get-ClaudeUsageSnapshot {
    $usage = $null
    if([bool]$script:State.settings.claudeControlEnabled){
        try {
            $control=Get-Content -LiteralPath $script:ClaudeControlUsagePath -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
            $controlItems=@($control.items)
            if([bool]$control.stale){
                $controlItems=@(if(Test-UtpClaudeTransientFailure $control.errorCode){Get-UtpClaudeCachedItems -Snapshot $control})
            }
            $five=@($controlItems)|Where-Object key -eq 'five_hour'|Select-Object -First 1 -Wait
            $week=@($controlItems)|Where-Object key -eq 'seven_day'|Select-Object -First 1 -Wait
            $usage=[pscustomobject]@{source='claude-code-control';lastCheckedAt=$control.lastCheckedAt;lastError=$control.lastError;errorCode=$control.errorCode;lastSuccessAt=$control.lastSuccessAt;stale=[bool]$control.stale;available=[bool]$control.available;fiveHourRemainingPercent=$five.remainingPercent;fiveHourResetsAt=$five.resetsAt;sevenDayRemainingPercent=$week.remainingPercent;sevenDayResetsAt=$week.resetsAt;limits=@($controlItems);modelName='';version=''}
        }catch{return $null}
    }
    elseif (Test-Path -LiteralPath $script:ClaudeUsagePath) {
        try {
            $raw = Get-Content -LiteralPath $script:ClaudeUsagePath -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($raw)) { $usage = $raw | ConvertFrom-Json -ErrorAction Stop }
        }
        catch { $usage = $null }
    }

    if (-not [bool]$script:State.settings.claudeControlEnabled -and (Test-ClaudeUsageNeedsDesktopFallback $usage)) {
        $desktopUsage = Get-ClaudeDesktopUsageSnapshot
        if ($null -ne $desktopUsage) { $usage = $desktopUsage }
    }

    if ($null -eq $usage) { return $null }
    try {
        $cacheAllowed=[bool]$usage.stale -and (Test-UtpClaudeTransientFailure ([string]$usage.errorCode))
        $checked = Get-DateOrNull $(if($cacheAllowed){[string]$usage.lastSuccessAt}else{[string]$usage.lastCheckedAt})
        $maxAge=if($cacheAllowed){10}else{15}
        if ($null -eq $checked -or $checked -gt (Get-Date).AddMinutes(1) -or ((Get-Date) - $checked).TotalMinutes -gt $maxAge -or (-not [string]::IsNullOrWhiteSpace([string]$usage.lastError) -and -not $cacheAllowed)) {
            $usage.fiveHourRemainingPercent = $null
            $usage.sevenDayRemainingPercent = $null
            foreach ($limit in @($usage.limits)) { $limit.remainingPercent = $null }
        }
        $now = Get-Date
        if ($null -ne (Get-DateOrNull ([string]$usage.fiveHourResetsAt)) -and (Get-DateOrNull ([string]$usage.fiveHourResetsAt)) -lt $now) { $usage.fiveHourRemainingPercent = $null }
        if ($null -ne (Get-DateOrNull ([string]$usage.sevenDayResetsAt)) -and (Get-DateOrNull ([string]$usage.sevenDayResetsAt)) -lt $now) { $usage.sevenDayRemainingPercent = $null }
        foreach ($limit in @($usage.limits)) {
            $reset = Get-DateOrNull ([string]$limit.resetsAt)
            if ($null -ne $reset -and $reset -lt $now) { $limit.remainingPercent = $null }
            $observed = Get-DateOrNull ([string]$limit.observedAt)
            if ($null -ne $observed -and ($observed -gt $now.AddMinutes(1) -or ($now - $observed).TotalMinutes -gt 15)) { $limit.remainingPercent = $null }
            if ($limit.key -eq 'five_hour') { $usage.fiveHourRemainingPercent = $limit.remainingPercent }
            if ($limit.key -eq 'seven_day') { $usage.sevenDayRemainingPercent = $limit.remainingPercent }
        }
        if($usage.source -eq 'claude-code-control'){$usage.available=($null -ne $usage.fiveHourRemainingPercent -or $null -ne $usage.sevenDayRemainingPercent)}
        return $usage
    }
    catch {
        return [pscustomobject]@{
            source = "claude-code-statusline"
            lastCheckedAt = ""
            lastError = $_.Exception.Message
            fiveHourRemainingPercent = $null
            fiveHourResetsAt = ""
            sevenDayRemainingPercent = $null
            sevenDayResetsAt = ""
            modelName = ""
            version = ""
        }
    }
}

function Write-AntigravityUsageSnapshot {
    param([Parameter(Mandatory = $true)] [object]$Usage)

    Ensure-DataDirectory
    $json = $Usage | ConvertTo-Json -Depth 6
    $tempPath = "$($script:AntigravityUsagePath).tmp-$PID"
    try {
        [System.IO.File]::WriteAllText($tempPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tempPath -Destination $script:AntigravityUsagePath -Force
    }
    finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-AntigravityUsageSnapshot {
    if (-not (Test-Path -LiteralPath $script:AntigravityUsagePath)) { return $null }
    try {
        $usage = Get-Content -LiteralPath $script:AntigravityUsagePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not [bool]$usage.available) { return $usage }
        $now = Get-Date
        $checked = Get-DateOrNull ([string]$usage.lastCheckedAt)
        if ($null -eq $checked -or $checked -gt $now.AddMinutes(1) -or ($now - $checked).TotalMinutes -gt 5) {
            $usage.available = $false
            foreach ($item in @($usage.items)) { $item.remainingPercent = $null }
        }
        foreach ($item in @($usage.items)) {
            $reset = Get-DateOrNull ([string]$item.resetsAt)
            if ($null -ne $reset -and $reset -lt $now) { $item.remainingPercent = $null }
        }
        return $usage
    }
    catch { return $null }
}

function Format-ClaudeUsageSummary {
    $usage = Get-ClaudeUsageSnapshot
    if ($null -eq $usage) {
        return ""
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$usage.lastError)) {
        return "Claude usage error: $($usage.lastError)"
    }

    $parts = @()
    if ($null -ne $usage.fiveHourRemainingPercent) {
        $parts += "Claude 5h remaining $($usage.fiveHourRemainingPercent)% reset $(Format-ShortDisplayDate $usage.fiveHourResetsAt)"
    }
    if ($null -ne $usage.sevenDayRemainingPercent) {
        $parts += "7d remaining $($usage.sevenDayRemainingPercent)% reset $(Format-ShortDisplayDate $usage.sevenDayResetsAt)"
    }

    if ($parts.Count -eq 0) {
        return ""
    }

    return ($parts -join " | ")
}

function Format-LiveUsageSummary {
    $bucket = Get-MainLiveBucket
    if ($null -eq $bucket) {
        if (-not [string]::IsNullOrWhiteSpace([string]$script:State.liveUsage.lastError)) {
            return "Live usage error: $($script:State.liveUsage.lastError)"
        }
        return "Live usage has not loaded yet"
    }

    $parts = @()
    $five = Get-LiveBucketWindow -Bucket $bucket -Minutes 300
    $week = Get-LiveBucketWindow -Bucket $bucket -Minutes 10080
    if ($null -ne $five.remainingPercent) {
        $parts += "5h remaining $($five.remainingPercent)% reset $(Format-ShortDisplayDate $five.resetsAt)"
    }
    if ($null -ne $week.remainingPercent) {
        $parts += "weekly remaining $($week.remainingPercent)% reset $(Format-ShortDisplayDate $week.resetsAt)"
    }
    if ($null -ne $script:State.liveUsage.resetCreditsAvailable) {
        $parts += "resets $($script:State.liveUsage.resetCreditsAvailable)"
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$script:State.liveUsage.creditsBalance)) {
        $parts += "credits $($script:State.liveUsage.creditsBalance)"
    }

    return ($parts -join " | ")
}

function Format-TaskbarBadgeText {
    $bucket = Get-MainLiveBucket
    if ($null -eq $bucket) {
        return "weekly --"
    }

    $secondary = "--"
    $weeklyRemaining = Get-WeeklyBucketRemainingPercent -Bucket $bucket
    if ($null -ne $weeklyRemaining) {
        $secondary = (Format-RemainingPercent $weeklyRemaining)
    }

    return "weekly $secondary"
}

function Get-TaskbarBadgeDefaultSource {
    $source = [string]$script:State.settings.taskbarBadgeDefaultSource
    if ($source -notin (Get-TaskbarBadgeSources)) {
        return "codex"
    }
    return $source
}

function Get-TaskbarBadgeSources {
    $sources = @("codex", "claude", "antigravity")
    if ($null -ne $script:State -and [bool]$script:State.settings.openCodeGoEnabled) {
        $sources += "opencodego"
    }
    if ($null -ne $script:State -and [bool]$script:State.settings.qwenTokenPlanEnabled) {
        $sources += "qwen"
    }
    return @($sources)
}

function Get-NextTaskbarBadgeSource {
    param([string]$Source)

    $sources = @(Get-TaskbarBadgeSources)
    $index = [Array]::IndexOf($sources, $Source)
    if ($index -lt 0) { return "codex" }
    return $sources[($index + 1) % $sources.Count]
}

function Get-TaskbarBadgeData {
    param([string]$Source)

    $neutralColor = if ($script:BadgeTheme -eq 'Dark') { [System.Drawing.Color]::FromArgb(196,198,208) } else { [System.Drawing.Color]::FromArgb(82,88,100) }

    if ($Source -eq "qwen") {
        $usage = Get-QwenUsageSnapshot
        $items = @()
        foreach ($definition in @(
            @{ Label = "5h"; Key = "five_hour" },
            @{ Label = "weekly"; Key = "seven_day" }
        )) {
            $remaining = $null
            if ($null -ne $usage -and [bool]$usage.available) {
                $match = @($usage.items) | Where-Object { $_.key -eq $definition.Key } | Select-Object -First 1 -Wait
                if ($null -ne $match) { $remaining = $match.remainingPercent }
            }
            $items += [pscustomobject]@{
                Label = $definition.Label
                Text = $(if ($null -ne $remaining) { (Format-RemainingPercent $remaining) } else { "--" })
                Color = $(if ($null -ne $remaining -and -not [bool]$usage.stale) { Get-PercentColor -Percent $remaining } else { $neutralColor })
            }
        }

        return [pscustomobject]@{
            Source = "qwen"
            SourceText = ""
            PrimaryPrefix = $items[0].Label
            PrimaryText = $items[0].Text
            PrimaryColor = $items[0].Color
            SecondaryPrefix = $items[1].Label
            SecondaryText = $items[1].Text
            SecondaryColor = $items[1].Color
            Items = @($items)
            Width = [Math]::Max($script:BadgeMinimumWidth, $script:BadgeHorizontalChrome + (Get-BadgeContentWidth -Items $items))
        }
    }

    if ($Source -eq "opencodego") {
        $usage = Get-OpenCodeGoUsageSnapshot
        $items = @()
        foreach ($definition in @(
            @{ Label = "5h"; Key = "five_hour" },
            @{ Label = "weekly"; Key = "seven_day" },
            @{ Label = "monthly"; Key = "monthly" }
        )) {
            $remaining = $null
            if ($null -ne $usage -and [bool]$usage.available) {
                $match = @($usage.items) | Where-Object { $_.key -eq $definition.Key } | Select-Object -First 1 -Wait
                if ($null -ne $match) { $remaining = $match.remainingPercent }
            }
            $items += [pscustomobject]@{
                Label = $definition.Label
                Text = $(if ($null -ne $remaining) { (Format-RemainingPercent $remaining) } else { "--" })
                Color = $(if ($null -ne $remaining -and -not [bool]$usage.stale) { Get-PercentColor -Percent $remaining } else { $neutralColor })
            }
        }

        return [pscustomobject]@{
            Source = "opencodego"
            SourceText = ""
            PrimaryPrefix = $items[0].Label
            PrimaryText = $items[0].Text
            PrimaryColor = $items[0].Color
            SecondaryPrefix = $items[1].Label
            SecondaryText = $items[1].Text
            SecondaryColor = $items[1].Color
            Items = @($items)
            Width = [Math]::Max($script:BadgeMinimumWidth, $script:BadgeHorizontalChrome + (Get-BadgeContentWidth -Items $items))
        }
    }

    if ($Source -eq "antigravity") {
        $usage = Get-AntigravityUsageSnapshot
        $items = @()
        if ($null -ne $usage -and [bool]$usage.available) {
            foreach ($item in @(Get-AntigravityDisplayItems $usage) | Select-Object -First 3 -Wait) {
                $remaining = $item.remainingPercent
                $items += [pscustomobject]@{
                    Label = [string]$item.label
                    Text = $(if ($null -ne $remaining) { (Format-RemainingPercent $remaining) } else { "--" })
                    Color = $(if ($null -ne $remaining -and -not [bool]$usage.stale) { Get-PercentColor -Percent $remaining } else { $neutralColor })
                }
            }
        }
        if ($items.Count -eq 0) {
            $items = @([pscustomobject]@{ Label = "usage"; Text = "--"; Color = $neutralColor })
        }

        $contentWidth = Get-BadgeContentWidth -Items $items
        return [pscustomobject]@{
            Source = "antigravity"
            SourceText = ""
            PrimaryPrefix = $items[0].Label
            PrimaryText = $items[0].Text
            PrimaryColor = $items[0].Color
            SecondaryPrefix = ""
            SecondaryText = ""
            SecondaryColor = $neutralColor
            Items = @($items)
            Width = [Math]::Max($script:BadgeMinimumWidth, $script:BadgeHorizontalChrome + $contentWidth)
        }
    }

    if ($Source -eq "claude") {
        $usage = Get-ClaudeUsageSnapshot
        $items = @()
        foreach ($definition in @(
            @{ Label = "5h"; Key = "five_hour"; Legacy = "fiveHourRemainingPercent" },
            @{ Label = "weekly"; Key = "seven_day"; Legacy = "sevenDayRemainingPercent" }
        )) {
            $remaining = $null
            if ($null -ne $usage) {
                $match = @($usage.limits) | Where-Object { $_.key -eq $definition.Key -or $_.label -eq $definition.Label } | Select-Object -First 1 -Wait
                if ($null -ne $match) { $remaining = $match.remainingPercent }
                elseif (-not [string]::IsNullOrWhiteSpace($definition.Legacy)) { $remaining = $usage.($definition.Legacy) }
            }
            $items += [pscustomobject]@{
                Label = $definition.Label
                Text = $(if ($null -ne $remaining) { (Format-RemainingPercent $remaining) } else { "--" })
                Color = $(if ($null -ne $remaining -and -not [bool]$usage.stale) { Get-PercentColor -Percent $remaining } else { $neutralColor })
            }
        }

        $cached=[bool]$usage.stale -and @($items|Where-Object {$_.Text -ne '--'}).Count -gt 0
        if($cached){$items += [pscustomobject]@{Label='cache';Text='';Color=$neutralColor}}
        $status=if($cached){'Cached '+(Get-DateOrNull $usage.lastSuccessAt).ToString('HH:mm')}elseif(@($items|Where-Object {$_.Text -ne '--'}).Count -gt 0){'Remaining allowance'}elseif(-not $script:State.settings.claudeControlEnabled){'Waiting for statusline data'}elseif($usage.errorCode -in @('auth_required','unsupported_auth_context','setup_required')){'CLI sign-in / setup required'}elseif((Get-ProviderRetrySeconds ([string]$usage.errorCode) 1) -lt 0){'Collection paused; check Details'}else{'Usage unavailable; retrying'}
        return [pscustomobject]@{
            Cached = $cached
            StatusText = $status
            Source = "claude"
            SourceText = ""
            PrimaryPrefix = $items[0].Label
            PrimaryText = $items[0].Text
            PrimaryColor = $items[0].Color
            SecondaryPrefix = $items[1].Label
            SecondaryText = $items[1].Text
            SecondaryColor = $neutralColor
            Items = @($items)
            Width = [Math]::Max($script:BadgeMinimumWidth, $script:BadgeHorizontalChrome + (Get-BadgeContentWidth -Items $items))
        }
    }

    $bucket = Get-MainLiveBucket
    $codexSecondaryText = "--"
    $codexSecondaryColor = $neutralColor
    $windowLabel = 'weekly'

    if ($null -ne $bucket) {
        $weeklyRemaining = Get-WeeklyBucketRemainingPercent -Bucket $bucket
        if($null -eq (Get-LiveBucketWindow -Bucket $bucket -Minutes 10080) -and $null -ne $bucket.primaryWindowDurationMins){
            $minutes=[double]$bucket.primaryWindowDurationMins
            $windowLabel=if($minutes -lt 60){"${minutes}m"}elseif($minutes -lt 1440){'{0}h' -f ($minutes/60)}else{'{0}d' -f ($minutes/1440)}
            $weeklyRemaining=$bucket.primaryRemainingPercent
        }
        if ($null -ne $weeklyRemaining) {
            $codexSecondaryText = (Format-RemainingPercent $weeklyRemaining)
            $codexSecondaryColor = Get-PercentColor -Percent $weeklyRemaining
        }
    }

    $codexItem = [pscustomobject]@{ Label = $windowLabel; Text = $codexSecondaryText; Color = $codexSecondaryColor }
    return [pscustomobject]@{
        Source = "codex"
        SourceText = ""
        PrimaryPrefix = $windowLabel
        PrimaryText = $codexSecondaryText
        PrimaryColor = $codexSecondaryColor
        SecondaryPrefix = ""
        SecondaryText = ""
        SecondaryColor = $neutralColor
        Items = @($codexItem)
        Width = [Math]::Max($script:BadgeMinimumWidth, $script:BadgeHorizontalChrome + (Get-BadgeContentWidth -Items @($codexItem)))
    }
}

function Get-AntigravityDisplayItems {
    param($Usage)
    foreach($group in @($Usage.items | Group-Object {if($_.family){$_.family}else{$_.key}})) {
        $known=@($group.Group | Where-Object {$null -ne $_.remainingPercent} | Sort-Object remainingPercent)
        if($known.Count -eq $group.Count -or ($known.Count -gt 0 -and $known[0].remainingPercent -eq 0)){$known|Select-Object -First 1 -Wait}
        else{$group.Group|Where-Object {$null -eq $_.remainingPercent}|Select-Object -First 1 -Wait}
    }
}

function Get-TaskbarBadgeColor {
    if ($script:BadgeTheme -ne 'Dark') { return [System.Drawing.Color]::FromArgb(250,251,253) }
    return [System.Drawing.Color]::FromArgb(32, 33, 38)
}

function Get-TaskbarBadgeBorderColor {
    if ($script:BadgeTheme -ne 'Dark') { return [System.Drawing.Color]::FromArgb(205,210,219) }
    return [System.Drawing.Color]::FromArgb(75,78,88)
}

function Get-TaskbarBadgeAccentColor {
    return [System.Drawing.Color]::FromArgb(16, 163, 127)
}

function Get-PercentColor {
    param([int]$Percent)

    if ($null -eq $Percent) {
        return [System.Drawing.Color]::FromArgb(125, 131, 140)
    }

    if ($Percent -gt 50) {
        if ($script:BadgeTheme -ne 'Dark') { return [System.Drawing.Color]::FromArgb(13,132,89) }
        return [System.Drawing.Color]::FromArgb(115, 226, 181)
    }

    if ($Percent -ge 20) {
        if ($script:BadgeTheme -ne 'Dark') { return [System.Drawing.Color]::FromArgb(142,98,10) }
        return [System.Drawing.Color]::FromArgb(246, 206, 122)
    }

    if ($script:BadgeTheme -ne 'Dark') { return [System.Drawing.Color]::FromArgb(196,45,57) }
    return [System.Drawing.Color]::FromArgb(255, 144, 153)
}

function Get-TaskbarBadgeBounds {
    param([int]$Width = 0)

    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    $bounds = $screen.Bounds
    $workArea = $screen.WorkingArea
    if ($Width -le 0) {
        $source = $(if ([string]::IsNullOrWhiteSpace([string]$script:BadgeDisplayedSource)) { Get-TaskbarBadgeDefaultSource } else { $script:BadgeDisplayedSource })
        $Width = [int](Get-TaskbarBadgeData -Source $source).Width
    }
    $width = ConvertTo-BadgePixels $Width

    $taskbarHeight = $bounds.Bottom - $workArea.Bottom
    $taskbarTop = $workArea.Top - $bounds.Top

    $trayArrowWidth = ConvertTo-BadgePixels 248
    $x = $bounds.Right - $trayArrowWidth - $width - (ConvertTo-BadgePixels 16)

    if ($taskbarHeight -gt 0) {
        $height = [Math]::Min((ConvertTo-BadgePixels 28), [Math]::Max((ConvertTo-BadgePixels 24), $taskbarHeight - (ConvertTo-BadgePixels 8)))
        $y = $workArea.Bottom + [int](($taskbarHeight - $height) / 2)
    }
    elseif ($taskbarTop -gt 0) {
        $height = [Math]::Min((ConvertTo-BadgePixels 28), [Math]::Max((ConvertTo-BadgePixels 24), $taskbarTop - (ConvertTo-BadgePixels 8)))
        $y = $bounds.Top + [int](($taskbarTop - $height) / 2)
    }
    else {
        $height = ConvertTo-BadgePixels 28
        $y = $workArea.Bottom - $height
    }

    return New-Object System.Drawing.Rectangle $x, $y, $width, $height
}

function Test-WindowCoversMonitorBounds {
    param(
        [System.Drawing.Rectangle]$WindowBounds,
        [System.Drawing.Rectangle]$MonitorBounds,
        [int]$Tolerance = 2
    )

    if ($WindowBounds.Width -le 0 -or $WindowBounds.Height -le 0 -or $MonitorBounds.Width -le 0 -or $MonitorBounds.Height -le 0) {
        return $false
    }

    return (
        $WindowBounds.Left -le ($MonitorBounds.Left + $Tolerance) -and
        $WindowBounds.Top -le ($MonitorBounds.Top + $Tolerance) -and
        $WindowBounds.Right -ge ($MonitorBounds.Right - $Tolerance) -and
        $WindowBounds.Bottom -ge ($MonitorBounds.Bottom - $Tolerance)
    )
}

function Test-WindowFullscreenState {
    param(
        [System.Drawing.Rectangle]$WindowBounds,
        [System.Drawing.Rectangle]$MonitorBounds,
        [bool]$IsMaximized
    )

    # Chromium keeps IsZoomed set while an F11/video window covers the complete monitor.
    # Geometry is authoritative; a regular maximized window stops at the taskbar work area.
    return (Test-WindowCoversMonitorBounds -WindowBounds $WindowBounds -MonitorBounds $MonitorBounds)
}

function Test-OwnTrayWindowHandle {
    param([IntPtr]$Handle)

    if ($Handle -eq [IntPtr]::Zero) {
        return $false
    }

    foreach ($form in @($script:BadgeForm, $script:MainForm)) {
        if ($null -eq $form -or $form.IsDisposed) {
            continue
        }

        try {
            if ($form.Handle -eq $Handle) {
                return $true
            }
        }
        catch {
        }
    }

    return $false
}

function Test-ForegroundWindowFullscreen {
    try {
        $handle = [UsageTrayPillNative]::GetForegroundWindow()
        if ($handle -eq [IntPtr]::Zero -or (Test-OwnTrayWindowHandle -Handle $handle)) {
            return $false
        }

        $nativeRect = New-Object UsageTrayPillNative+RECT
        if (-not [UsageTrayPillNative]::GetWindowRect($handle, [ref]$nativeRect)) {
            return $false
        }

        $width = [Math]::Max(0, $nativeRect.Right - $nativeRect.Left)
        $height = [Math]::Max(0, $nativeRect.Bottom - $nativeRect.Top)
        $windowBounds = New-Object System.Drawing.Rectangle $nativeRect.Left, $nativeRect.Top, $width, $height
        $monitorBounds = [System.Windows.Forms.Screen]::FromHandle($handle).Bounds

        return (Test-WindowFullscreenState `
            -WindowBounds $windowBounds `
            -MonitorBounds $monitorBounds `
            -IsMaximized ([UsageTrayPillNative]::IsZoomed($handle)))
    }
    catch {
        return $false
    }
}

function Get-CodexIconCandidatePaths {
    param([string]$AppDirectory)

    if ([string]::IsNullOrWhiteSpace($AppDirectory)) {
        return @()
    }

    return @(
        (Join-Path $AppDirectory "resources\chatgpt-tray-light.ico"),
        (Join-Path $AppDirectory "resources\chatgpt-tray-dark.ico"),
        (Join-Path $AppDirectory "resources\icon-chatgpt.ico"),
        (Join-Path $AppDirectory "resources\icon.ico"),
        (Join-Path $AppDirectory "resources\codex-tray.ico")
    )
}

function Get-UtpAppxInstallLocation {
    param([string[]]$PackageNames)

    if ($null -eq (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
        return $null
    }

    foreach ($packageName in @($PackageNames)) {
        try {
            $package = Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue |
                Sort-Object Version -Descending |
                Select-Object -First 1 -Wait
            if ($null -ne $package -and
                -not [string]::IsNullOrWhiteSpace([string]$package.InstallLocation) -and
                (Test-Path -LiteralPath $package.InstallLocation)) {
                return [string]$package.InstallLocation
            }
        }
        catch {
        }
    }

    return $null
}

function Get-CodexIconPath {
    try {
        $processPath = Get-Process -Name "ChatGPT", "Codex" -ErrorAction SilentlyContinue |
            Where-Object { Test-CodexAppProcess $_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.Path) } |
            Select-Object -First 1 -Wait -ExpandProperty Path

        if (-not [string]::IsNullOrWhiteSpace($processPath)) {
            $appDir = Split-Path -Parent $processPath
            foreach ($candidate in @(Get-CodexIconCandidatePaths -AppDirectory $appDir)) {
                if (Test-Path -LiteralPath $candidate) {
                    return $candidate
                }
            }
        }
    }
    catch {
    }

    $installLocation = Get-UtpAppxInstallLocation -PackageNames @("OpenAI.Codex")
    if (-not [string]::IsNullOrWhiteSpace($installLocation)) {
        $appDir = Join-Path $installLocation "app"
        foreach ($candidate in @(Get-CodexIconCandidatePaths -AppDirectory $appDir)) {
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }

        $executable = Join-Path $appDir "ChatGPT.exe"
        if (Test-Path -LiteralPath $executable) {
            return $executable
        }
    }

    try {
        $package = Get-ChildItem -Directory "C:\Program Files\WindowsApps" -Filter "OpenAI.Codex_*" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 -Wait
        if ($null -ne $package) {
            $appDir = Join-Path $package.FullName "app"
            foreach ($candidate in @(Get-CodexIconCandidatePaths -AppDirectory $appDir)) {
                if (Test-Path -LiteralPath $candidate) {
                    return $candidate
                }
            }
        }
    }
    catch {
    }

    return $null
}

function Get-ClaudeIconCandidatePaths {
    param([string]$AppDirectory)

    if ([string]::IsNullOrWhiteSpace($AppDirectory)) {
        return @()
    }

    return @(
        (Join-Path $AppDirectory "resources\Tray-Win32.ico"),
        (Join-Path $AppDirectory "resources\Tray-Win32-Dark.ico"),
        (Join-Path $AppDirectory "resources\ion-dist\images\claude_app_icon.png"),
        (Join-Path $AppDirectory "resources\ion-dist\favicon.ico")
    )
}

function Get-ClaudeIconPath {
    try {
        $processPath = Get-Process -Name "Claude" -ErrorAction SilentlyContinue |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_.Path) -and
                $_.Path -notmatch '[\\/]claude-code[\\/]'
            } |
            Select-Object -First 1 -Wait -ExpandProperty Path

        if (-not [string]::IsNullOrWhiteSpace($processPath)) {
            $appDir = Split-Path -Parent $processPath
            foreach ($candidate in @(Get-ClaudeIconCandidatePaths -AppDirectory $appDir)) {
                if (Test-Path -LiteralPath $candidate) {
                    return $candidate
                }
            }

            if (Test-Path -LiteralPath $processPath) {
                return $processPath
            }
        }
    }
    catch {
    }

    $installLocation = Get-UtpAppxInstallLocation -PackageNames @("Claude")
    if (-not [string]::IsNullOrWhiteSpace($installLocation)) {
        $appDir = Join-Path $installLocation "app"
        foreach ($candidate in @(Get-ClaudeIconCandidatePaths -AppDirectory $appDir)) {
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }

        $executable = Join-Path $appDir "Claude.exe"
        if (Test-Path -LiteralPath $executable) {
            return $executable
        }
    }

    $commonExecutables = @(
        (Join-Path $env:LOCALAPPDATA "AnthropicClaude\Claude.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Claude\Claude.exe"),
        (Join-Path $env:LOCALAPPDATA "Claude\Claude.exe")
    )
    foreach ($executable in $commonExecutables) {
        if (-not (Test-Path -LiteralPath $executable)) {
            continue
        }

        $appDir = Split-Path -Parent $executable
        foreach ($candidate in @(Get-ClaudeIconCandidatePaths -AppDirectory $appDir)) {
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }
        return $executable
    }

    try {
        $package = Get-ChildItem -Directory "C:\Program Files\WindowsApps" -Filter "Claude_*" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 -Wait
        if ($null -ne $package) {
            $appDir = Join-Path $package.FullName "app"
            foreach ($candidate in @(Get-ClaudeIconCandidatePaths -AppDirectory $appDir)) {
                if (Test-Path -LiteralPath $candidate) {
                    return $candidate
                }
            }

            $executable = Join-Path $appDir "Claude.exe"
            if (Test-Path -LiteralPath $executable) {
                return $executable
            }
        }
    }
    catch {
    }

    return $null
}

function Get-AntigravityAppPath {
    try {
        $runningPath = Get-Process -Name 'Antigravity' -ErrorAction SilentlyContinue |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.Path) } |
            Select-Object -First 1 -Wait -ExpandProperty Path
        if (-not [string]::IsNullOrWhiteSpace([string]$runningPath)) { return $runningPath }
    }
    catch {
    }

    $defaultPath = Join-Path $env:LOCALAPPDATA 'Programs\antigravity\Antigravity.exe'
    if (Test-Path -LiteralPath $defaultPath) { return $defaultPath }
    return $null
}

function Get-AntigravityBadgeIconRectangle {
    # The installed 32px icon has a 3px transparent inset on every side.
    # A 26px draw area with a 2px optical lift aligns its bottom-heavy mark with the other logos.
    return (New-Object System.Drawing.Rectangle 11, -1, 26, 26)
}

function New-BadgeLogoImage {
    param(
        [int]$Size = 22,
        [string]$Source = "codex",
        [switch]$DarkSurface
    )

    $bitmap = New-Object System.Drawing.Bitmap $Size, $Size
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $iconInset = 0
        if ($DarkSurface -and $Source -eq 'codex') {
            $disc = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(245,246,248))
            try { $graphics.FillEllipse($disc,0,0,($Size-1),($Size-1)) } finally { $disc.Dispose() }
            $iconInset = [Math]::Max(1,[int][Math]::Round($Size * 3.0 / 22))
        }

        if ($Source -eq "qwen") {
            $qwenIconPath = Join-Path $PSScriptRoot "assets\qwen-logo.png"
            if (-not (Test-Path -LiteralPath $qwenIconPath)) {
                throw "The official Qwen provider logo is missing."
            }

            $sourceImage = [System.Drawing.Image]::FromFile($qwenIconPath)
            try {
                $imageRect = New-Object System.Drawing.Rectangle 0, 0, $Size, $Size
                $graphics.DrawImage($sourceImage, $imageRect)
                $bitmap.Tag = "official:qwen"
                return $bitmap
            }
            finally {
                $sourceImage.Dispose()
            }
        }

        $iconPath = $(if ($Source -eq "antigravity") {
            Get-AntigravityAppPath
        } elseif ($Source -eq "opencodego") {
            Get-OpenCodeAppPath
        } elseif ($Source -eq "claude") {
            Get-ClaudeIconPath
        } elseif ($Source -eq "codex") {
            Get-CodexIconPath
        } else {
            $null
        })
        if (-not [string]::IsNullOrWhiteSpace($iconPath)) {
            try {
                if ([System.IO.Path]::GetExtension($iconPath) -match '^\.(png|jpg|jpeg|bmp)$') {
                    $sourceImage = [System.Drawing.Image]::FromFile($iconPath)
                    try {
                        $imageRect = New-Object System.Drawing.Rectangle $iconInset, $iconInset, ($Size-2*$iconInset), ($Size-2*$iconInset)
                        $graphics.DrawImage($sourceImage, $imageRect)
                    }
                    finally {
                        $sourceImage.Dispose()
                    }
                }
                else {
                    $icon = $(if ([System.IO.Path]::GetExtension($iconPath) -ieq ".ico") {
                        New-Object System.Drawing.Icon -ArgumentList $iconPath, $Size, $Size
                    } else {
                        [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath)
                    })
                    try {
                        $iconRect = $(if ($Source -in @("antigravity", "opencodego")) {
                            New-Object System.Drawing.Rectangle -2, -2, ($Size + 4), ($Size + 4)
                        } else {
                            New-Object System.Drawing.Rectangle $iconInset, $iconInset, ($Size-2*$iconInset), ($Size-2*$iconInset)
                        })
                        if ($Source -eq "claude" -and [System.IO.Path]::GetExtension($iconPath) -ieq ".ico") {
                            $sourceBitmap = $icon.ToBitmap()
                            try {
                                for ($x = 0; $x -lt $sourceBitmap.Width; $x++) {
                                    for ($y = 0; $y -lt $sourceBitmap.Height; $y++) {
                                        $pixel = $sourceBitmap.GetPixel($x, $y)
                                        if ($pixel.A -gt 0) {
                                            $sourceBitmap.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($pixel.A, 217, 119, 87))
                                        }
                                    }
                                }
                                $graphics.DrawImage($sourceBitmap, $iconRect)
                            }
                            finally {
                                $sourceBitmap.Dispose()
                            }
                        }
                        else {
                            $graphics.DrawIcon($icon, $iconRect)
                        }
                    }
                    finally {
                        $icon.Dispose()
                    }
                }

                $bitmap.Tag = "local:$Source"
                return $bitmap
            }
            catch {
            }
        }

        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(205, 91, 100, 114)), 1.7
        try {
            $rect = New-Object System.Drawing.Rectangle 3, 3, ($Size - 6), ($Size - 6)
            $graphics.DrawEllipse($pen, $rect)

            $fallbackText = $(if ($Source -eq "claude") { "A" } elseif ($Source -eq "opencodego") { "O" } elseif ($Source -eq "antigravity") { "G" } elseif ($Source -eq "qwen") { "Q" } else { "C" })
            $fontSize = [Math]::Max(7.0, $Size * 0.48)
            $font = New-Object System.Drawing.Font "Segoe UI Semibold", $fontSize, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
            $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(230, 76, 85, 99))
            $format = New-Object System.Drawing.StringFormat
            try {
                $format.Alignment = [System.Drawing.StringAlignment]::Center
                $format.LineAlignment = [System.Drawing.StringAlignment]::Center
                $textRect = New-Object System.Drawing.RectangleF 0, 0, $Size, $Size
                $graphics.DrawString($fallbackText, $font, $brush, $textRect, $format)
            }
            finally {
                $format.Dispose()
                $brush.Dispose()
                $font.Dispose()
            }

            $bitmap.Tag = "fallback:$Source"
            return $bitmap
        }
        finally {
            $pen.Dispose()
        }
    }
    finally {
        $graphics.Dispose()
    }
}

function New-TaskbarBadgeBitmap {
    $bitmap = [UtpPillForm]::RenderSurface($script:BadgeForm.Width, $script:BadgeForm.Height, (Get-TaskbarBadgeColor), (Get-TaskbarBadgeBorderColor))
    try {
        [UtpPillForm]::DrawViewport($bitmap, $script:BadgeTextViewport)
        [UtpPillForm]::DrawViewport($bitmap, $script:BadgeLogoViewport)
        return $bitmap
    } catch { $bitmap.Dispose(); throw }
}

function Present-TaskbarBadge {
    if ($null -eq $script:BadgeForm -or $script:BadgeForm.IsDisposed) { return }
    $bitmap = New-TaskbarBadgeBitmap
    try { $script:BadgeForm.Present($bitmap) } finally { $bitmap.Dispose() }
}

function Set-BadgeWindowStyle {
    if ($null -eq $script:BadgeForm -or $script:BadgeForm.IsDisposed) {
        return
    }

    $GWL_EXSTYLE = -20
    $WS_EX_TOPMOST = 0x00000008
    $WS_EX_TOOLWINDOW = 0x00000080
    $WS_EX_NOACTIVATE = 0x08000000

    $handle = $script:BadgeForm.Handle
    if ($handle -eq [IntPtr]::Zero) {
        return
    }

    $current = [UsageTrayPillNative]::GetWindowLongPtr($handle, $GWL_EXSTYLE).ToInt64()
    $next = $current -bor $WS_EX_TOPMOST -bor $WS_EX_TOOLWINDOW -bor $WS_EX_NOACTIVATE
    if ($next -ne $current) {
        [void][UsageTrayPillNative]::SetWindowLongPtr($handle, $GWL_EXSTYLE, ([IntPtr]$next))
    }
}

function Set-BadgeTopMostNoActivate {
    if ($null -eq $script:BadgeForm -or $script:BadgeForm.IsDisposed) {
        return
    }

    if (-not [bool]$script:State.settings.showTaskbarBadge) {
        return
    }

    $handle = $script:BadgeForm.Handle
    if ($handle -eq [IntPtr]::Zero) {
        return
    }

    $SW_SHOWNOACTIVATE = 4
    [void][UsageTrayPillNative]::ShowWindow($handle, $SW_SHOWNOACTIVATE)

    if ($script:BadgeAnimating) {
        $rect = $script:BadgeForm.Bounds
    }
    else {
        $rect = Get-TaskbarBadgeBounds
    }
    $HWND_TOPMOST = [IntPtr](-1)
    $SWP_NOACTIVATE = 0x0010
    $SWP_SHOWWINDOW = 0x0040
    $SWP_NOOWNERZORDER = 0x0200
    $flags = [uint32]($SWP_NOACTIVATE -bor $SWP_SHOWWINDOW -bor $SWP_NOOWNERZORDER)

    [void][UsageTrayPillNative]::SetWindowPos($handle, $HWND_TOPMOST, $rect.X, $rect.Y, $rect.Width, $rect.Height, $flags)
}

function Test-TaskbarBadgeOccluded {
    if ($null -eq $script:BadgeForm -or $script:BadgeForm.IsDisposed -or -not $script:BadgeForm.Visible) {
        return $false
    }

    $bounds = $script:BadgeForm.Bounds
    if ($bounds.Width -le 0 -or $bounds.Height -le 0) {
        return $false
    }

    $point = New-Object UsageTrayPillNative+POINT
    $point.X = $bounds.Left + [int]($bounds.Width / 2)
    $point.Y = $bounds.Top + [int]($bounds.Height / 2)
    $windowAtCenter = [UsageTrayPillNative]::WindowFromPoint($point)
    if ($windowAtCenter -eq [IntPtr]::Zero) {
        return $false
    }

    $GA_ROOT = 2
    $rootWindow = [UsageTrayPillNative]::GetAncestor($windowAtCenter, $GA_ROOT)
    return ($rootWindow -ne $script:BadgeForm.Handle)
}

function Hide-TaskbarBadge {
    if ($null -ne $script:BadgeForm -and -not $script:BadgeForm.IsDisposed -and $script:BadgeForm.Visible) {
        $script:BadgeForm.Hide()
    }
}

function Dispose-TaskbarBadge {
    foreach ($picture in @($script:BadgeLogo, $script:BadgeLogoNext)) {
        if ($null -ne $picture -and $null -ne $picture.Image) { $picture.Image.Dispose(); $picture.Image = $null }
    }
    foreach ($viewport in @($script:BadgeLogoViewport, $script:BadgeTextViewport)) {
        if ($null -ne $viewport) { $viewport.Dispose() }
    }
    if ($null -ne $script:BadgeToolTip) { $script:BadgeToolTip.Dispose(); $script:BadgeToolTip = $null }
    if ($null -ne $script:BadgeForm) {
        try {
            if ($null -ne $script:BadgeAnimationTimer) {
                $script:BadgeAnimationTimer.Stop()
                $script:BadgeAnimationTimer.Dispose()
                $script:BadgeAnimationTimer = $null
            }
            $script:BadgeForm.Close()
            $script:BadgeForm.Dispose()
        }
        catch {
        }
        $script:BadgeForm = $null
        $script:BadgeLogoViewport = $null
        $script:BadgeLogo = $null
        $script:BadgeLogoNext = $null
        $script:BadgeTextViewport = $null
        $script:BadgeCurrentRow = $null
        $script:BadgeNextRow = $null
        $script:BadgeSourceLabel = $null
        $script:BadgePrimaryPrefix = $null
        $script:BadgePrimaryValue = $null
        $script:BadgeSeparator = $null
        $script:BadgeSecondaryPrefix = $null
        $script:BadgeSecondaryValue = $null
        $script:BadgeNextSourceLabel = $null
        $script:BadgeNextPrimaryPrefix = $null
        $script:BadgeNextPrimaryValue = $null
        $script:BadgeNextSeparator = $null
        $script:BadgeNextSecondaryPrefix = $null
        $script:BadgeNextSecondaryValue = $null
        $script:BadgeDisplayedSource = ""
        $script:BadgeRenderSignature = ""
        $script:BadgeLastOcclusionRestoreAt = $null
        $script:BadgeHovering = $false
        $script:BadgeAnimating = $false
        $script:BadgePendingSource = ""
    }
}

function New-BadgeRowLabel {
    param(
        [int]$X,
        [int]$Width,
        [System.Drawing.ContentAlignment]$Align,
        [float]$FontSize,
        [bool]$Bold,
        [System.Drawing.Color]$ForeColor,
        [System.Drawing.Color]$BackColor,
        [string]$Text = ""
    )

    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point (ConvertTo-BadgePixels $X), 0
    $label.Size = New-Object System.Drawing.Size (ConvertTo-BadgePixels $Width), (ConvertTo-BadgePixels 28)
    $label.TextAlign = $Align
    $label.ForeColor = $ForeColor
    $label.Font = New-BadgeFont -PointSize $FontSize -Bold $Bold
    $label.BackColor = $BackColor
    $label.Text = $Text
    $label.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $label
}

function New-BadgeRow {
    param(
        [int]$Y,
        [System.Drawing.Color]$BackColor
    )

    $row = New-Object System.Windows.Forms.Panel
    $row.Location = New-Object System.Drawing.Point 0, (ConvertTo-BadgePixels $Y)
    $row.Size = New-Object System.Drawing.Size (ConvertTo-BadgePixels 270), (ConvertTo-BadgePixels 28)
    $row.BackColor = $BackColor
    $row.Cursor = [System.Windows.Forms.Cursors]::Hand
    Enable-ControlDoubleBuffering -Control $row

    $source = New-BadgeRowLabel -X 0 -Width 0 -Align ([System.Drawing.ContentAlignment]::MiddleRight) -FontSize $script:BadgeLabelFontSize -Bold $true -ForeColor $BackColor -BackColor $BackColor -Text ""
    $primaryPrefix = New-BadgeRowLabel -X 0 -Width 0 -Align ([System.Drawing.ContentAlignment]::MiddleLeft) -FontSize $script:BadgeValueFontSize -Bold $true -ForeColor ([System.Drawing.Color]::FromArgb(120, 120, 120)) -BackColor $BackColor -Text ""
    $primaryValue = New-BadgeRowLabel -X 0 -Width 0 -Align ([System.Drawing.ContentAlignment]::MiddleRight) -FontSize $script:BadgeLabelFontSize -Bold $true -ForeColor $BackColor -BackColor $BackColor -Text ""
    $separator = New-BadgeRowLabel -X 0 -Width 0 -Align ([System.Drawing.ContentAlignment]::MiddleLeft) -FontSize $script:BadgeValueFontSize -Bold $true -ForeColor $BackColor -BackColor $BackColor -Text ""
    $secondaryPrefix = New-BadgeRowLabel -X 0 -Width 0 -Align ([System.Drawing.ContentAlignment]::MiddleRight) -FontSize $script:BadgeLabelFontSize -Bold $true -ForeColor $BackColor -BackColor $BackColor -Text ""
    $secondaryValue = New-BadgeRowLabel -X 0 -Width 0 -Align ([System.Drawing.ContentAlignment]::MiddleLeft) -FontSize $script:BadgeValueFontSize -Bold $true -ForeColor $BackColor -BackColor $BackColor -Text ""

    foreach ($ctrl in @($source, $primaryPrefix, $primaryValue, $separator, $secondaryPrefix, $secondaryValue)) {
        $ctrl.Add_MouseUp({
            param($eventSource, $eventData)
            Invoke-TaskbarBadgeMouseUp -EventArgs $eventData
        })
        $row.Controls.Add($ctrl)
    }

    return [pscustomobject]@{
        Panel = $row
        Source = $source
        PrimaryPrefix = $primaryPrefix
        PrimaryValue = $primaryValue
        Separator = $separator
        SecondaryPrefix = $secondaryPrefix
        SecondaryValue = $secondaryValue
    }
}

function Set-BadgePictureBoxImage {
    param(
        [System.Windows.Forms.PictureBox]$PictureBox,
        [string]$Source
    )

    if ($null -eq $PictureBox) {
        return
    }

    $imageKey = "$Source|$script:BadgeTheme"
    if ([string]$PictureBox.Tag -eq $imageKey -and $null -ne $PictureBox.Image -and $PictureBox.Image.Width -eq $PictureBox.Width) {
        return
    }

    $oldImage = $PictureBox.Image
    $PictureBox.Image = New-BadgeLogoImage -Size $PictureBox.Width -Source $Source -DarkSurface:($script:BadgeTheme -eq 'Dark')
    $PictureBox.Tag = $imageKey
    if ($null -ne $oldImage) {
        $oldImage.Dispose()
    }
}

function Paint-TaskbarBadgeLogo {
    param($Graphics)

    if ($null -eq $Graphics) {
        return
    }

    $source = $script:BadgeDisplayedSource
    if ([string]::IsNullOrWhiteSpace([string]$source)) {
        $source = Get-TaskbarBadgeDefaultSource
    }

    if ($source -eq 'antigravity') {
        $appPath = Get-AntigravityAppPath
        if ([string]::IsNullOrWhiteSpace([string]$appPath)) { return }
        try {
            $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($appPath)
            try {
                $logicalRect = Get-AntigravityBadgeIconRectangle
                $iconRect = New-Object System.Drawing.Rectangle `
                    (ConvertTo-BadgePixels $logicalRect.X), `
                    (ConvertTo-BadgePixels $logicalRect.Y), `
                    (ConvertTo-BadgePixels $logicalRect.Width), `
                    (ConvertTo-BadgePixels $logicalRect.Height)
                $Graphics.DrawIcon($icon, $iconRect)
            }
            finally { $icon.Dispose() }
        }
        catch {
        }
        return
    }

    try {
        $Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $Graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $image = New-BadgeLogoImage -Size 22 -Source $source
        try {
            $rect = New-Object System.Drawing.Rectangle `
                (ConvertTo-BadgePixels 13), `
                (ConvertTo-BadgePixels 3), `
                (ConvertTo-BadgePixels 22), `
                (ConvertTo-BadgePixels 22)
            $Graphics.DrawImage($image, $rect)
        }
        finally {
            $image.Dispose()
        }
    }
    catch {
    }
}

function Set-BadgeRowContent {
    param(
        [object]$Row,
        [object]$Data
    )

    if ($null -eq $Row -or $null -eq $Data) {
        return
    }

    $controls = @($Row.Source, $Row.PrimaryPrefix, $Row.PrimaryValue, $Row.Separator, $Row.SecondaryPrefix, $Row.SecondaryValue)
    $items = @($Data.Items)
    $x = 0
    $labelValueGap = ConvertTo-BadgePixels $script:BadgeLabelValueGap
    $itemGap = ConvertTo-BadgePixels $script:BadgeItemGap
    for ($index = 0; $index -lt 3; $index++) {
        $labelControl = $controls[$index * 2]
        $valueControl = $controls[($index * 2) + 1]
        if ($index -lt $items.Count) {
            $item = $items[$index]
            if ($index -gt 0) {
                $x += $itemGap
            }
            $labelWidth = Get-BadgeLabelWidth -Text ([string]$item.Label)
            $labelControl.Location = New-Object System.Drawing.Point $x, 0
            $labelControl.Width = ConvertTo-BadgePixels $labelWidth
            $labelControl.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
            $labelControl.BackColor = Get-TaskbarBadgeColor
            $labelControl.ForeColor = if ($script:BadgeTheme -eq 'Dark') { [System.Drawing.Color]::FromArgb(224,226,233) } else { [System.Drawing.Color]::FromArgb(52,56,64) }
            $labelControl.Text = $item.Label
            $x = $labelControl.Right + $labelValueGap
            $valueControl.Location = New-Object System.Drawing.Point $x, 0
            $valueControl.Width = ConvertTo-BadgePixels $script:BadgeValueWidth
            $valueControl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
            $valueControl.BackColor = Get-TaskbarBadgeColor
            $valueControl.ForeColor = $item.Color
            $valueControl.Text = $item.Text
            $x = $valueControl.Right
        }
        else {
            $labelControl.Text = ""
            $labelControl.Width = 0
            $valueControl.Text = ""
            $valueControl.Width = 0
        }
    }
    $Row.Panel.Width = [Math]::Max($x, [Math]::Max((ConvertTo-BadgePixels 110), (ConvertTo-BadgePixels ([int]$Data.Width - $script:BadgeHorizontalChrome))))
}

function Set-TaskbarBadgeWidth {
    param([int]$Width)

    if ($null -eq $script:BadgeForm -or $script:BadgeForm.IsDisposed) { return }
    $rect = Get-TaskbarBadgeBounds -Width $Width
    $widthChanged = $script:BadgeForm.Width -ne $rect.Width
    if (-not $script:BadgeForm.Bounds.Equals($rect)) {
        $script:BadgeForm.Bounds = $rect
    }
    $textWidth = [Math]::Max((ConvertTo-BadgePixels 110), $rect.Width - (ConvertTo-BadgePixels $script:BadgeHorizontalChrome))
    if ($null -ne $script:BadgeTextViewport) {
        $script:BadgeTextViewport.Location = New-Object System.Drawing.Point (ConvertTo-BadgePixels $script:BadgeTextLeft), 1
        $script:BadgeTextViewport.Width = $textWidth
    }
    foreach ($row in @($script:BadgeCurrentRow, $script:BadgeNextRow)) { if ($null -ne $row) { $row.Width = $textWidth } }
    if ($widthChanged) {
        $script:BadgeForm.Invalidate($true)
    }
}

function Set-TaskbarBadgeLayout {
    param([object]$Data)
    if ($null -eq $Data) { return }
    Set-TaskbarBadgeWidth -Width ([int]$Data.Width)
}

function Set-BadgeTextYOffset {
    param([int]$Offset)

    $rowHeight = ConvertTo-BadgePixels 26
    if ($null -ne $script:BadgeTextViewport -and -not $script:BadgeTextViewport.IsDisposed) {
        $rowHeight = [Math]::Max(1, $script:BadgeTextViewport.Height)
    }

    if ($null -ne $script:BadgeCurrentRow) {
        $script:BadgeCurrentRow.Location = New-Object System.Drawing.Point 0, $Offset
    }
    if ($null -ne $script:BadgeLogo) {
        $script:BadgeLogo.Location = New-Object System.Drawing.Point 0, $Offset
    }
    if ($null -ne $script:BadgeNextRow) {
        $script:BadgeNextRow.Location = New-Object System.Drawing.Point 0, -$rowHeight
    }
    if ($null -ne $script:BadgeLogoNext) {
        $script:BadgeLogoNext.Location = Get-HiddenBadgeLogoLocation
    }
}

function Get-TaskbarBadgeRenderSignature {
    param([Parameter(Mandatory = $true)] [object]$Data)

    $parts = @([string]$Data.Source, [string]$Data.Width, $script:BadgeTheme)
    foreach ($item in @($Data.Items)) {
        $color = 0
        if ($null -ne $item.Color) {
            try { $color = $item.Color.ToArgb() } catch {
            }
        }
        $parts += "{0}={1}:{2}" -f [string]$item.Label, [string]$item.Text, $color
    }
    return ($parts -join "|")
}

function Set-TaskbarBadgeContent {
    param(
        [string]$Source,
        [object]$Data = $null
    )

    if ($null -eq $Data) {
        $Data = Get-TaskbarBadgeData -Source $Source
    }
    Set-TaskbarBadgeLayout -Data $Data
    Set-BadgeRowContent -Row ([pscustomobject]@{
        Panel = $script:BadgeCurrentRow
        Source = $script:BadgeSourceLabel
        PrimaryPrefix = $script:BadgePrimaryPrefix
        PrimaryValue = $script:BadgePrimaryValue
        Separator = $script:BadgeSeparator
        SecondaryPrefix = $script:BadgeSecondaryPrefix
        SecondaryValue = $script:BadgeSecondaryValue
    }) -Data $Data
    Set-BadgePictureBoxImage -PictureBox $script:BadgeLogo -Source $Data.Source
    Set-BadgeTextYOffset -Offset 0
    $script:BadgeDisplayedSource = $Data.Source
    $script:BadgeRenderSignature = Get-TaskbarBadgeRenderSignature -Data $Data
    Update-BadgeToolTip -Source $Source
    Present-TaskbarBadge
    if ($null -ne $script:BadgeForm -and -not $script:BadgeForm.IsDisposed) {
        $script:BadgeForm.Invalidate()
    }
}

function Get-ProviderStatusMessage {
    param([string]$Source)
    $names = @{codex='ChatGPT / Codex';claude='Claude';antigravity='Antigravity';opencodego='OpenCode Go';qwen='Qwen Token Plan'}
    $name = $names[$Source]
    if ($script:ProviderRefreshes.ContainsKey($Source)) { return "$name - Refreshing..." }
    if ($script:ProviderRefreshErrors.ContainsKey($Source)) { return "$name - $($script:ProviderRefreshErrors[$Source])" }
    $usage = switch ($Source) {
        'codex' { $script:State.liveUsage }
        'claude' { Get-ClaudeUsageSnapshot }
        'antigravity' { Get-AntigravityUsageSnapshot }
        'opencodego' { Get-OpenCodeGoUsageSnapshot }
        'qwen' { Get-QwenUsageSnapshot }
    }
    if ($null -eq $usage) { return "$name - No usage data yet" }
    if ([string]$usage.lastError -eq 'auth_expired') { return "$name - Session expired. Right-click > Set up $name to sign in again." }
    if ([bool]$usage.stale -and [bool]$usage.available) { return "$name - Cached values from $(Format-DisplayDate $usage.lastSuccessAt)" }
    if (-not [string]::IsNullOrWhiteSpace([string]$usage.lastError)) { return "$name - Unable to refresh. Right-click > Refresh now." }
    $checked = Get-DateOrNull ([string]$usage.lastCheckedAt)
    $maxAge = if ($Source -eq 'antigravity') { 5 } else { 15 }
    if ($null -eq $checked -or ((Get-Date) - $checked).TotalMinutes -gt $maxAge) {
        if ($Source -eq 'claude' -and -not $script:State.settings.claudeControlEnabled) { return "$name - Usage is out of date. Open Claude Code or Claude Desktop to update it." }
        return "$name - Usage is out of date. Right-click > Refresh now."
    }
    return "$name - Updated $(Format-DisplayDate $usage.lastCheckedAt)"
}

function Update-BadgeToolTip {
    param([string]$Source)
    if ($null -ne $script:BadgeToolTip) { $script:BadgeToolTip.Dispose(); $script:BadgeToolTip=$null }
    if ($null -ne $script:BadgeForm -and -not $script:BadgeForm.IsDisposed) {
        $script:BadgeForm.AccessibleName=Get-ProviderStatusMessage -Source $Source
    }
}

function Test-MouseOverTaskbarBadge {
    if ($null -eq $script:BadgeForm -or $script:BadgeForm.IsDisposed) {
        return $false
    }

    return $script:BadgeForm.Bounds.Contains([System.Windows.Forms.Control]::MousePosition)
}

function Update-BadgeSlideAnimation {
    if (-not $script:BadgeAnimating -or $null -eq $script:BadgeForm -or $script:BadgeForm.IsDisposed) {
        if ($null -ne $script:BadgeAnimationTimer) {
            $script:BadgeAnimationTimer.Stop()
        }
        return
    }

    $durationMs = $script:BadgeAnimationDurationMs
    $elapsedMs = $script:BadgeAnimationStartedAt.Elapsed.TotalMilliseconds
    $progress = [Math]::Min(1, [Math]::Max(0, $elapsedMs / $durationMs))
    $ease = Get-BadgeTransitionEase -Progress $progress
    $rowHeight = $(if ($null -ne $script:BadgeTextViewport) { [Math]::Max(1, $script:BadgeTextViewport.Height) } else { [Math]::Max(1, $script:BadgeForm.Height - 2) })
    $logoHeight = ConvertTo-BadgePixels 22
    $currentWidth = [int][Math]::Round(
        $script:BadgeAnimationStartWidth +
        (($script:BadgeAnimationTargetWidth - $script:BadgeAnimationStartWidth) * $ease),
        0
    )
    Set-TaskbarBadgeWidth -Width $currentWidth

    if ($null -ne $script:BadgeCurrentRow) {
        $script:BadgeCurrentRow.Location = New-Object System.Drawing.Point 0, ([int]($rowHeight * $ease))
    }
    if ($null -ne $script:BadgeNextRow) {
        $script:BadgeNextRow.Location = New-Object System.Drawing.Point 0, ([int](-$rowHeight + ($rowHeight * $ease)))
    }
    if ($null -ne $script:BadgeLogo) {
        $script:BadgeLogo.Location = New-Object System.Drawing.Point 0, ([int]($logoHeight * $ease))
    }
    if ($null -ne $script:BadgeLogoNext) {
        $script:BadgeLogoNext.Location = New-Object System.Drawing.Point 0, ([int](-$logoHeight + ($logoHeight * $ease)))
    }
    Present-TaskbarBadge

    if ($progress -ge 1) {
        Set-TaskbarBadgeContent -Source $script:BadgeAnimationTargetSource
        if ($null -ne $script:BadgeNextRow) {
            $script:BadgeNextRow.Location = New-Object System.Drawing.Point 0, -$rowHeight
        }
        if ($null -ne $script:BadgeLogoNext) {
            $script:BadgeLogoNext.Location = New-Object System.Drawing.Point 0, -$logoHeight
        }
        $script:BadgeAnimating = $false
        if ($null -ne $script:BadgeAnimationTimer) {
            $script:BadgeAnimationTimer.Stop()
        }
        $pending = $script:BadgePendingSource
        $script:BadgePendingSource = ""
        if (-not [string]::IsNullOrWhiteSpace($pending) -and $pending -ne $script:BadgeDisplayedSource) { Start-BadgeSlideToSource -Source $pending }
    }
}

function Start-BadgeSlideToSource {
    param([string]$Source)

    if ($Source -notin (Get-TaskbarBadgeSources)) {
        $Source = "codex"
    }

    if ($script:BadgeDisplayedSource -eq $Source -and -not $script:BadgeAnimating) {
        Set-TaskbarBadgeContent -Source $Source
        Set-BadgeTextYOffset -Offset 0
        return
    }

    if ($script:BadgeAnimating) {
        $script:BadgePendingSource = $Source
        return
    }
    if (-not [System.Windows.Forms.SystemInformation]::IsMenuAnimationEnabled) {
        Set-TaskbarBadgeContent -Source $Source
        return
    }
    $targetData = Get-TaskbarBadgeData -Source $Source
    if ($null -ne $script:BadgeNextRow) {
        Set-BadgeRowContent -Row ([pscustomobject]@{
            Panel = $script:BadgeNextRow
            Source = $script:BadgeNextSourceLabel
            PrimaryPrefix = $script:BadgeNextPrimaryPrefix
            PrimaryValue = $script:BadgeNextPrimaryValue
            Separator = $script:BadgeNextSeparator
            SecondaryPrefix = $script:BadgeNextSecondaryPrefix
            SecondaryValue = $script:BadgeNextSecondaryValue
        }) -Data $targetData
        $nextRowHeight = $(if ($null -ne $script:BadgeTextViewport) { [Math]::Max(1, $script:BadgeTextViewport.Height) } else { [Math]::Max(1, $script:BadgeForm.Height - 2) })
        $script:BadgeNextRow.Location = New-Object System.Drawing.Point 0, -$nextRowHeight
    }
    if ($null -ne $script:BadgeLogoNext) {
        Set-BadgePictureBoxImage -PictureBox $script:BadgeLogoNext -Source $Source
        $script:BadgeLogoNext.Location = Get-HiddenBadgeLogoLocation
    }
    Set-BadgeTextYOffset -Offset 0

    if ($null -eq $script:BadgeAnimationTimer) {
        $script:BadgeAnimationTimer = New-Object System.Windows.Forms.Timer
        $script:BadgeAnimationTimer.Interval = 16
        $script:BadgeAnimationTimer.Add_Tick({ Update-BadgeSlideAnimation })
    }

    $script:BadgeAnimationTargetSource = $Source
    $script:BadgeAnimationStartWidth = [int][Math]::Round($script:BadgeForm.Width / $script:BadgeDpiScale, 0)
    $script:BadgeAnimationTargetWidth = [int]$targetData.Width
    $script:BadgeAnimationStartedAt = [Diagnostics.Stopwatch]::StartNew()
    $script:BadgeAnimationHalfUpdated = $false
    $script:BadgeAnimating = $true
    $script:BadgeAnimationTimer.Start()
}

function Toggle-TaskbarBadgeDefaultSource {
    $next = Get-NextTaskbarBadgeSource (Get-TaskbarBadgeDefaultSource)
    $script:State.settings.taskbarBadgeDefaultSource = $next
    $script:PendingStateSave = $true
    $script:BadgeHovering = $false
    Start-BadgeSlideToSource -Source $next
}

function Invoke-TaskbarBadgeMouseUp {
    param([Parameter(Mandatory = $true)] [System.Windows.Forms.MouseEventArgs]$EventArgs)

    if ($EventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        if ($null -ne $script:NotifyIcon -and $null -ne $script:NotifyIcon.ContextMenuStrip) {
            $script:NotifyIcon.ContextMenuStrip.Show([System.Windows.Forms.Control]::MousePosition)
        }
        return
    }
    if ($EventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        Toggle-TaskbarBadgeDefaultSource
    }
}

function Ensure-TaskbarBadge {
    if (-not [bool]$script:State.settings.showTaskbarBadge) {
        Hide-TaskbarBadge
        return
    }

    if ($null -eq $script:BadgeForm -or $script:BadgeForm.IsDisposed) {
        $badge = New-Object UtpPillForm
        $badge.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
        $badge.Text = "Usage Tray Pill"
        $badge.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
        $badge.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
        $badge.ShowInTaskbar = $false
        $badge.ShowIcon = $false
        $badge.Cursor = [System.Windows.Forms.Cursors]::Hand
        $badge.TopMost = $false
        $badge.BackColor = Get-TaskbarBadgeColor
        $badge.Bounds = Get-TaskbarBadgeBounds
        Enable-ControlDoubleBuffering -Control $badge
        $logoViewport = New-Object System.Windows.Forms.Panel
        $logoViewport.Location = Get-BadgeLogoViewportLocation -BadgeHeight $badge.Height
        $logoViewport.Size = New-Object System.Drawing.Size (ConvertTo-BadgePixels 22), (ConvertTo-BadgePixels 22)
        $logoViewport.BackColor = $badge.BackColor
        $logoViewport.Cursor = [System.Windows.Forms.Cursors]::Hand
        $logoViewport.Visible = $true
        Enable-ControlDoubleBuffering -Control $logoViewport
        $logoViewport.Add_MouseUp({
            param($eventSource, $eventData)
            Invoke-TaskbarBadgeMouseUp -EventArgs $eventData
        })
        # Layout controls are offscreen metadata; the visible window is one alpha bitmap.

        $logoNext = New-Object System.Windows.Forms.PictureBox
        $logoNext.Location = Get-HiddenBadgeLogoLocation
        $logoNext.Size = New-Object System.Drawing.Size (ConvertTo-BadgePixels 22), (ConvertTo-BadgePixels 22)
        $logoNext.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
        $logoNext.BackColor = $badge.BackColor
        $logoNext.Cursor = [System.Windows.Forms.Cursors]::Hand
        $logoNext.Image = $null
        $logoNext.Add_MouseUp({
            param($eventSource, $eventData)
            Invoke-TaskbarBadgeMouseUp -EventArgs $eventData
        })
        $logoViewport.Controls.Add($logoNext)

        $logo = New-Object System.Windows.Forms.PictureBox
        $logo.Location = New-Object System.Drawing.Point 0, 0
        $logo.Size = New-Object System.Drawing.Size (ConvertTo-BadgePixels 22), (ConvertTo-BadgePixels 22)
        $logo.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
        $logo.BackColor = $badge.BackColor
        $logo.Cursor = [System.Windows.Forms.Cursors]::Hand
        $logo.Image = $null
        $logo.Add_MouseUp({
            param($eventSource, $eventData)
            Invoke-TaskbarBadgeMouseUp -EventArgs $eventData
        })
        $logoViewport.Controls.Add($logo)

        $textViewport = New-Object System.Windows.Forms.Panel
        $textViewport.Location = New-Object System.Drawing.Point (ConvertTo-BadgePixels $script:BadgeTextLeft), 1
        $textViewport.Size = New-Object System.Drawing.Size (ConvertTo-BadgePixels 110), ([Math]::Max(1, (ConvertTo-BadgePixels 28) - 2))
        $textViewport.BackColor = $badge.BackColor
        $textViewport.Cursor = [System.Windows.Forms.Cursors]::Hand
        Enable-ControlDoubleBuffering -Control $textViewport
        $textViewport.Add_MouseUp({
            param($eventSource, $eventData)
            Invoke-TaskbarBadgeMouseUp -EventArgs $eventData
        })


        $nextRow = New-BadgeRow -Y -28 -BackColor $badge.BackColor
        $currentRow = New-BadgeRow -Y 0 -BackColor $badge.BackColor
        $textViewport.Controls.Add($nextRow.Panel)
        $textViewport.Controls.Add($currentRow.Panel)

        $sourceLabel = $currentRow.Source
        $primaryPrefix = $currentRow.PrimaryPrefix
        $primaryValue = $currentRow.PrimaryValue
        $separator = $currentRow.Separator
        $secondaryPrefix = $currentRow.SecondaryPrefix
        $secondaryValue = $currentRow.SecondaryValue

        $badge.Add_MouseUp({
            param($eventSource, $eventData)
            Invoke-TaskbarBadgeMouseUp -EventArgs $eventData
        })
        $script:BadgeForm = $badge
        $script:BadgeLogoViewport = $logoViewport
        $script:BadgeLogo = $logo
        $script:BadgeLogoNext = $logoNext
        $script:BadgeTextViewport = $textViewport
        $script:BadgeCurrentRow = $currentRow.Panel
        $script:BadgeNextRow = $nextRow.Panel
        $script:BadgeSourceLabel = $sourceLabel
        $script:BadgePrimaryPrefix = $primaryPrefix
        $script:BadgePrimaryValue = $primaryValue
        $script:BadgeSeparator = $separator
        $script:BadgeSecondaryPrefix = $secondaryPrefix
        $script:BadgeSecondaryValue = $secondaryValue
        $script:BadgeNextSourceLabel = $nextRow.Source
        $script:BadgeNextPrimaryPrefix = $nextRow.PrimaryPrefix
        $script:BadgeNextPrimaryValue = $nextRow.PrimaryValue
        $script:BadgeNextSeparator = $nextRow.Separator
        $script:BadgeNextSecondaryPrefix = $nextRow.SecondaryPrefix
        $script:BadgeNextSecondaryValue = $nextRow.SecondaryValue

        [void]$script:BadgeForm.Handle
        Set-BadgeWindowStyle
    }
}

function Test-TaskbarBadgeShouldHide {
    if(-not [bool]$script:State.settings.hideTaskbarBadgeInFullscreen){
        if($null -ne $script:BadgeVisibility){$script:BadgeVisibility.Reset($false)}
        return $false
    }
    if($null -eq $script:BadgeVisibility){$script:BadgeVisibility=New-Object UtpBadgeVisibility}
    $monitor=[Windows.Forms.Screen]::PrimaryScreen.Bounds
    $pill=if($null -ne $script:BadgeForm -and -not $script:BadgeForm.IsDisposed){$script:BadgeForm.Bounds}else{Get-TaskbarBadgeBounds}
    $handle=if($null -ne $script:BadgeForm -and -not $script:BadgeForm.IsDisposed){$script:BadgeForm.Handle}else{[IntPtr]::Zero}
    return $script:BadgeVisibility.Update([UtpBadgeVisibility]::ReadHideCandidate($monitor,$pill,$handle))
}

function Refresh-TaskbarBadge {
    param([switch]$GeometryOnly)

    # An invalidated render must survive an early return while the pill is hidden.
    $geometryOnlyMode = [bool]$GeometryOnly -and -not [string]::IsNullOrWhiteSpace($script:BadgeRenderSignature)
    $theme = Get-SystemTrayIconTheme
    if ($script:BadgeTheme -ne $theme) {
        $script:BadgeTheme = $theme
        $script:BadgeRenderSignature = ''
        $geometryOnlyMode = $false
        if ($script:BadgeAnimating) {
            $script:BadgeAnimationTimer.Stop()
            $script:BadgeAnimating = $false
            $script:BadgePendingSource = ''
        }
    }
    if (-not [bool]$script:State.settings.showTaskbarBadge) {
        $script:BadgeRenderSignature = ''
        Hide-TaskbarBadge
        return
    }

    if (Test-TaskbarBadgeShouldHide) {
        $script:BadgeRenderSignature = ''
        Hide-TaskbarBadge
        return
    }

    if ($null -ne $script:BadgeForm -and -not $script:BadgeForm.IsDisposed -and (Set-BadgeDpiScaleFromWindow -Form $script:BadgeForm)) {
        Dispose-TaskbarBadge
    }

    $badgeNeededCreation = ($null -eq $script:BadgeForm -or $script:BadgeForm.IsDisposed)
    Ensure-TaskbarBadge
    if ($badgeNeededCreation) {
        $geometryOnlyMode = $false
    }

    if ($null -eq $script:BadgeForm -or $script:BadgeForm.IsDisposed) {
        return
    }

    $targetSource = $(if ([string]::IsNullOrWhiteSpace([string]$script:BadgeDisplayedSource)) {
        Get-TaskbarBadgeDefaultSource
    } else {
        $script:BadgeDisplayedSource
    })
    $targetData = $null
    $targetSignature = $script:BadgeRenderSignature
    if (-not $geometryOnlyMode) {
        $targetSource = Get-TaskbarBadgeDefaultSource
        $targetData = Get-TaskbarBadgeData -Source $targetSource
        $targetSignature = Get-TaskbarBadgeRenderSignature -Data $targetData
        Update-BadgeToolTip -Source $targetSource
    }
    $logicalWidth = [Math]::Max(1, [int][Math]::Round($script:BadgeForm.Width / $script:BadgeDpiScale, 0))
    if ($null -ne $targetData) {
        $logicalWidth = [int]$targetData.Width
    }
    $rect = $(if ($script:BadgeAnimating) {
        $script:BadgeForm.Bounds
    } else {
        Get-TaskbarBadgeBounds -Width $logicalWidth
    })
    $boundsChanged = -not $script:BadgeForm.Bounds.Equals($rect)
    if ($boundsChanged) {
        $script:BadgeForm.Bounds = $rect
    }

    $badgeColor = Get-TaskbarBadgeColor
    if ($script:BadgeForm.BackColor.ToArgb() -ne $badgeColor.ToArgb()) {
        $script:BadgeForm.BackColor = $badgeColor
    }

    if ($null -ne $script:BadgeLogoViewport) {
        $logoLocation = Get-BadgeLogoViewportLocation -BadgeHeight $script:BadgeForm.Height
        if (-not $script:BadgeLogoViewport.Location.Equals($logoLocation)) {
            $script:BadgeLogoViewport.Location = $logoLocation
        }
        if ($script:BadgeLogoViewport.BackColor.ToArgb() -ne $badgeColor.ToArgb()) {
            $script:BadgeLogoViewport.BackColor = $badgeColor
        }
    }
    foreach ($logoCtrl in @($script:BadgeLogo, $script:BadgeLogoNext)) {
        if ($null -ne $logoCtrl -and $logoCtrl.BackColor.ToArgb() -ne $badgeColor.ToArgb()) {
            $logoCtrl.BackColor = $badgeColor
        }
    }

    $badgeH = $script:BadgeForm.Height
    $badgeContentH = [Math]::Max(1, $badgeH - 2)
    if ($null -ne $script:BadgeTextViewport) {
        if ($script:BadgeTextViewport.Top -ne 1) {
            $script:BadgeTextViewport.Top = 1
        }
        if ($script:BadgeTextViewport.Height -ne $badgeContentH) {
            $script:BadgeTextViewport.Height = $badgeContentH
        }
        if ($script:BadgeTextViewport.BackColor.ToArgb() -ne $badgeColor.ToArgb()) {
            $script:BadgeTextViewport.BackColor = $badgeColor
        }
    }
    foreach ($rowCtrl in @($script:BadgeCurrentRow, $script:BadgeNextRow)) {
        if ($null -ne $rowCtrl) {
            if ($rowCtrl.Height -ne $badgeContentH) {
                $rowCtrl.Height = $badgeContentH
            }
            if ($rowCtrl.BackColor.ToArgb() -ne $badgeColor.ToArgb()) {
                $rowCtrl.BackColor = $badgeColor
            }
        }
    }

    $allLabels = @($script:BadgeSourceLabel, $script:BadgePrimaryPrefix, $script:BadgePrimaryValue, $script:BadgeSeparator, $script:BadgeSecondaryPrefix, $script:BadgeSecondaryValue, $script:BadgeNextSourceLabel, $script:BadgeNextPrimaryPrefix, $script:BadgeNextPrimaryValue, $script:BadgeNextSeparator, $script:BadgeNextSecondaryPrefix, $script:BadgeNextSecondaryValue)
    foreach ($ctrl in $allLabels) {
        if ($null -ne $ctrl) {
            if ($ctrl.Height -ne $badgeContentH) {
                $ctrl.Height = $badgeContentH
            }
            if ($ctrl.BackColor.ToArgb() -ne $badgeColor.ToArgb()) {
                $ctrl.BackColor = $badgeColor
            }
        }
    }

    if (-not $geometryOnlyMode -and -not $script:BadgeAnimating) {
        if ($script:BadgeDisplayedSource -ne $targetSource -or $script:BadgeRenderSignature -ne $targetSignature) {
            Set-TaskbarBadgeContent -Source $targetSource -Data $targetData
        }
    }

    if ($boundsChanged) { Present-TaskbarBadge }

    $wasVisible = $script:BadgeForm.Visible
    if (-not $wasVisible) {
        $script:BadgeForm.Show()
        Set-BadgeWindowStyle
    }
    $restoreOccludedBadge = $false
    if (-not $script:TrayMenuOpen -and (Test-TaskbarBadgeOccluded)) {
        $restoreOccludedBadge = (
            $null -eq $script:BadgeLastOcclusionRestoreAt -or
            ((Get-Date) - $script:BadgeLastOcclusionRestoreAt).TotalSeconds -ge 5
        )
    }
    if (-not $wasVisible -or $boundsChanged -or $restoreOccludedBadge) {
        Set-BadgeTopMostNoActivate
        if ($restoreOccludedBadge) {
            $script:BadgeLastOcclusionRestoreAt = Get-Date
        }
    }
}

function Limit-Text {
    param(
        [string]$Text,
        [int]$MaxLength
    )

    if ($null -eq $Text) {
        return ""
    }

    if ($Text.Length -le $MaxLength) {
        return $Text
    }

    if ($MaxLength -le 3) {
        return $Text.Substring(0, $MaxLength)
    }

    return $Text.Substring(0, $MaxLength - 3) + "..."
}

function Get-StatusSnapshot {
    $activeResets = @(Get-ActiveResets)
    $effectiveResetCount = Get-EffectiveResetCount
    $nextReset = Get-NextReset
    $nextLimit = Get-NextLimit
    $codexRunning = Test-CodexRunning
    $claudeCodeRunning = Test-ClaudeCodeRunning
    $claudeKeeperRunning = Test-ClaudeKeeperRunning
    $level = "none"

    if ($effectiveResetCount -gt 0) {
        $level = "active"
    }

    if ($null -ne $nextReset) {
        $span = $nextReset.Date - (Get-Date)
        if ($span.TotalDays -lt 3) {
            $level = "soon"
        }
    }

    return [pscustomobject]@{
        ActiveResetCount = $effectiveResetCount
        ManualActiveResetCount = $activeResets.Count
        NextReset = $nextReset
        NextLimit = $nextLimit
        CodexRunning = $codexRunning
        ClaudeCodeRunning = $claudeCodeRunning
        ClaudeKeeperRunning = $claudeKeeperRunning
        ClaudeKeeperEnabled = [bool]$script:State.settings.keepClaudeCodeAlive
        Level = $level
    }
}

function Get-TrayIconPath {
    param(
        [ValidateSet("Light", "Dark")]
        [string]$Theme = "Light"
    )

    $path = Join-Path $PSScriptRoot ("assets\tray-icon-" + $Theme.ToLowerInvariant() + ".ico")
    if (Test-Path -LiteralPath $path) {
        return $path
    }

    return $null
}

function Get-TrayIconImagePath {
    param(
        [ValidateSet("Light", "Dark")]
        [string]$Theme = "Light"
    )

    $path = Join-Path $PSScriptRoot ("assets\tray-icon-" + $Theme.ToLowerInvariant() + ".png")
    if (Test-Path -LiteralPath $path) {
        return $path
    }

    return $null
}

function Get-SystemTrayIconTheme {
    try {
        $theme = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -ErrorAction Stop
        if ([int]$theme.SystemUsesLightTheme -eq 0) {
            return "Dark"
        }
    }
    catch {
    }

    return "Light"
}

function New-TrayIcon {
    param(
        [int]$Count,
        [string]$Level,
        [ValidateSet("Light", "Dark")]
        [string]$Theme = (Get-SystemTrayIconTheme)
    )

    $assetPath = Get-TrayIconImagePath -Theme $Theme
    if (-not [string]::IsNullOrWhiteSpace($assetPath)) {
        try {
            $source = New-Object System.Drawing.Bitmap $assetPath
            $bitmap = New-Object System.Drawing.Bitmap 32, 32
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.DrawImage($source, 0, 0, 32, 32)
            $handle = $bitmap.GetHicon()
            $icon = [System.Drawing.Icon]::FromHandle($handle)
            $clone = $icon.Clone()

            [void][UsageTrayPillNative]::DestroyIcon($handle)
            $icon.Dispose()
            $graphics.Dispose()
            $bitmap.Dispose()
            $source.Dispose()
            return $clone
        }
        catch {
        }
    }

    $bitmap = New-Object System.Drawing.Bitmap 32, 32
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $fill = [System.Drawing.Color]::FromArgb(90, 90, 90)
    if ($Level -eq "active") {
        $fill = [System.Drawing.Color]::FromArgb(36, 140, 82)
    }
    elseif ($Level -eq "soon") {
        $fill = [System.Drawing.Color]::FromArgb(218, 133, 34)
    }

    $brush = New-Object System.Drawing.SolidBrush $fill
    $graphics.FillEllipse($brush, 2, 2, 28, 28)

    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(245, 245, 245)), 2
    $graphics.DrawEllipse($pen, 2, 2, 28, 28)

    $text = [string]$Count
    if ($Count -gt 9) {
        $text = "9+"
    }

    $fontSize = 12
    if ($text.Length -gt 1) {
        $fontSize = 9
    }

    $font = New-Object System.Drawing.Font "Segoe UI", $fontSize, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
    $textBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center
    $rect = New-Object System.Drawing.RectangleF 0, 1, 32, 30
    $graphics.DrawString($text, $font, $textBrush, $rect, $format)

    $handle = $bitmap.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($handle)
    $clone = $icon.Clone()

    [void][UsageTrayPillNative]::DestroyIcon($handle)
    $format.Dispose()
    $textBrush.Dispose()
    $font.Dispose()
    $pen.Dispose()
    $brush.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()

    return $clone
}

function Get-TrayIconRenderSignature {
    param(
        [Parameter(Mandatory = $true)] [object]$Snapshot,
        [ValidateSet("Light", "Dark")]
        [string]$Theme = (Get-SystemTrayIconTheme)
    )

    $assetPath = Get-TrayIconImagePath -Theme $Theme
    if (-not [string]::IsNullOrWhiteSpace($assetPath)) {
        $assetVersion = ""
        try { $assetVersion = (Get-Item -LiteralPath $assetPath).LastWriteTimeUtc.Ticks } catch {
        }
        return "asset|$Theme|$assetVersion"
    }
    return "generated|$Theme|$($Snapshot.ActiveResetCount)|$($Snapshot.Level)"
}

function Get-TooltipText {
    param($Snapshot)

    $parts = @()
    $parts += "Codex: " + ($(if ($Snapshot.CodexRunning) { "active" } else { "inactive" }))
    $parts += "Resets: $($Snapshot.ActiveResetCount)"

    $liveSummary = Format-LiveUsageSummary
    if ($liveSummary -and $liveSummary -ne "Live usage has not loaded yet") {
        $parts += $liveSummary
    }
    $claudeSummary = Format-ClaudeUsageSummary
    if ($claudeSummary) {
        $parts += $claudeSummary
    }
    elseif ($null -ne $Snapshot.NextReset) {
        $parts += "Next reset: $(Format-ShortDisplayDate $Snapshot.NextReset.Reset.expiresAt)"
    }

    return Limit-Text -Text ($parts -join " | ") -MaxLength 63
}

function Refresh-Tray {
    if ($null -eq $script:NotifyIcon) {
        return
    }

    $snapshot = Get-StatusSnapshot
    $theme = Get-SystemTrayIconTheme
    $iconSignature = Get-TrayIconRenderSignature -Snapshot $snapshot -Theme $theme
    $tooltipText = Get-TooltipText $snapshot
    $shouldBeVisible = (-not [bool]$script:State.settings.showOnlyWhenCodexRuns) -or $snapshot.CodexRunning

    if (-not $script:TrayMenuOpen) {
        if ($null -eq $script:NotifyIcon.Icon -or $script:TrayIconSignature -ne $iconSignature) {
            $newIcon = New-TrayIcon -Count $snapshot.ActiveResetCount -Level $snapshot.Level -Theme $theme
            $oldIcon = $script:NotifyIcon.Icon
            $script:NotifyIcon.Icon = $newIcon
            $script:TrayIconSignature = $iconSignature
            if ($null -ne $oldIcon) {
                $oldIcon.Dispose()
            }
        }
        if ($script:TrayTooltipText -ne $tooltipText) {
            $script:NotifyIcon.Text = $tooltipText
            $script:TrayTooltipText = $tooltipText
        }
        if ($script:NotifyIcon.Visible -ne $shouldBeVisible) {
            $script:NotifyIcon.Visible = $shouldBeVisible
        }
    }
    Refresh-TaskbarBadge
}

function Show-Message {
    param(
        [string]$Text,
        [string]$Title = $script:AppName,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )

    [void][System.Windows.Forms.MessageBox]::Show($Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Icon)
}

function Show-ResetDialog {
    param($Existing)

    $isEdit = $null -ne $Existing
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $(if ($isEdit) { "Edit reset" } else { "Add reset" })
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size 430, 270

    $labelLabel = New-Object System.Windows.Forms.Label
    $labelLabel.Text = "Name"
    $labelLabel.Location = New-Object System.Drawing.Point 16, 18
    $labelLabel.AutoSize = $true
    $form.Controls.Add($labelLabel)

    $nameBox = New-Object System.Windows.Forms.TextBox
    $nameBox.Location = New-Object System.Drawing.Point 120, 14
    $nameBox.Size = New-Object System.Drawing.Size 290, 24
    $nameBox.Text = $(if ($isEdit) { [string]$Existing.label } else { "Banked reset" })
    $form.Controls.Add($nameBox)

    $dateLabel = New-Object System.Windows.Forms.Label
    $dateLabel.Text = "Expires at"
    $dateLabel.Location = New-Object System.Drawing.Point 16, 57
    $dateLabel.AutoSize = $true
    $form.Controls.Add($dateLabel)

    $datePicker = New-Object System.Windows.Forms.DateTimePicker
    $datePicker.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
    $datePicker.CustomFormat = "dd-MM-yyyy HH:mm"
    $datePicker.ShowUpDown = $true
    $datePicker.Location = New-Object System.Drawing.Point 120, 53
    $datePicker.Size = New-Object System.Drawing.Size 190, 24

    $existingDate = $null
    if ($isEdit) {
        $existingDate = Get-DateOrNull ([string]$Existing.expiresAt)
    }
    if ($null -eq $existingDate) {
        $existingDate = (Get-Date).AddDays(30)
    }
    $datePicker.Value = $existingDate
    $form.Controls.Add($datePicker)

    $usedCheck = New-Object System.Windows.Forms.CheckBox
    $usedCheck.Text = "Used"
    $usedCheck.Location = New-Object System.Drawing.Point 120, 88
    $usedCheck.AutoSize = $true
    $usedCheck.Checked = $(if ($isEdit) { [bool]$Existing.used } else { $false })
    $form.Controls.Add($usedCheck)

    $notesLabel = New-Object System.Windows.Forms.Label
    $notesLabel.Text = "Notes"
    $notesLabel.Location = New-Object System.Drawing.Point 16, 122
    $notesLabel.AutoSize = $true
    $form.Controls.Add($notesLabel)

    $notesBox = New-Object System.Windows.Forms.TextBox
    $notesBox.Location = New-Object System.Drawing.Point 120, 118
    $notesBox.Size = New-Object System.Drawing.Size 290, 80
    $notesBox.Multiline = $true
    $notesBox.ScrollBars = "Vertical"
    $notesBox.Text = $(if ($isEdit) { [string]$Existing.notes } else { "" })
    $form.Controls.Add($notesBox)

    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Text = "Save"
    $saveButton.Location = New-Object System.Drawing.Point 242, 222
    $saveButton.Size = New-Object System.Drawing.Size 80, 28
    $saveButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $saveButton
    $form.Controls.Add($saveButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Location = New-Object System.Drawing.Point 330, 222
    $cancelButton.Size = New-Object System.Drawing.Size 80, 28
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton = $cancelButton
    $form.Controls.Add($cancelButton)

    $result = $form.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        $form.Dispose()
        return $null
    }

    $item = [pscustomobject]@{
        id = $(if ($isEdit) { [string]$Existing.id } else { New-Id })
        label = $nameBox.Text.Trim()
        expiresAt = Format-DateForStorage $datePicker.Value
        used = $usedCheck.Checked
        notes = $notesBox.Text.Trim()
    }

    if ([string]::IsNullOrWhiteSpace($item.label)) {
        $item.label = "Banked reset"
    }

    $form.Dispose()
    return $item
}

function Show-LimitDialog {
    param($Existing)

    $isEdit = $null -ne $Existing
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $(if ($isEdit) { "Edit limit" } else { "Add limit" })
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size 480, 340

    $nameLabel = New-Object System.Windows.Forms.Label
    $nameLabel.Text = "Name"
    $nameLabel.Location = New-Object System.Drawing.Point 16, 18
    $nameLabel.AutoSize = $true
    $form.Controls.Add($nameLabel)

    $nameBox = New-Object System.Windows.Forms.TextBox
    $nameBox.Location = New-Object System.Drawing.Point 136, 14
    $nameBox.Size = New-Object System.Drawing.Size 320, 24
    $nameBox.Text = $(if ($isEdit) { [string]$Existing.name } else { "GPT/Codex limit" })
    $form.Controls.Add($nameBox)

    $allowanceLabel = New-Object System.Windows.Forms.Label
    $allowanceLabel.Text = "Allowance"
    $allowanceLabel.Location = New-Object System.Drawing.Point 16, 57
    $allowanceLabel.AutoSize = $true
    $form.Controls.Add($allowanceLabel)

    $allowanceBox = New-Object System.Windows.Forms.TextBox
    $allowanceBox.Location = New-Object System.Drawing.Point 136, 53
    $allowanceBox.Size = New-Object System.Drawing.Size 320, 24
    $allowanceBox.Text = $(if ($isEdit) { [string]$Existing.allowance } else { "" })
    $form.Controls.Add($allowanceBox)

    $remainingLabel = New-Object System.Windows.Forms.Label
    $remainingLabel.Text = "Status/remaining"
    $remainingLabel.Location = New-Object System.Drawing.Point 16, 96
    $remainingLabel.AutoSize = $true
    $form.Controls.Add($remainingLabel)

    $remainingBox = New-Object System.Windows.Forms.TextBox
    $remainingBox.Location = New-Object System.Drawing.Point 136, 92
    $remainingBox.Size = New-Object System.Drawing.Size 320, 24
    $remainingBox.Text = $(if ($isEdit) { [string]$Existing.remaining } else { "" })
    $form.Controls.Add($remainingBox)

    $resetCheck = New-Object System.Windows.Forms.CheckBox
    $resetCheck.Text = "Has reset date"
    $resetCheck.Location = New-Object System.Drawing.Point 136, 130
    $resetCheck.AutoSize = $true
    $form.Controls.Add($resetCheck)

    $datePicker = New-Object System.Windows.Forms.DateTimePicker
    $datePicker.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
    $datePicker.CustomFormat = "dd-MM-yyyy HH:mm"
    $datePicker.ShowUpDown = $true
    $datePicker.Location = New-Object System.Drawing.Point 136, 160
    $datePicker.Size = New-Object System.Drawing.Size 190, 24
    $form.Controls.Add($datePicker)

    $existingDate = $null
    if ($isEdit) {
        $existingDate = Get-DateOrNull ([string]$Existing.resetAt)
    }
    if ($null -eq $existingDate) {
        $existingDate = (Get-Date).AddHours(3)
        $resetCheck.Checked = $false
    }
    else {
        $resetCheck.Checked = $true
    }
    $datePicker.Value = $existingDate
    $datePicker.Enabled = $resetCheck.Checked
    $resetCheck.Add_CheckedChanged({
        $datePicker.Enabled = $resetCheck.Checked
    })

    $notesLabel = New-Object System.Windows.Forms.Label
    $notesLabel.Text = "Notes"
    $notesLabel.Location = New-Object System.Drawing.Point 16, 202
    $notesLabel.AutoSize = $true
    $form.Controls.Add($notesLabel)

    $notesBox = New-Object System.Windows.Forms.TextBox
    $notesBox.Location = New-Object System.Drawing.Point 136, 198
    $notesBox.Size = New-Object System.Drawing.Size 320, 76
    $notesBox.Multiline = $true
    $notesBox.ScrollBars = "Vertical"
    $notesBox.Text = $(if ($isEdit) { [string]$Existing.notes } else { "" })
    $form.Controls.Add($notesBox)

    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Text = "Save"
    $saveButton.Location = New-Object System.Drawing.Point 288, 294
    $saveButton.Size = New-Object System.Drawing.Size 80, 28
    $saveButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $saveButton
    $form.Controls.Add($saveButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Location = New-Object System.Drawing.Point 376, 294
    $cancelButton.Size = New-Object System.Drawing.Size 80, 28
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton = $cancelButton
    $form.Controls.Add($cancelButton)

    $result = $form.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        $form.Dispose()
        return $null
    }

    $item = [pscustomobject]@{
        id = $(if ($isEdit) { [string]$Existing.id } else { New-Id })
        name = $nameBox.Text.Trim()
        allowance = $allowanceBox.Text.Trim()
        remaining = $remainingBox.Text.Trim()
        resetAt = $(if ($resetCheck.Checked) { Format-DateForStorage $datePicker.Value } else { "" })
        notes = $notesBox.Text.Trim()
    }

    if ([string]::IsNullOrWhiteSpace($item.name)) {
        $item.name = "Limit"
    }

    $form.Dispose()
    return $item
}

function Replace-ItemById {
    param(
        [array]$Items,
        [string]$Id,
        [object]$NewItem
    )

    $result = @()
    foreach ($item in $Items) {
        if ([string]$item.id -eq $Id) {
            $result += $NewItem
        }
        else {
            $result += $item
        }
    }

    return $result
}

function Remove-ItemById {
    param(
        [array]$Items,
        [string]$Id
    )

    return @($Items | Where-Object { [string]$_.id -ne $Id })
}

function New-ListView {
    param(
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height
    )

    $list = New-Object System.Windows.Forms.ListView
    $list.Location = New-Object System.Drawing.Point $X, $Y
    $list.Size = New-Object System.Drawing.Size $Width, $Height
    $list.View = [System.Windows.Forms.View]::Details
    $list.FullRowSelect = $true
    $list.GridLines = $false
    $list.MultiSelect = $false
    $list.HideSelection = $false
    $list.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $list.ShowItemToolTips = $true
    $list.BackColor = [System.Drawing.Color]::White
    $list.ForeColor = [System.Drawing.Color]::FromArgb(36, 39, 46)
    $list.Font = New-Object System.Drawing.Font "Segoe UI", 10
    $list.HeaderStyle = [System.Windows.Forms.ColumnHeaderStyle]::Nonclickable
    return $list
}

function Set-MainWindowButtonStyle {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Button]$Button,

        [ValidateSet("Primary", "Secondary")]
        [string]$Kind = "Secondary"
    )

    $Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Button.UseVisualStyleBackColor = $false
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $Button.Font = New-Object System.Drawing.Font "Segoe UI Semibold", 9
    $Button.FlatAppearance.BorderSize = 0
    $Button.Padding = New-Object System.Windows.Forms.Padding 8, 0, 8, 0

    if ($Kind -eq "Primary") {
        $Button.BackColor = [System.Drawing.Color]::FromArgb(208, 34, 121)
        $Button.ForeColor = [System.Drawing.Color]::White
        $Button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(208, 34, 121)
        $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(187, 28, 107)
        $Button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(166, 23, 94)
        return
    }

    $Button.BackColor = [System.Drawing.Color]::FromArgb(239, 238, 235)
    $Button.ForeColor = [System.Drawing.Color]::FromArgb(45, 48, 56)
    $Button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(205, 209, 216)
    $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(245, 246, 248)
    $Button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(235, 237, 241)
}

function Set-MainWindowListRows {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.ListView]$List
    )

    for ($index = 0; $index -lt $List.Items.Count; $index++) {
        $item = $List.Items[$index]
        $item.ToolTipText = (@($item.SubItems | ForEach-Object { $_.Text }) -join " | ")
        $item.BackColor = if (($index % 2) -eq 0) {
            [System.Drawing.Color]::White
        }
        else {
            [System.Drawing.Color]::FromArgb(249, 250, 252)
        }
    }
}

function Get-SelectedTag {
    param([System.Windows.Forms.ListView]$List)

    if ($List.SelectedItems.Count -eq 0) {
        return $null
    }

    return $List.SelectedItems[0].Tag
}

function Hide-MainWindow {
    if ($null -ne $script:MainForm -and -not $script:MainForm.IsDisposed) {
        $script:MainForm.Hide()
        $script:MainForm.Visible = $false
    }
}

function Exit-TrayApp {
    $script:ExitRequested = $true
    $script:RefreshMainWindow = $null

    if ($null -ne $script:NotifyIcon) {
        $script:NotifyIcon.Visible = $false
        $script:NotifyIcon.Dispose()
        $script:NotifyIcon = $null
    }

    Dispose-TaskbarBadge
    Stop-ClaudeUsageKeeper
    Stop-OpenCodeGoUsageRefresh
    Stop-QwenUsageRefresh

    if ($null -ne $script:MainForm -and -not $script:MainForm.IsDisposed) {
        $script:MainForm.Close()
        $script:MainForm.Dispose()
        $script:MainForm = $null
    }

    [System.Windows.Forms.Application]::ExitThread()
    [System.Windows.Forms.Application]::Exit()
}

function Update-MainWindow {
    $form = $script:MainForm
    $header = $script:MainWindowControls.Header
    $liveStatusLabel = $script:MainWindowControls.Status
    $refreshLiveButton = $script:MainWindowControls.Refresh
    $liveList = $script:MainWindowControls.Live
    $resetsList = $script:MainWindowControls.Resets
    $limitsList = $script:MainWindowControls.Limits

        if ($null -eq $form -or $form.IsDisposed) {
            return
        }

        if ($null -ne $script:MainWindowControls.QwenEnabled) { $script:MainWindowControls.QwenEnabled.Checked=[bool]$script:State.settings.qwenTokenPlanEnabled }
        if($null -ne $script:MainWindowControls.FullscreenHide){$script:MainWindowControls.FullscreenHide.Checked=[bool]$script:State.settings.hideTaskbarBadgeInFullscreen}
        if($null -ne $script:MainWindowControls.ClaudeControl){$script:MainWindowControls.ClaudeControl.Checked=[bool]$script:State.settings.claudeControlEnabled}
        Update-CodexBucketChoices
        $refreshing = $script:ProviderRefreshes.Count -gt 0
        $refreshLiveButton.Enabled = -not $refreshing
        $refreshLiveButton.Text = $(if ($refreshing) { "Refreshing..." } else { "Refresh now" })
        $selections = @{}
        foreach ($list in @($liveList, $resetsList, $limitsList)) {
            $selections[$list.GetHashCode()] = @($list.SelectedItems | ForEach-Object { if ($null -ne $_.Tag.id) { [string]$_.Tag.id } else { $_.Text } })
            $list.BeginUpdate()
        }
        try {
        $snapshot = Get-StatusSnapshot
        $codexState = $(if ($snapshot.CodexRunning) { "active" } else { "inactive" })
        $resetLabel = $(if ($snapshot.ActiveResetCount -eq 1) { "active reset" } else { "active resets" })
        $header.Text = "Your AI usage, in one quiet place.    $($snapshot.ActiveResetCount) $resetLabel"

        $lastChecked = Format-DisplayDate $script:State.liveUsage.lastCheckedAt
        $liveStatus = "Last checked: $lastChecked"
        if (-not [string]::IsNullOrWhiteSpace([string]$script:State.liveUsage.lastError)) {
            $liveStatus += " | error: $($script:State.liveUsage.lastError)"
        }
        elseif ($null -ne $script:State.liveUsage.resetCreditsAvailable) {
            $liveStatus += " | resets available: $($script:State.liveUsage.resetCreditsAvailable)"
        }
        $liveStatusLabel.Text = Limit-Text -Text $liveStatus -MaxLength 130

        $liveList.Items.Clear()
        foreach ($bucket in @(Get-LiveUsageBuckets)) {
            $bucketName = [string]$bucket.limitName
            if ([string]::IsNullOrWhiteSpace($bucketName)) {
                $bucketName = [string]$bucket.limitId
            }
            if ([string]::IsNullOrWhiteSpace($bucketName)) {
                $bucketName = "codex"
            }

            $item = New-Object System.Windows.Forms.ListViewItem $bucketName
            $five = Get-LiveBucketWindow -Bucket $bucket -Minutes 300
            $week = Get-LiveBucketWindow -Bucket $bucket -Minutes 10080
            [void]$item.SubItems.Add($(if ($null -ne $five.remainingPercent) { (Format-RemainingPercent $five.remainingPercent) } else { "-" }))
            [void]$item.SubItems.Add((Format-ShortDisplayDate $five.resetsAt))
            [void]$item.SubItems.Add($(if ($null -ne $week.remainingPercent) { (Format-RemainingPercent $week.remainingPercent) } else { "-" }))
            [void]$item.SubItems.Add((Format-ShortDisplayDate $week.resetsAt))
            [void]$item.SubItems.Add([string]$bucket.creditsBalance)
            [void]$item.SubItems.Add([string]$bucket.planType)
            [void]$item.SubItems.Add([string]$bucket.rateLimitReachedType)
            $item.Tag = $bucket
            [void]$liveList.Items.Add($item)
        }

        $claudeUsage = Get-ClaudeUsageSnapshot
        $claudeName = "Claude Code"
        $claudeStatus = "waiting for statusline"
        if ($null -ne $claudeUsage) {
            if (-not [string]::IsNullOrWhiteSpace([string]$claudeUsage.modelName)) {
                $claudeName = "Claude Code ($($claudeUsage.modelName))"
            }
            $claudeStatus = $(if (-not [string]::IsNullOrWhiteSpace([string]$claudeUsage.lastError)) { "error" } elseif($claudeUsage.source -eq "claude-code-control"){"CLI quotas"}else { "statusline" })
        }

        $claudeItem = New-Object System.Windows.Forms.ListViewItem $claudeName
        [void]$claudeItem.SubItems.Add($(if ($null -ne $claudeUsage -and $null -ne $claudeUsage.fiveHourRemainingPercent) { (Format-RemainingPercent $claudeUsage.fiveHourRemainingPercent) } else { "-" }))
        [void]$claudeItem.SubItems.Add($(if ($null -ne $claudeUsage) { Format-ShortDisplayDate $claudeUsage.fiveHourResetsAt } else { "-" }))
        [void]$claudeItem.SubItems.Add($(if ($null -ne $claudeUsage -and $null -ne $claudeUsage.sevenDayRemainingPercent) { (Format-RemainingPercent $claudeUsage.sevenDayRemainingPercent) } else { "-" }))
        [void]$claudeItem.SubItems.Add($(if ($null -ne $claudeUsage) { Format-ShortDisplayDate $claudeUsage.sevenDayResetsAt } else { "-" }))
        [void]$claudeItem.SubItems.Add("")
        [void]$claudeItem.SubItems.Add($(if ($null -ne $claudeUsage) { [string]$claudeUsage.version } else { "" }))
        [void]$claudeItem.SubItems.Add($claudeStatus)
        $claudeItem.Tag = $claudeUsage
        [void]$liveList.Items.Add($claudeItem)

        foreach($quota in @((Get-AntigravityUsageSnapshot).items)) {
            $item=New-Object System.Windows.Forms.ListViewItem ("Antigravity: $($quota.label)")
            $isFive=[string]$quota.label -match '5h$'
            [void]$item.SubItems.Add($(if($isFive){Format-RemainingPercent $quota.remainingPercent}else{'-'}))
            [void]$item.SubItems.Add($(if($isFive){Format-ShortDisplayDate $quota.resetsAt}else{'-'}))
            [void]$item.SubItems.Add($(if(-not $isFive){Format-RemainingPercent $quota.remainingPercent}else{'-'}))
            [void]$item.SubItems.Add($(if(-not $isFive){Format-ShortDisplayDate $quota.resetsAt}else{'-'}))
            [void]$item.SubItems.Add('');[void]$item.SubItems.Add('');[void]$item.SubItems.Add('CLI quota')
            $item.Tag=$quota
            [void]$liveList.Items.Add($item)
        }

        $openCodeGoUsage = if ([bool]$script:State.settings.openCodeGoEnabled) { Get-OpenCodeGoUsageSnapshot } else { $null }
        $openCodeGoValues = @{}
        if ($null -ne $openCodeGoUsage) {
            foreach ($usageItem in @($openCodeGoUsage.items)) {
                $openCodeGoValues[[string]$usageItem.key] = $usageItem
            }
        }
        $openCodeGoItem = New-Object System.Windows.Forms.ListViewItem "OpenCode Go"
        $openCodeGoFiveHour = $openCodeGoValues["five_hour"]
        $openCodeGoWeekly = $openCodeGoValues["seven_day"]
        $openCodeGoMonthly = $openCodeGoValues["monthly"]
        [void]$openCodeGoItem.SubItems.Add($(if ($null -ne $openCodeGoFiveHour -and $null -ne $openCodeGoFiveHour.remainingPercent) { (Format-RemainingPercent $openCodeGoFiveHour.remainingPercent) } else { "-" }))
        [void]$openCodeGoItem.SubItems.Add($(if ($null -ne $openCodeGoFiveHour) { Format-ShortDisplayDate $openCodeGoFiveHour.resetsAt } else { "-" }))
        [void]$openCodeGoItem.SubItems.Add($(if ($null -ne $openCodeGoWeekly -and $null -ne $openCodeGoWeekly.remainingPercent) { (Format-RemainingPercent $openCodeGoWeekly.remainingPercent) } else { "-" }))
        [void]$openCodeGoItem.SubItems.Add($(if ($null -ne $openCodeGoWeekly) { Format-ShortDisplayDate $openCodeGoWeekly.resetsAt } else { "-" }))
        [void]$openCodeGoItem.SubItems.Add($(if ($null -ne $openCodeGoMonthly -and $null -ne $openCodeGoMonthly.remainingPercent) { (Format-RemainingPercent $openCodeGoMonthly.remainingPercent) } else { "-" }))
        [void]$openCodeGoItem.SubItems.Add("")
        [void]$openCodeGoItem.SubItems.Add($(if ([bool]$script:State.settings.openCodeGoEnabled) { Get-OpenCodeGoStatusText } else { 'Disabled in Preferences' }))
        $openCodeGoItem.Tag = $openCodeGoUsage
        [void]$liveList.Items.Add($openCodeGoItem)

        $qwenUsage = if ([bool]$script:State.settings.qwenTokenPlanEnabled) { Get-QwenUsageSnapshot } else { $null }
        $qwenValues = @{}
        if ($null -ne $qwenUsage) {
            foreach ($usageItem in @($qwenUsage.items)) {
                $qwenValues[[string]$usageItem.key] = $usageItem
            }
        }
        $qwenItem = New-Object System.Windows.Forms.ListViewItem "Qwen Token Plan"
        $qwenFiveHour = $qwenValues["five_hour"]
        $qwenWeekly = $qwenValues["seven_day"]
        [void]$qwenItem.SubItems.Add($(if ($null -ne $qwenFiveHour -and $null -ne $qwenFiveHour.remainingPercent) { (Format-RemainingPercent $qwenFiveHour.remainingPercent) } else { "-" }))
        [void]$qwenItem.SubItems.Add($(if ($null -ne $qwenFiveHour) { Format-ShortDisplayDate $qwenFiveHour.resetsAt } else { "-" }))
        [void]$qwenItem.SubItems.Add($(if ($null -ne $qwenWeekly -and $null -ne $qwenWeekly.remainingPercent) { (Format-RemainingPercent $qwenWeekly.remainingPercent) } else { "-" }))
        [void]$qwenItem.SubItems.Add($(if ($null -ne $qwenWeekly) { Format-ShortDisplayDate $qwenWeekly.resetsAt } else { "-" }))
        [void]$qwenItem.SubItems.Add("")
        [void]$qwenItem.SubItems.Add("")
        [void]$qwenItem.SubItems.Add($(if ([bool]$script:State.settings.qwenTokenPlanEnabled) { Get-QwenStatusText } else { 'Paused in Preferences' }))
        $qwenItem.Tag = $qwenUsage
        [void]$liveList.Items.Add($qwenItem)

        $resetsList.Items.Clear()
        foreach ($reset in ($script:State.resets | Sort-Object { Get-DateOrNull ([string]$_.expiresAt) })) {
            $item = New-Object System.Windows.Forms.ListViewItem ([string]$reset.label)
            [void]$item.SubItems.Add((Format-DisplayDate $reset.expiresAt))
            [void]$item.SubItems.Add((Format-TimeLeft $reset.expiresAt))
            [void]$item.SubItems.Add((Get-ResetStatus $reset))
            [void]$item.SubItems.Add([string]$reset.notes)
            $item.Tag = $reset
            [void]$resetsList.Items.Add($item)
        }

        $limitsList.Items.Clear()
        foreach ($limit in $script:State.limits) {
            $item = New-Object System.Windows.Forms.ListViewItem ([string]$limit.name)
            [void]$item.SubItems.Add([string]$limit.allowance)
            [void]$item.SubItems.Add([string]$limit.remaining)
            [void]$item.SubItems.Add((Format-TimeLeft $limit.resetAt))
            [void]$item.SubItems.Add([string]$limit.notes)
            $item.Tag = $limit
            [void]$limitsList.Items.Add($item)
        }

        Update-UsageProviderRows
        Set-MainWindowListRows -List $liveList
        Set-MainWindowListRows -List $resetsList
        Set-MainWindowListRows -List $limitsList
        } finally {
            foreach ($list in @($liveList, $resetsList, $limitsList)) {
                foreach ($row in $list.Items) {
                    $key = if ($null -ne $row.Tag.id) { [string]$row.Tag.id } else { $row.Text }
                    if ($selections[$list.GetHashCode()] -contains $key) { $row.Selected = $true }
                }
                $list.EndUpdate()
            }
        }
        Refresh-Tray
}

function New-UsageProviderRow {
    param([string]$Source)
    $names = @{codex='ChatGPT / Codex';claude='Claude';antigravity='Antigravity';opencodego='OpenCode Go';qwen='Qwen Token Plan'}
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Height = 88
    $panel.BackColor = [System.Drawing.Color]::White
    Enable-ControlDoubleBuffering -Control $panel
    $panel.Add_Paint({
        param($eventSource,$eventData)
        $pen=New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(237,237,240))
        try { $eventData.Graphics.DrawLine($pen,0,($eventSource.Height-1),$eventSource.Width,($eventSource.Height-1)) } finally { $pen.Dispose() }
    })
    $icon = New-Object System.Windows.Forms.PictureBox
    $icon.Location = New-Object System.Drawing.Point 4,26
    $icon.Size = New-Object System.Drawing.Size 28,28
    $icon.SizeMode = 'Zoom'
    $icon.Image = New-BadgeLogoImage -Size 28 -Source $Source
    $icon.Add_Disposed({ param($eventSource,$eventData) if($null -ne $eventSource.Image){ $eventSource.Image.Dispose() } })
    $panel.Controls.Add($icon)
    $name = New-Object System.Windows.Forms.Label
    $name.Text = $names[$Source]
    $name.Location = New-Object System.Drawing.Point 44,20
    $name.Size = New-Object System.Drawing.Size 190,26
    $name.Font = New-Object System.Drawing.Font 'Segoe UI Semibold',12
    $name.ForeColor = [System.Drawing.Color]::FromArgb(36,38,44)
    $panel.Controls.Add($name)
    $status = New-Object System.Windows.Forms.Label
    $status.Location = New-Object System.Drawing.Point 44,49
    $status.Size = New-Object System.Drawing.Size 184,21
    $status.Font = New-Object System.Drawing.Font 'Segoe UI',9
    $status.ForeColor = [System.Drawing.Color]::FromArgb(99,104,117)
    $panel.Controls.Add($status)
    $groups=@()
    for ($index=0;$index -lt 3;$index++) {
        $group=New-Object System.Windows.Forms.Panel
        $group.Height=76
        $label=New-Object System.Windows.Forms.Label
        $label.Location=New-Object System.Drawing.Point 0,8
        $label.Size=New-Object System.Drawing.Size 154,18
        $label.Font=New-Object System.Drawing.Font 'Segoe UI',9
        $label.ForeColor=[System.Drawing.Color]::FromArgb(99,104,117)
        $group.Controls.Add($label)
        $value=New-Object System.Windows.Forms.Label
        $value.Location=New-Object System.Drawing.Point 0,25
        $value.Size=New-Object System.Drawing.Size 154,34
        $value.Font=New-Object System.Drawing.Font 'Segoe UI Semibold',19
        $value.ForeColor=[System.Drawing.Color]::FromArgb(36,38,44)
        $group.Controls.Add($value)
        $track=New-Object System.Windows.Forms.Panel
        $track.Location=New-Object System.Drawing.Point 1,65
        $track.Height=3
        $track.BackColor=[System.Drawing.Color]::FromArgb(235,235,239)
        $fill=New-Object System.Windows.Forms.Panel
        $fill.Height=3
        $track.Controls.Add($fill)
        $group.Controls.Add($track)
        $panel.Controls.Add($group)
        $groups += [pscustomobject]@{Panel=$group;Label=$label;Value=$value;Track=$track;Fill=$fill;Percent=$null}
    }
    return [pscustomobject]@{Panel=$panel;Icon=$icon;Name=$name;Status=$status;Groups=$groups;Source=$Source}
}

function Update-UsageRowLayout {
    param([System.Windows.Forms.Panel]$Container)
    if ($null -eq $script:UsageProviderRows) { return }
    $y=$Container.AutoScrollPosition.Y
    $width=[Math]::Max(350,$Container.ClientSize.Width - 20)
    foreach ($source in @('codex','claude','antigravity','opencodego','qwen')) {
        $row=$script:UsageProviderRows[$source]
        if ($null -eq $row) { continue }
        $row.Panel.SetBounds(0,$y,$width,88)
        $columnWidth=[int][Math]::Floor(($width-242)/3)
        for ($index=0;$index -lt 3;$index++) {
            $group=$row.Groups[$index]
            $group.Panel.SetBounds((242+$index*$columnWidth),0,$columnWidth,76)
            $group.Label.Width=$columnWidth-12
            $group.Value.Width=$columnWidth-12
            $group.Track.Width=[Math]::Max(10,$columnWidth-28)
            $group.Fill.Width=if ($null -ne $group.Percent) { [int][Math]::Round($group.Track.Width*$group.Percent/100) } else { 0 }
        }
        $y+=88
    }
}

function Update-UsageProviderRows {
    if ($null -eq $script:UsageProviderRows) { return }
    foreach ($source in @('codex','claude','antigravity','opencodego','qwen')) {
        $row=$script:UsageProviderRows[$source]
        $data=Get-TaskbarBadgeData -Source $source
        $items=@($data.Items|Where-Object {$_.Label -ne 'cache'})
        if ($source -eq 'codex') {
            $bucket=Get-MainLiveBucket
            $items=@(foreach ($window in @(@{Label='5h';Minutes=300},@{Label='weekly';Minutes=10080})) {
                $value=(Get-LiveBucketWindow -Bucket $bucket -Minutes $window.Minutes).remainingPercent
                [pscustomobject]@{Label=$window.Label;Text=$(if($null -ne $value){(Format-RemainingPercent $value)}else{'--'})}
            })
        }
        $hasValues=@($items | Where-Object {$_.Text -ne '--'}).Count -gt 0
        $status=if($hasValues){'Remaining allowance'}else{'Waiting for usage'}
        if ($source -eq 'opencodego') { $status=Get-OpenCodeGoStatusText; if(-not $script:State.settings.openCodeGoEnabled){$status='Connect in Preferences'} }
        if ($source -eq 'qwen') { $status=Get-QwenStatusText; if(-not $script:State.settings.qwenTokenPlanEnabled){$status='Paused in Preferences'} }
        if ($status -in @('Connect in Preferences','Paused in Preferences')) {
            foreach ($item in $items) { $item.Text='--' }
        }
        if ($source -eq 'antigravity' -and -not $hasValues) { $status='CLI setup / sign-in required' }
        if ($source -eq 'claude') { $status=$data.StatusText }
        if ($script:ProviderRefreshes.ContainsKey($source)) { $status='Refreshing...' }
        if ($script:ProviderRefreshErrors.ContainsKey($source)) { $status='Refresh unavailable' }
        $row.Status.Text=$status
        $row.Panel.AccessibleName="$($row.Name.Text). $status. " + (($items | ForEach-Object { "$($_.Label) $($_.Text)" }) -join '. ')
        for ($index=0;$index -lt 3;$index++) {
            $group=$row.Groups[$index]
            $group.Panel.Visible=$index -lt $items.Count
            if ($index -ge $items.Count) { continue }
            $item=$items[$index]
            $group.Label.Text=switch($item.Label){'5h'{'5-hour window'} 'weekly'{'Weekly window'} 'monthly'{'Monthly window'} default{$item.Label}}
            $group.Value.Text=$item.Text
            $group.Percent=if($item.Text -eq '<1%'){0.5}elseif($item.Text -match '^(\d+)%$'){[int]$Matches[1]}else{$null}
            $group.Value.ForeColor=if($null -eq $group.Percent){[System.Drawing.Color]::FromArgb(132,136,145)}else{[System.Drawing.Color]::FromArgb(36,38,44)}
            $group.Fill.BackColor=if($null -eq $group.Percent -or $status -eq 'cache' -or [bool]$data.Cached){[System.Drawing.Color]::FromArgb(169,173,184)}elseif($group.Percent -lt 20){[System.Drawing.Color]::FromArgb(209,67,67)}else{[System.Drawing.Color]::FromArgb(208,34,121)}
        }
    }
    Update-UsageRowLayout -Container $script:MainWindowControls.Rows
}

function Update-UsageTabLayout {
    param([System.Windows.Forms.TabPage]$Page)
    $isLive = $Page.Text -eq 'Live usage'
    foreach ($control in $Page.Controls) {
        if ($control -is [System.Windows.Forms.ListView]) {
            $control.Width = [Math]::Max(100, $Page.ClientSize.Width - 28)
            $bottomSpace = if ($isLive -or $Page.Text -eq 'Details') { 14 } else { 54 }
            $control.Height = [Math]::Max(60, $Page.ClientSize.Height - $control.Top - $bottomSpace)
        } elseif ($control.Tag -eq 'provider-rows') {
            $control.Size = New-Object System.Drawing.Size ([Math]::Max(200,$Page.ClientSize.Width - 36)),([Math]::Max(100,$Page.ClientSize.Height - 72))
        } elseif ($control -is [System.Windows.Forms.Button]) {
            if ($isLive) { $control.Left = [Math]::Max(14, $Page.ClientSize.Width - $control.Width - 14) }
            else { $control.Top = [Math]::Max(14, $Page.ClientSize.Height - $control.Height - 14) }
        } elseif ($isLive -and $control -is [System.Windows.Forms.Label]) {
            $control.Width = [Math]::Max(100, $Page.ClientSize.Width - 162)
        }
    }
}

function Show-MainWindow {
    if ($null -ne $script:MainForm -and -not $script:MainForm.IsDisposed) {
        $script:MainForm.WindowState = "Normal"
        $script:MainForm.ShowInTaskbar = $true
        $script:MainForm.Show()
        $script:MainForm.Activate()
        return
    }

    $form = New-Object System.Windows.Forms.Form
    $script:MainForm = $form
    $form.Text = "Usage Tray Pill"
    $form.StartPosition = "CenterScreen"
    $form.ClientSize = New-Object System.Drawing.Size 1040, 760
    $form.MinimumSize = New-Object System.Drawing.Size 900, 620
    $form.ShowInTaskbar = $true
    $form.BackColor = [System.Drawing.Color]::FromArgb(245, 244, 241)
    $form.ForeColor = [System.Drawing.Color]::FromArgb(36, 39, 46)
    $form.Font = New-Object System.Drawing.Font "Segoe UI", 9

    if ($null -ne $script:NotifyIcon -and $null -ne $script:NotifyIcon.Icon) {
        $form.Icon = $script:NotifyIcon.Icon
    }

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "Usage overview"
    $title.Location = New-Object System.Drawing.Point 30, 28
    $title.Size = New-Object System.Drawing.Size 680, 45
    $title.Font = New-Object System.Drawing.Font "Segoe UI Semibold", 26
    $form.Controls.Add($title)

    $header = New-Object System.Windows.Forms.Label
    $header.Location = New-Object System.Drawing.Point 33, 79
    $header.Size = New-Object System.Drawing.Size 910, 22
    $header.Anchor = "Top,Left,Right"
    $header.ForeColor = [System.Drawing.Color]::FromArgb(103, 108, 118)
    $form.Controls.Add($header)

    $settingsPanel = New-Object System.Windows.Forms.Panel
    $settingsPanel.Location = New-Object System.Drawing.Point 20, 82
    $settingsPanel.Size = New-Object System.Drawing.Size 920, 96
    $settingsPanel.Anchor = "Top,Left,Right"
    $settingsPanel.BackColor = [System.Drawing.Color]::White
    $settingsPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $form.Controls.Add($settingsPanel)

    $planLabel = New-Object System.Windows.Forms.Label
    $planLabel.Text = "Plan name"
    $planLabel.Location = New-Object System.Drawing.Point 14, 12
    $planLabel.AutoSize = $true
    $planLabel.ForeColor = [System.Drawing.Color]::FromArgb(82, 87, 97)
    $settingsPanel.Controls.Add($planLabel)

    $planBox = New-Object System.Windows.Forms.TextBox
    $planBox.Location = New-Object System.Drawing.Point 16, 34
    $planBox.Size = New-Object System.Drawing.Size 230, 25
    $planBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $planBox.Text = [string]$script:State.planName
    $settingsPanel.Controls.Add($planBox)

    $savePlanButton = New-Object System.Windows.Forms.Button
    $savePlanButton.Text = "Save plan"
    $savePlanButton.Location = New-Object System.Drawing.Point 256, 32
    $savePlanButton.Size = New-Object System.Drawing.Size 104, 30
    Set-MainWindowButtonStyle -Button $savePlanButton
    $settingsPanel.Controls.Add($savePlanButton)

    $onlyCodexCheck = New-Object System.Windows.Forms.CheckBox
    $onlyCodexCheck.Text = "Tray icon only while Codex runs"
    $onlyCodexCheck.Location = New-Object System.Drawing.Point 378, 36
    $onlyCodexCheck.Size = New-Object System.Drawing.Size 250, 22
    $onlyCodexCheck.Checked = [bool]$script:State.settings.showOnlyWhenCodexRuns
    $settingsPanel.Controls.Add($onlyCodexCheck)
    $qwenEnabledCheck = New-Object System.Windows.Forms.CheckBox
    $qwenEnabledCheck.Text = 'Enable Qwen Token Plan'
    $qwenEnabledCheck.Location = New-Object System.Drawing.Point 390,78
    $qwenEnabledCheck.Size = New-Object System.Drawing.Size 270,24
    $qwenEnabledCheck.Checked = [bool]$script:State.settings.qwenTokenPlanEnabled
    $qwenEnabledCheck.Add_Click({param($eventSource,$eventData) Set-QwenEnabled -Enabled $eventSource.Checked})
    $settingsPanel.Controls.Add($qwenEnabledCheck)
    $claudeControlCheck=New-Object System.Windows.Forms.CheckBox
    $claudeControlCheck.Text='Use Claude CLI quotas (experimental)'
    $claudeControlCheck.Location=New-Object System.Drawing.Point 16,110
    $claudeControlCheck.Size=New-Object System.Drawing.Size 330,24
    $claudeControlCheck.Checked=[bool]$script:State.settings.claudeControlEnabled
    $claudeControlCheck.Add_Click({param($eventSource,$eventData)
        $script:State.settings.claudeControlEnabled=$eventSource.Checked
        Save-State
        Stop-UsageCollection
        Start-UsageCollection
        if($null -ne $script:RefreshMainWindow){& $script:RefreshMainWindow}
    })
    $settingsPanel.Controls.Add($claudeControlCheck)
    $fullscreenCheck=New-Object System.Windows.Forms.CheckBox
    $fullscreenCheck.Text='Hide pill when full-screen covers taskbar'
    $fullscreenCheck.Location=New-Object System.Drawing.Point 390,110
    $fullscreenCheck.Size=New-Object System.Drawing.Size 380,24
    $fullscreenCheck.Checked=[bool]$script:State.settings.hideTaskbarBadgeInFullscreen
    $fullscreenCheck.Add_Click({param($eventSource,$eventData)
        $script:State.settings.hideTaskbarBadgeInFullscreen=$eventSource.Checked
        Save-State
        Refresh-TaskbarBadge -GeometryOnly
    })
    $settingsPanel.Controls.Add($fullscreenCheck)
    $codexBucketBox = New-Object System.Windows.Forms.ComboBox
    $codexBucketBox.DropDownStyle = 'DropDownList'
    $codexBucketBox.DisplayMember = 'Label'
    $codexBucketBox.Location = New-Object System.Drawing.Point 390,34
    $codexBucketBox.Size = New-Object System.Drawing.Size 300,25
    $codexBucketBox.Add_SelectionChangeCommitted({param($eventSource,$eventData)
        $script:State.settings.codexLimitId=$eventSource.SelectedItem.Id
        Save-State
        Refresh-Tray
    })
    $settingsPanel.Controls.Add($codexBucketBox)
    $bucketLabel = New-Object System.Windows.Forms.Label
    $bucketLabel.Text = 'Codex allowance shown in the pill'
    $bucketLabel.Location = New-Object System.Drawing.Point 390,12
    $bucketLabel.AutoSize=$true
    $settingsPanel.Controls.Add($bucketLabel)

    $quickAddResetButton = New-Object System.Windows.Forms.Button
    $quickAddResetButton.Text = "+ Reset"
    $quickAddResetButton.Location = New-Object System.Drawing.Point 708, 32
    $quickAddResetButton.Size = New-Object System.Drawing.Size 88, 30
    $quickAddResetButton.Anchor = "Top,Right"
    Set-MainWindowButtonStyle -Button $quickAddResetButton
    $settingsPanel.Controls.Add($quickAddResetButton)

    $quickAddLimitButton = New-Object System.Windows.Forms.Button
    $quickAddLimitButton.Text = "+ Limit"
    $quickAddLimitButton.Location = New-Object System.Drawing.Point 806, 32
    $quickAddLimitButton.Size = New-Object System.Drawing.Size 88, 30
    $quickAddLimitButton.Anchor = "Top,Right"
    Set-MainWindowButtonStyle -Button $quickAddLimitButton
    $settingsPanel.Controls.Add($quickAddLimitButton)

    $usageHint = New-Object System.Windows.Forms.Label
    $usageHint.Text = "Live provider usage updates automatically. Reset bank and limits remain available for personal tracking."
    $usageHint.Location = New-Object System.Drawing.Point 16, 68
    $usageHint.Size = New-Object System.Drawing.Size 878, 18
    $usageHint.Anchor = "Top,Left,Right"
    $usageHint.ForeColor = [System.Drawing.Color]::FromArgb(103, 108, 118)
    $settingsPanel.Controls.Add($usageHint)

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Location = New-Object System.Drawing.Point 28, 126
    $tabs.Size = New-Object System.Drawing.Size 984, 572
    $tabs.Anchor = "Top,Bottom,Left,Right"
    $tabs.DrawMode = [System.Windows.Forms.TabDrawMode]::OwnerDrawFixed
    $tabs.SizeMode = [System.Windows.Forms.TabSizeMode]::Fixed
    $tabs.ItemSize = New-Object System.Drawing.Size 136, 40
    $tabs.Padding = New-Object System.Drawing.Point 18, 4
    $tabs.Font = New-Object System.Drawing.Font "Segoe UI Semibold", 10
    $tabs.Add_DrawItem({
        param($eventSource, $eventData)

        $isSelected = ($eventData.Index -eq $eventSource.SelectedIndex)
        $background = if ($isSelected) {
            [System.Drawing.Color]::White
        }
        else {
            [System.Drawing.Color]::FromArgb(245, 244, 241)
        }
        $foreground = if ($isSelected) {
            [System.Drawing.Color]::FromArgb(36, 39, 46)
        }
        else {
            [System.Drawing.Color]::FromArgb(103, 108, 118)
        }

        $backgroundBrush = New-Object System.Drawing.SolidBrush $background
        try {
            $eventData.Graphics.FillRectangle($backgroundBrush, $eventData.Bounds)
        }
        finally {
            $backgroundBrush.Dispose()
        }

        if ($isSelected) {
            $accentBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(208, 34, 121))
            try {
                $underline = New-Object System.Drawing.Rectangle $eventData.Bounds.X, ($eventData.Bounds.Bottom - 3), $eventData.Bounds.Width, 3
                $eventData.Graphics.FillRectangle($accentBrush, $underline)
            }
            finally {
                $accentBrush.Dispose()
            }
        }

        $textFlags = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor
            [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
            [System.Windows.Forms.TextFormatFlags]::SingleLine -bor
            [System.Windows.Forms.TextFormatFlags]::EndEllipsis
        [System.Windows.Forms.TextRenderer]::DrawText(
            $eventData.Graphics,
            $eventSource.TabPages[$eventData.Index].Text,
            $eventSource.Font,
            $eventData.Bounds,
            $foreground,
            $textFlags
        )
    }.GetNewClosure())
    $form.Controls.Add($tabs)

    $liveTab = New-Object System.Windows.Forms.TabPage
    $liveTab.Text = "Live usage"
    $liveTab.BackColor = [System.Drawing.Color]::White
    $liveTab.UseVisualStyleBackColor = $false
    $tabs.TabPages.Add($liveTab)

    $limitsTab = New-Object System.Windows.Forms.TabPage
    $limitsTab.Text = "Limits"
    $limitsTab.BackColor = [System.Drawing.Color]::White
    $limitsTab.UseVisualStyleBackColor = $false
    $tabs.TabPages.Add($limitsTab)

    $resetsTab = New-Object System.Windows.Forms.TabPage
    $resetsTab.Text = "Reset bank"
    $resetsTab.BackColor = [System.Drawing.Color]::White
    $resetsTab.UseVisualStyleBackColor = $false
    $tabs.TabPages.Add($resetsTab)

    $detailsTab = New-Object System.Windows.Forms.TabPage
    $detailsTab.Text = "Details"
    $detailsTab.BackColor = [System.Drawing.Color]::White
    $tabs.TabPages.Add($detailsTab)
    $preferencesTab = New-Object System.Windows.Forms.TabPage
    $preferencesTab.Text = "Preferences"
    $preferencesTab.BackColor = [System.Drawing.Color]::White
    $preferencesTab.AutoScroll = $true
    $tabs.TabPages.Add($preferencesTab)
    $settingsPanel.Location = New-Object System.Drawing.Point 12, 12
    $settingsPanel.Size = New-Object System.Drawing.Size 940, 148
    $settingsPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $settingsPanel.Anchor = 'Top,Left'
    $onlyCodexCheck.Location = New-Object System.Drawing.Point 16, 78
    $usageHint.Visible = $false
    $quickAddResetButton.Visible = $false
    $quickAddLimitButton.Visible = $false
    $preferencesTab.Controls.Add($settingsPanel)
    $preferencesTab.Tag = $settingsPanel
    $preferencesTab.Add_Resize({ param($eventSource,$eventData) $eventSource.Tag.Width=[Math]::Max(400,$eventSource.ClientSize.Width-40) })

    $liveStatusLabel = New-Object System.Windows.Forms.Label
    $liveStatusLabel.Location = New-Object System.Drawing.Point 14, 17
    $liveStatusLabel.Size = New-Object System.Drawing.Size 710, 22
    $liveStatusLabel.Anchor = "Top,Left,Right"
    $liveStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(82, 87, 97)
    $liveTab.Controls.Add($liveStatusLabel)

    $refreshLiveButton = New-Object System.Windows.Forms.Button
    $refreshLiveButton.Text = "Refresh now"
    $refreshLiveButton.Location = New-Object System.Drawing.Point 748, 12
    $refreshLiveButton.Size = New-Object System.Drawing.Size 120, 28
    $refreshLiveButton.Anchor = "Top,Right"
    Set-MainWindowButtonStyle -Button $refreshLiveButton -Kind "Primary"
    $liveTab.Controls.Add($refreshLiveButton)

    $liveList = New-ListView -X 14 -Y 54 -Width 872 -Height 286
    $liveList.Anchor = "Top,Bottom,Left,Right"
    [void]$liveList.Columns.Add("Provider", 170)
    [void]$liveList.Columns.Add("5h left", 74)
    [void]$liveList.Columns.Add("5h reset", 110)
    [void]$liveList.Columns.Add("Weekly left", 90)
    [void]$liveList.Columns.Add("Weekly reset", 120)
    [void]$liveList.Columns.Add("Monthly / credits", 112)
    [void]$liveList.Columns.Add("Plan", 80)
    [void]$liveList.Columns.Add("Status", 96)
    $liveList.Top = 14
    $detailsTab.Controls.Add($liveList)
    $usageRows = New-Object System.Windows.Forms.Panel
    $usageRows.Location = New-Object System.Drawing.Point 18, 60
    $usageRows.AutoScroll = $true
    $usageRows.BackColor = [System.Drawing.Color]::White
    $usageRows.Tag = 'provider-rows'
    Enable-ControlDoubleBuffering -Control $usageRows
    $liveTab.Controls.Add($usageRows)
    $script:UsageProviderRows = @{}
    foreach ($source in @('codex','claude','antigravity','opencodego','qwen')) {
        $row = New-UsageProviderRow -Source $source
        $script:UsageProviderRows[$source] = $row
        $usageRows.Controls.Add($row.Panel)
    }
    $usageRows.Add_Resize({ param($eventSource,$eventData) Update-UsageRowLayout -Container $eventSource })

    $resetsList = New-ListView -X 14 -Y 14 -Width 872 -Height 286
    $resetsList.Anchor = "Top,Bottom,Left,Right"
    [void]$resetsList.Columns.Add("Name", 170)
    [void]$resetsList.Columns.Add("Expires at", 140)
    [void]$resetsList.Columns.Add("Remaining", 100)
    [void]$resetsList.Columns.Add("Status", 110)
    [void]$resetsList.Columns.Add("Notes", 330)
    $resetsTab.Controls.Add($resetsList)

    $addResetButton = New-Object System.Windows.Forms.Button
    $addResetButton.Text = "Add"
    $addResetButton.Location = New-Object System.Drawing.Point 14, 312
    $addResetButton.Size = New-Object System.Drawing.Size 90, 28
    $addResetButton.Anchor = "Bottom,Left"
    Set-MainWindowButtonStyle -Button $addResetButton
    $resetsTab.Controls.Add($addResetButton)

    $editResetButton = New-Object System.Windows.Forms.Button
    $editResetButton.Text = "Edit"
    $editResetButton.Location = New-Object System.Drawing.Point 112, 312
    $editResetButton.Size = New-Object System.Drawing.Size 90, 28
    $editResetButton.Anchor = "Bottom,Left"
    Set-MainWindowButtonStyle -Button $editResetButton
    $resetsTab.Controls.Add($editResetButton)

    $usedResetButton = New-Object System.Windows.Forms.Button
    $usedResetButton.Text = "Mark used"
    $usedResetButton.Location = New-Object System.Drawing.Point 210, 312
    $usedResetButton.Size = New-Object System.Drawing.Size 100, 28
    $usedResetButton.Anchor = "Bottom,Left"
    Set-MainWindowButtonStyle -Button $usedResetButton
    $resetsTab.Controls.Add($usedResetButton)

    $deleteResetButton = New-Object System.Windows.Forms.Button
    $deleteResetButton.Text = "Delete"
    $deleteResetButton.Location = New-Object System.Drawing.Point 318, 312
    $deleteResetButton.Size = New-Object System.Drawing.Size 90, 28
    $deleteResetButton.Anchor = "Bottom,Left"
    Set-MainWindowButtonStyle -Button $deleteResetButton
    $resetsTab.Controls.Add($deleteResetButton)

    $limitsList = New-ListView -X 14 -Y 14 -Width 872 -Height 286
    $limitsList.Anchor = "Top,Bottom,Left,Right"
    [void]$limitsList.Columns.Add("Name", 170)
    [void]$limitsList.Columns.Add("Limit", 150)
    [void]$limitsList.Columns.Add("Status / remaining", 150)
    [void]$limitsList.Columns.Add("Reset", 120)
    [void]$limitsList.Columns.Add("Notes", 260)
    $limitsTab.Controls.Add($limitsList)

    $addLimitButton = New-Object System.Windows.Forms.Button
    $addLimitButton.Text = "Add"
    $addLimitButton.Location = New-Object System.Drawing.Point 14, 312
    $addLimitButton.Size = New-Object System.Drawing.Size 90, 28
    $addLimitButton.Anchor = "Bottom,Left"
    Set-MainWindowButtonStyle -Button $addLimitButton
    $limitsTab.Controls.Add($addLimitButton)

    $editLimitButton = New-Object System.Windows.Forms.Button
    $editLimitButton.Text = "Edit"
    $editLimitButton.Location = New-Object System.Drawing.Point 112, 312
    $editLimitButton.Size = New-Object System.Drawing.Size 90, 28
    $editLimitButton.Anchor = "Bottom,Left"
    Set-MainWindowButtonStyle -Button $editLimitButton
    $limitsTab.Controls.Add($editLimitButton)

    $deleteLimitButton = New-Object System.Windows.Forms.Button
    $deleteLimitButton.Text = "Delete"
    $deleteLimitButton.Location = New-Object System.Drawing.Point 210, 312
    $deleteLimitButton.Size = New-Object System.Drawing.Size 90, 28
    $deleteLimitButton.Anchor = "Bottom,Left"
    Set-MainWindowButtonStyle -Button $deleteLimitButton
    $limitsTab.Controls.Add($deleteLimitButton)

    $openDataButton = New-Object System.Windows.Forms.Button
    $openDataButton.Text = "Open data"
    $openDataButton.Location = New-Object System.Drawing.Point 20, 602
    $openDataButton.Size = New-Object System.Drawing.Size 100, 32
    $openDataButton.Anchor = "Bottom,Left"
    Set-MainWindowButtonStyle -Button $openDataButton
    $form.Controls.Add($openDataButton)

    $codexSettingsButton = New-Object System.Windows.Forms.Button
    $codexSettingsButton.Text = "Codex settings"
    $codexSettingsButton.Location = New-Object System.Drawing.Point 128, 602
    $codexSettingsButton.Size = New-Object System.Drawing.Size 112, 32
    $codexSettingsButton.Anchor = "Bottom,Left"
    Set-MainWindowButtonStyle -Button $codexSettingsButton
    $form.Controls.Add($codexSettingsButton)

    $usageDashboardButton = New-Object System.Windows.Forms.Button
    $usageDashboardButton.Text = "Usage dashboard"
    $usageDashboardButton.Location = New-Object System.Drawing.Point 248, 602
    $usageDashboardButton.Size = New-Object System.Drawing.Size 128, 32
    $usageDashboardButton.Anchor = "Bottom,Left"
    Set-MainWindowButtonStyle -Button $usageDashboardButton
    $form.Controls.Add($usageDashboardButton)

    $openCodeGoButton = New-Object System.Windows.Forms.Button
    $openCodeGoButton.Text = "OpenCode Go"
    $openCodeGoButton.Location = New-Object System.Drawing.Point 384, 602
    $openCodeGoButton.Size = New-Object System.Drawing.Size 112, 32
    $openCodeGoButton.Anchor = "Bottom,Left"
    Set-MainWindowButtonStyle -Button $openCodeGoButton
    $form.Controls.Add($openCodeGoButton)

    $qwenButton = New-Object System.Windows.Forms.Button
    $qwenButton.Text = "Qwen"
    $qwenButton.Location = New-Object System.Drawing.Point 504, 602
    $qwenButton.Size = New-Object System.Drawing.Size 90, 32
    $qwenButton.Anchor = "Bottom,Left"
    Set-MainWindowButtonStyle -Button $qwenButton
    $form.Controls.Add($qwenButton)

    $hideButton = New-Object System.Windows.Forms.Button
    $hideButton.Text = "Hide"
    $hideButton.Location = New-Object System.Drawing.Point 752, 602
    $hideButton.Size = New-Object System.Drawing.Size 90, 32
    $hideButton.Anchor = "Bottom,Right"
    Set-MainWindowButtonStyle -Button $hideButton
    $form.Controls.Add($hideButton)

    $exitButton = New-Object System.Windows.Forms.Button
    $exitButton.Text = "Exit"
    $exitButton.Location = New-Object System.Drawing.Point 850, 602
    $exitButton.Size = New-Object System.Drawing.Size 90, 32
    $exitButton.Anchor = "Bottom,Right"
    Set-MainWindowButtonStyle -Button $exitButton
    $form.Controls.Add($exitButton)

    $utilityY = 176
    foreach ($button in @($codexSettingsButton,$usageDashboardButton,$openCodeGoButton,$qwenButton,$openDataButton)) {
        $button.Location = New-Object System.Drawing.Point 28,$utilityY
        $button.Size = New-Object System.Drawing.Size 220,36
        $button.Anchor = 'Top,Left'
        $preferencesTab.Controls.Add($button)
        $utilityY += 46
    }
    $footer = New-Object System.Windows.Forms.Label
    $footer.Text = 'Click the pill to switch providers. Right-click for actions.'
    $footer.Location = New-Object System.Drawing.Point 30,720
    $footer.Size = New-Object System.Drawing.Size 560,24
    $footer.ForeColor = [System.Drawing.Color]::FromArgb(99,104,117)
    $footer.Anchor = 'Bottom,Left'
    $form.Controls.Add($footer)
    $hideButton.Location = New-Object System.Drawing.Point 820,716
    $exitButton.Location = New-Object System.Drawing.Point 920,716
    $script:MainWindowControls = @{FullscreenHide=$fullscreenCheck;ClaudeControl=$claudeControlCheck;QwenEnabled=$qwenEnabledCheck;CodexBucket=$codexBucketBox;Rows=$usageRows;Plan=$planBox;Resets=$resetsList;Limits=$limitsList;Live=$liveList;Header=$header;Status=$liveStatusLabel;Refresh=$refreshLiveButton}
    $script:RefreshMainWindow = { Update-MainWindow }


    $savePlanButton.Add_Click({
        $planBox = $script:MainWindowControls.Plan
        $script:State.planName = $planBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($script:State.planName)) {
            $script:State.planName = "ChatGPT Pro"
            $planBox.Text = $script:State.planName
        }
        Save-State
        if ($null -ne $script:RefreshMainWindow) { & $script:RefreshMainWindow }
    })

    $onlyCodexCheck.Add_CheckedChanged({
        param($eventSource, $eventData)
        $script:State.settings.showOnlyWhenCodexRuns = $eventSource.Checked
        Save-State
        Refresh-Tray
    })

    $refreshLiveButton.Add_Click({ Start-AllUsageRefresh })

    $addResetAction = {
        $newItem = Show-ResetDialog $null
        if ($null -ne $newItem) {
            $script:State.resets = @($script:State.resets) + $newItem
            Save-State
            if ($null -ne $script:RefreshMainWindow) { & $script:RefreshMainWindow }
        }
    }

    $addResetButton.Add_Click($addResetAction)
    $quickAddResetButton.Add_Click($addResetAction)

    $editResetAction = {
        $selected = Get-SelectedTag $script:MainWindowControls.Resets
        if ($null -eq $selected) {
            Show-Message "Select a reset first."
            return
        }

        $updated = Show-ResetDialog $selected
        if ($null -ne $updated) {
            $script:State.resets = @(Replace-ItemById -Items $script:State.resets -Id ([string]$selected.id) -NewItem $updated)
            Save-State
            if ($null -ne $script:RefreshMainWindow) { & $script:RefreshMainWindow }
        }
    }

    $editResetButton.Add_Click($editResetAction)
    $resetsList.Add_DoubleClick($editResetAction)

    $usedResetButton.Add_Click({
        $selected = Get-SelectedTag $script:MainWindowControls.Resets
        if ($null -eq $selected) {
            Show-Message "Select a reset first."
            return
        }

        $selected.used = $true
        $script:State.resets = @(Replace-ItemById -Items $script:State.resets -Id ([string]$selected.id) -NewItem $selected)
        Save-State
        if ($null -ne $script:RefreshMainWindow) { & $script:RefreshMainWindow }
    })

    $deleteResetButton.Add_Click({
        $selected = Get-SelectedTag $script:MainWindowControls.Resets
        if ($null -eq $selected) {
            Show-Message "Select a reset first."
            return
        }

        $answer = [System.Windows.Forms.MessageBox]::Show("Delete this reset?", $script:AppName, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
            $script:State.resets = @(Remove-ItemById -Items $script:State.resets -Id ([string]$selected.id))
            Save-State
            if ($null -ne $script:RefreshMainWindow) { & $script:RefreshMainWindow }
        }
    })

    $addLimitAction = {
        $newItem = Show-LimitDialog $null
        if ($null -ne $newItem) {
            $script:State.limits = @($script:State.limits) + $newItem
            Save-State
            if ($null -ne $script:RefreshMainWindow) { & $script:RefreshMainWindow }
        }
    }

    $addLimitButton.Add_Click($addLimitAction)
    $quickAddLimitButton.Add_Click($addLimitAction)

    $editLimitAction = {
        $selected = Get-SelectedTag $script:MainWindowControls.Limits
        if ($null -eq $selected) {
            Show-Message "Select a limit first."
            return
        }

        $updated = Show-LimitDialog $selected
        if ($null -ne $updated) {
            $script:State.limits = @(Replace-ItemById -Items $script:State.limits -Id ([string]$selected.id) -NewItem $updated)
            Save-State
            if ($null -ne $script:RefreshMainWindow) { & $script:RefreshMainWindow }
        }
    }

    $editLimitButton.Add_Click($editLimitAction)
    $limitsList.Add_DoubleClick($editLimitAction)

    $deleteLimitButton.Add_Click({
        $selected = Get-SelectedTag $script:MainWindowControls.Limits
        if ($null -eq $selected) {
            Show-Message "Select a limit first."
            return
        }

        $answer = [System.Windows.Forms.MessageBox]::Show("Delete this limit?", $script:AppName, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
            $script:State.limits = @(Remove-ItemById -Items $script:State.limits -Id ([string]$selected.id))
            Save-State
            if ($null -ne $script:RefreshMainWindow) { & $script:RefreshMainWindow }
        }
    })

    $openDataButton.Add_Click({
        Ensure-DataDirectory
        $explorerPath = Join-Path $env:SystemRoot "explorer.exe"
        Start-Process -FilePath $explorerPath -ArgumentList $script:DataDir
    })

    $codexSettingsButton.Add_Click({
        Start-Process "codex://settings"
    })

    $usageDashboardButton.Add_Click({
        Start-Process "https://chatgpt.com/codex/settings/usage"
    })

    $openCodeGoButton.Add_Click({
        [void](Show-OpenCodeGoSetupDialog)
    })

    $qwenButton.Add_Click({
        [void](Show-QwenSetupDialog)
    })

    $hideButton.Add_Click({ Hide-MainWindow })

    $exitButton.Add_Click({ Exit-TrayApp })

    $form.Add_FormClosing({
        param($eventSource, $eventData)
        if (-not $script:ExitRequested -and $eventData.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
            $eventData.Cancel = $true
            Hide-MainWindow
        }
    })

    $form.Add_FormClosed({
        $script:RefreshMainWindow = $null
    })

    foreach ($page in @($liveTab, $limitsTab, $resetsTab, $detailsTab)) {
        foreach ($control in $page.Controls) { $control.Anchor = 'Top,Left' }
        $page.Add_Resize({ param($eventSource, $eventData) Update-UsageTabLayout -Page $eventSource })
        Update-UsageTabLayout -Page $page
    }
    if ($null -ne $script:RefreshMainWindow) { & $script:RefreshMainWindow }
    $form.Show()
    $form.Activate()
}

function New-TrayMenu {
    $menu = New-Object System.Windows.Forms.ContextMenuStrip

    $statusItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $statusItem.Enabled = $false
    [void]$menu.Items.Add($statusItem)

    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $openItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $openItem.Text = "Open usage overview"
    $openItem.Add_Click({ Show-MainWindow })
    [void]$menu.Items.Add($openItem)

    $refreshItem = New-Object System.Windows.Forms.ToolStripMenuItem "Refresh now"
    $refreshItem.Add_Click({ Start-AllUsageRefresh })
    [void]$menu.Items.Add($refreshItem)

    $addResetItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $addResetItem.Text = "Add reset"
    $addResetItem.Add_Click({
        $newItem = Show-ResetDialog $null
        if ($null -ne $newItem) {
            $script:State.resets = @($script:State.resets) + $newItem
            Save-State
            Refresh-Tray
            if ($null -ne $script:MainForm -and -not $script:MainForm.IsDisposed -and $script:MainForm.Visible) {
                $script:MainForm.Dispose()
                $script:MainForm = $null
                Show-MainWindow
            }
        }
    })
    [void]$menu.Items.Add($addResetItem)

    $addLimitItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $addLimitItem.Text = "Add limit"
    $addLimitItem.Add_Click({
        $newItem = Show-LimitDialog $null
        if ($null -ne $newItem) {
            $script:State.limits = @($script:State.limits) + $newItem
            Save-State
            Refresh-Tray
            if ($null -ne $script:MainForm -and -not $script:MainForm.IsDisposed -and $script:MainForm.Visible) {
                $script:MainForm.Dispose()
                $script:MainForm = $null
                Show-MainWindow
            }
        }
    })
    [void]$menu.Items.Add($addLimitItem)

    $settingsItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $settingsItem.Text = "Open Codex settings"
    $settingsItem.Add_Click({ Start-Process "codex://settings" })
    [void]$menu.Items.Add($settingsItem)

    $openCodeGoItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $openCodeGoItem.Text = "Set up OpenCode Go"
    $openCodeGoItem.Add_Click({ [void](Show-OpenCodeGoSetupDialog) })
    [void]$menu.Items.Add($openCodeGoItem)

    $qwenItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $qwenItem.Text = "Set up Qwen Token Plan"
    $qwenItem.Add_Click({ [void](Show-QwenSetupDialog) })
    [void]$menu.Items.Add($qwenItem)

    $dataItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $dataItem.Text = "Open data folder"
    $dataItem.Add_Click({
        Ensure-DataDirectory
        $explorerPath = Join-Path $env:SystemRoot "explorer.exe"
        Start-Process -FilePath $explorerPath -ArgumentList $script:DataDir
    })
    [void]$menu.Items.Add($dataItem)

    $badgeItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $badgeItem.Text = "Show status badge"
    $badgeItem.CheckOnClick = $true
    $badgeItem.Checked = [bool]$script:State.settings.showTaskbarBadge
    $badgeItem.Add_Click({
        param($eventSource, $eventData)
        $script:State.settings.showTaskbarBadge = $eventSource.Checked
        Save-State
        if ($eventSource.Checked) {
            Refresh-TaskbarBadge
        }
        else {
            Hide-TaskbarBadge
        }
    })
    [void]$menu.Items.Add($badgeItem)

    $claudeKeeperItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $claudeKeeperItem.Text = "Keep Claude active"
    $claudeKeeperItem.CheckOnClick = $true
    $claudeKeeperItem.Checked = [bool]$script:State.settings.keepClaudeCodeAlive
    $claudeKeeperItem.Add_Click({
        param($eventSource, $eventData)
        $script:State.settings.keepClaudeCodeAlive = $eventSource.Checked
        if ($eventSource.Checked) {
            Clear-ClaudeKeeperCooldown
        }
        Save-State
        Ensure-ClaudeUsageKeeper
        Refresh-Tray
    })
    [void]$menu.Items.Add($claudeKeeperItem)

    $taskbarSettingsItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $taskbarSettingsItem.Text = "Taskbar settings"
    $taskbarSettingsItem.Add_Click({
        Start-Process "ms-settings:taskbar"
    })
    [void]$menu.Items.Add($taskbarSettingsItem)

    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $exitItem.Text = "Exit"
    $exitItem.Add_Click({ Exit-TrayApp })
    [void]$menu.Items.Add($exitItem)

    $menu.Tag = @{Badge=$badgeItem;Keeper=$claudeKeeperItem;Status=$statusItem;Refresh=$refreshItem}
    $menuOpeningAction = {
        param($eventSource, $eventData)
        $badgeItem = $eventSource.Tag.Badge
        $claudeKeeperItem = $eventSource.Tag.Keeper
        $statusItem = $eventSource.Tag.Status
        $refreshItem = $eventSource.Tag.Refresh
        $script:TrayMenuOpen = $true
        $refreshItem.Enabled = $script:ProviderRefreshes.Count -eq 0
        $refreshItem.Text = $(if ($refreshItem.Enabled) { "Refresh now" } else { "Refreshing..." })
        $snapshot = Get-StatusSnapshot
        $badgeItem.Checked = [bool]$script:State.settings.showTaskbarBadge
        $claudeKeeperItem.Checked = [bool]$script:State.settings.keepClaudeCodeAlive
        $nextText = "no active reset"
        if ($null -ne $snapshot.NextReset) {
            $nextText = "next reset expires in $(Format-TimeLeft $snapshot.NextReset.Reset.expiresAt)"
        }
        $claudeText = if ($snapshot.ClaudeCodeRunning) { "Claude: active" } elseif ($snapshot.ClaudeKeeperEnabled) { "Claude: keeper waiting" } else { "Claude: off" }
        $statusItem.Text = "Codex: $(if ($snapshot.CodexRunning) { "active" } else { "inactive" }) | $claudeText | resets: $($snapshot.ActiveResetCount) | $nextText"
    }
    $menu.Add_Opening($menuOpeningAction)
    $menu.Add_Closed({
        $script:TrayMenuOpen = $false
        Refresh-Tray
    })

    return $menu
}

function New-CollectorStartInfo {
    $info=New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $ownerTicks=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks
    $collector=Join-Path $PSScriptRoot 'Start-UsageCollector.ps1'
    $info.Arguments="-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$collector`" -OwnerProcessId $PID -OwnerStartTicks $ownerTicks -DataDirectory `"$script:DataDir`""
    $info.WorkingDirectory=$PSScriptRoot
    $info.UseShellExecute=$false
    $info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true
    $info.RedirectStandardError=$true
    return $info
}

function Start-UsageCollection {
    if($null -ne $script:CollectorProcess -and -not $script:CollectorProcess.HasExited){return}
    if((Get-Date) -lt $script:CollectorRestartAt){return}
    try {
        if($null -ne $script:CollectorProcess){$script:CollectorProcess.Dispose()}
        $script:CollectorProcess=[Diagnostics.Process]::Start((New-CollectorStartInfo))
        $script:CollectorStatus='Running'
        if($script:CollectorProcess.StartInfo.RedirectStandardError){$script:CollectorErrorDrain=$script:CollectorProcess.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)}
        if($script:CollectorProcess.StartInfo.RedirectStandardOutput){$script:CollectorOutputDrain=$script:CollectorProcess.StandardOutput.BaseStream.CopyToAsync([IO.Stream]::Null)}
    } catch {$script:CollectorProcess=$null;$script:CollectorRestartAt=(Get-Date).AddSeconds(30)}
}

function Stop-UsageCollection {
    if($null -ne $script:CollectorProcess){Stop-OwnedRefreshProcess $script:CollectorProcess;$script:CollectorProcess=$null}
    $script:ProviderRefreshes.Clear()
}

function Start-UsageMonitoring {
    Ensure-DataDirectory
    if(-not ('UtpUsageFileMonitor' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'UsageFileMonitor.cs')}
    $script:UsageMonitor=New-Object UtpUsageFileMonitor $script:DataDir
    foreach($package in @(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue)) {
        $directory=Join-Path $package.FullName 'LocalCache\Roaming\Claude'
        $script:UsageMonitor.Watch($directory,'plan-usage-history.json')
    }
}

function Get-ProviderCachePath {
    param([string]$Source)
    switch($Source){'codex'{$script:CodexUsagePath} 'claude'{$script:ClaudeControlUsagePath} 'antigravity'{$script:AntigravityUsagePath} 'opencodego'{$script:OpenCodeGoUsagePath} 'qwen'{$script:QwenUsagePath}}
}

function Sync-CodexUsageSnapshot {
    if (-not (Test-Path -LiteralPath $script:CodexUsagePath)) { return }
    try {
        $usage = Get-Content -LiteralPath $script:CodexUsagePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($null -ne $usage -and $usage.source -eq 'codex-app-server') { $script:State.liveUsage = $usage }
    } catch { $script:State.liveUsage.lastError = 'The Codex usage cache could not be read.' }
}

function Set-ProviderRefreshFailure {
    param([string]$Source, [string]$Message)
    $script:ProviderRefreshErrors[$Source] = $Message
    try { switch ($Source) {
        'codex' {
            $script:State.liveUsage.lastError='network_error'
            $script:State.liveUsage.lastCheckedAt=Format-DateForStorage (Get-Date)
            Write-OpenCodeGoJsonAtomically -Path $script:CodexUsagePath -Value $script:State.liveUsage -MutexName 'UsageTrayPillCodexUsageWrite'
        }
        'claude' {
            $previous=$null
            try { $previous=Get-Content -LiteralPath $script:ClaudeControlUsagePath -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop } catch {}
            $failure=New-UtpExternalUsageFailure 'claude-code-control' 'provider_error' $Message
            $snapshot=Merge-UtpClaudeUsageSnapshot -Current $failure -Previous $previous
            Write-OpenCodeGoJsonAtomically -Path $script:ClaudeControlUsagePath -Value $snapshot -MutexName 'UsageTrayPillClaudeControlUsageWrite'
        }
        'antigravity' { Write-AntigravityUsageSnapshot ([pscustomobject]@{source='antigravity-language-server';lastCheckedAt=Format-DateForStorage (Get-Date);lastError=$Message;available=$false;items=@()}) }
        'opencodego' { Set-OpenCodeGoFailureSnapshot -Code network_error -Message $Message }
        'qwen' { Set-QwenFailureSnapshot -Code network_error -Message $Message }
    } } catch { } # Keep the in-memory error visible even if the cache cannot be written.
}

function Get-ProviderCacheVersion {
    param([string]$Source)
    $path = switch ($Source) {
        'codex' { $script:CodexUsagePath }
        'claude' { $script:ClaudeControlUsagePath }
        'antigravity' { $script:AntigravityUsagePath }
        'opencodego' { $script:OpenCodeGoUsagePath }
        'qwen' { $script:QwenUsagePath }
    }
    $file = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
    if ($null -eq $file) { return 0L }
    return $file.LastWriteTimeUtc.Ticks
}

function Stop-OwnedRefreshProcess {
    param([System.Diagnostics.Process]$Process)
    if ($null -eq $Process) { return }
    try {
        if (-not $Process.HasExited) {
            # Kill only this worker's descendants, discovered before its parent exits.
            foreach ($childId in @(Get-DescendantProcessIds @($Process.Id))) {
                Stop-Process -Id $childId -Force -ErrorAction SilentlyContinue
            }
            $Process.Kill()
            [void]$Process.WaitForExit(2000)
        }
    } catch {} finally { $Process.Dispose() }
}

function Start-ProviderUsageRefresh {
    param([ValidateSet('codex','claude','antigravity','opencodego','qwen')][string]$Source)
    if($Source -eq 'opencodego' -and -not $script:State.settings.openCodeGoEnabled){return}
    if($Source -eq 'qwen' -and -not $script:State.settings.qwenTokenPlanEnabled){return}
    if($Source -eq 'claude' -and -not $script:State.settings.claudeControlEnabled){return}
    if($script:ProviderRefreshes.ContainsKey($Source)){return}
    $path=Join-Path $script:DataDir 'refresh-requests.json'
    $requests=[pscustomobject]@{}
    try{if(Test-Path $path){$requests=Get-Content $path -Raw|ConvertFrom-Json}}catch{}
    $requests|Add-Member -NotePropertyName $Source -NotePropertyValue ([guid]::NewGuid().ToString('N')) -Force
    $version=Get-ProviderCacheVersion -Source $Source
    Write-OpenCodeGoJsonAtomically -Path $path -Value $requests -MutexName 'UsageTrayPillRefreshRequests'
    $script:ProviderRefreshes[$Source]=[pscustomobject]@{StartedAt=Get-Date;CacheVersion=$version}
    $script:ProviderRefreshErrors.Remove($Source)
    Start-UsageCollection
}

function Update-ProviderRefreshProcessState {
    $changed=$false
    foreach($source in @($script:ProviderRefreshes.Keys)){
        $request=$script:ProviderRefreshes[$source]
        if($null -eq $request){continue}
        if((Get-ProviderCacheVersion $source) -gt $request.CacheVersion){
            $script:ProviderRefreshes.Remove($source);$script:ProviderRefreshErrors.Remove($source);$changed=$true
            if($source -eq 'codex'){Sync-CodexUsageSnapshot}
        }elseif(((Get-Date)-$request.StartedAt).TotalSeconds -ge 45){
            $script:ProviderRefreshes.Remove($source)
            # Provider requests have their own bounded lifetimes. A UI deadline
            # must not terminate the shared collector or unrelated requests.
            Set-ProviderRefreshFailure -Source $source -Message 'Refresh timed out. Try again.'
            $changed=$true
        }
    }
    if($null -ne $script:CollectorProcess -and $script:CollectorProcess.HasExited){
        $script:CollectorProcess.Dispose();$script:CollectorProcess=$null
        $script:CollectorRestartAt=(Get-Date).AddSeconds(30)
        $script:CollectorStatus='Reconnecting...'
        $changed=$true
    }
    Start-UsageCollection
    if($changed){Refresh-Tray;if($null -ne $script:RefreshMainWindow){& $script:RefreshMainWindow}}
}

function Stop-ProviderUsageRefresh {
    param([string]$Source)
    # Stop the collector to cancel any in-flight request before disabling/removing credentials.
    Stop-UsageCollection
    $script:ProviderRefreshErrors.Remove($Source)
}

function Start-AllUsageRefresh {
    foreach ($source in @('codex','claude','antigravity','opencodego','qwen')) { Start-ProviderUsageRefresh -Source $source }
    Refresh-Tray
    if ($null -ne $script:RefreshMainWindow) { & $script:RefreshMainWindow }
}

function Start-OpenCodeGoUsageRefresh { Start-ProviderUsageRefresh -Source opencodego }
function Stop-OpenCodeGoUsageRefresh { Stop-ProviderUsageRefresh -Source opencodego }
function Start-QwenUsageRefresh { Start-ProviderUsageRefresh -Source qwen }
function Stop-QwenUsageRefresh { Stop-ProviderUsageRefresh -Source qwen }

function Start-TrayApp {
    $createdNew = $false
    $script:Mutex = New-Object System.Threading.Mutex($true, "UsageTrayPill", [ref]$createdNew)
    if (-not $createdNew) {
        $script:Mutex.Dispose()
        $script:Mutex = $null
        return
    }

    $timer = $null
    $badgeKeepAliveTimer = $null
    $claudeKeeperTimer = $null
    $usageTimer = $null
    $antigravityTimer = $null
    $openCodeGoTimer = $null
    $qwenTimer = $null
    try {
        Ensure-ClaudeUsageKeeper

        Start-UsageCollection
        Start-UsageMonitoring

    $script:NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $script:NotifyIcon.ContextMenuStrip = New-TrayMenu
    $script:NotifyIcon.Visible = $true
    $script:NotifyIcon.Add_MouseClick({
        param($eventSource, $eventData)
        if ($eventData.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            Show-MainWindow
        }
    })
    $script:NotifyIcon.Add_MouseDoubleClick({
        param($eventSource, $eventData)
        if ($eventData.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            Show-MainWindow
        }
    })

    Refresh-Tray

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 60000
    $timer.Add_Tick({
        Refresh-Tray
        if ($null -ne $script:RefreshMainWindow) {
            & $script:RefreshMainWindow
        }
    })
    $timer.Start()

    $badgeKeepAliveTimer = New-Object System.Windows.Forms.Timer
    $badgeKeepAliveTimer.Interval = 500
    $badgeKeepAliveTimer.Add_Tick({
        Update-ProviderRefreshProcessState
        if ($null -ne $script:UsageMonitor -and $script:UsageMonitor.ConsumeChanges()) {
            foreach($name in $script:UsageMonitor.TakeChangedFiles()) {
                foreach($source in @('codex','claude','antigravity','opencodego','qwen')) {
                    if($name -eq '*' -or $name -eq [IO.Path]::GetFileName((Get-ProviderCachePath $source))){$script:ProviderRefreshErrors.Remove($source)}
                }
            }
            Sync-CodexUsageSnapshot
            Refresh-Tray
            if ($null -ne $script:RefreshMainWindow) { & $script:RefreshMainWindow }
        }
        if ($script:PendingStateSave -and -not $script:BadgeAnimating) {
            try { Save-State; $script:PendingStateSave = $false } catch { }
        }
        if ([bool]$script:State.settings.showTaskbarBadge) {
            Refresh-TaskbarBadge -GeometryOnly
        }
    })
    $badgeKeepAliveTimer.Start()

    $claudeKeeperTimer = New-Object System.Windows.Forms.Timer
    $claudeKeeperTimer.Interval = 30000
    $claudeKeeperTimer.Add_Tick({
        Ensure-ClaudeUsageKeeper
    })
    $claudeKeeperTimer.Start()

    if ($OpenEditor) {
        Show-MainWindow
    }

        [System.Windows.Forms.Application]::Run()
    }
    finally {
        foreach ($runtimeTimer in @(
            $timer,
            $badgeKeepAliveTimer,
            $claudeKeeperTimer,
            $usageTimer,
            $antigravityTimer,
            $openCodeGoTimer,
            $qwenTimer
        )) {
            if ($null -eq $runtimeTimer) { continue }
            try { $runtimeTimer.Stop() } catch {
            }
            try { $runtimeTimer.Dispose() } catch {
            }
        }

        Stop-UsageCollection
        if ($null -ne $script:UsageMonitor) { $script:UsageMonitor.Dispose();$script:UsageMonitor=$null }
        if ($script:PendingStateSave) { try { Save-State } catch {} }
        Dispose-TaskbarBadge
        Stop-ClaudeUsageKeeper
        if ($null -ne $script:NotifyIcon) {
            try {
                $script:NotifyIcon.Visible = $false
                $script:NotifyIcon.Dispose()
            }
            catch {
            }
            $script:NotifyIcon = $null
        }
        if ($null -ne $script:Mutex) {
            try { $script:Mutex.ReleaseMutex() } catch {
            }
            $script:Mutex.Dispose()
            $script:Mutex = $null
        }
    }
}

function Assert-SelfTest {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw "Self-test failed: $Message"
    }
}

function Invoke-SelfTest {
    $ErrorActionPreference = "Stop"
    $defaultState = New-DefaultState
    Assert-SelfTest (-not [bool]$defaultState.settings.keepClaudeCodeAlive) "new installations must disable the Claude keeper by default"
    Assert-SelfTest (-not [bool]$defaultState.settings.openCodeGoEnabled) "OpenCode Go must remain disabled without explicit setup"
    Assert-SelfTest (-not [bool]$defaultState.settings.qwenTokenPlanEnabled) "Qwen Token Plan must remain disabled without explicit setup"

    Assert-SelfTest ($null -ne (Get-Command Get-SilentTrayLaunchCommand -ErrorAction SilentlyContinue)) "the hidden tray launch helper must exist"
    $silentLaunch = Get-SilentTrayLaunchCommand -ScriptPath (Join-Path $PSScriptRoot "Start-UsageTrayPill.ps1")
    Assert-SelfTest ($silentLaunch -match "-WindowStyle Hidden") "the tray launcher must start PowerShell hidden"
    Assert-SelfTest ($silentLaunch -notmatch "-OpenEditor") "the tray launcher must not open the editor"
    Assert-SelfTest ($silentLaunch -match [regex]::Escape("Start-UsageTrayPill.ps1")) "the tray launcher must start the tray script"

    Assert-SelfTest ($null -ne (Get-Command Get-TrayIconPath -ErrorAction SilentlyContinue)) "the UTP tray icon helper must exist"
    $hiddenBadgeLogoLocation = Get-HiddenBadgeLogoLocation
    Assert-SelfTest ($hiddenBadgeLogoLocation.X -eq 0 -and $hiddenBadgeLogoLocation.Y -eq -(ConvertTo-BadgePixels 22)) "the hidden provider logo must sit above the pill without a New-Object argument error"
    $mainScriptSource = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "Start-UsageTrayPill.ps1"))
    Assert-SelfTest ($mainScriptSource -notmatch '(?m)^\s*function\s+Refresh-WindowLists\b') "main-window refresh must not depend on a function scoped to Show-MainWindow"
    Assert-SelfTest ($null -ne (Get-Command Update-MainWindow -ErrorAction SilentlyContinue)) "main-window refresh must use the live script state and retained controls"
    Assert-SelfTest ($mainScriptSource -match '(?s)\$timer\.Add_Tick\(\{.*?&\s+\$script:RefreshMainWindow') "the post-return timer callback must invoke the retained refresh closure"
    Assert-SelfTest ($mainScriptSource -match '\$title\.Text\s*=\s*"Usage overview"') "the main window must expose a clear visual title"
    Assert-SelfTest ($mainScriptSource -match '\$tabs\.DrawMode\s*=\s*\[System\.Windows\.Forms\.TabDrawMode\]::OwnerDrawFixed') "the main window must use the styled tab treatment"
    $testMainButton = New-Object System.Windows.Forms.Button
    try {
        Set-MainWindowButtonStyle -Button $testMainButton -Kind "Primary"
        Assert-SelfTest ($testMainButton.FlatStyle -eq [System.Windows.Forms.FlatStyle]::Flat) "main-window buttons must use the flat native style"
        Assert-SelfTest ($testMainButton.BackColor.ToArgb() -eq ([System.Drawing.Color]::FromArgb(208, 34, 121)).ToArgb()) "the primary main-window action must use the UTP accent color"
        Assert-SelfTest ($testMainButton.ForeColor.ToArgb() -eq [System.Drawing.Color]::White.ToArgb()) "the primary main-window action must retain readable contrast"
    }
    finally {
        $testMainButton.Dispose()
    }
    $testMainList = New-ListView -X 0 -Y 0 -Width 320 -Height 120
    try {
        [void]$testMainList.Items.Add("First")
        [void]$testMainList.Items.Add("Second")
        Set-MainWindowListRows -List $testMainList
        Assert-SelfTest (-not $testMainList.GridLines) "main-window lists must avoid the spreadsheet-style grid"
        Assert-SelfTest ($testMainList.Items[0].BackColor.ToArgb() -ne $testMainList.Items[1].BackColor.ToArgb()) "main-window lists must use subtle alternating rows"
    }
    finally {
        $testMainList.Dispose()
    }
    $postReturnRefresh = & {
        $retainedControl = [pscustomobject]@{ Text = "" }
        {
            $retainedControl.Text = "refreshed"
            return $retainedControl.Text
        }.GetNewClosure()
    }
    Assert-SelfTest ((& $postReturnRefresh) -eq "refreshed") "refresh closure must remain callable after its creator returns"

    $testTrayMenu = New-TrayMenu
    try {
        $onOpening = [System.Windows.Forms.ToolStripDropDown].GetMethod(
            "OnOpening",
            [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic)
        try {
            $openingEventArgs = [System.ComponentModel.CancelEventArgs](New-Object System.ComponentModel.CancelEventArgs)
            [void]$onOpening.Invoke($testTrayMenu, [object[]]@($openingEventArgs))
        }
        catch {
            throw "Self-test failed: tray menu opening must retain its menu items after New-TrayMenu returns: $($_.Exception.GetBaseException().Message)"
        }
    }
    finally {
        $testTrayMenu.Dispose()
    }

    $lightTrayIcon = Get-TrayIconPath -Theme "Light"
    $darkTrayIcon = Get-TrayIconPath -Theme "Dark"
    Assert-SelfTest ($lightTrayIcon -match "tray-icon-light\.ico$") "the light tray icon must be used"
    Assert-SelfTest ($darkTrayIcon -match "tray-icon-dark\.ico$") "the dark tray icon must be used"
    Assert-SelfTest ($null -ne (Get-Command Get-TrayIconImagePath -ErrorAction SilentlyContinue)) "the tray image helper must exist"
    Assert-SelfTest ((Get-TrayIconImagePath -Theme "Light") -match "tray-icon-light\.png$") "the light tray image must be used"
    Assert-SelfTest ((Get-TrayIconImagePath -Theme "Dark") -match "tray-icon-dark\.png$") "the dark tray image must be used"
    $traySignatureSnapshotA = [pscustomobject]@{ ActiveResetCount = 0; Level = "none" }
    $traySignatureSnapshotB = [pscustomobject]@{ ActiveResetCount = 3; Level = "soon" }
    $lightTraySignatureA = Get-TrayIconRenderSignature -Snapshot $traySignatureSnapshotA -Theme "Light"
    $lightTraySignatureB = Get-TrayIconRenderSignature -Snapshot $traySignatureSnapshotB -Theme "Light"
    Assert-SelfTest ($lightTraySignatureA -eq $lightTraySignatureB) "a static UTP asset must not be resent to the tray on every status check"
    Assert-SelfTest ($lightTraySignatureA -ne (Get-TrayIconRenderSignature -Snapshot $traySignatureSnapshotA -Theme "Dark")) "a system theme change must activate a new tray icon"

    Assert-SelfTest ($null -ne (Get-Command Test-CodexAppProcess -ErrorAction SilentlyContinue)) "the Codex/ChatGPT process helper must exist"
    Assert-SelfTest ($null -ne (Get-Command Resolve-CodexCommandPath -ErrorAction SilentlyContinue)) "the Codex command resolver must exist"
    Assert-SelfTest ($null -ne (Get-Command New-CodexAppServerStartInfo -ErrorAction SilentlyContinue)) "the Codex start-info helper must exist"
    $codexExeStartInfo = New-CodexAppServerStartInfo -CodexPath "C:\Program Files\Codex\codex.exe"
    Assert-SelfTest ($codexExeStartInfo.FileName -eq "C:\Program Files\Codex\codex.exe") "codex.exe must be started directly"
    Assert-SelfTest ($codexExeStartInfo.Arguments -eq "app-server --stdio") "codex.exe arguments must be fixed"
    $unsafeShimRejected = $false
    try { [void](New-CodexAppServerStartInfo -CodexPath "C:\Tools\bad&codex.cmd") } catch { $unsafeShimRejected = $true }
    Assert-SelfTest $unsafeShimRejected "a Codex cmd shim with metacharacters must be rejected"
    $legacyCodexProcess = [pscustomobject]@{ ProcessName = "Codex"; Path = "C:\Program Files\WindowsApps\OpenAI.Codex_1.0.0.0_x64__test\app\Codex.exe" }
    $chatGptProcess = [pscustomobject]@{ ProcessName = "ChatGPT"; Path = "C:\Program Files\WindowsApps\OpenAI.Codex_2.0.0.0_x64__test\app\ChatGPT.exe" }
    $unrelatedProcess = [pscustomobject]@{ ProcessName = "notepad"; Path = "C:\Windows\System32\notepad.exe" }
    Assert-SelfTest (Test-CodexAppProcess $legacyCodexProcess) "the legacy Codex process name must remain supported"
    Assert-SelfTest (Test-CodexAppProcess $chatGptProcess) "the new ChatGPT process name must count as the Codex app"
    Assert-SelfTest (-not (Test-CodexAppProcess $unrelatedProcess)) "an unrelated process must not count as the Codex app"

    # Worker overlap and completion are covered by Test-UtpReliability.ps1.

    Assert-SelfTest ($null -ne (Get-Command Get-CodexIconCandidatePaths -ErrorAction SilentlyContinue)) "the Codex/ChatGPT icon helper must exist"
    $chatGptIconCandidates = @(Get-CodexIconCandidatePaths -AppDirectory "C:\Program Files\WindowsApps\OpenAI.Codex_2.0.0.0_x64__test\app")
    Assert-SelfTest ($chatGptIconCandidates -contains "C:\Program Files\WindowsApps\OpenAI.Codex_2.0.0.0_x64__test\app\resources\icon-chatgpt.ico") "the new ChatGPT icon must be a candidate"
    Assert-SelfTest ($chatGptIconCandidates[0] -match "chatgpt-tray-light\.ico$") "the transparent ChatGPT tray icon must take precedence"
    Assert-SelfTest ($null -ne (Get-Command Get-ClaudeIconCandidatePaths -ErrorAction SilentlyContinue)) "the Claude icon helper must exist"
    $claudeIconCandidates = @(Get-ClaudeIconCandidatePaths -AppDirectory "C:\Program Files\WindowsApps\Claude_1.0.0.0_x64__test\app")
    Assert-SelfTest ($claudeIconCandidates -contains "C:\Program Files\WindowsApps\Claude_1.0.0.0_x64__test\app\resources\ion-dist\images\claude_app_icon.png") "the Claude app icon must be a candidate"
    Assert-SelfTest ($claudeIconCandidates[0] -match "Tray-Win32\.ico$") "the transparent Claude tray icon must take precedence"
    $antigravityIconRect = Get-AntigravityBadgeIconRectangle
    Assert-SelfTest ($antigravityIconRect.Width -eq 26 -and $antigravityIconRect.Height -eq 26) "the Antigravity icon must be large but drawn fully inside the pill"
    Assert-SelfTest (($antigravityIconRect.Left + ($antigravityIconRect.Width / 2)) -eq 24 -and $antigravityIconRect.Top -eq -1) "the Antigravity icon must be horizontally centered with an optical vertical adjustment"
    $originalBadgeDpiScale = $script:BadgeDpiScale
    try {
        $script:BadgeDpiScale = 1.5
        Assert-SelfTest ((ConvertTo-BadgePixels 176) -eq 264) "badge dimensions must scale to native pixels at 150 percent"
        Assert-SelfTest ([Math]::Abs((ConvertTo-BadgeFontPixels 10) - 20.0) -lt 0.01) "badge fonts must scale to native pixels at 150 percent"

        $script:BadgeDpiScale = 1.75
        $highDpiBadgeHeight = ConvertTo-BadgePixels 28
        $highDpiLogoSize = ConvertTo-BadgePixels 22
        $highDpiLogoLocation = Get-BadgeLogoViewportLocation -BadgeHeight $highDpiBadgeHeight
        $highDpiLogoCenter = $highDpiLogoLocation.Y + ($highDpiLogoSize / 2.0)
        Assert-SelfTest ($highDpiLogoLocation.Y -eq 5) "the provider logo must retain its one-pixel optical lift at 175 percent"
        Assert-SelfTest ([Math]::Abs($highDpiLogoCenter - ($highDpiBadgeHeight / 2.0)) -le 0.5) "the provider logo must remain vertically centered at 175 percent"
    }
    finally { $script:BadgeDpiScale = $originalBadgeDpiScale }

    $normalizedState = Normalize-State ([pscustomobject]@{
        planName = "Test"
        limits = @()
        resets = @()
        settings = [pscustomobject]@{}
        liveUsage = [pscustomobject]@{}
    })
    Assert-SelfTest (-not [bool]$normalizedState.settings.keepClaudeCodeAlive) "existing data without a keeper setting must remain disabled by default"
    Assert-SelfTest (-not [bool]$normalizedState.settings.openCodeGoEnabled) "existing data without an OpenCode Go setting must remain disabled by default"
    Assert-SelfTest (-not [bool]$normalizedState.settings.qwenTokenPlanEnabled) "existing data without a Qwen setting must remain disabled by default"
    Assert-SelfTest ((Get-NextTaskbarBadgeSource 'codex') -eq 'claude') "the click cycle must move from ChatGPT to Claude"
    Assert-SelfTest ((Get-NextTaskbarBadgeSource 'claude') -eq 'antigravity') "the click cycle must move from Claude to Antigravity"
    Assert-SelfTest ((Get-NextTaskbarBadgeSource 'antigravity') -eq 'codex') "the click cycle must move from Antigravity to ChatGPT"

    $freshClaudeStatuslineFixture = [pscustomobject]@{
        lastCheckedAt = Format-DateForStorage (Get-Date)
        lastError = ""
        fiveHourResetsAt = Format-DateForStorage (Get-Date).AddHours(2)
        sevenDayResetsAt = Format-DateForStorage (Get-Date).AddDays(2)
    }
    Assert-SelfTest (-not (Test-ClaudeUsageNeedsDesktopFallback $freshClaudeStatuslineFixture)) "a fresh Claude statusline snapshot must remain preferred"

    $staleClaudeStatuslineFixture = [pscustomobject]@{
        lastCheckedAt = Format-DateForStorage (Get-Date).AddMinutes(-30)
        lastError = ""
        fiveHourResetsAt = Format-DateForStorage (Get-Date).AddHours(2)
        sevenDayResetsAt = Format-DateForStorage (Get-Date).AddDays(2)
    }
    Assert-SelfTest (Test-ClaudeUsageNeedsDesktopFallback $staleClaudeStatuslineFixture) "a stale Claude statusline snapshot must use the Desktop fallback"

    $failedClaudeStatuslineFixture = [pscustomobject]@{
        lastCheckedAt = Format-DateForStorage (Get-Date)
        lastError = "statusline unavailable"
        fiveHourResetsAt = ""
        sevenDayResetsAt = ""
    }
    Assert-SelfTest (Test-ClaudeUsageNeedsDesktopFallback $failedClaudeStatuslineFixture) "a failed Claude statusline snapshot must use the Desktop fallback"

    # OpenCode API and credential migration are tested by Test-OpenCodeGoApi.ps1.

    $testQwenCookie = "login_qwencloud_ticket=selftest-ticket; login_aliyunid_pk=123; cna=selftest"
    Assert-SelfTest ((ConvertTo-QwenCookieHeader "Cookie: $testQwenCookie") -eq $testQwenCookie) "the Qwen Cookie header must be normalized"
    $qwenCrLfRejected = $false
    try { [void](ConvertTo-QwenCookieHeader "$testQwenCookie`r`nInjected: yes") } catch { $qwenCrLfRejected = $true }
    Assert-SelfTest $qwenCrLfRejected "a Qwen cookie with header injection must be rejected"
    $qwenUnrelatedCookieRejected = $false
    try { [void](ConvertTo-QwenCookieHeader "theme=dark; locale=en") } catch { $qwenUnrelatedCookieRejected = $true }
    Assert-SelfTest $qwenUnrelatedCookieRejected "Qwen configuration must require a login cookie"

    $limitedReaderBytes = [System.Text.Encoding]::UTF8.GetBytes("bounded")
    foreach ($readerTest in @(
        [pscustomobject]@{ Name = "OpenCode Go"; Command = { param($stream) Read-OpenCodeGoLimitedUtf8Stream -Stream $stream -MaximumBytes 7 } },
        [pscustomobject]@{ Name = "Qwen"; Command = { param($stream) Read-QwenLimitedUtf8Stream -Stream $stream -MaximumBytes 7 } }
    )) {
        $exactStream = New-Object System.IO.MemoryStream (,$limitedReaderBytes)
        try {
            Assert-SelfTest ((& $readerTest.Command $exactStream) -eq "bounded") "the $($readerTest.Name) reader must accept a response exactly at the limit"
        }
        finally {
            $exactStream.Dispose()
        }

        $oversizedBytes = New-Object byte[] 8
        $oversizedStream = New-Object System.IO.MemoryStream (,$oversizedBytes)
        $oversizedRejected = $false
        try {
            [void](& $readerTest.Command $oversizedStream)
        }
        catch {
            $oversizedRejected = $true
        }
        finally {
            $oversizedStream.Dispose()
        }
        Assert-SelfTest $oversizedRejected "the $($readerTest.Name) reader must reject an oversized response while reading"
    }

    $qwenReset5h = [DateTimeOffset]::Now.AddHours(2).ToUnixTimeMilliseconds()
    $qwenResetWeekly = [DateTimeOffset]::Now.AddDays(5).ToUnixTimeMilliseconds()
    $qwenDirectUsage = @(ConvertFrom-QwenUsageResponse ([pscustomobject]@{
        per5HourPercentage = 0.491
        per5HourResetTime = $qwenReset5h
        per1WeekPercentage = 0.155
        per1WeekResetTime = $qwenResetWeekly
    }))
    Assert-SelfTest (($qwenDirectUsage.label -join ",") -eq "5h,weekly") "Qwen quotas must appear in a fixed order"
    Assert-SelfTest ([Math]::Abs($qwenDirectUsage[0].remainingPercent - 50.9) -lt 0.001 -and [Math]::Abs($qwenDirectUsage[1].remainingPercent - 84.5) -lt 0.001) "Qwen consumed fractions must preserve remaining precision"
    $qwenWrappedUsage = @(ConvertFrom-QwenUsageResponse ([pscustomobject]@{
        data = [pscustomobject]@{
            DataV2 = [pscustomobject]@{
                data = [pscustomobject]@{
                    data = [pscustomobject]@{
                        per5HourPercentage = 0.04
                        per5HourResetTime = $qwenReset5h
                        per1WeekPercentage = 0.25
                        per1WeekResetTime = $qwenResetWeekly
                    }
                }
            }
        }
    }))
    Assert-SelfTest (($qwenWrappedUsage.remainingPercent -join ",") -eq "96,75") "the Qwen gateway envelope must be unpacked correctly"
    $qwenUnknownPercentageRejected = $false
    try {
        [void](ConvertFrom-QwenUsageResponse ([pscustomobject]@{
            per5HourPercentage = 49.1
            per5HourResetTime = $qwenReset5h
        }))
    }
    catch { $qwenUnknownPercentageRejected = ((Get-QwenExceptionCode $_) -eq "parse_error") }
    Assert-SelfTest $qwenUnknownPercentageRejected "Qwen must reject an unexpected percentage format"
    $qwenPartialUsage = @(ConvertFrom-QwenUsageResponse ([pscustomobject]@{
        per1WeekPercentage = 0.25
        per1WeekResetTime = $qwenResetWeekly
    }))
    Assert-SelfTest ($qwenPartialUsage.Count -eq 1 -and $qwenPartialUsage[0].key -eq "seven_day") "a partial Qwen response must retain usable windows"

    $oldQwenCredentialPath = $script:QwenCredentialPath
    $oldQwenEnvironmentCookie = $env:QWEN_TOKEN_PLAN_COOKIE
    $tempQwenCredentialPath = Join-Path ([System.IO.Path]::GetTempPath()) ("qwen-token-plan-credentials-" + [Guid]::NewGuid().ToString("N") + ".json")
    try {
        $env:QWEN_TOKEN_PLAN_COOKIE = $null
        $script:QwenCredentialPath = $tempQwenCredentialPath
        Save-QwenCredentials -CookieHeader $testQwenCookie
        $storedQwenCredential = Get-Content -LiteralPath $tempQwenCredentialPath -Raw
        Assert-SelfTest ($storedQwenCredential -notmatch [regex]::Escape("selftest-ticket")) "the Qwen cookie must not be stored as plaintext"
        $roundTripQwenCredential = Get-QwenCredentials
        Assert-SelfTest ($roundTripQwenCredential.cookieHeader -eq $testQwenCookie) "the Qwen DPAPI credential round trip must restore the cookie"
        Assert-SelfTest ($roundTripQwenCredential.source -eq "dpapi") "a locally stored Qwen credential must be identifiable as a DPAPI source"
    }
    finally {
        $script:QwenCredentialPath = $oldQwenCredentialPath
        $env:QWEN_TOKEN_PLAN_COOKIE = $oldQwenEnvironmentCookie
        Remove-Item -LiteralPath $tempQwenCredentialPath -Force -ErrorAction SilentlyContinue
    }

    $normalizedAntigravityUsage = [pscustomobject]@{
        source='antigravity-cli';lastCheckedAt=Format-DateForStorage (Get-Date);available=$true;lastError=''
        items=@([pscustomobject]@{key='fixture-a';label='Gemini';remainingPercent=91;resetsAt=''},[pscustomobject]@{key='fixture-b';label='Other';remainingPercent=100;resetsAt=''})
    }

    $oldSelfTestState = $script:State
    try {
        $script:State = New-DefaultState
        $script:State.liveUsage = [pscustomobject]@{
            lastCheckedAt = Format-DateForStorage (Get-Date)
            lastError = ""
            buckets = @(
                [pscustomobject]@{
                    limitId = "codex"
                    primaryRemainingPercent = 85
                    primaryWindowDurationMins = 10080
                    secondaryRemainingPercent = $null
                }
            )
        }
        $weeklyBadgeData = Get-TaskbarBadgeData -Source "codex"
        Assert-SelfTest ($weeklyBadgeData.PrimaryPrefix -eq "weekly") "the weekly-only badge must use the weekly label"
        Assert-SelfTest ($weeklyBadgeData.PrimaryText -eq "85%") "the weekly-only badge must show the primary weekly usage"
        Assert-SelfTest (@($weeklyBadgeData.Items).Count -eq 1) "the ChatGPT badge must contain one item"
        Assert-SelfTest ($weeklyBadgeData.Width -eq 176) "the ChatGPT badge must remain 176 pixels wide"
        $weeklyBadgeSignature = Get-TaskbarBadgeRenderSignature -Data $weeklyBadgeData
        Assert-SelfTest ($weeklyBadgeSignature -eq (Get-TaskbarBadgeRenderSignature -Data $weeklyBadgeData)) "unchanged badge content must retain the same render signature"
        $changedWeeklyBadgeData = [pscustomobject]@{
            Source = $weeklyBadgeData.Source
            Width = $weeklyBadgeData.Width
            Items = @([pscustomobject]@{
                Label = "weekly"
                Text = "84%"
                Color = Get-PercentColor -Percent 84
            })
        }
        Assert-SelfTest ($weeklyBadgeSignature -ne (Get-TaskbarBadgeRenderSignature -Data $changedWeeklyBadgeData)) "an actual quota change must trigger a new badge render"

        $script:State.settings.openCodeGoEnabled = $true
        Assert-SelfTest ((Get-NextTaskbarBadgeSource 'antigravity') -eq 'opencodego') "enabled OpenCode Go must follow Antigravity in the click cycle"
        Assert-SelfTest ((Get-NextTaskbarBadgeSource 'opencodego') -eq 'codex') "OpenCode Go must cycle back to ChatGPT"
        $script:State.settings.qwenTokenPlanEnabled = $true
        Assert-SelfTest ((Get-NextTaskbarBadgeSource 'opencodego') -eq 'qwen') "enabled Qwen must follow OpenCode Go in the click cycle"
        Assert-SelfTest ((Get-NextTaskbarBadgeSource 'qwen') -eq 'codex') "Qwen must cycle back to ChatGPT"
        $oldOpenCodeGoUsagePath = $script:OpenCodeGoUsagePath
        $tempOpenCodeGoUsagePath = Join-Path ([System.IO.Path]::GetTempPath()) ("opencode-go-usage-badge-" + [Guid]::NewGuid().ToString("N") + ".json")
        try {
            $script:OpenCodeGoUsagePath = $tempOpenCodeGoUsagePath
            [pscustomobject]@{
                version = 1
                source = "opencode-go-dashboard"
                credentialRevision = Get-UtpCredentialRevision 'opencodego'
                available = $true
                stale = $false
                lastCheckedAt = Format-DateForStorage (Get-Date)
                lastSuccessAt = Format-DateForStorage (Get-Date)
                lastError = ""
                lastErrorMessage = ""
                items = @(
                    [pscustomobject]@{ key = "five_hour"; label = "5h"; remainingPercent = 88; resetsAt = (Get-Date).AddHours(1).ToString("s") },
                    [pscustomobject]@{ key = "seven_day"; label = "weekly"; remainingPercent = 75; resetsAt = (Get-Date).AddDays(1).ToString("s") },
                    [pscustomobject]@{ key = "monthly"; label = "monthly"; remainingPercent = 56; resetsAt = (Get-Date).AddDays(10).ToString("s") }
                )
            } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tempOpenCodeGoUsagePath -Encoding UTF8
            $openCodeGoBadgeData = Get-TaskbarBadgeData -Source "opencodego"
            Assert-SelfTest (@($openCodeGoBadgeData.Items).Count -eq 3) "the OpenCode Go badge must show three quotas"
            Assert-SelfTest (($openCodeGoBadgeData.Items.Label -join ",") -eq "5h,weekly,monthly") "the OpenCode Go badge must use fixed labels"
            Assert-SelfTest (($openCodeGoBadgeData.Items.Text -join ",") -eq "88%,75%,56%") "the OpenCode Go badge must show current remaining percentages"
            Assert-SelfTest ($openCodeGoBadgeData.Width -gt $weeklyBadgeData.Width) "the OpenCode Go badge must expand dynamically for three values"

            Set-OpenCodeGoFailureSnapshot -Code "network_error" -Message "Temporarily unavailable."
            $staleOpenCodeGoUsage = Get-OpenCodeGoUsageSnapshot
            Assert-SelfTest ([bool]$staleOpenCodeGoUsage.available -and [bool]$staleOpenCodeGoUsage.stale) "a temporary OpenCode Go error must retain the recent cache"
            Assert-SelfTest (@($staleOpenCodeGoUsage.items).Count -eq 3) "a temporary OpenCode Go error must not clear recent quotas"

            Set-OpenCodeGoFailureSnapshot -Code "rate_limited" -Message "Try again later."
            $rateLimitedOpenCodeGoUsage = Get-OpenCodeGoUsageSnapshot
            Assert-SelfTest ([bool]$rateLimitedOpenCodeGoUsage.available -and [bool]$rateLimitedOpenCodeGoUsage.stale) "an OpenCode Go rate limit must retain the recent cache"
            Assert-SelfTest ((Get-OpenCodeGoStatusText) -eq "cache") "an OpenCode Go rate limit with cache must be shown as cache"

            Set-OpenCodeGoFailureSnapshot -Code "auth_expired" -Message "Session expired."
            $expiredOpenCodeGoUsage = Get-OpenCodeGoUsageSnapshot
            Assert-SelfTest (-not [bool]$expiredOpenCodeGoUsage.available) "expired OpenCode Go authentication must not show quotas as current"
            Assert-SelfTest (@($expiredOpenCodeGoUsage.items).Count -eq 0) "expired OpenCode Go authentication must clear visible quotas"

            [pscustomobject]@{
                version = 1
                source = "opencode-go-dashboard"
                credentialRevision = Get-UtpCredentialRevision 'opencodego'
                available = $true
                stale = $true
                lastCheckedAt = Format-DateForStorage (Get-Date)
                lastSuccessAt = Format-DateForStorage ((Get-Date).AddHours(-7))
                lastError = "network_error"
                lastErrorMessage = "Temporarily unavailable."
                items = @([pscustomobject]@{ key = "five_hour"; label = "5h"; remainingPercent = 88; resetsAt = "" })
            } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tempOpenCodeGoUsagePath -Encoding UTF8
            $tooOldOpenCodeGoUsage = Get-OpenCodeGoUsageSnapshot
            Assert-SelfTest (-not [bool]$tooOldOpenCodeGoUsage.available -and $null -eq $tooOldOpenCodeGoUsage.items[0].remainingPercent) "an OpenCode Go cache older than six hours must be shown as unknown"
        }
        finally {
            $script:OpenCodeGoUsagePath = $oldOpenCodeGoUsagePath
            Remove-Item -LiteralPath $tempOpenCodeGoUsagePath -Force -ErrorAction SilentlyContinue
        }

        $oldQwenUsagePath = $script:QwenUsagePath
        $tempQwenUsagePath = Join-Path ([System.IO.Path]::GetTempPath()) ("qwen-token-plan-usage-badge-" + [Guid]::NewGuid().ToString("N") + ".json")
        try {
            $script:QwenUsagePath = $tempQwenUsagePath
            [pscustomobject]@{
                version = 1
                source = "qwencloud-token-plan"
                credentialRevision = Get-UtpCredentialRevision 'qwen'
                available = $true
                stale = $false
                lastCheckedAt = Format-DateForStorage (Get-Date)
                lastSuccessAt = Format-DateForStorage (Get-Date)
                lastError = ""
                lastErrorMessage = ""
                items = @(
                    [pscustomobject]@{ key = "five_hour"; label = "5h"; remainingPercent = 51; resetsAt = (Get-Date).AddHours(2).ToString("s") },
                    [pscustomobject]@{ key = "seven_day"; label = "weekly"; remainingPercent = 85; resetsAt = (Get-Date).AddDays(5).ToString("s") }
                )
            } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tempQwenUsagePath -Encoding UTF8
            $qwenBadgeData = Get-TaskbarBadgeData -Source "qwen"
            Assert-SelfTest (($qwenBadgeData.Items.Label -join ",") -eq "5h,weekly") "the Qwen badge must use fixed labels"
            Assert-SelfTest (($qwenBadgeData.Items.Text -join ",") -eq "51%,85%") "the Qwen badge must show current remaining percentages"
            Assert-SelfTest ($qwenBadgeData.Width -gt $weeklyBadgeData.Width) "the Qwen badge must expand dynamically for two values"

            Set-QwenFailureSnapshot -Code "network_error" -Message "Temporarily unavailable."
            $staleQwenUsage = Get-QwenUsageSnapshot
            Assert-SelfTest ([bool]$staleQwenUsage.available -and [bool]$staleQwenUsage.stale) "a temporary Qwen error must retain the recent cache"
            Assert-SelfTest (@($staleQwenUsage.items).Count -eq 2) "a temporary Qwen error must not clear recent quotas"

            Set-QwenFailureSnapshot -Code "rate_limited" -Message "Try again later."
            $rateLimitedQwenUsage = Get-QwenUsageSnapshot
            Assert-SelfTest ([bool]$rateLimitedQwenUsage.available -and [bool]$rateLimitedQwenUsage.stale) "a Qwen rate limit must retain the recent cache"
            Assert-SelfTest ((Get-QwenStatusText) -eq "cache") "a Qwen rate limit with cache must be shown as cache"

            Set-QwenFailureSnapshot -Code "auth_expired" -Message "Session expired."
            $expiredQwenUsage = Get-QwenUsageSnapshot
            Assert-SelfTest (-not [bool]$expiredQwenUsage.available) "expired Qwen authentication must not show quotas as current"
            Assert-SelfTest (@($expiredQwenUsage.items).Count -eq 0) "expired Qwen authentication must clear visible quotas"

            [pscustomobject]@{
                version = 1
                source = "qwencloud-token-plan"
                credentialRevision = Get-UtpCredentialRevision 'qwen'
                available = $true
                stale = $true
                lastCheckedAt = Format-DateForStorage (Get-Date)
                lastSuccessAt = Format-DateForStorage ((Get-Date).AddHours(-7))
                lastError = "network_error"
                lastErrorMessage = "Temporarily unavailable."
                items = @([pscustomobject]@{ key = "five_hour"; label = "5h"; remainingPercent = 51; resetsAt = "" })
            } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tempQwenUsagePath -Encoding UTF8
            $tooOldQwenUsage = Get-QwenUsageSnapshot
            Assert-SelfTest (-not [bool]$tooOldQwenUsage.available -and $null -eq $tooOldQwenUsage.items[0].remainingPercent) "a Qwen cache older than six hours must be shown as unknown"
        }
        finally {
            $script:QwenUsagePath = $oldQwenUsagePath
            Remove-Item -LiteralPath $tempQwenUsagePath -Force -ErrorAction SilentlyContinue
        }

        $oldAntigravityUsagePath = $script:AntigravityUsagePath
        $tempAntigravityUsagePath = Join-Path ([System.IO.Path]::GetTempPath()) ("antigravity-usage-badge-" + [Guid]::NewGuid().ToString("N") + ".json")
        try {
            $script:AntigravityUsagePath = $tempAntigravityUsagePath
            $normalizedAntigravityUsage | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $tempAntigravityUsagePath -Encoding UTF8
            $antigravityBadgeData = Get-TaskbarBadgeData -Source 'antigravity'
            Assert-SelfTest (@($antigravityBadgeData.Items).Count -eq 2) "the Antigravity badge must show the two current quota groups"
            Assert-SelfTest ($antigravityBadgeData.Width -gt $weeklyBadgeData.Width) "the Antigravity badge must expand dynamically"
            Assert-SelfTest (($antigravityBadgeData.Items.Text -join ',') -eq '91%,100%') "the Antigravity badge must show current percentages"
        }
        finally {
            $script:AntigravityUsagePath = $oldAntigravityUsagePath
            Remove-Item -LiteralPath $tempAntigravityUsagePath -Force -ErrorAction SilentlyContinue
        }

        $badgeValueFont = New-BadgeFont -PointSize $script:BadgeValueFontSize -Bold $true
        $badgeLabelFont = New-BadgeFont -PointSize $script:BadgeLabelFontSize -Bold $true
        $badgeMeasurementBitmap = New-Object System.Drawing.Bitmap 1, 1
        $badgeMeasurementGraphics = [System.Drawing.Graphics]::FromImage($badgeMeasurementBitmap)
        try {
            $maximumBadgeValueWidth = [System.Windows.Forms.TextRenderer]::MeasureText(
                "100%",
                $badgeValueFont,
                (New-Object System.Drawing.Size 1000, (ConvertTo-BadgePixels 28)),
                ([System.Windows.Forms.TextFormatFlags]::SingleLine -bor [System.Windows.Forms.TextFormatFlags]::NoPadding)
            ).Width
            Assert-SelfTest ((ConvertTo-BadgePixels $script:BadgeValueWidth) -ge ($maximumBadgeValueWidth + (ConvertTo-BadgePixels 2))) "the 100% badge value must fit on one line with safety spacing"
            $weeklyTextWidth = [System.Windows.Forms.TextRenderer]::MeasureText("weekly", $badgeLabelFont, (New-Object System.Drawing.Size 1000, 28), ([System.Windows.Forms.TextFormatFlags]::SingleLine -bor [System.Windows.Forms.TextFormatFlags]::NoPadding)).Width
            Assert-SelfTest ((ConvertTo-BadgePixels (Get-BadgeLabelWidth -Text "weekly")) -ge $weeklyTextWidth) "the weekly label must fit on one line"
        }
        finally {
            $badgeMeasurementGraphics.Dispose()
            $badgeMeasurementBitmap.Dispose()
            $badgeValueFont.Dispose()
            $badgeLabelFont.Dispose()
        }

        Assert-SelfTest ($null -ne (Get-Command Get-BadgeTransitionEase -ErrorAction SilentlyContinue)) "the badge transition must use a shared easing helper"
        Assert-SelfTest ([Math]::Abs((Get-BadgeTransitionEase -Progress 0)) -lt 0.0001) "badge easing must start at exactly zero"
        Assert-SelfTest ([Math]::Abs((Get-BadgeTransitionEase -Progress 1) - 1) -lt 0.0001) "badge easing must end at exactly one"
        $easeSamples = @(0, 0.1, 0.25, 0.5, 0.75, 0.9, 1) | ForEach-Object { Get-BadgeTransitionEase -Progress $_ }
        for ($easeIndex = 1; $easeIndex -lt $easeSamples.Count; $easeIndex++) {
            Assert-SelfTest ($easeSamples[$easeIndex] -ge $easeSamples[$easeIndex - 1]) "badge easing must always move forward"
        }
        Assert-SelfTest ((Get-BadgeTransitionEase -Progress 0.25) -lt 0.15) "badge easing must accelerate gradually"
        Assert-SelfTest ((Get-BadgeTransitionEase -Progress 0.75) -gt 0.85) "badge easing must decelerate smoothly"
        Assert-SelfTest ($null -ne (Get-Command Set-TaskbarBadgeWidth -ErrorAction SilentlyContinue)) "the badge transition must be able to interpolate the pill width"
        foreach ($logoSource in @("codex", "claude")) {
            $logoImage = New-BadgeLogoImage -Size 22 -Source $logoSource
            try {
                Assert-SelfTest ([string]$logoImage.Tag -in @("local:$logoSource", "fallback:$logoSource")) "the $logoSource badge must render a local app icon or neutral fallback"
            }
            finally {
                $logoImage.Dispose()
            }
        }
        $openCodeExecutable = Get-OpenCodeAppPath
        if (-not [string]::IsNullOrWhiteSpace([string]$openCodeExecutable)) {
            $openCodeLogoImage = New-BadgeLogoImage -Size 22 -Source "opencodego"
            try {
                Assert-SelfTest ([string]$openCodeLogoImage.Tag -eq "local:opencodego") "the OpenCode Go badge must use the locally installed OpenCode icon"
            }
            finally {
                $openCodeLogoImage.Dispose()
            }
        }
        $qwenLogoImage = New-BadgeLogoImage -Size 22 -Source "qwen"
        try {
            Assert-SelfTest ([string]$qwenLogoImage.Tag -eq "official:qwen") "the Qwen badge must render the official Qwen Code logo"
        }
        finally {
            $qwenLogoImage.Dispose()
        }

        $oldClaudeUsagePath = $script:ClaudeUsagePath
        $tempClaudeUsagePath = Join-Path ([System.IO.Path]::GetTempPath()) ("claude-usage-badge-" + [Guid]::NewGuid().ToString("N") + ".json")
        try {
            $script:ClaudeUsagePath = $tempClaudeUsagePath
            [pscustomobject]@{
                source = "claude-code-statusline"; lastCheckedAt = Format-DateForStorage (Get-Date); lastError = ""
                fiveHourRemainingPercent = 49; fiveHourResetsAt = (Get-Date).AddHours(2).ToString("yyyy-MM-dd HH:mm:ss")
                sevenDayRemainingPercent = 42; sevenDayResetsAt = (Get-Date).AddDays(2).ToString("yyyy-MM-dd HH:mm:ss")
                limits = @(
                    [pscustomobject]@{ key = "five_hour"; label = "5h"; remainingPercent = 49; resetsAt = (Get-Date).AddHours(2).ToString("yyyy-MM-dd HH:mm:ss") },
                    [pscustomobject]@{ key = "seven_day"; label = "weekly"; remainingPercent = 42; resetsAt = (Get-Date).AddDays(2).ToString("yyyy-MM-dd HH:mm:ss") }
                )
            } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tempClaudeUsagePath -Encoding UTF8
            $claudeBadgeData = Get-TaskbarBadgeData -Source "claude"
            Assert-SelfTest (@($claudeBadgeData.Items).Count -eq 2) "the Claude badge must contain two items"
            Assert-SelfTest ((@($claudeBadgeData.Items).Label -join ",") -eq "5h,weekly") "Claude items must appear in a fixed order"
            Assert-SelfTest ($claudeBadgeData.Width -gt $weeklyBadgeData.Width) "the Claude badge must be wider"
            $claudeTestRow = New-BadgeRow -Y 0 -BackColor ([System.Drawing.Color]::White)
            try {
                Set-BadgeRowContent -Row $claudeTestRow -Data $claudeBadgeData
                Assert-SelfTest ($claudeTestRow.Source.Width -eq (ConvertTo-BadgePixels (Get-BadgeLabelWidth -Text "5h"))) "the 5h label must fit compactly on one line"
                Assert-SelfTest ($claudeTestRow.PrimaryValue.Width -eq (ConvertTo-BadgePixels (Get-BadgeLabelWidth -Text "weekly"))) "the weekly label must fit compactly on one line"
                Assert-SelfTest ($claudeTestRow.PrimaryPrefix.Width -eq (ConvertTo-BadgePixels $script:BadgeValueWidth)) "the 5h value must use the full badge value width"
                Assert-SelfTest ($claudeTestRow.Separator.Width -eq (ConvertTo-BadgePixels $script:BadgeValueWidth)) "the weekly value must use the full badge value width"
                Assert-SelfTest ($claudeTestRow.PrimaryPrefix.TextAlign -eq [System.Drawing.ContentAlignment]::MiddleLeft) "the 5h percentage must start immediately after the label"
                Assert-SelfTest ($claudeTestRow.Separator.TextAlign -eq [System.Drawing.ContentAlignment]::MiddleLeft) "the weekly percentage must start immediately after the label"
                Assert-SelfTest (($claudeTestRow.PrimaryPrefix.Left - $claudeTestRow.Source.Right) -eq (ConvertTo-BadgePixels $script:BadgeLabelValueGap)) "the 5h label and percentage must use the shared spacing"
                Assert-SelfTest (($claudeTestRow.PrimaryValue.Left - $claudeTestRow.PrimaryPrefix.Right) -eq (ConvertTo-BadgePixels $script:BadgeItemGap)) "Claude groups must use the shared inter-item spacing"
                Assert-SelfTest (($claudeTestRow.Separator.Left - $claudeTestRow.PrimaryValue.Right) -eq (ConvertTo-BadgePixels $script:BadgeLabelValueGap)) "the weekly label and percentage must use the shared spacing"
                Assert-SelfTest ($claudeTestRow.SecondaryPrefix.Width -eq 0) "the third Claude label must remain hidden"
                Assert-SelfTest ($claudeTestRow.SecondaryValue.Width -eq 0) "the third Claude value must remain hidden"
                Assert-SelfTest ($claudeTestRow.Panel.Width -ge (ConvertTo-BadgePixels (Get-BadgeContentWidth -Items $claudeBadgeData.Items))) "the Claude row must contain both labels and values compactly"
            }
            finally {
                $claudeTestRow.Panel.Dispose()
            }
            $codexBounds = Get-TaskbarBadgeBounds -Width $weeklyBadgeData.Width
            $claudeBounds = Get-TaskbarBadgeBounds -Width $claudeBadgeData.Width
            Assert-SelfTest ($codexBounds.Right -eq $claudeBounds.Right) "the badge's right edge must remain fixed when switching sources"
        }
        finally {
            $script:ClaudeUsagePath = $oldClaudeUsagePath
            Remove-Item -LiteralPath $tempClaudeUsagePath -Force -ErrorAction SilentlyContinue
        }

        $desktopHistory = [pscustomobject]@{
            version = 2
            samples = @(
                [pscustomobject]@{ t = [DateTimeOffset]::Now.AddMinutes(-5).ToUnixTimeMilliseconds(); u = [pscustomobject]@{ fh = 20; sd = 10 } },
                [pscustomobject]@{ t = [DateTimeOffset]::Now.ToUnixTimeMilliseconds(); u = [pscustomobject]@{ fh = 29; sd = 18; om = 35 } }
            )
        }
        $desktopUsage = Convert-ClaudeDesktopUsageHistory -History $desktopHistory
        Assert-SelfTest ($desktopUsage.source -eq "claude-desktop-plan-history") "Claude Desktop history must be identifiable as a source"
        Assert-SelfTest ($desktopUsage.fiveHourRemainingPercent -eq 71) "Claude Desktop five-hour remaining"
        Assert-SelfTest ($desktopUsage.sevenDayRemainingPercent -eq 82) "Claude Desktop weekly remaining"
    }
    finally {
        $script:State = $oldSelfTestState
    }

    Assert-SelfTest ($null -ne (Get-Command Test-WindowCoversMonitorBounds -ErrorAction SilentlyContinue)) "the fullscreen monitor-bounds helper must exist"
    $monitorBounds = New-Object System.Drawing.Rectangle 0, 0, 1920, 1080
    $fullscreenBounds = New-Object System.Drawing.Rectangle 0, 0, 1920, 1080
    $borderlessOverscanBounds = New-Object System.Drawing.Rectangle -1, -1, 1922, 1082
    $windowedBounds = New-Object System.Drawing.Rectangle 200, 100, 1280, 720
    $almostFullscreenWithGap = New-Object System.Drawing.Rectangle 3, 0, 1917, 1080
    Assert-SelfTest (Test-WindowCoversMonitorBounds -WindowBounds $fullscreenBounds -MonitorBounds $monitorBounds) "an exact fullscreen window must count as fullscreen"
    Assert-SelfTest (Test-WindowCoversMonitorBounds -WindowBounds $borderlessOverscanBounds -MonitorBounds $monitorBounds) "borderless overscan must count as fullscreen"
    Assert-SelfTest (-not (Test-WindowCoversMonitorBounds -WindowBounds $windowedBounds -MonitorBounds $monitorBounds)) "a normal window must not count as fullscreen"
    Assert-SelfTest (-not (Test-WindowCoversMonitorBounds -WindowBounds $almostFullscreenWithGap -MonitorBounds $monitorBounds)) "a visible gap larger than the tolerance must not count as fullscreen"
    Assert-SelfTest ($null -ne (Get-Command Test-WindowFullscreenState -ErrorAction SilentlyContinue)) "the fullscreen status helper must exist"
    Assert-SelfTest (Test-WindowFullscreenState -WindowBounds $fullscreenBounds -MonitorBounds $monitorBounds -IsMaximized $false) "borderless fullscreen must remain fullscreen"
    $maximizedWorkAreaBounds = New-Object System.Drawing.Rectangle 0, 0, 1920, 1040
    Assert-SelfTest (Test-WindowFullscreenState -WindowBounds $fullscreenBounds -MonitorBounds $monitorBounds -IsMaximized $true) "Chromium fullscreen with IsZoomed must remain fullscreen"
    Assert-SelfTest (-not (Test-WindowFullscreenState -WindowBounds $maximizedWorkAreaBounds -MonitorBounds $monitorBounds -IsMaximized $true)) "a normal window maximized to the taskbar must not count as fullscreen"

    $keeperPath = Get-NormalizedKeeperScriptPath
    $powerShellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

    $quotedKeeper = [pscustomobject]@{
        Name = "powershell.exe"
        CommandLine = "`"$powerShellPath`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$keeperPath`" -WorkingDirectory `"$env:USERPROFILE`""
    }
    Assert-SelfTest (Test-ClaudeKeeperProcess $quotedKeeper) "a quoted keeper command line must match"

    $unquotedKeeper = [pscustomobject]@{
        Name = "powershell.exe"
        CommandLine = "`"$powerShellPath`" -NoProfile -ExecutionPolicy Bypass -File $keeperPath -WorkingDirectory `"$env:USERPROFILE`""
    }
    Assert-SelfTest (Test-ClaudeKeeperProcess $unquotedKeeper) "an unquoted keeper command line must match"

    $inlineInspector = [pscustomobject]@{
        Name = "powershell.exe"
        CommandLine = "`"$powerShellPath`" -Command `" `$keeperPath='$keeperPath'; Write-Host '-File `"`"$keeperPath`"`"' `""
    }
    Assert-SelfTest (-not (Test-ClaudeKeeperProcess $inlineInspector)) "inline -Command inspection must not match"

    $wrongScript = [pscustomobject]@{
        Name = "powershell.exe"
        CommandLine = "`"$powerShellPath`" -NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\Start-UsageTrayPill.ps1`""
    }
    Assert-SelfTest (-not (Test-ClaudeKeeperProcess $wrongScript)) "another script must not match"

    $oldDataDir = $script:DataDir
    $oldCooldownPath = $script:ClaudeKeeperCooldownPath
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("UsageTrayPillSelfTest-" + [Guid]::NewGuid().ToString("N"))

    try {
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
        $script:DataDir = $tempDir
        $script:ClaudeKeeperCooldownPath = Join-Path $tempDir "claude-keeper-cooldown.json"

        Assert-SelfTest (-not (Test-ClaudeKeeperCooldownActive)) "a missing cooldown must not be active"

        [pscustomobject]@{
            disabledUntil = (Get-Date).AddMinutes(5).ToString("o")
            reason = "selftest"
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:ClaudeKeeperCooldownPath -Encoding UTF8
        Assert-SelfTest (Test-ClaudeKeeperCooldownActive) "a future cooldown must be active"

        [pscustomobject]@{
            disabledUntil = (Get-Date).AddMinutes(-5).ToString("o")
            reason = "selftest"
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:ClaudeKeeperCooldownPath -Encoding UTF8
        Assert-SelfTest (-not (Test-ClaudeKeeperCooldownActive)) "an expired cooldown must not remain active"
        Assert-SelfTest (-not (Test-Path -LiteralPath $script:ClaudeKeeperCooldownPath)) "an expired cooldown must be removed"
    }
    finally {
        $script:DataDir = $oldDataDir
        $script:ClaudeKeeperCooldownPath = $oldCooldownPath
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Self-test OK"
}

if ($LibraryOnly) { return }

if ($SelfTest) {
    Invoke-SelfTest
    exit 0
}

try { Load-State | Out-Null }
catch {
    if (-not ($RefreshLiveOnce -or $RefreshAntigravityOnce -or $RefreshOpenCodeGoOnce -or $RefreshQwenOnce -or $Validate)) {
        Show-Message -Text 'UTP could not read its saved settings. Your data has not been changed. Check data.json in the UsageTrayPill data folder and try again.'
    }
    exit 1
}
Sync-CodexUsageSnapshot

if ($Validate) {
    $snapshot = Get-StatusSnapshot
    Write-Host "OK - data: $script:DataPath"
    Write-Host "Plan: $($script:State.planName)"
    Write-Host "Active resets: $($snapshot.ActiveResetCount)"
    Write-Host "Codex active: $($snapshot.CodexRunning)"
    exit 0
}

if ($RefreshLiveOnce) {
    $ok = Update-LiveUsage
    Write-Host "Live refresh: $ok"
    Write-Host (Format-LiveUsageSummary)
    if (-not [string]::IsNullOrWhiteSpace([string]$script:State.liveUsage.lastError)) {
        Write-Host "Error: $($script:State.liveUsage.lastError)"
    }
    exit $(if ($ok) { 0 } else { 1 })
}

if ($RefreshAntigravityOnce) {
    $ok = Update-AntigravityCliUsage
    $usage = Get-AntigravityUsageSnapshot
    Write-Host "Antigravity refresh: $ok"
    if ($null -ne $usage -and [bool]$usage.available) {
        foreach ($item in @($usage.items)) {
            Write-Host "$($item.label): $($item.remainingPercent)% reset $($item.resetsAt)"
        }
    }
    elseif ($null -ne $usage) {
        Write-Host "Error: $($usage.lastError)"
    }
    exit $(if ($ok) { 0 } else { 1 })
}

if ($RefreshOpenCodeGoOnce) {
    $ok = Update-OpenCodeGoUsage
    $usage = Get-OpenCodeGoUsageSnapshot
    Write-Host "OpenCode Go refresh: $ok"
    if ($null -ne $usage -and [bool]$usage.available) {
        foreach ($item in @($usage.items)) {
            Write-Host "$($item.label): $($item.remainingPercent)% reset $($item.resetsAt)"
        }
        if ([bool]$usage.stale) { Write-Host "Status: cache" }
    }
    elseif ($null -ne $usage) {
        Write-Host "Error: $($usage.lastError)"
    }
    exit $(if ($ok) { 0 } else { 1 })
}

if ($RefreshQwenOnce) {
    $ok = Update-QwenUsage
    $usage = Get-QwenUsageSnapshot
    Write-Host "Qwen refresh: $ok"
    if ($null -ne $usage -and [bool]$usage.available) {
        foreach ($item in @($usage.items)) {
            Write-Host "$($item.label): $($item.remainingPercent)% reset $($item.resetsAt)"
        }
        if ([bool]$usage.stale) { Write-Host "Status: cache" }
    }
    elseif ($null -ne $usage) {
        Write-Host "Error: $($usage.lastError)"
    }
    exit $(if ($ok) { 0 } else { 1 })
}

Start-TrayApp
