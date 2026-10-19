$sourceRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
$ErrorActionPreference = 'Stop'
. (Join-Path $sourceRoot 'Start-UsageTrayPill.ps1') -LibraryOnly
function Check { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }

# Offline doubles: no provider, setup dialog or window is ever opened.
$script:DataDir = Join-Path ([IO.Path]::GetTempPath()) ('UTP quick panel test ' + [guid]::NewGuid().ToString('N'))
function Save-State { }
function Get-AntigravityUsageSnapshot { return $null }
function Get-ClaudeUsageSnapshot { return $script:TestClaude }
$script:Actions = New-Object System.Collections.ArrayList
function Start-AllUsageRefresh { [void]$script:Actions.Add('refresh') }
function Show-MainWindow { [void]$script:Actions.Add('overview') }
function Show-OpenCodeGoSetupDialog { [void]$script:Actions.Add('setup-opencode') }
function Show-QwenSetupDialog { [void]$script:Actions.Add('setup-qwen') }
function New-ClaudeSnapshot {
    param([double]$FiveHour = 15, [double]$Weekly = 62, [bool]$Stale = $false, [string]$ErrorCode = '')
    $now = Get-Date
    return [pscustomobject]@{
        lastCheckedAt = $now.ToString('o'); lastSuccessAt = $now.AddMinutes(-20).ToString('o'); lastError = ''; errorCode = $ErrorCode; stale = $Stale; available = $true
        limits = @(
            [pscustomobject]@{ key = 'five_hour'; label = '5h'; remainingPercent = $FiveHour; resetsAt = $now.AddMinutes(40).AddSeconds(-30).ToString('o') },
            [pscustomobject]@{ key = 'seven_day'; label = 'weekly'; remainingPercent = $Weekly; resetsAt = $now.AddDays(3).AddSeconds(-30).ToString('o') }
        )
    }
}
function Get-RowColors {
    param([System.Drawing.Bitmap]$Bitmap, [int]$X)
    # Distinct meter fills from top to bottom along one column.
    $known = @{ accent = '208,34,121'; low = '214,48,49' }
    $found = @()
    $previous = ''
    for ($y = 0; $y -lt $Bitmap.Height; $y++) {
        $pixel = $Bitmap.GetPixel($X, $y)
        $rgb = "$($pixel.R),$($pixel.G),$($pixel.B)"
        $name = @($known.Keys | Where-Object { $known[$_] -eq $rgb })[0]
        if ($name -and $name -ne $previous) { $found += $name }
        $previous = if ($name) { $name } else { '' }
    }
    return $found
}

$script:BadgeDpiScale = 1.0
$script:BadgeTheme = 'Light'
$script:State = New-DefaultState
$script:State.liveUsage.lastCheckedAt = (Get-Date).ToString('o')
$script:State.liveUsage.buckets = @([pscustomobject]@{
    limitId = 'codex'
    primaryRemainingPercent = 72; primaryWindowDurationMins = 300; primaryResetsAt = (Get-Date).AddHours(1).AddSeconds(-30).ToString('o')
    secondaryRemainingPercent = 41; secondaryWindowDurationMins = 10080; secondaryResetsAt = (Get-Date).AddDays(2).AddSeconds(-30).ToString('o')
})
$script:State.settings.claudeControlEnabled = $true
$script:TestClaude = New-ClaudeSnapshot

# Model: every window a provider reports, short reset texts, disabled providers left out.
$model = @(Get-QuickViewModel)
Check ((@($model | ForEach-Object Source) -join ',') -eq 'codex,claude,antigravity') 'The quick view must list the enabled providers in pill order'
$codex = $model[0]
Check ((@($codex.Windows | ForEach-Object Name) -join ',') -eq '5-hour,Weekly' -and (@($codex.Windows | ForEach-Object Text) -join ',') -eq '72%,41%') 'Codex must show both of its windows, not only the pill window'
Check ($codex.Windows[0].Reset -eq 'resets in 1h' -and $codex.Windows[1].Reset -eq 'resets in 2d') 'Each window must say when it resets'
Check ($model[1].Windows[0].Text -eq '15%' -and -not $model[1].Attention) 'Claude values must come from its snapshot'
Check (@($model[2].Windows).Count -eq 0 -and $model[2].Status -eq 'No usage data yet') 'A provider without data must show one quiet status line, never invented values'
$script:State.settings.openCodeGoEnabled = $true
Check (@(Get-QuickViewModel | Where-Object Source -eq 'opencodego').Count -eq 1) 'Enabling a provider must add it to the quick view'
$script:State.settings.openCodeGoEnabled = $false

$script:TestClaude = New-ClaudeSnapshot -Stale $true
$cached = @(Get-QuickViewModel)[1]
Check ($cached.Cached -and @($cached.Windows | Where-Object Reset).Count -eq 0) 'Cached values must not count down'
Check ($cached.Status -match '^Cached values from \d{2}:\d{2}$') "The status must drop the date and keep the time, got '$($cached.Status)'"
$script:TestClaude = New-ClaudeSnapshot -ErrorCode 'auth_expired'
$attention = @(Get-QuickViewModel)[1]
Check ($attention.Attention -and $attention.Status -eq 'Sign in again') 'A provider that needs the user must say what to do'

