$sourceRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
$ErrorActionPreference='Stop'
. (Join-Path $sourceRoot 'Start-UsageTrayPill.ps1') -LibraryOnly
function Check { param([bool]$Condition,[string]$Message) if(-not $Condition){throw $Message} }
# Keep the real rendering logic, but never show a test pill on the desktop.
$refreshBody=(Get-Command Refresh-TaskbarBadge).ScriptBlock.ToString().Replace('$script:BadgeForm.Show()','')
Set-Item Function:Refresh-TaskbarBadge -Value ([scriptblock]::Create($refreshBody))
function Test-TaskbarBadgeShouldHide { return $script:TestBadgeHidden }
function Get-ClaudeUsageSnapshot { return $null }
$script:TestBadgeHidden=$false
$script:BadgeTheme='Light'
Check ((Get-TaskbarBadgeColor).GetBrightness() -gt 0.9) 'Light taskbar theme must use a light pill'
$script:BadgeTheme='Dark'
Check ((Get-TaskbarBadgeColor).GetBrightness() -lt 0.2) 'Dark taskbar theme must use a dark pill'
Check ($null -ne (Get-Command New-TaskbarBadgeBitmap -ErrorAction SilentlyContinue)) 'The pill requires an alpha bitmap renderer instead of a binary window region'
foreach($theme in @('Light','Dark')) {
$script:BadgeTheme=$theme
foreach($scale in @(1.0,1.25,1.5,1.75,2.0)) {
    $script:BadgeDpiScale=$scale
    $bitmap=[UtpPillForm]::RenderSurface([int](176*$scale),[int](28*$scale),(Get-TaskbarBadgeColor),(Get-TaskbarBadgeBorderColor))
    try {
        Check ($bitmap.GetPixel(0,0).A -eq 0) 'Corners must be fully transparent'
        $partial=0
        for($y=0;$y -lt $bitmap.Height;$y++) {
            for($x=0;$x -lt [Math]::Min(16,$bitmap.Width);$x++) {
                $alpha=$bitmap.GetPixel($x,$y).A
                if($alpha -gt 0 -and $alpha -lt 255){$partial++}
            }
        }
        Check ($partial -gt 10) 'The outside curve must contain partially transparent antialiasing pixels at every tested DPI'
        Check ($bitmap.GetPixel([int]($bitmap.Width/2),[int]($bitmap.Height/2)).A -eq 255) 'The capsule interior must remain opaque and readable'
    } finally {$bitmap.Dispose()}
    $script:State=New-DefaultState
    Ensure-TaskbarBadge
    $script:BadgeForm.PresentEnabled=$false
    try {
        Set-BadgeTextYOffset -Offset 0
        Check ($script:BadgeLogoNext.Bottom -le 0) 'The inactive logo must remain fully outside its viewport at every DPI'
        Set-TaskbarBadgeContent -Source codex
        Check ($script:BadgeLogo.Image.Width -eq $script:BadgeLogo.Width) 'Provider icons must be generated at their final physical size'
        $frame=New-TaskbarBadgeBitmap
        $surface=[UtpPillForm]::RenderSurface($frame.Width,$frame.Height,(Get-TaskbarBadgeColor),(Get-TaskbarBadgeBorderColor))
        try {
            for($y=0;$y -lt $frame.Height;$y++) {for($x=0;$x -lt $frame.Width;$x++) {
                Check ($frame.GetPixel($x,$y).A -eq $surface.GetPixel($x,$y).A) 'Native text must preserve the original alpha mask'
            }}
        }finally{$frame.Dispose();$surface.Dispose()}
    } finally {Dispose-TaskbarBadge}
}
}
$script:BadgeDpiScale=1.0
$script:State=New-DefaultState
function Get-SystemTrayIconTheme { return $script:TestTheme }
function Set-BadgeDpiScaleFromWindow { return $false }
function Set-BadgeTopMostNoActivate {}
Ensure-TaskbarBadge
$script:BadgeForm.PresentEnabled=$false
try {
    foreach($theme in @('Light','Dark','Light')) {
        $script:TestTheme=$theme
        Refresh-TaskbarBadge -GeometryOnly
        Check ($script:BadgeTheme -eq $theme) 'Theme changes must update during normal geometry ticks'
        Check ($script:BadgeLogo.Tag -eq "codex|$theme") 'Provider artwork must be refreshed when the theme changes'
        Check ($script:BadgeSourceLabel.BackColor.ToArgb() -eq (Get-TaskbarBadgeColor).ToArgb()) 'Native text must use the current opaque theme background'
        $bitmap=New-TaskbarBadgeBitmap
        try {
            $center=$bitmap.GetPixel(150,14)
            Check ($center.ToArgb() -eq (Get-TaskbarBadgeColor).ToArgb()) 'The actual rendered surface must match the selected theme'
        } finally {$bitmap.Dispose()}
    }
    Set-TaskbarBadgeContent -Source claude
    Start-BadgeSlideToSource -Source codex
    $script:TestBadgeHidden=$true
    $script:TestTheme='Dark'
    Refresh-TaskbarBadge -GeometryOnly
    $script:TestBadgeHidden=$false
    Refresh-TaskbarBadge -GeometryOnly
    Check ($script:BadgeLogo.Tag -eq 'codex|Dark') 'Leaving fullscreen must apply a theme change that happened while hidden'
    Check ($script:BadgeSourceLabel.ForeColor.ToArgb() -eq [Drawing.Color]::FromArgb(224,226,233).ToArgb()) 'Restored text must use dark-theme foreground colors'
    Check (-not [string]::IsNullOrWhiteSpace($script:BadgeRenderSignature)) 'Restoring the pill must complete its pending render'
    Check (-not $script:BadgeAnimating -and $script:BadgeCurrentRow.Top -eq 0) 'A theme change must recover from an interrupted slide with aligned content'
    Check (-not $script:BadgeForm.Visible) 'Rendering tests must never show a desktop pill'
    $script:State.liveUsage.lastCheckedAt=(Get-Date).ToString('o')
    $script:State.liveUsage.buckets=@([pscustomobject]@{limitId='codex';primaryRemainingPercent=76;primaryWindowDurationMins=10080;primaryResetsAt=(Get-Date).AddDays(1).ToString('o')})
    Refresh-TaskbarBadge
    Check ($script:BadgePrimaryPrefix.Text -eq '76%') 'The visible fixture must start at the original cached quota'
    $script:TestBadgeHidden=$true
    $script:State.liveUsage.buckets[0].primaryRemainingPercent=23
    Refresh-TaskbarBadge
    $script:TestBadgeHidden=$false
    Refresh-TaskbarBadge -GeometryOnly
    Check ($script:BadgePrimaryPrefix.Text -eq '23%') 'The first reveal must show quota changes received while fullscreen was active'
    Check ($script:BadgeDisplayedSource -eq 'codex') 'Refreshing hidden content must preserve the selected provider'
    $bounds=Get-TaskbarBadgeBounds -Width 176
    Check ($bounds.Right -eq ([Windows.Forms.Screen]::PrimaryScreen.Bounds.Right - (ConvertTo-BadgePixels 248) - (ConvertTo-BadgePixels 16))) 'The pill must leave the increased gap next to the tray arrow'
} finally {Dispose-TaskbarBadge}
$window=New-Object UtpPillForm
try {
    $window.StartPosition='Manual'
    $window.ShowInTaskbar=$false
    $window.FormBorderStyle='None'
    $window.Bounds=New-Object Drawing.Rectangle -10000,-10000,176,28
    [void]$window.Handle
    foreach($width in @(176,280,176)) {
        $bitmap=[UtpPillForm]::RenderSurface($width,28,(Get-TaskbarBadgeColor),(Get-TaskbarBadgeBorderColor))
        try { $window.Present($bitmap) } finally { $bitmap.Dispose() }
    }
    Check ($window.Controls.Count -eq 0) 'The alpha window must not contain opaque child windows'
} finally { $window.Dispose() }
Write-Output 'Alpha pill rendering tests OK'
