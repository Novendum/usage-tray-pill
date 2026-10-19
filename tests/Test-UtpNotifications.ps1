$sourceRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
$ErrorActionPreference = 'Stop'
. (Join-Path $sourceRoot 'Start-UsageTrayPill.ps1') -LibraryOnly
function Check { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }

# Never touch the real profile: state and notification files go to a disposable folder.
$temporaryRoot = (Get-Item -LiteralPath ([IO.Path]::GetTempPath())).FullName
$testRoot = Join-Path $temporaryRoot ('UTP notification test ' + [guid]::NewGuid().ToString('N'))
$script:DataDir = Join-Path $testRoot 'data'
function Save-State { }
function Get-AntigravityUsageSnapshot { return $null }
function Get-ClaudeUsageSnapshot { return $script:TestClaude }
function New-ClaudeSnapshot {
    param([double]$FiveHour = 60, [double]$Weekly = 40, [bool]$Stale = $false, [string]$ErrorCode = '')
    $now = Get-Date
    return [pscustomobject]@{
        lastCheckedAt = $now.ToString('o'); lastSuccessAt = $now.ToString('o'); lastError = ''; errorCode = $ErrorCode; stale = $Stale
        limits = @(
            [pscustomobject]@{ key = 'five_hour'; label = '5h'; remainingPercent = $FiveHour; resetsAt = $now.AddMinutes(130).AddSeconds(-30).ToString('o') },
            [pscustomobject]@{ key = 'seven_day'; label = 'weekly'; remainingPercent = $Weekly; resetsAt = $now.AddHours(72).AddSeconds(-30).ToString('o') }
        )
    }
}
function New-TestState {
    $state = New-DefaultState
    $state.liveUsage.lastCheckedAt = (Get-Date).ToString('o')
    $state.liveUsage.buckets = @([pscustomobject]@{ limitId = 'codex'; primaryRemainingPercent = 41; primaryWindowDurationMins = 10080; primaryResetsAt = (Get-Date).AddDays(2).ToString('o') })
    return $state
}

