param(
    [switch]$Validate,
    [switch]$RefreshLiveOnce,
    [switch]$RefreshAntigravityOnce,
    [switch]$RefreshOpenCodeGoOnce,
    [switch]$RefreshQwenOnce,
    [switch]$OpenEditor,
    [switch]$SelfTest
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

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:AppName = "Usage Tray Pill"
$script:DataDir = Join-Path $env:APPDATA "UsageTrayPill"
$script:DataPath = Join-Path $script:DataDir "data.json"
$script:ClaudeUsagePath = Join-Path $script:DataDir "claude-usage.json"
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
$script:RefreshMainWindow = $null
$script:BadgeForm = $null
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
$script:BadgeAnimationDurationMs = 340
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
            taskbarBadgeDefaultSource = "codex"
            keepClaudeCodeAlive = $false
            openCodeGoEnabled = $false
            qwenTokenPlanEnabled = $false
        }
        liveUsage = [pscustomobject]@{
            source = "codex-app-server"
            lastCheckedAt = ""
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
        Save-State
        return $script:State
    }

    try {
        $raw = Get-Content -LiteralPath $script:DataPath -Raw -ErrorAction Stop
        $state = $raw | ConvertFrom-Json -ErrorAction Stop
        $script:State = Normalize-State $state
        Save-State
        return $script:State
    }
    catch {
        $backupPath = "$($script:DataPath).broken-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $script:DataPath -Destination $backupPath -Force -ErrorAction SilentlyContinue
        $script:State = Normalize-State (New-DefaultState)
        Save-State
        return $script:State
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

    return ($active | Sort-Object Date | Select-Object -First 1)
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

    return ($items | Sort-Object Date | Select-Object -First 1)
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
                Select-Object -First 1
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

    if (Test-ClaudeCodeRunning -or Test-ClaudeKeeperRunning) {
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
        $task = $Process.StandardOutput.ReadLineAsync()
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        try {
            $message = $line | ConvertFrom-Json -ErrorAction Stop
            if ($message.PSObject.Properties.Name -contains "id" -and [int]$message.id -eq $ExpectedId) {
                return $message
            }
        }
        catch {
            continue
        }
    }

    throw "No app-server response for request ID $ExpectedId within $TimeoutSeconds seconds."
}

