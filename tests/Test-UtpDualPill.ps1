$sourceRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
$ErrorActionPreference='Stop'
. (Join-Path $sourceRoot 'Start-UsageTrayPill.ps1') -LibraryOnly
function Check { param([bool]$Condition,[string]$Message) if(-not $Condition){throw $Message} }
# Keep the real rendering logic, but never show a test pill on the desktop or write settings.
$refreshBody=(Get-Command Refresh-TaskbarBadge).ScriptBlock.ToString().Replace('$script:BadgeForm.Show()','')
Set-Item Function:Refresh-TaskbarBadge -Value ([scriptblock]::Create($refreshBody))
function Test-TaskbarBadgeShouldHide { return $false }
function Get-SystemTrayIconTheme { return $script:TestTheme }
function Set-BadgeDpiScaleFromWindow { return $false }
function Set-BadgeTopMostNoActivate {}
function Save-State { $script:TestSaveCount++ }
function Get-AntigravityUsageSnapshot { return $null }
function Get-ClaudeUsageSnapshot { return $script:TestClaude }
function Wait-BadgeAnimation {
    $deadline=(Get-Date).AddSeconds(3)
    while ($script:BadgeAnimating -and (Get-Date) -lt $deadline) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10 }
    Check (-not $script:BadgeAnimating) 'Pill transitions must finish'
}
function New-TestState {
    $state=New-DefaultState
    $state.liveUsage.lastCheckedAt=(Get-Date).ToString('o')
    $state.liveUsage.buckets=@([pscustomobject]@{limitId='codex';primaryRemainingPercent=41;primaryWindowDurationMins=10080;primaryResetsAt=(Get-Date).AddDays(2).ToString('o')})
    return $state
}
$script:TestTheme='Light'
$script:TestSaveCount=0
$script:TestClaude=[pscustomobject]@{lastCheckedAt=(Get-Date).ToString('o');lastSuccessAt=(Get-Date).ToString('o');lastError='';stale=$false;fiveHourRemainingPercent=80;sevenDayRemainingPercent=62;limits=@()}