try {
    # Settings: new options start off, and broken saved values recover safely.
    $defaults = New-DefaultState
    Check (-not $defaults.settings.notifyLowAllowance -and -not $defaults.settings.notifyReset -and $defaults.settings.notifyLowThreshold -eq 10) 'Notifications must start off with a 10% threshold'
    Check (-not $defaults.settings.taskbarBadgeResetCountdownWeekly) 'The long countdown must start off'
    Check ($defaults.settings.openCodeGoKeySource -eq 'auto') 'OpenCode must keep using the Windows variable by default'
    $legacy = New-DefaultState
    foreach ($name in @('notifyLowAllowance', 'notifyLowThreshold', 'notifyReset', 'taskbarBadgeResetCountdownWeekly', 'openCodeGoKeySource')) { $legacy.settings.PSObject.Properties.Remove($name) }
    $legacy = Normalize-State $legacy
    Check ($legacy.settings.notifyLowThreshold -eq 10 -and -not $legacy.settings.notifyReset -and $legacy.settings.openCodeGoKeySource -eq 'auto') 'Existing settings must gain safe defaults'
    $broken = New-DefaultState
    $broken.settings.notifyLowAllowance = 'yes'
    $broken.settings.notifyReset = 'true-ish'
    $broken.settings.notifyLowThreshold = 7
    $broken.settings.openCodeGoKeySource = 'environment'
    $broken.settings.taskbarBadgeResetCountdownWeekly = 'on'
    $broken = Normalize-State $broken
    Check (-not $broken.settings.notifyLowAllowance -and -not $broken.settings.notifyReset -and -not $broken.settings.taskbarBadgeResetCountdownWeekly) 'Only real booleans may switch options on'
    Check ($broken.settings.notifyLowThreshold -eq 10 -and $broken.settings.openCodeGoKeySource -eq 'auto') 'Unknown threshold or key source must recover'
    $valid = New-DefaultState
    $valid.settings.notifyLowAllowance = $true
    $valid.settings.notifyReset = $true
    $valid.settings.notifyLowThreshold = 25
    $valid.settings.openCodeGoKeySource = 'saved'
    $valid.settings.taskbarBadgeResetCountdownWeekly = $true
    $roundTrip = Normalize-State ($valid | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
    Check ($roundTrip.settings.notifyLowAllowance -and $roundTrip.settings.notifyReset -and $roundTrip.settings.notifyLowThreshold -eq 25 -and $roundTrip.settings.openCodeGoKeySource -eq 'saved' -and $roundTrip.settings.taskbarBadgeResetCountdownWeekly) 'Saved choices must survive a settings round trip'

    # Countdown text: rounds up, compact, days for long windows, nothing for the past or bad input.
    $now = [DateTimeOffset]::Parse('2026-10-19T12:00:00+02:00', [Globalization.CultureInfo]::InvariantCulture)
    foreach ($case in @(
        @{ At = $now.AddSeconds(30); Text = '1m' },
        @{ At = $now.AddMinutes(40); Text = '40m' },
        @{ At = $now.AddMinutes(59).AddSeconds(1); Text = '1h' },
        @{ At = $now.AddMinutes(61); Text = '1h01m' },
        @{ At = $now.AddMinutes(130); Text = '2h10m' },
        @{ At = $now.AddHours(24); Text = '1d' },
        @{ At = $now.AddHours(72); Text = '3d' },
        @{ At = $now.AddHours(53).AddMinutes(30); Text = '2d5h' },
        @{ At = $now.AddMinutes(-5); Text = '' }
    )) {
        $actual = Format-BadgeResetCountdown -ResetsAt $case.At.ToString('o') -Now $now
        Check ($actual -eq $case.Text) "Countdown for $($case.At.ToString('o')) must be '$($case.Text)', got '$actual'"
    }
    Check ((Format-BadgeResetCountdown -ResetsAt 'soon' -Now $now) -eq '' -and (Format-BadgeResetCountdown -ResetsAt '' -Now $now) -eq '') 'Unreadable reset times must not count down'

    # Pill countdown: 5h by default, weekly/monthly/day windows only when the long countdown is on.
    $script:State = New-TestState
    $script:TestClaude = New-ClaudeSnapshot
    $script:State.settings.taskbarBadgeResetCountdown = $false
    Check (@((Get-TaskbarBadgeSegment -Source 'claude').Items | Where-Object Countdown).Count -eq 0) 'No countdown may show while the option is off'
    $script:State.settings.taskbarBadgeResetCountdown = $true
    $items = @((Get-TaskbarBadgeSegment -Source 'claude').Items)
    Check ($items[0].Countdown -eq '2h10m' -and $items[1].Countdown -eq '') 'Only the 5-hour window counts down by default'
    $script:State.settings.taskbarBadgeResetCountdownWeekly = $true
    $items = @((Get-TaskbarBadgeSegment -Source 'claude').Items)
    Check ($items[0].Countdown -eq '2h10m' -and $items[1].Countdown -eq '3d') 'The weekly window must count down in days when enabled'
    $script:State.liveUsage.buckets = @([pscustomobject]@{ limitId = 'codex'; primaryRemainingPercent = 55; primaryWindowDurationMins = 2880; primaryResetsAt = (Get-Date).AddHours(30).AddSeconds(-30).ToString('o') })
    Check (@((Get-TaskbarBadgeSegment -Source 'codex').Items)[0].Countdown -eq '1d6h') 'Day-length Codex windows must count down with the long option'
    $script:TestClaude = New-ClaudeSnapshot -Stale $true
    Check (@((Get-TaskbarBadgeSegment -Source 'claude').Items | Where-Object Countdown).Count -eq 0) 'Cached values must never count down'

    # Attention: only problems the user must fix mark a provider; temporary errors stay quiet.
    $script:State = New-TestState
    $script:TestClaude = New-ClaudeSnapshot
    Check (-not (Get-ProviderAttention -Source 'codex')) 'A healthy provider needs no attention'
    $script:State.liveUsage.lastError = 'network_error'
    Check (-not (Get-ProviderAttention -Source 'codex')) 'A network error retries by itself and must not ask for attention'
    $script:State.liveUsage.lastError = 'auth_expired'
    Check ((Get-ProviderAttentionCode -Source 'codex') -eq 'auth_expired') 'An expired sign-in must ask for attention'
    $script:TestClaude = New-ClaudeSnapshot -ErrorCode 'auth_required'
    $script:State.settings.claudeControlEnabled = $false
    Check (-not (Get-ProviderAttention -Source 'claude')) 'Claude without live collection must not ask for attention'
    $script:State.settings.claudeControlEnabled = $true
    Check (Get-ProviderAttention -Source 'claude') 'Claude sign-in problems must ask for attention when collection is on'
    Check ((Get-ProviderAttentionText -Source 'claude' -Code 'auth_required') -eq 'Sign-in required' -and (Get-ProviderAttentionText -Source 'qwen' -Code 'auth_expired') -eq 'Session expired') 'Attention text must stay short and specific'
    $single = Get-TaskbarBadgeData -Source 'claude'
    $withAttention = Get-TaskbarBadgeRenderSignature -Data $single
    $script:TestClaude = New-ClaudeSnapshot
    Check ($withAttention -ne (Get-TaskbarBadgeRenderSignature -Data $single)) 'The single pill must redraw when attention changes'
    $script:State.settings.taskbarBadgeDualSources = @('codex', 'claude')
    $dual = Get-TaskbarBadgeDualData -Sources @('codex', 'claude')
    Check (@($dual.Items | Where-Object Label -eq '@codex!').Count -eq 1 -and @($dual.Items | Where-Object Label -eq '@claude').Count -eq 1) 'Dual markers must carry attention per side'
    Check ($dual.Segments[0].Attention -and -not $dual.Segments[1].Attention) 'Each dual segment must know its own attention state'
    $dotSurface = New-Object System.Drawing.Bitmap 40, 40
    $graphics = [System.Drawing.Graphics]::FromImage($dotSurface)
    try {
        $graphics.Clear([System.Drawing.Color]::White)
        Draw-BadgeAttentionDot -Graphics $graphics -LogoRect (New-Object System.Drawing.Rectangle 10, 10, 20, 20) -Surface ([System.Drawing.Color]::White)
    }
    finally { $graphics.Dispose() }
    $dotPixel = $dotSurface.GetPixel(26, 13)
    $dotSurface.Dispose()
    Check ($dotPixel.R -gt 180 -and $dotPixel.G -lt 90 -and $dotPixel.B -lt 90) 'The attention dot must sit on the logo''s top-right corner in red'

    # Notification decisions: pure, latched with hysteresis, and quiet after restarts.
    $notificationState = @{}
    function Get-Events {
        param([double]$Percent, [string]$ResetsAt, [int]$Threshold = 10, [bool]$Low = $true, [bool]$Reset = $true, [string]$Key = 'claude|5h', [string]$Label = '5h')
        $observation = [pscustomobject]@{ Key = $Key; Provider = 'Claude'; Label = $Label; Percent = $Percent; ResetsAt = $ResetsAt }
        return @(Get-UsageNotificationEvents -State $notificationState -Observations @($observation) -Threshold $Threshold -NotifyLow $Low -NotifyReset $Reset -Now $now)
    }
    $firstReset = $now.AddHours(2).ToString('o')
    Check (@(Get-Events 50 $firstReset).Count -eq 0) 'A first healthy reading must stay quiet'
    $events = @(Get-Events 8 $firstReset)
    Check ($events.Count -eq 1 -and $events[0].Kind -eq 'low' -and $events[0].Title -eq 'Claude 5-hour limit' -and $events[0].Text -eq 'Only 8% left. Resets in 2h.') 'Falling under the threshold must notify once with the reset time'
    Check (@(Get-Events 7 $firstReset).Count -eq 0) 'A low window must not notify again'
    Check (@(Get-Events 12 $firstReset).Count -eq 0 -and @(Get-Events 9 $firstReset).Count -eq 0) 'Small swings around the threshold must stay quiet'
    Check (@(Get-Events 16 $firstReset).Count -eq 0) 'Recovering above the margin re-arms silently'
    Check (@(Get-Events 9 $firstReset).Count -eq 1) 'A new drop after recovery must notify again'
    $nextReset = $now.AddHours(7).ToString('o')
    $events = @(Get-Events 100 $nextReset)
    Check ($events.Count -eq 1 -and $events[0].Kind -eq 'reset' -and $events[0].Title -eq 'Claude 5-hour limit reset' -and $events[0].Text -eq '100% available again.') 'A new window with more allowance must report the reset'
    Check (-not $notificationState['claude|5h'].low) 'A reset must re-arm the low warning'
    Check (@(Get-Events 90 $now.AddHours(7).AddSeconds(30).ToString('o')).Count -eq 0) 'A reset time that moves by seconds is not a reset'
    Check (@(Get-Events 80 $now.AddHours(12).ToString('o')).Count -eq 0) 'A later reset time without more allowance is not a reset'
    Check (@(Get-Events 50 '').Count -eq 0) 'Without reset times a small rise is not a reset'
    Check (@(Get-Events 85 '').Count -eq 1) 'Without reset times a large jump counts as a reset'
    Check (@(Get-Events 5 '' -Low $false -Reset $false).Count -eq 0 -and $notificationState['claude|5h'].low) 'Disabled warnings still track state so enabling them later stays quiet'
    Check (@(Get-Events 24 $firstReset -Threshold 25 -Key 'codex|weekly' -Label 'weekly')[0].Title -eq 'Claude weekly limit') 'Weekly windows must be named in the title'
    Check ((Get-UsageWindowTitle 'monthly') -eq 'monthly limit' -and (Get-UsageWindowTitle 'Flash') -eq 'Flash limit') 'Window names must read naturally'

    # Observations: fresh known values only; cached, unknown and cache markers never notify.
    $script:State = New-TestState
    $script:TestClaude = New-ClaudeSnapshot -FiveHour 9
    $observations = @(Get-UsageNotificationObservations)
    Check (@($observations | ForEach-Object Key) -join ',' -eq 'codex|weekly,claude|5h,claude|weekly') 'Only known provider windows may be observed'
    $script:TestClaude = New-ClaudeSnapshot -FiveHour 9 -Stale $true
    Check (@(Get-UsageNotificationObservations | Where-Object Key -like 'claude*').Count -eq 0) 'Cached Claude values must never notify'

    # Integration: one balloon per check, state persisted, nothing when both options are off.
    $script:Sent = New-Object System.Collections.ArrayList
    function Send-UtpNotification { param([string]$Title, [string]$Text) [void]$script:Sent.Add("$Title|$Text") }
    $script:NotificationState = $null
    $script:State.settings.notifyLowAllowance = $false
    $script:State.settings.notifyReset = $false
    Update-UsageNotifications
    Check ($script:Sent.Count -eq 0 -and -not (Test-Path -LiteralPath (Get-UsageNotificationPath))) 'With notifications off nothing may be sent or written'
    $script:State.settings.notifyLowAllowance = $true
    $script:TestClaude = New-ClaudeSnapshot -FiveHour 9 -Weekly 6
    Update-UsageNotifications
    Check ($script:Sent.Count -eq 1 -and $script:Sent[0] -like 'Claude weekly limit|Only 6% left.*(+1 more)') 'Several warnings at once must become one balloon'
    Check (Test-Path -LiteralPath (Get-UsageNotificationPath)) 'Notification state must persist'
    $script:NotificationState = $null
    Update-UsageNotifications
    Check ($script:Sent.Count -eq 1) 'A restart must not repeat warnings that were already shown'
    [IO.File]::WriteAllText((Get-UsageNotificationPath), '{broken')
    Check ((Read-UsageNotificationState).Count -eq 0) 'A corrupted state file must be ignored'

    Write-Host 'Notification, attention and countdown tests OK (settings, countdown text, weekly countdown, attention markers, latching, resets, persistence).'
}
finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if ($resolved.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'UTP notification test *' -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
