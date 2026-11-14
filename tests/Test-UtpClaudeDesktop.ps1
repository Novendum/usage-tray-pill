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
    function Write-DesktopAccount {
        param([string]$Directory, [string]$Account)
        [void](New-Item -ItemType Directory -Path $Directory -Force)
        # The account sits between unrelated settings and an opaque token cache that UTP must leave alone.
        $field = if ($Account) { '"lastKnownAccountUuid":"' + $Account + '",' } else { '' }
        ('{"locale":"nl-NL",' + $field + '"oauth:tokenCacheV2":"opaque-fixture"}') | Set-Content -LiteralPath (Join-Path $Directory 'config.json') -Encoding UTF8
    }
    function Write-DesktopData {
        param([string]$Directory, [object[]]$Samples, [string]$Account)
        [void](New-Item -ItemType Directory -Path $Directory -Force)
        [pscustomobject]@{ version = 2; samples = @($Samples) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Directory 'plan-usage-history.json') -Encoding UTF8
        Write-DesktopAccount $Directory $Account
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

    # Which login answers. Claude Desktop's own sessions write their account into the CLI's shared .claude.json, so
    # that file says whose credentials the CLI's own login holds only while UTP keeps no logins of its own.
    $accountA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    $accountB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
    function Set-LoginFixture {
        param([string]$Desktop, [string]$Own, [hashtable]$Kept = @{})
        $accounts = Get-ClaudeAccountsDirectory
        if (Test-Path -LiteralPath $accounts) { Remove-Item -LiteralPath $accounts -Recurse -Force }
        foreach ($folder in $Kept.Keys) {
            $path = Join-Path $accounts $folder
            [void](New-Item -ItemType Directory -Path $path -Force)
            if ($Kept[$folder]) { ('{"oauthAccount":{"accountUuid":"' + $Kept[$folder] + '"}}') | Set-Content -LiteralPath (Join-Path $path '.claude.json') -Encoding UTF8 }
        }
        Write-DesktopAccount $current $Desktop
        Write-CliAccount $Own
        $script:ClaudeCliAccountCache = $null
        $script:ClaudeDesktopAccountCache = $null
    }
    function Test-UsageLogin {
        param([string]$Account, [string]$Folder, [bool]$Missing, [string]$Message)
        $login = Get-ClaudeUsageLogin
        $expected = if ($Folder) { Join-Path (Get-ClaudeAccountsDirectory) $Folder } else { '' }
        Check ($login.Account -eq $Account -and $login.ConfigDirectory -eq $expected -and [bool]$login.Missing -eq $Missing) "$Message (account '$($login.Account)', folder '$($login.ConfigDirectory)', missing $($login.Missing))"
    }
    Set-LoginFixture -Desktop $accountA -Own $accountA
    Test-UsageLogin $accountA '' $false 'With one account and no kept logins, the CLI''s own login must answer'
    $revisionAlone = Get-UtpCredentialRevision 'claude'
    Set-LoginFixture -Desktop $accountA -Own $accountA -Kept @{ $accountA = $accountA }
    Test-UsageLogin $accountA $accountA $false 'A kept login must answer for its account, also when .claude.json names that account'
    Set-LoginFixture -Desktop $accountA -Own $accountA -Kept @{ $accountB = $accountB }
    Test-UsageLogin $accountA '' $true 'Next to a kept login, a .claude.json that names the Desktop account must not make the CLI''s own login answer'
    Check ((Get-UtpCredentialRevision 'claude') -ne $revisionAlone) 'A login kept for another account must make the collector ask again at once'
    Set-LoginFixture -Desktop $accountB -Own $accountA -Kept @{ $accountB = $accountB }
    Test-UsageLogin $accountB $accountB $false 'Another account in Claude Desktop must answer through its kept login'
    Set-LoginFixture -Desktop $accountB -Own $accountA
    Test-UsageLogin $accountB '' $true 'Another account without a kept login must ask for a sign-in'
    Set-LoginFixture -Desktop '' -Own $accountA -Kept @{ $accountB = $accountB }
    Test-UsageLogin $accountA '' $false 'Without an account in Claude Desktop the CLI''s own login must answer'
    Set-LoginFixture -Desktop $accountA -Own $accountA -Kept @{ 'pending-fixture' = '' }
    Test-UsageLogin $accountA '' $false 'A sign-in still in progress must not count as a kept login'
    Set-LoginFixture -Desktop $accountA -Own $accountA -Kept @{ $accountA = $accountB }
    Test-UsageLogin $accountA '' $true 'A folder that holds another account''s login must not answer'
    Set-LoginFixture -Desktop $desktopAccount -Own $cliAccount

    # The CLI source answers for the account Claude Desktop uses, through a login of its own for another account.
    $script:Asked = New-Object System.Collections.ArrayList
    $script:Answer = 'own'
    function Get-UtpClaudeControlUsage {
        param([string]$ConfigDirectory = '')
        [void]$script:Asked.Add($ConfigDirectory)
        $now = [DateTimeOffset]::Now
        if ($script:Answer -eq 'timeout') { return New-UtpExternalUsageFailure 'claude-code-control' 'timeout' 'Synthetic timeout' }
        $values = if ($ConfigDirectory) { @(33, 44) } else { @(61, 70) }
        return [pscustomobject]@{ source = 'claude-code-control'; available = $true; lastCheckedAt = $now.ToString('o'); lastSuccessAt = $now.ToString('o'); lastError = ''; errorCode = ''; items = @(
            [pscustomobject]@{ key = 'five_hour'; label = '5h'; remainingPercent = $values[0]; resetsAt = $now.AddMinutes(90).ToString('o') },
            [pscustomobject]@{ key = 'seven_day'; label = 'weekly'; remainingPercent = $values[1]; resetsAt = $now.AddDays(3).ToString('o') }) }
    }
    Reset-ClaudeCaches
    Write-DesktopData $current @(New-Sample 5 40 18) $desktopAccount
    $login = Get-ClaudeUsageLogin
    Check ($login.Account -eq $desktopAccount -and $login.Missing -and -not $login.ConfigDirectory) 'Another account in Claude Desktop needs a login of its own'
    $revisionWithout = Get-UtpCredentialRevision 'claude'
    [void](Update-ClaudeControlUsage)
    $usage = Get-ClaudeUsageSnapshot
    Check ($script:Asked.Count -eq 0 -and $usage.errorCode -eq 'account_sign_in_required' -and $null -eq $usage.fiveHourRemainingPercent) 'Without that login UTP must ask for a sign-in, never show the CLI account'
    Check ((Get-ProviderAttentionCode -Source 'claude') -eq 'account_sign_in_required' -and (Get-ProviderAttentionText -Source 'claude' -Code 'account_sign_in_required') -eq 'Sign in for this account') 'The pill and quick view must ask to sign in for this account'
    Check ((Get-ProviderRetrySeconds 'account_sign_in_required' 1) -lt 0) 'A missing login must pause instead of retrying'

    # Once UTP keeps a login for it, Claude answers for that account through it, with reset times.
    $accountLogin = Join-Path (Get-ClaudeAccountsDirectory) $desktopAccount
    [void](New-Item -ItemType Directory -Path $accountLogin -Force)
    ('{"oauthAccount":{"accountUuid":"' + $desktopAccount + '"}}') | Set-Content -LiteralPath (Join-Path $accountLogin '.claude.json') -Encoding UTF8
    $login = Get-ClaudeUsageLogin
    Check ($login.ConfigDirectory -eq $accountLogin -and -not $login.Missing) 'A kept login must answer for its account'
    Check ((Get-UtpCredentialRevision 'claude') -ne $revisionWithout) 'A new login must make the collector ask again at once'
    [void](Update-ClaudeControlUsage)
    $usage = Get-ClaudeUsageSnapshot
    Check ($script:Asked[-1] -eq $accountLogin -and $usage.fiveHourRemainingPercent -eq 33 -and $usage.fiveHourResetsAt) 'The account in Claude Desktop must show, with reset times'

    # Back to the account the CLI's own .claude.json names, also signed in through UTP: it answers through that kept
    # login, and until it does, nothing of the other account shows.
    $ownLogin = Join-Path (Get-ClaudeAccountsDirectory) $cliAccount
    [void](New-Item -ItemType Directory -Path $ownLogin -Force)
    ('{"oauthAccount":{"accountUuid":"' + $cliAccount + '"}}') | Set-Content -LiteralPath (Join-Path $ownLogin '.claude.json') -Encoding UTF8
    $revisionDesktop = Get-UtpCredentialRevision 'claude'
    Write-DesktopData $current @(New-Sample 5 40 18) $cliAccount
    Check ((Get-UtpCredentialRevision 'claude') -ne $revisionDesktop) 'A switch in Claude Desktop must make the collector ask again at once'
    $usage = Get-ClaudeUsageSnapshot
    Check ([bool]$usage.pending -and $null -eq $usage.fiveHourRemainingPercent -and (Get-ProviderStatusMessage -Source 'claude') -eq 'Claude - Switching accounts' -and (Get-TaskbarBadgeData -Source 'claude').StatusText -eq 'Switching accounts') 'A switch must not show the previous account'
    Test-QuickViewStatusFits
    $script:Answer = 'timeout'
    [void](Update-ClaudeControlUsage)
    Check ($script:Asked[-1] -eq $ownLogin -and $null -eq (Get-ClaudeUsageSnapshot).fiveHourRemainingPercent) 'Cached values of another account must never fill in'
    $script:Answer = 'own'
    [void](Update-ClaudeControlUsage)
    Check ($script:Asked[-1] -eq $ownLogin -and (Get-ClaudeUsageSnapshot).fiveHourRemainingPercent -eq 33) 'Next to other kept logins, the CLI''s own account must answer through its kept login'

    # Forget that login. Claude Desktop's sessions also write their account into the CLI's shared .claude.json, so
    # next to the login still kept for the other account, that file no longer proves whose credentials the CLI's
    # own login holds: UTP asks for a sign-in instead of showing what may be another account's usage.
    Remove-Item -LiteralPath $ownLogin -Recurse -Force
    $asksBefore = $script:Asked.Count
    [void](Update-ClaudeControlUsage)
    $usage = Get-ClaudeUsageSnapshot
    Check ($script:Asked.Count -eq $asksBefore -and $usage.errorCode -eq 'account_sign_in_required' -and $null -eq $usage.fiveHourRemainingPercent) 'Next to kept logins, the CLI''s own login must never answer'

    # Without kept logins, the CLI's own login answers for the account its .claude.json names.
    Remove-Item -LiteralPath $accountLogin -Recurse -Force
    [void](Update-ClaudeControlUsage)
    Check ($script:Asked[-1] -eq '' -and (Get-ClaudeUsageSnapshot).fiveHourRemainingPercent -eq 61) 'Without kept logins the CLI''s own account must answer through its own login'
    Write-CliUsage
    Check ((Get-ClaudeUsageSnapshot).fiveHourRemainingPercent -eq 61) 'A cache from before accounts were tracked must still show'

    # Claude Desktop's own history still fills in for the statusline source: freshness and account switches.
    $script:State.settings.claudeControlEnabled = $false
    Reset-ClaudeCaches
    Write-DesktopData $current @(New-Sample 18 25 30) $desktopAccount
    Check ((Get-ClaudeUsageSnapshot).fiveHourRemainingPercent -eq 75) 'A recent Claude Desktop sample must not blink to unknown'
    Reset-ClaudeCaches
    Write-DesktopData $current @(New-Sample 40 25 30) $desktopAccount
    Check ($null -eq (Get-ClaudeDesktopUsageSnapshot)) 'An old Claude Desktop sample must not show'
    Reset-ClaudeCaches
    Write-DesktopData $current @(New-Sample 5 40 18) $desktopAccount
    $usage = Get-ClaudeUsageSnapshot
    Check ($usage.source -eq 'claude-desktop-plan-history' -and $usage.fiveHourRemainingPercent -eq 60) 'Without statusline data the current Desktop folder must be used'
    $thirdAccount = '33333333-3333-4333-8333-333333333333'
    Write-DesktopData $current @(New-Sample 5 40 18) $thirdAccount
    $usage = Get-ClaudeUsageSnapshot
    Check ($usage.source -eq 'claude-desktop-plan-history' -and [bool]$usage.pending -and $null -eq $usage.fiveHourRemainingPercent) 'Right after a switch the old account must not show'
    Check ((Get-ProviderStatusMessage -Source 'claude') -eq 'Claude - Waiting for Claude Desktop' -and (Get-TaskbarBadgeData -Source 'claude').StatusText -eq 'Waiting for Claude Desktop') 'The wait must be explained'
    Test-QuickViewStatusFits
    Write-DesktopData $current @((New-Sample 5 40 18), (New-Sample -1 12 9)) $thirdAccount
    Check ((Get-ClaudeUsageSnapshot).fiveHourRemainingPercent -eq 88) 'The first sample of the new account must show'
    Write-Output 'Claude Desktop account tests OK (discovery, which login answers, logins per account, switch, no cross-account cache, statusline fallback)'
}
finally {
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
    $resolved = [IO.Path]::GetFullPath($root)
    if ($resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'UtpClaudeDesktop-*') { Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue }
}