# Settings: new installs and existing data keep the single pill; invalid values recover safely.
$state=New-DefaultState
Check ($state.settings.taskbarBadgeLayout -eq 'single') 'New installs must keep the single-provider pill'
Check ((@($state.settings.taskbarBadgeDualSources) -join ',') -eq 'codex,claude') 'Two-provider mode must start with ChatGPT and Claude'
Check ($state.settings.taskbarBadgeDualDetail -eq 'all') 'Two-provider mode must show all windows by default'
$legacy=New-DefaultState
foreach($name in @('taskbarBadgeLayout','taskbarBadgeDualSources','taskbarBadgeDualDetail')){ $legacy.settings.PSObject.Properties.Remove($name) }
$legacy=Normalize-State $legacy
Check ($legacy.settings.taskbarBadgeLayout -eq 'single' -and (@($legacy.settings.taskbarBadgeDualSources) -join ',') -eq 'codex,claude') 'Existing settings must gain safe pill defaults'
$broken=New-DefaultState
$broken.settings.taskbarBadgeLayout='sideways'
$broken.settings.taskbarBadgeDualSources=@('claude','claude')
$broken.settings.taskbarBadgeDualDetail='everything'
$broken=Normalize-State $broken
Check ($broken.settings.taskbarBadgeLayout -eq 'single' -and (@($broken.settings.taskbarBadgeDualSources) -join ',') -eq 'codex,claude' -and $broken.settings.taskbarBadgeDualDetail -eq 'all') 'Invalid or duplicate pill settings must recover'
$valid=New-DefaultState
$valid.settings.taskbarBadgeLayout='dual'
$valid.settings.taskbarBadgeDualSources=@('antigravity','codex')
$valid.settings.taskbarBadgeDualDetail='tightest'
$roundTrip=Normalize-State ($valid | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
Check ($roundTrip.settings.taskbarBadgeLayout -eq 'dual' -and (@($roundTrip.settings.taskbarBadgeDualSources) -join ',') -eq 'antigravity,codex' -and $roundTrip.settings.taskbarBadgeDualDetail -eq 'tightest') 'Saved pill choices must survive a settings round trip'

# Sides: disabled providers keep their saved slot, and a side never repeats the other side.
$script:State=New-TestState
$script:State.settings.taskbarBadgeDualSources=@('qwen','claude')
Check ((@(Get-TaskbarBadgeDualSources) -join ',') -eq 'codex,claude') 'A paused provider must borrow an unused provider'
Check (@($script:State.settings.taskbarBadgeDualSources)[0] -eq 'qwen') 'Borrowing must not overwrite the saved choice'
$script:State.settings.qwenTokenPlanEnabled=$true
Check ((@(Get-TaskbarBadgeDualSources) -join ',') -eq 'qwen,claude') 'Re-enabling a provider must restore its side'
$script:State=New-TestState
Check ((Get-NextTaskbarBadgeDualSource -Slot 0) -eq 'antigravity') 'Switching the left side must skip the right provider'
Check ((Get-NextTaskbarBadgeDualSource -Slot 1) -eq 'antigravity') 'Switching the right side must skip the left provider'
$script:State.settings.taskbarBadgeDualSources=@('antigravity','claude')
Check ((Get-NextTaskbarBadgeDualSource -Slot 0) -eq 'codex') 'Switching wraps around the enabled providers'

# Data and layout: compact labels, truthful values, no overlap.
$script:State=New-TestState
$script:State.settings.taskbarBadgeLayout='dual'
$script:BadgeTheme='Light'
$single=Get-TaskbarBadgeData -Source codex
$dual=Get-TaskbarBadgeData -Source dual
Check ((@($dual.Segments | ForEach-Object Source) -join ',') -eq 'codex,claude') 'The pill must show both selected providers in order'
Check ((@($dual.Segments[0].Items | ForEach-Object { "$($_.Label) $($_.Text)" }) -join ',') -eq 'wk 41%') 'Codex must show its weekly allowance compactly'
Check ((@($dual.Segments[1].Items | ForEach-Object { "$($_.Label) $($_.Text)" }) -join ',') -eq '5h 80%,wk 62%') 'Claude must show both windows'
Check ($dual.Width -gt $single.Width) 'Two providers need a wider capsule'
Check (@($dual.Dividers).Count -eq 1 -and $dual.Segments[0].End -lt $dual.Dividers[0] -and $dual.Dividers[0] -lt $dual.Segments[1].Start) 'The divider must sit between the providers'
foreach($segment in $dual.Segments){
    $parts=@($segment.Parts)
    for($index=1;$index -lt $parts.Count;$index++){ Check ($parts[$index].X -ge ($parts[$index-1].X + $parts[$index-1].Width)) 'Labels and values must never overlap' }
    Check ($parts[0].X -ge ($segment.LogoX + 22)) 'Text must start after its provider logo'
}
$script:State.settings.taskbarBadgeDualDetail='tightest'
$tight=Get-TaskbarBadgeData -Source dual
Check ((@($tight.Segments[1].Items | ForEach-Object { "$($_.Label) $($_.Text)" }) -join ',') -eq 'wk 62%') 'Tightest mode must show the most restrictive window'
Check ($tight.Width -lt $dual.Width) 'Tightest mode must be narrower'
$script:TestClaude=[pscustomobject]@{lastCheckedAt=(Get-Date).ToString('o');lastSuccessAt='';lastError='';stale=$false;fiveHourRemainingPercent=$null;sevenDayRemainingPercent=$null;limits=@()}
$unknown=Get-TaskbarBadgeData -Source dual
Check ((@($unknown.Segments[1].Items | ForEach-Object Text) -join ',') -eq '--') 'Unknown values must stay unknown in tightest mode'
$script:State.settings.taskbarBadgeDualDetail='all'
$unknown=Get-TaskbarBadgeData -Source dual
Check ((@($unknown.Segments[1].Items | ForEach-Object Text) -join ',') -eq '--,--') 'Unknown values must never be invented'
$script:TestClaude=[pscustomobject]@{lastCheckedAt=(Get-Date).ToString('o');lastSuccessAt=(Get-Date).ToString('o');lastError='';stale=$false;fiveHourRemainingPercent=80;sevenDayRemainingPercent=62;limits=@()}

# Reset countdown: off by default, only on known 5-hour windows, rounded up, never for cached values.
$now=[DateTimeOffset]::new(2026,10,16,14,0,0,[TimeSpan]::FromHours(2))
Check ((Format-BadgeResetCountdown $now.AddMinutes(40).ToString('o') -Now $now) -eq '40m') 'Countdown must show minutes below one hour'
Check ((Format-BadgeResetCountdown $now.AddMinutes(130).ToString('o') -Now $now) -eq '2h10m') 'Countdown must show hours and minutes'
Check ((Format-BadgeResetCountdown $now.AddMinutes(180).ToString('o') -Now $now) -eq '3h') 'Whole hours must not show 00m'
Check ((Format-BadgeResetCountdown $now.AddSeconds(30).ToString('o') -Now $now) -eq '1m') 'Remaining seconds must round up, never to 0m'
Check ((Format-BadgeResetCountdown $now.AddMinutes(-1).ToString('o') -Now $now) -eq '') 'A passed reset must not count down'
Check ((Format-BadgeResetCountdown '' -Now $now) -eq '' -and (Format-BadgeResetCountdown 'not a date' -Now $now) -eq '') 'Unknown resets must stay unknown'
Check ($now.ToUniversalTime().AddMinutes(95).ToString('o') -match 'Z|\+00:00' -and (Format-BadgeResetCountdown $now.ToUniversalTime().AddMinutes(95).ToString('o') -Now $now) -eq '1h35m') 'UTC reset times must count down correctly'
Check (-not [bool](New-DefaultState).settings.taskbarBadgeResetCountdown) 'The countdown must be off by default'
$script:State=New-TestState
$script:State.settings.taskbarBadgeLayout='dual'
$script:TestClaude=[pscustomobject]@{lastCheckedAt=(Get-Date).ToString('o');lastSuccessAt=(Get-Date).ToString('o');lastError='';stale=$false;fiveHourRemainingPercent=80;fiveHourResetsAt=[DateTimeOffset]::Now.AddMinutes(130).ToString('o');sevenDayRemainingPercent=62;sevenDayResetsAt=(Get-Date).AddDays(3).ToString('o');limits=@()}
$plain=Get-TaskbarBadgeData -Source dual
Check (@($plain.Segments[1].Parts | Where-Object Kind -eq 'countdown').Count -eq 0) 'Without the option the pill must not show a countdown'
$script:State.settings.taskbarBadgeResetCountdown=$true
$timed=Get-TaskbarBadgeData -Source dual
$countdown=@($timed.Segments[1].Parts | Where-Object Kind -eq 'countdown')
Check ($countdown.Count -eq 1 -and $countdown[0].Text -match '^2h(09|10)m$') 'The 5-hour window must count down to its reset'
Check (@($timed.Segments[1].Parts | Where-Object Kind -eq 'clock').Count -eq 1) 'The countdown must carry a clock glyph'
Check (@($timed.Segments[0].Parts | Where-Object Kind -eq 'countdown').Count -eq 0) 'Weekly windows must not count down'
Check ($timed.Width -gt $plain.Width) 'The countdown needs room in the capsule'
$script:TestClaude.fiveHourResetsAt=(Get-Date).AddMinutes(7).ToString('o')
Check ((Get-TaskbarBadgeData -Source dual).Width -eq $timed.Width) 'Shorter countdowns must not resize the pill'
Check ((Get-TaskbarBadgeRenderSignature -Data (Get-TaskbarBadgeData -Source dual)) -ne (Get-TaskbarBadgeRenderSignature -Data $timed)) 'A changing countdown must trigger a redraw'
$script:TestClaude.stale=$true
Check (@((Get-TaskbarBadgeData -Source dual).Segments[1].Parts | Where-Object Kind -eq 'countdown').Count -eq 0) 'Cached values must not count down'
# The rendering checks below include the clock glyph and countdown text.
$script:TestClaude=[pscustomobject]@{lastCheckedAt=(Get-Date).ToString('o');lastSuccessAt=(Get-Date).ToString('o');lastError='';stale=$false;fiveHourRemainingPercent=80;fiveHourResetsAt=(Get-Date).AddMinutes(130).ToString('o');sevenDayRemainingPercent=62;limits=@()}

# Codex 5-hour window: on by default when the plan has one, optional, never shown twice.
function New-CodexBucket { param($FiveHour,$Weekly,$FiveHourResetsAt=[DateTimeOffset]::Now.AddMinutes(130).ToString('o')) [pscustomobject]@{limitId='codex';primaryRemainingPercent=$FiveHour;primaryWindowDurationMins=300;primaryResetsAt=$FiveHourResetsAt;secondaryRemainingPercent=$Weekly;secondaryWindowDurationMins=10080;secondaryResetsAt=[DateTimeOffset]::Now.AddDays(6).AddHours(5).ToString('o')} }
function Get-CodexText { param($Items) (@($Items | ForEach-Object { "$($_.Label) $($_.Text)" }) -join ',') }
Check ((New-DefaultState).settings.taskbarBadgeCodexFiveHour -eq $true) 'The Codex 5-hour window must be on by default'
$legacy=New-DefaultState
$legacy.settings.PSObject.Properties.Remove('taskbarBadgeCodexFiveHour')
Check ((Normalize-State $legacy).settings.taskbarBadgeCodexFiveHour -eq $true) 'Existing settings must gain the Codex 5-hour window'
foreach($value in @('off',0,$null)){ $odd=New-DefaultState; $odd.settings.taskbarBadgeCodexFiveHour=$value; Check ((Normalize-State $odd).settings.taskbarBadgeCodexFiveHour -eq $true) "Only a saved false may hide the Codex 5-hour window ($value)" }
$hidden=New-DefaultState
$hidden.settings.taskbarBadgeCodexFiveHour=$false
Check ((Normalize-State ($hidden | ConvertTo-Json -Depth 8 | ConvertFrom-Json)).settings.taskbarBadgeCodexFiveHour -eq $false) 'Hiding the Codex 5-hour window must survive a settings round trip'
$countdownState=$script:State
$script:State=New-TestState
$script:State.settings.taskbarBadgeLayout='dual'
$script:State.liveUsage.buckets=@(New-CodexBucket 100 0)
$plus=Get-TaskbarBadgeData -Source codex
Check ((Get-CodexText $plus.Items) -eq '5h 100%,weekly 0%') 'A plan with a 5-hour limit must show it before the weekly window'
Check ($plus.PrimaryPrefix -eq '5h' -and $plus.SecondaryPrefix -eq 'weekly' -and $plus.Width -gt 176) 'The one-provider pill must make room for both Codex windows'
Check ((Get-CodexText (Get-TaskbarBadgeData -Source dual).Segments[0].Items) -eq '5h 100%,wk 0%') 'Two providers must show both Codex windows'
$script:State.settings.taskbarBadgeDualDetail='tightest'
Check ((Get-CodexText (Get-TaskbarBadgeData -Source dual).Segments[0].Items) -eq 'wk 0%') 'Tightest mode must keep an exhausted weekly window'
$script:State.liveUsage.buckets=@(New-CodexBucket 12 64)
Check ((Get-CodexText (Get-TaskbarBadgeData -Source dual).Segments[0].Items) -eq '5h 12%') 'Tightest mode must pick the Codex 5-hour window when it binds'
$script:State.settings.taskbarBadgeDualDetail='all'
$script:State.settings.taskbarBadgeResetCountdown=$true
$codexParts=@((Get-TaskbarBadgeData -Source dual).Segments[0].Parts)
Check (@($codexParts | Where-Object Kind -eq 'countdown').Count -eq 1 -and @($codexParts | Where-Object Kind -eq 'countdown')[0].Text -match '^2h(09|10)m$') 'Only the Codex 5-hour window may count down by default'
$script:State.liveUsage.buckets=@(New-CodexBucket 100 64 -FiveHourResetsAt (Get-Date).AddMinutes(-1).ToString('o'))
$stale=Get-TaskbarBadgeData -Source dual
Check ((Get-CodexText $stale.Segments[0].Items) -eq '5h --,wk 64%') 'A Codex 5-hour window that just reset must stay as unknown until the next refresh'
Check (@($stale.Segments[0].Parts | Where-Object Kind -eq 'countdown').Count -eq 0) 'An unknown Codex 5-hour window must not count down'
$script:State.liveUsage.buckets=@([pscustomobject]@{limitId='codex';primaryRemainingPercent=61;primaryWindowDurationMins=300;primaryResetsAt=(Get-Date).AddHours(2).ToString('o')})
Check ((Get-CodexText (Get-TaskbarBadgeData -Source codex).Items) -eq '5h 61%') 'A plan with only a 5-hour window must show it once'
$script:State.liveUsage.buckets=@(New-CodexBucket 12 64)
$script:State.settings.taskbarBadgeCodexFiveHour=$false
$weeklyOnly=Get-TaskbarBadgeData -Source codex
Check ((Get-CodexText $weeklyOnly.Items) -eq 'weekly 64%' -and $weeklyOnly.Width -eq 176) 'Hiding the Codex 5-hour window must restore the weekly-only pill'
Check ((Get-CodexText (Get-TaskbarBadgeData -Source dual).Segments[0].Items) -eq 'wk 64%') 'Hiding the Codex 5-hour window must apply to two providers too'
Check ((@((Get-QuickViewModel)[0].Windows | ForEach-Object Text) -join ',') -eq '12%,64%') 'The quick view must keep both Codex windows when the pill hides one'
$script:State=$countdownState

# Rendering: native text and divider stay inside the opaque interior at every DPI and theme.
foreach($theme in @('Light','Dark')) {
    foreach($scale in @(1.0,1.25,1.5,1.75,2.0)) {
        $script:BadgeTheme=$theme
        $script:BadgeDpiScale=$scale
        Clear-BadgeSegmentLogoCache
        $data=Get-TaskbarBadgeData -Source dual
        $width=ConvertTo-BadgePixels $data.Width
        $height=ConvertTo-BadgePixels 28
        $script:State.settings.taskbarBadgeDualSources=@('antigravity','claude')
        $next=Get-TaskbarBadgeData -Source dual
        $script:State.settings.taskbarBadgeDualSources=@('codex','claude')
        foreach($frame in @(
            (New-TaskbarBadgeSegmentBitmap -Data $data -Width $width -Height $height),
            (New-TaskbarBadgeSegmentBitmap -Data $data -NextData $next -Ease 0.5 -Width $width -Height $height))) {
            $surface=[UtpPillForm]::RenderSurface($frame.Width,$frame.Height,(Get-TaskbarBadgeColor),(Get-TaskbarBadgeBorderColor))
            try {
                $changed=0
                for($y=0;$y -lt $frame.Height;$y++){ for($x=0;$x -lt $frame.Width;$x++){
                    $a=$frame.GetPixel($x,$y); $b=$surface.GetPixel($x,$y)
                    Check ($a.A -eq $b.A) "Two-provider content must preserve the alpha mask ($theme, $scale)"
                    if($a.ToArgb() -ne $b.ToArgb()){$changed++}
                }}
                Check ($changed -gt 200) 'Logos and text must be drawn'
            } finally { $frame.Dispose(); $surface.Dispose() }
        }
        $frame=New-TaskbarBadgeSegmentBitmap -Data $data -Width $width -Height $height
        try {
            $dividerPixel=$frame.GetPixel((ConvertTo-BadgePixels $data.Dividers[0]),[int]($height/2))
            Check ($dividerPixel.ToArgb() -eq (Get-TaskbarBadgeDividerColor).ToArgb()) "The divider must be a crisp device pixel ($theme, $scale)"
        } finally { $frame.Dispose() }
    }
}

# Live pill: layout switches, side clicks, rapid clicks, swaps and theme changes.
$script:BadgeDpiScale=1.0
$script:State=New-TestState
$script:TestTheme='Light'
Ensure-TaskbarBadge
$script:BadgeForm.PresentEnabled=$false
try {
    Refresh-TaskbarBadge
    Check ($script:BadgeDisplayedSource -eq 'codex') 'The single pill must remain the default'
    $singleWidth=$script:BadgeForm.Width
    $saves=$script:TestSaveCount
    Set-TaskbarBadgePreference -Layout dual
    Check ($script:TestSaveCount -gt $saves) 'Layout changes must be saved'
    Check ($script:BadgeDisplayedSource -eq 'dual' -and $null -ne $script:BadgeDualData) 'Switching layout must redraw immediately'
    Check ($script:BadgeForm.Width -eq (ConvertTo-BadgePixels $script:BadgeDualData.Width)) 'The capsule must fit both providers'
    Check ($script:BadgeForm.AccessibleName -match 'ChatGPT / Codex' -and $script:BadgeForm.AccessibleName -match 'Claude') 'Both providers must be announced'
    $bitmap=New-TaskbarBadgeBitmap
    try { Check ($bitmap.Width -eq $script:BadgeForm.Width) 'The presented frame must use the dual renderer' } finally { $bitmap.Dispose() }

    $left=New-Object Windows.Forms.MouseEventArgs ([Windows.Forms.MouseButtons]::Left),1,5,5,0
    Invoke-TaskbarBadgeMouseUp -EventArgs $left
    Wait-BadgeAnimation
    Check ((@(Get-TaskbarBadgeDualSources) -join ',') -eq 'antigravity,claude') 'Clicking the left side must switch only that side'
    Check ((@($script:BadgeDualData.Sources) -join ',') -eq 'antigravity,claude') 'The pill must show the new left provider'
    Check ($script:PendingStateSave) 'Side switches must be saved after the transition'
    $right=New-Object Windows.Forms.MouseEventArgs ([Windows.Forms.MouseButtons]::Left),1,($script:BadgeForm.Width-5),5,0
    Invoke-TaskbarBadgeMouseUp -EventArgs $right
    Invoke-TaskbarBadgeMouseUp -EventArgs $right
    Wait-BadgeAnimation
    Check ((@($script:BadgeDualData.Sources) -join ',') -eq (@(Get-TaskbarBadgeDualSources) -join ',')) 'Rapid clicks must finish at the latest selection'
    Check (@(Get-TaskbarBadgeDualSources)[0] -eq 'antigravity') 'Clicking the right side must keep the left side'

    Set-TaskbarBadgePreference -Slot 0 -Source codex
    Set-TaskbarBadgePreference -Slot 1 -Source claude
    Set-TaskbarBadgePreference -Swap
    Check ((@(Get-TaskbarBadgeDualSources) -join ',') -eq 'claude,codex') 'Swap must exchange both sides'
    Set-TaskbarBadgePreference -Slot 0 -Source codex
    Check ((@(Get-TaskbarBadgeDualSources) -join ',') -eq 'codex,claude') 'Choosing the other side''s provider must swap instead of duplicating'
    Check ((@($script:BadgeDualData.Sources) -join ',') -eq 'codex,claude') 'Side choices must redraw the pill'

    $weeklyBuckets=$script:State.liveUsage.buckets
    $script:State.liveUsage.buckets=@(New-CodexBucket 72 41)
    Set-TaskbarBadgePreference -CodexFiveHour on
    $wide=$script:BadgeForm.Width
    Check ((Get-CodexText $script:BadgeDualData.Segments[0].Items) -eq '5h 72%,wk 41%') 'The live pill must show the Codex 5-hour window'
    $saves=$script:TestSaveCount
    Set-TaskbarBadgePreference -CodexFiveHour off
    Check ($script:TestSaveCount -gt $saves -and $script:State.settings.taskbarBadgeCodexFiveHour -eq $false) 'Hiding the Codex 5-hour window must be saved'
    Check ((Get-CodexText $script:BadgeDualData.Segments[0].Items) -eq 'wk 41%' -and $script:BadgeForm.Width -lt $wide) 'Hiding the Codex 5-hour window must redraw a narrower pill right away'
    Set-TaskbarBadgePreference -CodexFiveHour on
    Check ($script:State.settings.taskbarBadgeCodexFiveHour -eq $true -and $script:BadgeForm.Width -eq $wide) 'Showing it again must restore the wider pill'
    $script:State.liveUsage.buckets=$weeklyBuckets
    Refresh-TaskbarBadge

    $script:TestTheme='Dark'
    Refresh-TaskbarBadge -GeometryOnly
    Check ($script:BadgeTheme -eq 'Dark' -and $script:BadgeDisplayedSource -eq 'dual' -and $script:BadgeRenderSignature -match 'Dark') 'Theme changes must redraw the dual pill'

    Set-TaskbarBadgePreference -Layout single
    Check ($script:BadgeDisplayedSource -eq 'codex' -and $script:BadgePrimaryPrefix.Text -eq '41%') 'Returning to one provider must restore the label row'
    Check ($script:BadgeForm.Width -eq $singleWidth) 'Returning to one provider must restore its width'
    $left=New-Object Windows.Forms.MouseEventArgs ([Windows.Forms.MouseButtons]::Left),1,5,5,0
    Invoke-TaskbarBadgeMouseUp -EventArgs $left
    Wait-BadgeAnimation
    Check ($script:BadgeDisplayedSource -eq 'claude') 'Single-provider clicks must keep cycling providers'
    Check ((@(Get-TaskbarBadgeDualSources) -join ',') -eq 'codex,claude') 'Single-provider clicks must not change the dual sides'
    Check (-not $script:BadgeForm.Visible) 'Rendering tests must never show a desktop pill'
} finally { Dispose-TaskbarBadge }
Check ($script:BadgeDualLogoCache.Count -eq 0) 'Disposing the pill must release cached provider artwork'
Write-Output 'Two-provider pill tests OK'
