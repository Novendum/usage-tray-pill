$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Start-UsageTrayPill.ps1') -LibraryOnly
function Check { param([bool]$Condition,[string]$Message) if(-not $Condition){throw $Message} }
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
function Test-ForegroundWindowFullscreen { return $false }
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
