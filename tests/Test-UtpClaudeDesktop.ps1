$sourceRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
$ErrorActionPreference = 'Stop'
. (Join-Path $sourceRoot 'Start-UsageTrayPill.ps1') -LibraryOnly
function Check { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }

# Never read the real Claude Desktop or Claude CLI: every location points into a disposable folder.
$root = Join-Path ([IO.Path]::GetTempPath()) ('UtpClaudeDesktop-' + [guid]::NewGuid().ToString('N'))
$savedEnvironment = @{}
foreach ($name in @('LOCALAPPDATA', 'APPDATA', 'USERPROFILE', 'CLAUDE_CONFIG_DIR')) { $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    $env:LOCALAPPDATA = Join-Path $root 'local'
    $env:APPDATA = Join-Path $root 'roaming'
    $env:USERPROFILE = Join-Path $root 'profile'
    [Environment]::SetEnvironmentVariable('CLAUDE_CONFIG_DIR', $null, 'Process')
    foreach ($directory in @($env:LOCALAPPDATA, $env:APPDATA, $env:USERPROFILE)) { [void](New-Item -ItemType Directory -Path $directory -Force) }
    $script:DataDir = Join-Path $root 'utp'
    [void](New-Item -ItemType Directory -Path $script:DataDir)
    $script:ClaudeControlUsagePath = Join-Path $script:DataDir 'claude-control-usage.json'
    $script:ClaudeUsagePath = Join-Path $script:DataDir 'claude-usage.json'
    $desktopAccount = '11111111-1111-4111-8111-111111111111'
    $cliAccount = '22222222-2222-4222-8222-222222222222'
    $current = Join-Path $env:LOCALAPPDATA 'Claude-Data\claude_fixture'
    $older = Join-Path $env:LOCALAPPDATA 'Packages\Claude_fixture\LocalCache\Roaming\Claude'

    function New-Sample { param([double]$MinutesAgo, $FiveHour, $Week) [pscustomobject]@{ t = [DateTimeOffset]::Now.AddMinutes(-$MinutesAgo).ToUnixTimeMilliseconds(); org = 'fixture-org'; u = [pscustomobject]@{ fh = $FiveHour; sd = $Week } } }
    function Write-DesktopData {
        param([string]$Directory, [object[]]$Samples, [string]$Account)
        [void](New-Item -ItemType Directory -Path $Directory -Force)
        [pscustomobject]@{ version = 2; samples = @($Samples) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Directory 'plan-usage-history.json') -Encoding UTF8
        # The account sits between unrelated settings and an opaque token cache that UTP must leave alone.
        ('{"locale":"nl-NL","lastKnownAccountUuid":"' + $Account + '","oauth:tokenCacheV2":"opaque-fixture"}') | Set-Content -LiteralPath (Join-Path $Directory 'config.json') -Encoding UTF8
    }
    function Write-CliAccount {
        param([string]$Account)
        # Keys that differ only in case make this file unreadable for ConvertFrom-Json in Windows PowerShell.
        ('{"projects":{"C:/Work":{},"c:/work":{}},"oauthAccount":{"ccOnboardingFlags":{"seen":true},"accountUuid":"' + $Account + '","organizationType":"claude_team"}}') | Set-Content -LiteralPath (Join-Path $env:USERPROFILE '.claude.json') -Encoding UTF8
    }
    function Write-CliUsage {
        param([string]$ErrorCode = '')
        $now = [DateTimeOffset]::Now
        $items = @(if (-not $ErrorCode) {
            [pscustomobject]@{ key = 'five_hour'; label = '5h'; remainingPercent = 61; resetsAt = $now.AddMinutes(90).ToString('o') }
            [pscustomobject]@{ key = 'seven_day'; label = 'weekly'; remainingPercent = 70; resetsAt = $now.AddDays(3).ToString('o') }
        })
        [pscustomobject]@{ source = 'claude-code-control'; available = (-not $ErrorCode); stale = $false; lastError = $ErrorCode; errorCode = $ErrorCode; lastCheckedAt = $now.ToString('o'); lastSuccessAt = $now.ToString('o'); items = $items } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:ClaudeControlUsagePath -Encoding UTF8
    }
    function Test-QuickViewStatusFits {
        # The quick view draws a provider status in a 170-pixel slot and cuts longer text off.
        $status = [string](@(Get-QuickViewModel) | Where-Object Source -eq 'claude').Status
        $font = New-Object System.Drawing.Font 'Segoe UI', 12, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
        try { $width = [System.Windows.Forms.TextRenderer]::MeasureText($status, $font, (New-Object System.Drawing.Size 1000, 40), ([System.Windows.Forms.TextFormatFlags]::SingleLine -bor [System.Windows.Forms.TextFormatFlags]::NoPadding)).Width }
        finally { $font.Dispose() }
        Check ($status -and $width -le 170) "The quick view status must fit its slot: '$status' is $width px"
    }
    function Reset-ClaudeCaches { $script:ClaudeDesktopHistoryCache = $null; $script:ClaudeDesktopAccount = $null; $script:ClaudeCliAccountCache = $null }

    $script:State = New-DefaultState
    $script:State.settings.claudeControlEnabled = $true

    # Discovery: current and older Claude Desktop folders; the most recently written history wins.
    Check (@(Get-ClaudeDesktopDataDirectories).Count -eq 0) 'Without Claude Desktop there must be nothing to read'
    Write-DesktopData $older @(New-Sample 2 50 50) $desktopAccount
    (Get-Item -LiteralPath (Join-Path $older 'plan-usage-history.json')).LastWriteTime = (Get-Date).AddHours(-2)
    Write-DesktopData $current @((New-Sample 30 90 90), (New-Sample 5 40 18)) $desktopAccount
    Check (@(Get-ClaudeDesktopDataDirectories).Count -eq 2) 'Both Claude Desktop folder layouts must be found'
    $desktop = Get-ClaudeDesktopUsageSnapshot
    Check ($desktop.fiveHourRemainingPercent -eq 60 -and $desktop.sevenDayRemainingPercent -eq 82 -and $desktop.accountUuid -eq $desktopAccount) 'The newest Claude Desktop history and its signed-in account must be read'
    Write-CliAccount $cliAccount
    Check ((Get-ClaudeCliAccountUuid) -eq $cliAccount) 'The CLI account must be readable without parsing the whole settings file'

    # Another account in Claude Desktop: the pill follows Desktop, with percentages and no reset times.
    Write-CliUsage
    $usage = Get-ClaudeUsageSnapshot
    Check ($usage.source -eq 'claude-desktop-plan-history' -and $usage.fiveHourRemainingPercent -eq 60 -and $usage.sevenDayRemainingPercent -eq 82) 'A Desktop account other than the CLI account must decide what the pill shows'
    Check ((Get-ProviderStatusMessage -Source 'claude') -like 'Claude - Via Claude Desktop, *') 'The overview must say the numbers come from Claude Desktop'
    Test-QuickViewStatusFits
    $pill = Get-TaskbarBadgeData -Source 'claude'
    Check ((@($pill.Items | ForEach-Object { "$($_.Label) $($_.Text)" }) -join ',') -eq '5h 60%,weekly 82%' -and @($pill.Items | Where-Object { $_.ResetsAt }).Count -eq 0) 'The pill must show the Desktop account without invented reset times'

    # The same account in both: the CLI answer stays, because it carries reset times.
    Reset-ClaudeCaches
    Write-CliAccount $desktopAccount
    $usage = Get-ClaudeUsageSnapshot
    Check ($usage.source -eq 'claude-code-control' -and $usage.fiveHourRemainingPercent -eq 61 -and $usage.fiveHourResetsAt) 'With one account the CLI answer and its reset times must stay'
    Write-CliUsage -ErrorCode 'auth_required'
    Check ((Get-ClaudeUsageSnapshot).fiveHourRemainingPercent -eq 60) 'Without a CLI answer, Claude Desktop must fill in'

    # Desktop samples about every 15 minutes: an 18-minute-old sample is still current, a 40-minute-old one is not.
    Reset-ClaudeCaches
    Write-CliUsage
    Write-CliAccount $cliAccount
    Write-DesktopData $current @(New-Sample 18 25 30) $desktopAccount
    Check ((Get-ClaudeUsageSnapshot).fiveHourRemainingPercent -eq 75) 'A sample from the last Desktop interval must not blink to unknown'
    Reset-ClaudeCaches
    Write-DesktopData $current @(New-Sample 40 25 30) $desktopAccount
    $usage = Get-ClaudeUsageSnapshot
    Check ($usage.source -eq 'claude-code-control' -and $usage.fiveHourRemainingPercent -eq 61) 'When Claude Desktop stopped recording, the CLI answer must stay'

    # An account switch in Desktop: old samples belong to the old account, so wait for the first new one.
    Reset-ClaudeCaches
    Write-DesktopData $current @(New-Sample 5 40 18) $desktopAccount
    Check ((Get-ClaudeUsageSnapshot).fiveHourRemainingPercent -eq 60) 'Before the switch the Desktop account must show'
    $thirdAccount = '33333333-3333-4333-8333-333333333333'
    Write-DesktopData $current @(New-Sample 5 40 18) $thirdAccount
    $usage = Get-ClaudeUsageSnapshot
    Check ($usage.source -eq 'claude-desktop-plan-history' -and [bool]$usage.pending -and $null -eq $usage.fiveHourRemainingPercent) 'Right after a switch the old account must not show'
    Check ((Get-ProviderStatusMessage -Source 'claude') -eq 'Claude - Waiting for Claude Desktop' -and (Get-TaskbarBadgeData -Source 'claude').StatusText -eq 'Waiting for Claude Desktop') 'The wait must be explained'
    Test-QuickViewStatusFits
    Write-DesktopData $current @((New-Sample 5 40 18), (New-Sample -1 12 9)) $thirdAccount
    Check ((Get-ClaudeUsageSnapshot).fiveHourRemainingPercent -eq 88) 'The first sample of the new account must show'
    Write-DesktopData $current @((New-Sample 5 40 18), (New-Sample -1 12 9)) $cliAccount
    $usage = Get-ClaudeUsageSnapshot
    Check ($usage.source -eq 'claude-code-control' -and $usage.fiveHourRemainingPercent -eq 61) 'Switching back to the CLI account must use the CLI answer right away'

    # The statusline source keeps its Desktop fallback, now in the current folder.
    Reset-ClaudeCaches
    $script:State.settings.claudeControlEnabled = $false
    Write-DesktopData $current @(New-Sample 5 40 18) $desktopAccount
    $usage = Get-ClaudeUsageSnapshot
    Check ($usage.source -eq 'claude-desktop-plan-history' -and $usage.fiveHourRemainingPercent -eq 60) 'Without statusline data the current Desktop folder must be used'
    Write-Output 'Claude Desktop account tests OK (discovery, account match, freshness, switch, statusline fallback)'
}
finally {
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
    $resolved = [IO.Path]::GetFullPath($root)
    if ($resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'UtpClaudeDesktop-*') { Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue }
}