# Size follows the content and the display scale.
$script:TestClaude = New-ClaudeSnapshot -ErrorCode 'auth_expired'
$model = @(Get-QuickViewModel)
$size = Get-QuickPanelSize -Model $model
Check ($size.Width -eq 372 -and $size.Height -eq 442) "The panel must fit its rows exactly, got $($size.Width)x$($size.Height)"
$script:BadgeDpiScale = 1.5
Check ((Get-QuickPanelSize -Model $model).Width -eq 558) 'The panel must scale with the display'
$script:BadgeDpiScale = 1.0

# Rendering: themed surface, proportional meters, red under 20%, and the right click targets.
foreach ($theme in @('Light', 'Dark')) {
    $script:BadgeTheme = $theme
    $palette = Get-QuickPanelPalette
    $bitmap = New-Object System.Drawing.Bitmap $size.Width, $size.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try { Draw-QuickPanel -Graphics $graphics -Size $size -Model $model }
    finally { $graphics.Dispose() }
    try {
        Check ($bitmap.GetPixel(4, 4).ToArgb() -eq $palette.Back.ToArgb()) "The $theme panel must use its theme surface"
        Check ($bitmap.GetPixel(0, 200).ToArgb() -eq $palette.Border.ToArgb()) "The $theme panel must have a visible border"
        Check ((@(Get-RowColors -Bitmap $bitmap -X 50) -join ',') -eq 'accent,accent,low,accent') "Meters must fill per window and turn red under 20% ($theme)"
        $meterRow = 117
        $filled = @(0..($size.Width - 1) | Where-Object { $bitmap.GetPixel($_, $meterRow).ToArgb() -eq $palette.Accent.ToArgb() }).Count
        Check ([Math]::Abs($filled - [Math]::Round(310 * 0.72)) -le 3) "The 72% meter must fill 72% of its track ($theme, got $filled px)"
    }
    finally { $bitmap.Dispose() }
}
$hotspotActions = @($script:QuickPanelHotspots | ForEach-Object Action)
Check (($hotspotActions -join ',') -eq 'setup:claude,refresh,overview') 'Click targets must cover setup for the provider that needs attention, refresh and the overview'
$script:BadgeTheme = 'Light'

# Actions close the panel first and open the matching place.
foreach ($action in @('refresh', 'overview', 'setup:opencodego', 'setup:qwen', 'setup:claude')) { Invoke-QuickPanelAction -Action $action }
Check (($script:Actions -join ',') -eq 'refresh,overview,setup-opencode,setup-qwen,overview') 'Each quick panel action must open the matching place'

# Position: above the pill on a bottom taskbar, below it otherwise, always inside the work area.
$work = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$panelSize = New-Object System.Drawing.Size 372, 300
$script:BadgeForm = $null
$bounds = Get-QuickPanelBounds -Size $panelSize
Check ($bounds.Right -eq $work.Right - 10 -and $bounds.Bottom -eq $work.Bottom - 10) 'Without a pill the panel must sit above the clock corner'
$script:BadgeForm = [pscustomobject]@{ IsDisposed = $false; Visible = $true; Bounds = (New-Object System.Drawing.Rectangle ($work.Right - 600), ($work.Bottom + 4), 200, 32) }
$bounds = Get-QuickPanelBounds -Size $panelSize
Check ($bounds.Right -eq $work.Right - 400 -and $bounds.Bottom -eq $work.Bottom - 10) 'On a bottom taskbar the panel must open above the pill, right-aligned with it'
$script:BadgeForm.Bounds = New-Object System.Drawing.Rectangle ($work.Left + 20), ($work.Bottom + 4), 120, 32
Check ((Get-QuickPanelBounds -Size $panelSize).Left -eq $work.Left + 10) 'The panel must never leave the screen on the left'
$script:BadgeForm.Bounds = New-Object System.Drawing.Rectangle ($work.Right - 300), ($work.Top + 4), 200, 32
Check ((Get-QuickPanelBounds -Size $panelSize).Top -eq $work.Top + 46) 'A pill above the work area bottom must open the panel below it'
$script:BadgeForm.Visible = $false
Check ((Get-QuickPanelBounds -Size $panelSize).Bottom -eq $work.Bottom - 10) 'A hidden pill must not anchor the panel'
$script:BadgeForm = $null

# Middle-click opens the quick view; the flyout is a shadowed tool window without a taskbar button.
function Show-QuickPanel { [void]$script:Actions.Add('quick') }
Invoke-TaskbarBadgeMouseUp -EventArgs (New-Object System.Windows.Forms.MouseEventArgs ([System.Windows.Forms.MouseButtons]::Middle), 1, 10, 10, 0)
Check ($script:Actions[-1] -eq 'quick') 'A middle-click on the pill must open the quick view'
$flyout = New-Object UtpFlyoutForm
try {
    $createParams = [System.Windows.Forms.Form].GetProperty('CreateParams', [Reflection.BindingFlags]'Instance,NonPublic').GetValue($flyout, $null)
    Check (($createParams.ClassStyle -band 0x20000) -ne 0) 'The quick view must cast a drop shadow'
    Check (($createParams.ExStyle -band 0x80) -ne 0 -and -not $flyout.ShowInTaskbar) 'The quick view must not create a taskbar button'
    Check ($flyout.FormBorderStyle -eq [System.Windows.Forms.FormBorderStyle]::None -and $flyout.KeyPreview) 'The quick view must be borderless and handle Esc itself'
}
finally { $flyout.Dispose() }

Write-Host 'Quick panel tests OK (model, cached and attention states, size, light/dark rendering, meters, actions, position, flyout window).'
