$sourceRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
$ErrorActionPreference = 'Stop'
. (Join-Path $sourceRoot 'Start-UsageTrayPill.ps1') -LibraryOnly
function Check { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }

# No real balloon, sign-in window, overview or provider request: every side effect is recorded instead.
$script:Balloons = New-Object System.Collections.ArrayList
$script:NotifyIcon = [pscustomobject]@{}
$script:NotifyIcon | Add-Member -MemberType ScriptMethod -Name ShowBalloonTip -Value { param($Timeout, $Title, $Text, $Icon) [void]$script:Balloons.Add("$Title|$Text") }
$script:TestCode = ''
function Get-ProviderAttentionCode { param([string]$Source) if ($Source -eq 'claude') { return $script:TestCode } return '' }
$script:TestCli = 'C:\fixture\claude.exe'
function Resolve-UtpClaudeUsageCli { return $script:TestCli }
$script:Started = New-Object System.Collections.ArrayList
function Start-ClaudeSignInProcess {
    param([string]$FilePath)
    [void]$script:Started.Add($FilePath)
    $process = [pscustomobject]@{ HasExited = $false; Disposed = $false }
    $process | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.Disposed = $true }
    $script:LastProcess = $process
    return $process
}
$script:Refreshes = New-Object System.Collections.ArrayList
function Start-ProviderUsageRefresh { param([string]$Source) [void]$script:Refreshes.Add($Source) }
$script:Overviews = 0
function Show-MainWindow { $script:Overviews++ }
function Close-QuickPanel { }
# Claude's answers come from a disposable cache file and fixed pill items.
$cacheRoot = Join-Path ([IO.Path]::GetTempPath()) ('UtpClaudeSignIn-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $cacheRoot)
$script:ClaudeControlUsagePath = Join-Path $cacheRoot 'claude-control-usage.json'
function Write-ClaudeAnswer { param([DateTime]$At) @{ lastCheckedAt = $At.ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $script:ClaudeControlUsagePath -Encoding UTF8 }
$script:TestItems = @()
function Get-TaskbarBadgeData { param([string]$Source, [switch]$AllWindows) [pscustomobject]@{ Items = $script:TestItems } }
try {

# The sign-in window: Claude's own browser sign-in for a subscription, in a console of its own.
$info = New-ClaudeSignInStartInfo -FilePath 'C:\fixture\claude.exe'
Check ($info.FileName -eq 'C:\fixture\claude.exe' -and $info.Arguments -eq 'auth login --claudeai' -and $info.UseShellExecute) 'The sign-in must run Claude''s own login in a window of its own'

# One balloon per sign-in problem, and only for problems a sign-in fixes.
Update-ClaudeSignInPrompt
Check ($script:Balloons.Count -eq 0) 'A working Claude source must not prompt'
$script:TestCode = 'setup_required'
Update-ClaudeSignInPrompt
Check ($script:Balloons.Count -eq 0) 'A missing or old CLI is not fixed by signing in'
$script:TestCode = 'unsupported_auth_context'
Update-ClaudeSignInPrompt
Update-ClaudeSignInPrompt
Check ($script:Balloons.Count -eq 1 -and $script:Balloons[0] -like 'Claude needs a new sign-in|*' -and $script:NotificationAction -eq 'claude-sign-in') 'A sign-in problem must prompt once, with a click that signs in'

# A click starts the sign-in once; the prompt stays quiet while the window is open.
Invoke-UtpNotificationAction
Check ($script:Started.Count -eq 1 -and $script:Started[0] -eq $script:TestCli -and $script:NotificationAction -eq '') 'Clicking the balloon must start the sign-in once'
Invoke-UtpNotificationAction
Check ([bool](Start-ClaudeSignIn) -and $script:Started.Count -eq 1) 'An open sign-in window must not get a second one'
$script:ClaudeSignInPrompted = $false
Update-ClaudeSignInPrompt
Check ($script:Balloons.Count -eq 1) 'No new balloon while the sign-in window is open'

# Closing the window asks Claude again right away.
Complete-ClaudeSignIn
Check ($script:Refreshes.Count -eq 0 -and $null -ne $script:ClaudeSignInProcess) 'Nothing may happen while the sign-in window is open'
$script:LastProcess.HasExited = $true
Complete-ClaudeSignIn
Check ($null -eq $script:ClaudeSignInProcess -and $script:LastProcess.Disposed -and ($script:Refreshes -join ',') -eq 'claude') 'A closed sign-in window must trigger a Claude refresh'

# The first answer after the window closed decides the message; older answers do not count.
Write-ClaudeAnswer (Get-Date).AddMinutes(-5)
$script:TestCode = ''
Update-ClaudeSignInResult
Check ($script:Balloons.Count -eq 1 -and $null -ne $script:ClaudeSignInResultSince) 'An answer from before the sign-in must not be reported'
Update-ClaudeSignInPrompt
Check ($script:Balloons.Count -eq 1) 'No sign-in prompt while the result is still coming'
Write-ClaudeAnswer (Get-Date).AddSeconds(5)
$script:TestItems = @([pscustomobject]@{ Label = '5h'; Text = '78%' }, [pscustomobject]@{ Label = 'weekly'; Text = '96%' })
Update-ClaudeSignInResult
Check ($script:Balloons[-1] -eq 'Signed in to Claude|Your Claude usage is back: 5-hour 78% left, weekly 96% left.' -and $null -eq $script:ClaudeSignInResultSince -and $script:NotificationAction -eq '') 'A successful sign-in must say so, with the usage that is back'
Update-ClaudeSignInResult
Check ($script:Balloons.Count -eq 2) 'The result must be reported once'
# Still signed out after the window closed: offer another try.
$script:ClaudeSignInResultSince = (Get-Date).AddSeconds(-1)
Write-ClaudeAnswer (Get-Date).AddSeconds(5)
$script:TestCode = 'unsupported_auth_context'
Update-ClaudeSignInResult
Check ($script:Balloons[-1] -like 'Claude sign-in did not finish|*' -and $script:NotificationAction -eq 'claude-sign-in') 'A sign-in that did not finish must offer another try'
# No answer within two minutes: stay quiet.
$script:ClaudeSignInResultSince = (Get-Date).AddMinutes(-3)
Write-ClaudeAnswer (Get-Date).AddMinutes(-4)
Update-ClaudeSignInResult
Check ($script:Balloons.Count -eq 3 -and $null -eq $script:ClaudeSignInResultSince) 'Without an answer the wait must end quietly'

# After Claude worked again, a later problem prompts again; other balloons do not sign in.
$script:TestCode = ''
Update-ClaudeSignInPrompt
$script:TestCode = 'auth_required'
Update-ClaudeSignInPrompt
Check ($script:Balloons.Count -eq 4) 'A new sign-in problem after a working period must prompt again'
Send-UtpNotification -Title 'ChatGPT 5-hour limit' -Text 'Only 8% left.'
Invoke-UtpNotificationAction
Check ($script:Started.Count -eq 1) 'A click on another balloon must not start a sign-in'

# The quick view: a sign-in problem signs in, anything else opens the overview.
Invoke-QuickPanelAction -Action 'setup:claude'
Check ($script:Started.Count -eq 2) 'Sign-in required in the quick view must start the sign-in'
$script:LastProcess.HasExited = $true
Complete-ClaudeSignIn
$script:TestCode = 'setup_required'
Invoke-QuickPanelAction -Action 'setup:claude'
Check ($script:Started.Count -eq 2 -and $script:Overviews -eq 1) 'Setup problems must open the overview instead'
$script:TestCode = 'auth_required'
$script:TestCli = ''
Check (-not (Start-ClaudeSignIn) -and $script:Overviews -eq 2) 'Without a Claude CLI the overview must explain what to install'
Write-Output 'Claude sign-in tests OK (window, one prompt per problem, click, refresh and result after sign-in, quick view)'
}
finally {
    $resolved = [IO.Path]::GetFullPath($cacheRoot)
    if ($resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'UtpClaudeSignIn-*') { Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue }
}