function Resolve-CodexCommandPath {
    $commands = @(Get-Command -Name "codex" -All -CommandType Application -ErrorAction SilentlyContinue)
    $command = $commands | Where-Object { [System.IO.Path]::GetExtension([string]$_.Source) -in @(".cmd", ".bat") } | Select-Object -First 1
    if ($null -eq $command) {
        $command = $commands | Where-Object { [System.IO.Path]::GetExtension([string]$_.Source) -ieq ".exe" } | Select-Object -First 1
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

    $psi.WorkingDirectory = $PSScriptRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    return $psi
}

function Invoke-CodexRateLimitsRead {
    $codexPath = Resolve-CodexCommandPath
    $psi = New-CodexAppServerStartInfo -CodexPath $codexPath

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    if (-not $process.Start()) {
        throw "Could not start the Codex app-server."
    }

    $stderrDrainTask = $process.StandardError.BaseStream.CopyToAsync([System.IO.Stream]::Null)
    try {
        $initialize = @{
            method = "initialize"
            id = 0
            params = @{
                clientInfo = @{
                    name = "usage-tray-pill"
                    version = "0.2.0"
                }
            }
        } | ConvertTo-Json -Depth 6 -Compress

        $rateLimits = @{
            method = "account/rateLimits/read"
            id = 1
        } | ConvertTo-Json -Depth 4 -Compress

        $process.StandardInput.WriteLine($initialize)
        $process.StandardInput.WriteLine($rateLimits)
        $process.StandardInput.Flush()

        [void](Get-JsonLineResponse -Process $process -ExpectedId 0 -TimeoutSeconds 15)
        $response = Get-JsonLineResponse -Process $process -ExpectedId 1 -TimeoutSeconds 20

        if ($response.PSObject.Properties.Name -contains "error" -and $null -ne $response.error) {
            throw [string]$response.error.message
        }

        return $response.result
    }
    finally {
        try {
            if (-not $process.HasExited) {
                $process.Kill()
            }
            [void]$process.WaitForExit(2000)
        }
        catch {
        }
        if ($null -ne $stderrDrainTask) {
            try { [void]$stderrDrainTask.Wait(500) } catch {
            }
        }
        $process.Dispose()
    }
}

function Convert-LiveBucket {
    param($Bucket)

    if ($null -eq $Bucket) {
        return $null
    }

    $primary = $Bucket.primary
    $secondary = $Bucket.secondary
    $credits = $Bucket.credits

    return [pscustomobject]@{
        limitId = [string]$Bucket.limitId
        limitName = [string]$Bucket.limitName
        planType = [string]$Bucket.planType
        primaryUsedPercent = $(if ($null -ne $primary) { [int][Math]::Round([double]$primary.usedPercent) } else { $null })
        primaryRemainingPercent = $(if ($null -ne $primary) { [int][Math]::Max(0, 100 - [double]$primary.usedPercent) } else { $null })
        primaryWindowDurationMins = $(if ($null -ne $primary) { $primary.windowDurationMins } else { $null })
        primaryResetsAt = $(if ($null -ne $primary) { Format-UnixDateForStorage $primary.resetsAt } else { "" })
        secondaryUsedPercent = $(if ($null -ne $secondary) { [int][Math]::Round([double]$secondary.usedPercent) } else { $null })
        secondaryRemainingPercent = $(if ($null -ne $secondary) { [int][Math]::Max(0, 100 - [double]$secondary.usedPercent) } else { $null })
        secondaryWindowDurationMins = $(if ($null -ne $secondary) { $secondary.windowDurationMins } else { $null })
        secondaryResetsAt = $(if ($null -ne $secondary) { Format-UnixDateForStorage $secondary.resetsAt } else { "" })
        creditsBalance = $(if ($null -ne $credits -and $credits.PSObject.Properties.Name -contains "balance") { [string]$credits.balance } else { "" })
        rateLimitReachedType = [string]$Bucket.rateLimitReachedType
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

        $mainBucket = $buckets | Where-Object { $_.limitId -eq "codex" } | Select-Object -First 1
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
        $script:State.liveUsage.resetCreditsAvailable = $resetCredits
        $script:State.liveUsage.buckets = @($buckets)
        $script:State.liveUsage.planType = $(if ($null -ne $mainBucket) { [string]$mainBucket.planType } else { "" })
        $script:State.liveUsage.creditsBalance = $(if ($null -ne $mainBucket) { [string]$mainBucket.creditsBalance } else { "" })
        Save-State
        return $true
    }
    catch {
        $script:State.liveUsage.lastCheckedAt = Format-DateForStorage (Get-Date)
        $script:State.liveUsage.lastError = $_.Exception.Message
        Save-State
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

    $buckets = @(As-Array $script:State.liveUsage.buckets)
    $bucket = $buckets | Where-Object { $_.limitId -eq "codex" } | Select-Object -First 1
    if ($null -ne $bucket) {
        return $bucket
    }

    if ($buckets.Count -gt 0) {
        return $buckets[0]
    }

    return $null
}

function Get-WeeklyBucketRemainingPercent {
    param([object]$Bucket = (Get-MainLiveBucket))

    if ($null -eq $Bucket) {
        return $null
    }

    $weeklyWindowMinutes = 7 * 24 * 60
    if ($null -ne $Bucket.primaryWindowDurationMins -and [double]$Bucket.primaryWindowDurationMins -ge $weeklyWindowMinutes -and $null -ne $Bucket.primaryRemainingPercent) {
        return $Bucket.primaryRemainingPercent
    }
    if ($null -ne $Bucket.secondaryWindowDurationMins -and [double]$Bucket.secondaryWindowDurationMins -ge $weeklyWindowMinutes -and $null -ne $Bucket.secondaryRemainingPercent) {
        return $Bucket.secondaryRemainingPercent
    }

    # Older snapshots may not contain window durations. Prefer the only populated window.
    if ($null -eq $Bucket.primaryRemainingPercent -and $null -ne $Bucket.secondaryRemainingPercent) {
        return $Bucket.secondaryRemainingPercent
    }
    if ($null -ne $Bucket.primaryRemainingPercent -and $null -eq $Bucket.secondaryRemainingPercent) {
        return $Bucket.primaryRemainingPercent
    }

    return $null
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

    if (((Get-Date) - $lastChecked).TotalMinutes -gt $maxAgeMinutes) {
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
        $used = [int][Math]::Max(0, [Math]::Min(100, [Math]::Round([double]$sample.u.($definition.Key))))
        $limits += [pscustomobject]@{
            key = $definition.SourceKey
            label = $definition.Label
            usedPercent = $used
            remainingPercent = 100 - $used
            resetsAt = ""
        }
    }

    $five = $limits | Where-Object { $_.key -eq "five_hour" } | Select-Object -First 1
    $seven = $limits | Where-Object { $_.key -eq "seven_day" } | Select-Object -First 1
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
        Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace([string]$historyPath)) { return $null }
    try {
        $history = Get-Content -LiteralPath $historyPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        return Convert-ClaudeDesktopUsageHistory -History $history
    }
    catch { return $null }
}

function Get-ClaudeUsageSnapshot {
    $usage = $null
    if (Test-Path -LiteralPath $script:ClaudeUsagePath) {
        try {
            $raw = Get-Content -LiteralPath $script:ClaudeUsagePath -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($raw)) { $usage = $raw | ConvertFrom-Json -ErrorAction Stop }
        }
        catch { $usage = $null }
    }

    if (Test-ClaudeUsageNeedsDesktopFallback $usage) {
        $desktopUsage = Get-ClaudeDesktopUsageSnapshot
        if ($null -ne $desktopUsage) { $usage = $desktopUsage }
    }

    if ($null -eq $usage) { return $null }
    try {
        $now = Get-Date
        if ($null -ne (Get-DateOrNull ([string]$usage.fiveHourResetsAt)) -and (Get-DateOrNull ([string]$usage.fiveHourResetsAt)) -lt $now) { $usage.fiveHourRemainingPercent = $null }
        if ($null -ne (Get-DateOrNull ([string]$usage.sevenDayResetsAt)) -and (Get-DateOrNull ([string]$usage.sevenDayResetsAt)) -lt $now) { $usage.sevenDayRemainingPercent = $null }
        foreach ($limit in @($usage.limits)) {
            $reset = Get-DateOrNull ([string]$limit.resetsAt)
            if ($null -ne $reset -and $reset -lt $now) { $limit.remainingPercent = $null }
        }
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

function Get-AntigravityLanguageServerContext {
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='language_server.exe'" -ErrorAction SilentlyContinue)
    foreach ($process in $processes) {
        $executablePath = [string]$process.ExecutablePath
        $commandLine = [string]$process.CommandLine
        if ([string]::IsNullOrWhiteSpace($executablePath) -or
            $executablePath -notmatch '(?i)\\antigravity\\resources\\bin\\language_server\.exe$' -or
            $commandLine -notmatch '(?i)(?:^|\s)--override_ide_name\s+antigravity(?:\s|$)' -or
            $commandLine -notmatch '(?i)(?:^|\s)--app_data_dir\s+antigravity(?:\s|$)') {
            continue
        }

        $tokenMatch = [regex]::Match($commandLine, '(?i)(?:^|\s)--csrf_token(?:=|\s+)(?:"([^"]+)"|''([^'']+)''|([^\s]+))')
        if (-not $tokenMatch.Success) { continue }
        $csrfToken = @($tokenMatch.Groups[1].Value, $tokenMatch.Groups[2].Value, $tokenMatch.Groups[3].Value) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -First 1
        if ([string]::IsNullOrWhiteSpace([string]$csrfToken)) { continue }

        $ports = @()
        try {
            $ports = @(Get-NetTCPConnection -State Listen -OwningProcess ([int]$process.ProcessId) -ErrorAction Stop |
                Where-Object { $_.LocalAddress -in @('127.0.0.1', '::1') } |
                Select-Object -ExpandProperty LocalPort -Unique)
        }
        catch { $ports = @() }
        if ($ports.Count -eq 0) { continue }

        return [pscustomobject]@{
            ProcessId = [int]$process.ProcessId
            ExecutablePath = $executablePath
            CsrfToken = [string]$csrfToken
            Ports = @($ports)
        }
    }

    return $null
}

function Read-AntigravityLimitedUtf8Stream {
    param(
        [Parameter(Mandatory = $true)] [System.IO.Stream]$Stream,
        [int]$MaximumBytes = 2097152
    )

    $memory = New-Object System.IO.MemoryStream
    $buffer = New-Object byte[] 8192
    $totalBytes = 0
    try {
        while (($read = $Stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $totalBytes += $read
            if ($totalBytes -gt $MaximumBytes) {
                throw 'Antigravity returned an unexpectedly large response.'
            }
            $memory.Write($buffer, 0, $read)
        }
        return [System.Text.Encoding]::UTF8.GetString($memory.ToArray())
    }
    finally {
        [Array]::Clear($buffer, 0, $buffer.Length)
        $memory.Dispose()
    }
}

function Invoke-AntigravityUserStatusRequest {
    param(
        [Parameter(Mandatory = $true)] [int]$Port,
        [Parameter(Mandatory = $true)] [string]$CsrfToken
    )

    $uri = "https://127.0.0.1:$Port/exa.language_server_pb.LanguageServerService/GetUserStatus"
    $request = [System.Net.HttpWebRequest]::Create($uri)
    $request.Method = 'POST'
    $request.ContentType = 'application/json'
    $request.Accept = 'application/json'
    $request.Timeout = 3500
    $request.ReadWriteTimeout = 3500
    $request.KeepAlive = $false
    $request.Headers.Add('Connect-Protocol-Version', '1')
    $request.Headers.Add('X-Codeium-Csrf-Token', $CsrfToken)
    $request.ServerCertificateValidationCallback = { $true }
    $body = [System.Text.Encoding]::UTF8.GetBytes('{"metadata":{"ideName":"antigravity"}}')
    $request.ContentLength = $body.Length

    $requestStream = $null
    $response = $null
    try {
        $requestStream = $request.GetRequestStream()
        $requestStream.Write($body, 0, $body.Length)
        $requestStream.Dispose()
        $requestStream = $null
        $response = $request.GetResponse()
        if ($response.ContentLength -gt 2097152) { throw 'Antigravity returned an unexpectedly large response.' }
        $responseStream = $response.GetResponseStream()
        try {
            $json = Read-AntigravityLimitedUtf8Stream -Stream $responseStream -MaximumBytes 2097152
        }
        finally {
            $responseStream.Dispose()
        }
        if ([string]::IsNullOrWhiteSpace($json)) { throw 'Antigravity returned an empty status response.' }
        return $json | ConvertFrom-Json -ErrorAction Stop
    }
    finally {
        if ($null -ne $response) { $response.Dispose() }
        if ($null -ne $requestStream) { $requestStream.Dispose() }
        $request.Abort()
    }
}

function Convert-AntigravityStatusToUsage {
    param([Parameter(Mandatory = $true)] [object]$StatusResponse)

    $configs = @(As-Array $StatusResponse.userStatus.cascadeModelConfigData.clientModelConfigs)
    $families = @{}
    foreach ($config in $configs) {
        if ($null -eq $config.quotaInfo -or $null -eq $config.quotaInfo.remainingFraction) { continue }
        try {
            $fraction = [double]$config.quotaInfo.remainingFraction
        }
        catch { continue }
        $remainingPercent = [int][Math]::Round([Math]::Min(1.0, [Math]::Max(0.0, $fraction)) * 100, 0)
        $modelLabel = [string]$config.label
        $family = if ($modelLabel -match '(?i)\bgemini\b') { 'Gemini' } elseif ($modelLabel -match '(?i)\bclaude\b') { 'Claude' } elseif ($modelLabel -match '(?i)\bgpt(?:-|\b)') { 'GPT' } else { 'Other' }
        $candidate = [pscustomobject]@{
            label = $family
            remainingPercent = $remainingPercent
            resetsAt = [string]$config.quotaInfo.resetTime
        }
        if (-not $families.ContainsKey($family) -or $remainingPercent -lt [int]$families[$family].remainingPercent) {
            $families[$family] = $candidate
        }
    }

    if ($families.Count -eq 0) { throw 'Antigravity returned no usable quotas.' }

    $items = @()
    if ($families.ContainsKey('Gemini')) { $items += $families['Gemini'] }
    if ($families.ContainsKey('Claude') -and $families.ContainsKey('GPT') -and
        [int]$families['Claude'].remainingPercent -eq [int]$families['GPT'].remainingPercent -and
        [string]$families['Claude'].resetsAt -eq [string]$families['GPT'].resetsAt) {
        $items += [pscustomobject]@{
            label = 'Other'
            remainingPercent = [int]$families['Claude'].remainingPercent
            resetsAt = [string]$families['Claude'].resetsAt
        }
    }
    else {
        if ($families.ContainsKey('Claude')) { $items += $families['Claude'] }
        if ($families.ContainsKey('GPT')) { $items += $families['GPT'] }
    }
    if ($families.ContainsKey('Other') -and $items.Count -lt 3) { $items += $families['Other'] }
    $items = @($items | Select-Object -First 3)

    return [pscustomobject]@{
        source = 'antigravity-language-server'
        lastCheckedAt = Format-DateForStorage (Get-Date)
        lastError = ''
        available = $true
        items = @($items)
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

function Update-AntigravityUsage {
    if ($script:AntigravityUsagePollInProgress) { return $false }
    $script:AntigravityUsagePollInProgress = $true
    try {
        $context = Get-AntigravityLanguageServerContext
        if ($null -eq $context) { throw 'Antigravity is not running.' }

        $lastError = $null
        foreach ($port in @($context.Ports)) {
            try {
                $status = Invoke-AntigravityUserStatusRequest -Port ([int]$port) -CsrfToken $context.CsrfToken
                $usage = Convert-AntigravityStatusToUsage -StatusResponse $status
                Write-AntigravityUsageSnapshot -Usage $usage
                return $true
            }
            catch { $lastError = $_ }
        }
        if ($null -ne $lastError) { throw 'The local Antigravity status is unreachable.' }
        throw 'Antigravity has no local status port.'
    }
    catch {
        Write-AntigravityUsageSnapshot -Usage ([pscustomobject]@{
            source = 'antigravity-language-server'
            lastCheckedAt = Format-DateForStorage (Get-Date)
            lastError = $_.Exception.Message
            available = $false
            items = @()
        })
        return $false
    }
    finally {
        $script:AntigravityUsagePollInProgress = $false
    }
}

function Get-AntigravityUsageSnapshot {
    if (-not (Test-Path -LiteralPath $script:AntigravityUsagePath)) { return $null }
    try {
        $usage = Get-Content -LiteralPath $script:AntigravityUsagePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not [bool]$usage.available) { return $usage }
        $now = Get-Date
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
    if ($null -ne $bucket.primaryRemainingPercent) {
        $parts += "5h remaining $($bucket.primaryRemainingPercent)% reset $(Format-ShortDisplayDate $bucket.primaryResetsAt)"
    }
    if ($null -ne $bucket.secondaryRemainingPercent) {
        $parts += "weekly remaining $($bucket.secondaryRemainingPercent)% reset $(Format-ShortDisplayDate $bucket.secondaryResetsAt)"
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
        $secondary = "$weeklyRemaining%"
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

    $neutralColor = [System.Drawing.Color]::FromArgb(120, 120, 120)

    if ($Source -eq "qwen") {
        $usage = Get-QwenUsageSnapshot
        $items = @()
        foreach ($definition in @(
            @{ Label = "5h"; Key = "five_hour" },
            @{ Label = "weekly"; Key = "seven_day" }
        )) {
            $remaining = $null
            if ($null -ne $usage -and [bool]$usage.available) {
                $match = @($usage.items) | Where-Object { $_.key -eq $definition.Key } | Select-Object -First 1
                if ($null -ne $match) { $remaining = $match.remainingPercent }
            }
            $items += [pscustomobject]@{
                Label = $definition.Label
                Text = $(if ($null -ne $remaining) { "$remaining%" } else { "--" })
                Color = $(if ($null -ne $remaining) { Get-PercentColor -Percent $remaining } else { $neutralColor })
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
                $match = @($usage.items) | Where-Object { $_.key -eq $definition.Key } | Select-Object -First 1
                if ($null -ne $match) { $remaining = $match.remainingPercent }
            }
            $items += [pscustomobject]@{
                Label = $definition.Label
                Text = $(if ($null -ne $remaining) { "$remaining%" } else { "--" })
                Color = $(if ($null -ne $remaining) { Get-PercentColor -Percent $remaining } else { $neutralColor })
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
            foreach ($item in @($usage.items) | Select-Object -First 3) {
                $remaining = $item.remainingPercent
                $items += [pscustomobject]@{
                    Label = [string]$item.label
                    Text = $(if ($null -ne $remaining) { "$remaining%" } else { "--" })
                    Color = $(if ($null -ne $remaining) { Get-PercentColor -Percent $remaining } else { $neutralColor })
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
                $match = @($usage.limits) | Where-Object { $_.key -eq $definition.Key -or $_.label -eq $definition.Label } | Select-Object -First 1
                if ($null -ne $match) { $remaining = $match.remainingPercent }
                elseif (-not [string]::IsNullOrWhiteSpace($definition.Legacy)) { $remaining = $usage.($definition.Legacy) }
            }
            $items += [pscustomobject]@{
                Label = $definition.Label
                Text = $(if ($null -ne $remaining) { "$remaining%" } else { "--" })
                Color = $(if ($null -ne $remaining) { Get-PercentColor -Percent $remaining } else { $neutralColor })
            }
        }

        return [pscustomobject]@{
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

    if ($null -ne $bucket) {
        $weeklyRemaining = Get-WeeklyBucketRemainingPercent -Bucket $bucket
        if ($null -ne $weeklyRemaining) {
            $codexSecondaryText = "$weeklyRemaining%"
            $codexSecondaryColor = Get-PercentColor -Percent $weeklyRemaining
        }
    }

    $codexItem = [pscustomobject]@{ Label = "weekly"; Text = $codexSecondaryText; Color = $codexSecondaryColor }
    return [pscustomobject]@{
        Source = "codex"
        SourceText = ""
        PrimaryPrefix = "weekly"
        PrimaryText = $codexSecondaryText
        PrimaryColor = $codexSecondaryColor
        SecondaryPrefix = ""
        SecondaryText = ""
        SecondaryColor = $neutralColor
        Items = @($codexItem)
        Width = [Math]::Max($script:BadgeMinimumWidth, $script:BadgeHorizontalChrome + (Get-BadgeContentWidth -Items @($codexItem)))
    }
}

function Get-TaskbarBadgeColor {
    return [System.Drawing.Color]::FromArgb(252, 252, 253)
}

function Get-TaskbarBadgeBorderColor {
    return [System.Drawing.Color]::FromArgb(216, 221, 229)
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
        return [System.Drawing.Color]::FromArgb(15, 157, 105)
    }

    if ($Percent -ge 20) {
        return [System.Drawing.Color]::FromArgb(202, 138, 4)
    }

    return [System.Drawing.Color]::FromArgb(209, 67, 67)
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
    $x = $bounds.Right - $trayArrowWidth - $width - (ConvertTo-BadgePixels 4)

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
                Select-Object -First 1
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
            Select-Object -First 1 -ExpandProperty Path

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
            Select-Object -First 1
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
            Select-Object -First 1 -ExpandProperty Path

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
            Select-Object -First 1
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
            Select-Object -First 1 -ExpandProperty Path
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
        [string]$Source = "codex"
    )

    $bitmap = New-Object System.Drawing.Bitmap $Size, $Size
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.Clear([System.Drawing.Color]::Transparent)

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
                        $imageRect = New-Object System.Drawing.Rectangle 0, 0, $Size, $Size
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
                            New-Object System.Drawing.Rectangle 0, 0, $Size, $Size
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

function New-RoundedRectanglePath {
    param(
        [System.Drawing.Rectangle]$Rect,
        [int]$Radius
    )

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = $Radius * 2

    $path.AddArc($Rect.X, $Rect.Y, $diameter, $diameter, 180, 90)
    $path.AddArc($Rect.Right - $diameter, $Rect.Y, $diameter, $diameter, 270, 90)
    $path.AddArc($Rect.Right - $diameter, $Rect.Bottom - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($Rect.X, $Rect.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()

    return $path
}

function Paint-TaskbarBadgeSurface {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.Rectangle]$ClientRectangle
    )

    if ($null -eq $Graphics -or $ClientRectangle.Width -le 1 -or $ClientRectangle.Height -le 1) {
        return
    }

    $Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $Graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    $surfaceRect = New-Object System.Drawing.Rectangle 0, 0, ($ClientRectangle.Width - 1), ($ClientRectangle.Height - 1)
    $radius = [Math]::Max(1, [int](($surfaceRect.Height - 1) / 2))
    $surfacePath = New-RoundedRectanglePath -Rect $surfaceRect -Radius $radius
    $surfaceBrush = New-Object System.Drawing.SolidBrush (Get-TaskbarBadgeColor)
    $borderPen = New-Object System.Drawing.Pen (Get-TaskbarBadgeBorderColor), 1
    try {
        $Graphics.FillPath($surfaceBrush, $surfacePath)
        $Graphics.DrawPath($borderPen, $surfacePath)

        $highlightInset = [Math]::Max(6, $radius)
        $highlightPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(210, 255, 255, 255)), 1
        try {
            $Graphics.DrawLine($highlightPen, $highlightInset, 1, ($surfaceRect.Right - $highlightInset), 1)
        }
        finally {
            $highlightPen.Dispose()
        }
    }
    finally {
        $borderPen.Dispose()
        $surfaceBrush.Dispose()
        $surfacePath.Dispose()
    }
}

function Set-RoundedBadgeRegion {
    if ($null -eq $script:BadgeForm -or $script:BadgeForm.IsDisposed) {
        return
    }

    $rect = New-Object System.Drawing.Rectangle 0, 0, $script:BadgeForm.Width, $script:BadgeForm.Height
    $path = New-RoundedRectanglePath -Rect $rect -Radius ([Math]::Max(1, [int]($script:BadgeForm.Height / 2)))
    $oldRegion = $script:BadgeForm.Region
    $script:BadgeForm.Region = New-Object System.Drawing.Region $path
    if ($null -ne $oldRegion) {
        $oldRegion.Dispose()
    }
    $path.Dispose()
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

    if ([string]$PictureBox.Tag -eq $Source -and $null -ne $PictureBox.Image) {
        return
    }

    $oldImage = $PictureBox.Image
    $PictureBox.Image = New-BadgeLogoImage -Size 22 -Source $Source
    $PictureBox.Tag = $Source
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
            $labelControl.ForeColor = [System.Drawing.Color]::FromArgb(52, 56, 64)
            $labelControl.Text = $item.Label
            $x = $labelControl.Right + $labelValueGap
            $valueControl.Location = New-Object System.Drawing.Point $x, 0
            $valueControl.Width = ConvertTo-BadgePixels $script:BadgeValueWidth
            $valueControl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
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
    if ($widthChanged -or $null -eq $script:BadgeForm.Region) {
        Set-RoundedBadgeRegion
    }
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
        $script:BadgeLogoNext.Location = New-Object System.Drawing.Point 0, -22
    }
}

function Get-TaskbarBadgeRenderSignature {
    param([Parameter(Mandatory = $true)] [object]$Data)

    $parts = @([string]$Data.Source, [string]$Data.Width)
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
    if ($null -ne $script:BadgeForm -and -not $script:BadgeForm.IsDisposed) {
        $script:BadgeForm.Invalidate()
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
    $elapsedMs = ((Get-Date) - $script:BadgeAnimationStartedAt).TotalMilliseconds
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
    $script:BadgeForm.Invalidate($true)
    $script:BadgeForm.Update()

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
    $script:BadgeAnimationStartedAt = Get-Date
    $script:BadgeAnimationHalfUpdated = $false
    $script:BadgeAnimating = $true
    $script:BadgeAnimationTimer.Start()
}

function Toggle-TaskbarBadgeDefaultSource {
    $next = Get-NextTaskbarBadgeSource (Get-TaskbarBadgeDefaultSource)
    $script:State.settings.taskbarBadgeDefaultSource = $next
    Save-State
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
        $badge = New-Object System.Windows.Forms.Form
        $badge.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
        $badge.Text = "Usage Tray Pill"
        $badge.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
        $badge.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
        $badge.ShowInTaskbar = $false
        $badge.ShowIcon = $false
        $badge.TopMost = $false
        $badge.BackColor = Get-TaskbarBadgeColor
        $badge.Bounds = Get-TaskbarBadgeBounds
        Enable-ControlDoubleBuffering -Control $badge
        $badge.Add_Paint({
            param($eventSource, $eventData)
            Paint-TaskbarBadgeSurface -Graphics $eventData.Graphics -ClientRectangle $eventSource.ClientRectangle
        })

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
        $badge.Controls.Add($logoViewport)

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
        $badge.Controls.Add($textViewport)

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

function Refresh-TaskbarBadge {
    param([switch]$GeometryOnly)

    $geometryOnlyMode = [bool]$GeometryOnly
    if (-not [bool]$script:State.settings.showTaskbarBadge) {
        Hide-TaskbarBadge
        return
    }

    if (Test-ForegroundWindowFullscreen) {
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

    if ($boundsChanged -or $null -eq $script:BadgeForm.Region) {
        Set-RoundedBadgeRegion
    }

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
    $list.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $list.BackColor = [System.Drawing.Color]::White
    $list.ForeColor = [System.Drawing.Color]::FromArgb(36, 39, 46)
    $list.Font = New-Object System.Drawing.Font "Segoe UI", 9
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
    $Button.FlatAppearance.BorderSize = 1

    if ($Kind -eq "Primary") {
        $Button.BackColor = [System.Drawing.Color]::FromArgb(208, 34, 121)
        $Button.ForeColor = [System.Drawing.Color]::White
        $Button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(208, 34, 121)
        $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(187, 28, 107)
        $Button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(166, 23, 94)
        return
    }

    $Button.BackColor = [System.Drawing.Color]::White
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
    $form.ClientSize = New-Object System.Drawing.Size 960, 650
    $form.MinimumSize = New-Object System.Drawing.Size 900, 620
    $form.ShowInTaskbar = $true
    $form.BackColor = [System.Drawing.Color]::FromArgb(246, 247, 249)
    $form.ForeColor = [System.Drawing.Color]::FromArgb(36, 39, 46)
    $form.Font = New-Object System.Drawing.Font "Segoe UI", 9

    if ($null -ne $script:NotifyIcon -and $null -ne $script:NotifyIcon.Icon) {
        $form.Icon = $script:NotifyIcon.Icon
    }

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "Usage overview"
    $title.Location = New-Object System.Drawing.Point 20, 16
    $title.Size = New-Object System.Drawing.Size 500, 32
    $title.Font = New-Object System.Drawing.Font "Segoe UI Semibold", 17
    $form.Controls.Add($title)

    $header = New-Object System.Windows.Forms.Label
    $header.Location = New-Object System.Drawing.Point 22, 50
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
    $tabs.Location = New-Object System.Drawing.Point 20, 194
    $tabs.Size = New-Object System.Drawing.Size 920, 388
    $tabs.Anchor = "Top,Bottom,Left,Right"
    $tabs.DrawMode = [System.Windows.Forms.TabDrawMode]::OwnerDrawFixed
    $tabs.SizeMode = [System.Windows.Forms.TabSizeMode]::Fixed
    $tabs.ItemSize = New-Object System.Drawing.Size 124, 32
    $tabs.Padding = New-Object System.Drawing.Point 18, 4
    $tabs.Add_DrawItem({
        param($eventSource, $eventData)

        $isSelected = ($eventData.Index -eq $eventSource.SelectedIndex)
        $background = if ($isSelected) {
            [System.Drawing.Color]::White
        }
        else {
            [System.Drawing.Color]::FromArgb(246, 247, 249)
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
    $liveTab.Controls.Add($liveList)

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

    $script:RefreshMainWindow = {
        if ($null -eq $form -or $form.IsDisposed) {
            return
        }

        $snapshot = Get-StatusSnapshot
        $codexState = $(if ($snapshot.CodexRunning) { "active" } else { "inactive" })
        $resetLabel = $(if ($snapshot.ActiveResetCount -eq 1) { "active reset" } else { "active resets" })
        $header.Text = "Codex $codexState | $($snapshot.ActiveResetCount) $resetLabel"

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
        foreach ($bucket in @(As-Array $script:State.liveUsage.buckets)) {
            $bucketName = [string]$bucket.limitName
            if ([string]::IsNullOrWhiteSpace($bucketName)) {
                $bucketName = [string]$bucket.limitId
            }
            if ([string]::IsNullOrWhiteSpace($bucketName)) {
                $bucketName = "codex"
            }

            $item = New-Object System.Windows.Forms.ListViewItem $bucketName
            [void]$item.SubItems.Add($(if ($null -ne $bucket.primaryRemainingPercent) { "$($bucket.primaryRemainingPercent)%" } else { "-" }))
            [void]$item.SubItems.Add((Format-ShortDisplayDate $bucket.primaryResetsAt))
            [void]$item.SubItems.Add($(if ($null -ne $bucket.secondaryRemainingPercent) { "$($bucket.secondaryRemainingPercent)%" } else { "-" }))
            [void]$item.SubItems.Add((Format-ShortDisplayDate $bucket.secondaryResetsAt))
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
            $claudeStatus = $(if (-not [string]::IsNullOrWhiteSpace([string]$claudeUsage.lastError)) { "error" } else { "statusline" })
        }

        $claudeItem = New-Object System.Windows.Forms.ListViewItem $claudeName
        [void]$claudeItem.SubItems.Add($(if ($null -ne $claudeUsage -and $null -ne $claudeUsage.fiveHourRemainingPercent) { "$($claudeUsage.fiveHourRemainingPercent)%" } else { "-" }))
        [void]$claudeItem.SubItems.Add($(if ($null -ne $claudeUsage) { Format-ShortDisplayDate $claudeUsage.fiveHourResetsAt } else { "-" }))
        [void]$claudeItem.SubItems.Add($(if ($null -ne $claudeUsage -and $null -ne $claudeUsage.sevenDayRemainingPercent) { "$($claudeUsage.sevenDayRemainingPercent)%" } else { "-" }))
        [void]$claudeItem.SubItems.Add($(if ($null -ne $claudeUsage) { Format-ShortDisplayDate $claudeUsage.sevenDayResetsAt } else { "-" }))
        [void]$claudeItem.SubItems.Add("")
        [void]$claudeItem.SubItems.Add($(if ($null -ne $claudeUsage) { [string]$claudeUsage.version } else { "" }))
        [void]$claudeItem.SubItems.Add($claudeStatus)
        $claudeItem.Tag = $claudeUsage
        [void]$liveList.Items.Add($claudeItem)

        $openCodeGoUsage = Get-OpenCodeGoUsageSnapshot
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
        [void]$openCodeGoItem.SubItems.Add($(if ($null -ne $openCodeGoFiveHour -and $null -ne $openCodeGoFiveHour.remainingPercent) { "$($openCodeGoFiveHour.remainingPercent)%" } else { "-" }))
        [void]$openCodeGoItem.SubItems.Add($(if ($null -ne $openCodeGoFiveHour) { Format-ShortDisplayDate $openCodeGoFiveHour.resetsAt } else { "-" }))
        [void]$openCodeGoItem.SubItems.Add($(if ($null -ne $openCodeGoWeekly -and $null -ne $openCodeGoWeekly.remainingPercent) { "$($openCodeGoWeekly.remainingPercent)%" } else { "-" }))
        [void]$openCodeGoItem.SubItems.Add($(if ($null -ne $openCodeGoWeekly) { Format-ShortDisplayDate $openCodeGoWeekly.resetsAt } else { "-" }))
        [void]$openCodeGoItem.SubItems.Add($(if ($null -ne $openCodeGoMonthly -and $null -ne $openCodeGoMonthly.remainingPercent) { "$($openCodeGoMonthly.remainingPercent)%" } else { "-" }))
        [void]$openCodeGoItem.SubItems.Add("")
        [void]$openCodeGoItem.SubItems.Add((Get-OpenCodeGoStatusText))
        $openCodeGoItem.Tag = $openCodeGoUsage
        [void]$liveList.Items.Add($openCodeGoItem)

        $qwenUsage = Get-QwenUsageSnapshot
        $qwenValues = @{}
        if ($null -ne $qwenUsage) {
            foreach ($usageItem in @($qwenUsage.items)) {
                $qwenValues[[string]$usageItem.key] = $usageItem
            }
        }
        $qwenItem = New-Object System.Windows.Forms.ListViewItem "Qwen Token Plan"
        $qwenFiveHour = $qwenValues["five_hour"]
        $qwenWeekly = $qwenValues["seven_day"]
        [void]$qwenItem.SubItems.Add($(if ($null -ne $qwenFiveHour -and $null -ne $qwenFiveHour.remainingPercent) { "$($qwenFiveHour.remainingPercent)%" } else { "-" }))
        [void]$qwenItem.SubItems.Add($(if ($null -ne $qwenFiveHour) { Format-ShortDisplayDate $qwenFiveHour.resetsAt } else { "-" }))
        [void]$qwenItem.SubItems.Add($(if ($null -ne $qwenWeekly -and $null -ne $qwenWeekly.remainingPercent) { "$($qwenWeekly.remainingPercent)%" } else { "-" }))
        [void]$qwenItem.SubItems.Add($(if ($null -ne $qwenWeekly) { Format-ShortDisplayDate $qwenWeekly.resetsAt } else { "-" }))
        [void]$qwenItem.SubItems.Add("")
        [void]$qwenItem.SubItems.Add("")
        [void]$qwenItem.SubItems.Add((Get-QwenStatusText))
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

        Set-MainWindowListRows -List $liveList
        Set-MainWindowListRows -List $resetsList
        Set-MainWindowListRows -List $limitsList
        Refresh-Tray
    }.GetNewClosure()

    $savePlanButton.Add_Click({
        $script:State.planName = $planBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($script:State.planName)) {
            $script:State.planName = "ChatGPT Pro"
            $planBox.Text = $script:State.planName
        }
        Save-State
        if ($null -ne $script:RefreshMainWindow) { & $script:RefreshMainWindow }
    })

    $onlyCodexCheck.Add_CheckedChanged({
        $script:State.settings.showOnlyWhenCodexRuns = $onlyCodexCheck.Checked
        Save-State
        Refresh-Tray
    })

    $refreshLiveButton.Add_Click({
        $refreshLiveButton.Enabled = $false
        try {
            [void](Update-LiveUsage)
            [void](Update-AntigravityUsage)
            if ([bool]$script:State.settings.openCodeGoEnabled) {
                Start-OpenCodeGoUsageRefresh
            }
            if ([bool]$script:State.settings.qwenTokenPlanEnabled) {
                Start-QwenUsageRefresh
            }
            if ($null -ne $script:RefreshMainWindow) { & $script:RefreshMainWindow }
        }
        finally {
            $refreshLiveButton.Enabled = $true
        }
    })

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
        $selected = Get-SelectedTag $resetsList
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
        $selected = Get-SelectedTag $resetsList
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
        $selected = Get-SelectedTag $resetsList
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
        $selected = Get-SelectedTag $limitsList
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
        $selected = Get-SelectedTag $limitsList
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
    $openItem.Text = "Open reset bank"
    $openItem.Add_Click({ Show-MainWindow })
    [void]$menu.Items.Add($openItem)

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
        $script:State.settings.showTaskbarBadge = $badgeItem.Checked
        Save-State
        if ($badgeItem.Checked) {
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
        $script:State.settings.keepClaudeCodeAlive = $claudeKeeperItem.Checked
        if ($claudeKeeperItem.Checked) {
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

    $menuOpeningAction = {
        $script:TrayMenuOpen = $true
        $snapshot = Get-StatusSnapshot
        $badgeItem.Checked = [bool]$script:State.settings.showTaskbarBadge
        $claudeKeeperItem.Checked = [bool]$script:State.settings.keepClaudeCodeAlive
        $nextText = "no active reset"
        if ($null -ne $snapshot.NextReset) {
            $nextText = "next reset expires in $(Format-TimeLeft $snapshot.NextReset.Reset.expiresAt)"
        }
        $claudeText = if ($snapshot.ClaudeCodeRunning) { "Claude: active" } elseif ($snapshot.ClaudeKeeperEnabled) { "Claude: keeper waiting" } else { "Claude: off" }
        $statusItem.Text = "Codex: $(if ($snapshot.CodexRunning) { "active" } else { "inactive" }) | $claudeText | resets: $($snapshot.ActiveResetCount) | $nextText"
    }.GetNewClosure()
    $menu.Add_Opening($menuOpeningAction)
    $menu.Add_Closed({
        $script:TrayMenuOpen = $false
        Refresh-Tray
    })

    return $menu
}

function New-OpenCodeGoRefreshStartInfo {
    $powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $powershellPath
    $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -RefreshOpenCodeGoOnce"
    $startInfo.WorkingDirectory = $PSScriptRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    return $startInfo
}

function Start-OpenCodeGoUsageRefresh {
    if ($null -eq $script:State -or -not [bool]$script:State.settings.openCodeGoEnabled) { return }
    if ($null -ne $script:OpenCodeGoRefreshProcess) {
        try {
            if (-not $script:OpenCodeGoRefreshProcess.HasExited) { return }
            $script:OpenCodeGoRefreshProcess.Dispose()
        }
        catch {
        }
        $script:OpenCodeGoRefreshProcess = $null
    }

    try {
        $script:OpenCodeGoRefreshProcess = [System.Diagnostics.Process]::Start((New-OpenCodeGoRefreshStartInfo))
    }
    catch {
        $script:OpenCodeGoRefreshProcess = $null
    }
}

function Update-OpenCodeGoRefreshProcessState {
    if ($null -eq $script:OpenCodeGoRefreshProcess) { return }
    try {
        if (-not $script:OpenCodeGoRefreshProcess.HasExited) { return }
        $script:OpenCodeGoRefreshProcess.Dispose()
    }
    catch {
    }
    $script:OpenCodeGoRefreshProcess = $null
    if ($null -ne $script:RefreshMainWindow) { & $script:RefreshMainWindow }
}

function Stop-OpenCodeGoUsageRefresh {
    if ($null -eq $script:OpenCodeGoRefreshProcess) { return }
    try {
        if (-not $script:OpenCodeGoRefreshProcess.HasExited) {
            $script:OpenCodeGoRefreshProcess.Kill()
            [void]$script:OpenCodeGoRefreshProcess.WaitForExit(3000)
        }
        $script:OpenCodeGoRefreshProcess.Dispose()
    }
    catch {
    }
    $script:OpenCodeGoRefreshProcess = $null
}

function New-QwenRefreshStartInfo {
    $powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $powershellPath
    $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -RefreshQwenOnce"
    $startInfo.WorkingDirectory = $PSScriptRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    return $startInfo
}

function Start-QwenUsageRefresh {
    if ($null -eq $script:State -or -not [bool]$script:State.settings.qwenTokenPlanEnabled) { return }
    if ($null -ne $script:QwenRefreshProcess) {
        try {
            if (-not $script:QwenRefreshProcess.HasExited) { return }
            $script:QwenRefreshProcess.Dispose()
        }
        catch {
        }
        $script:QwenRefreshProcess = $null
    }

    try {
        $script:QwenRefreshProcess = [System.Diagnostics.Process]::Start((New-QwenRefreshStartInfo))
    }
    catch {
        $script:QwenRefreshProcess = $null
    }
}

function Update-QwenRefreshProcessState {
    if ($null -eq $script:QwenRefreshProcess) { return }
    try {
        if (-not $script:QwenRefreshProcess.HasExited) { return }
        $script:QwenRefreshProcess.Dispose()
    }
    catch {
    }
    $script:QwenRefreshProcess = $null
    if ($null -ne $script:RefreshMainWindow) { & $script:RefreshMainWindow }
}

function Stop-QwenUsageRefresh {
    if ($null -eq $script:QwenRefreshProcess) { return }
    try {
        if (-not $script:QwenRefreshProcess.HasExited) {
            $script:QwenRefreshProcess.Kill()
            [void]$script:QwenRefreshProcess.WaitForExit(3000)
        }
        $script:QwenRefreshProcess.Dispose()
    }
    catch {
    }
    $script:QwenRefreshProcess = $null
}

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
        Load-State | Out-Null
        Ensure-ClaudeUsageKeeper

        if ([bool]$script:State.settings.autoPollLiveUsage) {
            [void](Update-LiveUsage)
        }
        [void](Update-AntigravityUsage)

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
    Start-OpenCodeGoUsageRefresh
    Start-QwenUsageRefresh

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
        Update-OpenCodeGoRefreshProcessState
        Update-QwenRefreshProcessState
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

    $usageTimer = New-Object System.Windows.Forms.Timer
    $pollMinutes = 5
    try {
        $pollMinutes = [Math]::Max(1, [int]$script:State.settings.liveUsagePollIntervalMinutes)
    }
    catch {
        $pollMinutes = 5
    }
    $usageTimer.Interval = [Math]::Min(2147483647, $pollMinutes * 60000)
    $usageTimer.Add_Tick({
        if ([bool]$script:State.settings.autoPollLiveUsage) {
            [void](Update-LiveUsage)
            Refresh-Tray
            if ($null -ne $script:RefreshMainWindow) {
                & $script:RefreshMainWindow
            }
        }
    })
    $usageTimer.Start()

    $antigravityTimer = New-Object System.Windows.Forms.Timer
    $antigravityTimer.Interval = 90000
    $antigravityTimer.Add_Tick({
        [void](Update-AntigravityUsage)
        Refresh-TaskbarBadge
    })
    $antigravityTimer.Start()

    $openCodeGoTimer = New-Object System.Windows.Forms.Timer
    $openCodeGoTimer.Interval = 90000
    $openCodeGoTimer.Add_Tick({
        if ([bool]$script:State.settings.openCodeGoEnabled) {
            Start-OpenCodeGoUsageRefresh
        }
    })
    $openCodeGoTimer.Start()

    $qwenTimer = New-Object System.Windows.Forms.Timer
    $qwenTimer.Interval = $script:QwenRefreshIntervalMilliseconds
    $qwenTimer.Add_Tick({
        if ([bool]$script:State.settings.qwenTokenPlanEnabled) {
            Start-QwenUsageRefresh
        }
    })
    $qwenTimer.Start()

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

        Stop-OpenCodeGoUsageRefresh
        Stop-QwenUsageRefresh
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
    Assert-SelfTest ($mainScriptSource -match '(?s)\$script:RefreshMainWindow\s*=\s*\{.*?\}\.GetNewClosure\(\)') "main-window refresh must retain its controls in a closure"
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

    Assert-SelfTest ($null -ne (Get-Command New-OpenCodeGoRefreshStartInfo -ErrorAction SilentlyContinue)) "the OpenCode Go refresh start-info helper must exist"
    $openCodeGoRefreshStartInfo = New-OpenCodeGoRefreshStartInfo
    Assert-SelfTest ($openCodeGoRefreshStartInfo.FileName -eq (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe")) "OpenCode Go refresh must use an absolute PowerShell path"
    Assert-SelfTest ($openCodeGoRefreshStartInfo.Arguments -match "-RefreshOpenCodeGoOnce") "OpenCode Go refresh must only start one-time refresh mode"
    Assert-SelfTest ($openCodeGoRefreshStartInfo.CreateNoWindow -and $openCodeGoRefreshStartInfo.WindowStyle -eq [System.Diagnostics.ProcessWindowStyle]::Hidden) "OpenCode Go refresh must start hidden"
    Assert-SelfTest ($null -ne (Get-Command New-QwenRefreshStartInfo -ErrorAction SilentlyContinue)) "the Qwen refresh start-info helper must exist"
    $qwenRefreshStartInfo = New-QwenRefreshStartInfo
    Assert-SelfTest ($qwenRefreshStartInfo.FileName -eq (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe")) "Qwen refresh must use an absolute PowerShell path"
    Assert-SelfTest ($qwenRefreshStartInfo.Arguments -match "-RefreshQwenOnce") "Qwen refresh must only start one-time refresh mode"
    Assert-SelfTest ($qwenRefreshStartInfo.CreateNoWindow -and $qwenRefreshStartInfo.WindowStyle -eq [System.Diagnostics.ProcessWindowStyle]::Hidden) "Qwen refresh must start hidden"
    Assert-SelfTest ($script:QwenRefreshIntervalMilliseconds -eq 120000) "Qwen must refresh automatically every two minutes"

    $oldRefreshTestState = $script:State
    $oldOpenCodeGoRefreshProcess = $script:OpenCodeGoRefreshProcess
    $oldQwenRefreshProcess = $script:QwenRefreshProcess
    try {
        $script:State = New-DefaultState
        $script:State.settings.openCodeGoEnabled = $true
        $script:State.settings.qwenTokenPlanEnabled = $true
        $openCodeGoInFlight = [pscustomobject]@{ HasExited = $false }
        $qwenInFlight = [pscustomobject]@{ HasExited = $false }
        $script:OpenCodeGoRefreshProcess = $openCodeGoInFlight
        $script:QwenRefreshProcess = $qwenInFlight
        Start-OpenCodeGoUsageRefresh
        Start-QwenUsageRefresh
        Assert-SelfTest ([object]::ReferenceEquals($script:OpenCodeGoRefreshProcess, $openCodeGoInFlight)) "OpenCode Go must not start a second refresh while a helper is active"
        Assert-SelfTest ([object]::ReferenceEquals($script:QwenRefreshProcess, $qwenInFlight)) "Qwen must not start a second refresh while a helper is active"
    }
    finally {
        $script:State = $oldRefreshTestState
        $script:OpenCodeGoRefreshProcess = $oldOpenCodeGoRefreshProcess
        $script:QwenRefreshProcess = $oldQwenRefreshProcess
    }

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

    Assert-SelfTest ((ConvertTo-OpenCodeGoWorkspaceId "wrk_TEST123") -eq "wrk_TEST123") "the OpenCode Go workspace ID must be accepted"
    Assert-SelfTest ((ConvertTo-OpenCodeGoWorkspaceId "https://opencode.ai/workspace/wrk_TEST123/go") -eq "wrk_TEST123") "the OpenCode Go dashboard URL must be normalized to a workspace ID"
    Assert-SelfTest ((ConvertTo-OpenCodeGoAuthCookie "auth=test-cookie-value; Path=/") -eq "test-cookie-value") "the auth cookie header must be normalized to its value only"
    $openCodeGoCrLfRejected = $false
    try { [void](ConvertTo-OpenCodeGoAuthCookie "value`r`nInjected: yes") } catch { $openCodeGoCrLfRejected = $true }
    Assert-SelfTest $openCodeGoCrLfRejected "an OpenCode Go cookie with header injection must be rejected"

    $escapedOpenCodeGoFixture = '<script>self.__next_f.push([1,"{\"rollingUsage\":{\"usagePercent\":12.5,\"resetInSec\":3600},\"weeklyUsage\":{\"usagePercent\":25,\"resetInSec\":7200},\"monthlyUsage\":{\"usagePercent\":44,\"resetInSec\":10800}}"])</script>'
    $escapedOpenCodeGoUsage = @(ConvertFrom-OpenCodeGoDashboardHtml $escapedOpenCodeGoFixture)
    Assert-SelfTest ($escapedOpenCodeGoUsage.Count -eq 3) "the escaped OpenCode Go dashboard must produce three quotas"
    Assert-SelfTest (($escapedOpenCodeGoUsage.label -join ",") -eq "5h,weekly,monthly") "OpenCode Go quotas must appear in a fixed order"
    Assert-SelfTest (($escapedOpenCodeGoUsage.remainingPercent -join ",") -eq "88,75,56") "OpenCode Go used percentages must be converted to remaining percentages"

    $solidOpenCodeGoFixture = '$R[24]($R[18],$R[30]={rollingUsage:$R[31]={status:"ok",resetInSec:18000,usagePercent:0},weeklyUsage:$R[32]={status:"ok",usagePercent:33.4,resetInSec:80000},monthlyUsage:$R[33]={status:"ok",resetInSec:200000,usagePercent:99.6}});'
    $solidOpenCodeGoUsage = @(ConvertFrom-OpenCodeGoDashboardHtml $solidOpenCodeGoFixture)
    Assert-SelfTest ($solidOpenCodeGoUsage.Count -eq 3) "the Solid resource dashboard must produce three quotas"
    Assert-SelfTest (($solidOpenCodeGoUsage.remainingPercent -join ",") -eq "100,67,0") "Solid resource percentages must be rounded correctly"

    $partialOpenCodeGoUsage = @(ConvertFrom-OpenCodeGoDashboardHtml '{"weeklyUsage":{"usagePercent":10,"resetInSec":60}}')
    Assert-SelfTest ($partialOpenCodeGoUsage.Count -eq 1 -and $partialOpenCodeGoUsage[0].key -eq "seven_day") "a partial OpenCode Go response must retain usable windows"
    $malformedOpenCodeGoRejected = $false
    try { [void](ConvertFrom-OpenCodeGoDashboardHtml '<html>signed in but no quota</html>') } catch {
        $malformedOpenCodeGoRejected = ((Get-OpenCodeGoExceptionCode $_) -eq "parse_error")
    }
    Assert-SelfTest $malformedOpenCodeGoRejected "unknown OpenCode Go markup must result in parse_error"

    $oldOpenCodeGoCredentialPath = $script:OpenCodeGoCredentialPath
    $oldOpenCodeGoEnvironmentWorkspace = $env:OPENCODE_GO_WORKSPACE_ID
    $oldOpenCodeGoEnvironmentAuth = $env:OPENCODE_GO_AUTH_COOKIE
    $tempOpenCodeGoCredentialPath = Join-Path ([System.IO.Path]::GetTempPath()) ("opencode-go-credentials-" + [Guid]::NewGuid().ToString("N") + ".json")
    try {
        $env:OPENCODE_GO_WORKSPACE_ID = $null
        $env:OPENCODE_GO_AUTH_COOKIE = $null
        $script:OpenCodeGoCredentialPath = $tempOpenCodeGoCredentialPath
        $testOpenCodeGoSecret = "selftest-secret-" + [Guid]::NewGuid().ToString("N")
        Save-OpenCodeGoCredentials -WorkspaceId "wrk_TEST123" -AuthCookie $testOpenCodeGoSecret
        $storedOpenCodeGoCredential = Get-Content -LiteralPath $tempOpenCodeGoCredentialPath -Raw
        Assert-SelfTest ($storedOpenCodeGoCredential -notmatch [regex]::Escape($testOpenCodeGoSecret)) "the OpenCode Go cookie must not be stored as plaintext"
        $roundTripOpenCodeGoCredential = Get-OpenCodeGoCredentials
        Assert-SelfTest ($roundTripOpenCodeGoCredential.workspaceId -eq "wrk_TEST123") "the DPAPI credential round trip must retain the workspace"
        Assert-SelfTest ($roundTripOpenCodeGoCredential.authCookie -eq $testOpenCodeGoSecret) "the DPAPI credential round trip must restore the cookie"
        Assert-SelfTest ($roundTripOpenCodeGoCredential.source -eq "dpapi") "a locally stored credential must be identifiable as a DPAPI source"
    }
    finally {
        $script:OpenCodeGoCredentialPath = $oldOpenCodeGoCredentialPath
        $env:OPENCODE_GO_WORKSPACE_ID = $oldOpenCodeGoEnvironmentWorkspace
        $env:OPENCODE_GO_AUTH_COOKIE = $oldOpenCodeGoEnvironmentAuth
        Remove-Item -LiteralPath $tempOpenCodeGoCredentialPath -Force -ErrorAction SilentlyContinue
    }

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
        [pscustomobject]@{ Name = "Qwen"; Command = { param($stream) Read-QwenLimitedUtf8Stream -Stream $stream -MaximumBytes 7 } },
        [pscustomobject]@{ Name = "Antigravity"; Command = { param($stream) Read-AntigravityLimitedUtf8Stream -Stream $stream -MaximumBytes 7 } }
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
    Assert-SelfTest (($qwenDirectUsage.remainingPercent -join ",") -eq "51,85") "Qwen consumed fractions must be converted to remaining percentages"
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

    $antigravityFixture = [pscustomobject]@{
        userStatus = [pscustomobject]@{
            email = 'must-not-be-persisted@example.test'
            csrfToken = 'must-not-be-persisted'
            cascadeModelConfigData = [pscustomobject]@{
                clientModelConfigs = @(
                    [pscustomobject]@{ label = 'Gemini 3.1 Pro High'; quotaInfo = [pscustomobject]@{ remainingFraction = 0.91; resetTime = '2099-01-01T12:00:00Z' } },
                    [pscustomobject]@{ label = 'Gemini 3.1 Pro Low'; quotaInfo = [pscustomobject]@{ remainingFraction = 0.94; resetTime = '2099-01-01T12:00:00Z' } },
                    [pscustomobject]@{ label = 'Claude Sonnet 4.6 Thinking'; quotaInfo = [pscustomobject]@{ remainingFraction = 1; resetTime = '2099-01-01T13:00:00Z' } },
                    [pscustomobject]@{ label = 'GPT-OSS 120B Medium'; quotaInfo = [pscustomobject]@{ remainingFraction = 1; resetTime = '2099-01-01T13:00:00Z' } }
                )
            }
        }
    }
    $normalizedAntigravityUsage = Convert-AntigravityStatusToUsage -StatusResponse $antigravityFixture
    Assert-SelfTest (@($normalizedAntigravityUsage.items).Count -eq 2) "shared Antigravity quotas must be combined"
    Assert-SelfTest ($normalizedAntigravityUsage.items[0].label -eq 'Gemini') "Gemini must be the first Antigravity group"
    Assert-SelfTest ($normalizedAntigravityUsage.items[0].remainingPercent -eq 91) "the conservatively lowest Gemini quota must be used (actual: $($normalizedAntigravityUsage.items[0].remainingPercent))"
    Assert-SelfTest ($normalizedAntigravityUsage.items[1].label -eq 'Other') "shared Claude/GPT quotas must be shown as Other"
    $normalizedAntigravityJson = $normalizedAntigravityUsage | ConvertTo-Json -Depth 6
    Assert-SelfTest ($normalizedAntigravityJson -notmatch 'must-not-be-persisted') "Antigravity account and token details must not enter cache data"

    $oldSelfTestState = $script:State
    try {
        $script:State = New-DefaultState
        $script:State.liveUsage = [pscustomobject]@{
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

if ($SelfTest) {
    Invoke-SelfTest
    exit 0
}

Load-State | Out-Null

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
    $ok = Update-AntigravityUsage
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
