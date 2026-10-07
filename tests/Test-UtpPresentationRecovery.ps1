$sourceRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
$ErrorActionPreference='Stop'
. (Join-Path $sourceRoot 'Start-UsageTrayPill.ps1') -LibraryOnly
function Check {param([bool]$Condition,[string]$Message) if(-not $Condition){throw $Message}}
# Entirely synthetic data; no caches, credentials, processes or provider calls.
function Test-CodexRunning {return $false}
function Test-ClaudeKeeperRunning {return $false}
function Get-ClaudeUsageSnapshot {return $null}
function Get-AntigravityUsageSnapshot {return $null}
function Refresh-Tray {}
function New-BadgeLogoImage {param([int]$Size,[string]$Source,[switch]$DarkSurface) New-Object Drawing.Bitmap $Size,$Size}
$script:FixtureUsage=[pscustomobject]@{available=$true;stale=$false;lastError='';items=@([pscustomobject]@{key='five_hour';remainingPercent=88;resetsAt=(Get-Date).AddHours(1).ToString('o')})}
function Get-QwenUsageSnapshot {return $script:FixtureUsage}
function Get-OpenCodeGoUsageSnapshot {return $script:FixtureUsage}
$body=(Get-Command Show-MainWindow).ScriptBlock.ToString().Replace('$form.Show()','').Replace('$form.Activate()','')
Set-Item Function:Show-MainWindow -Value ([scriptblock]::Create($body))
$script:State=New-DefaultState
try {
    Show-MainWindow
    Check (-not $script:MainForm.Visible) 'The fixture window must stay hidden'
    foreach($enabled in @($false,$true,$false)) {
        $script:State.settings.qwenTokenPlanEnabled=$enabled
        $script:State.settings.openCodeGoEnabled=$enabled
        Update-MainWindow
        foreach($name in @('Qwen Token Plan','OpenCode Go')) {
            $row=@($script:MainWindowControls.Live.Items|Where-Object Text -eq $name)[0]
            if($enabled) {
                Check ($row.SubItems[1].Text -eq '88%') 'Enabling a source must restore its available quota in Details'
                Check ($row.SubItems[7].Text -notmatch 'Preferences') 'Enabled sources must show their collection status'
            } else {
                Check ($row.SubItems[7].Text -match 'Preferences') 'Disabled sources must be marked disabled in Details'
                Check ($row.SubItems[1].Text -eq '-') 'Disabled sources must not present cached quota as active in Details'
            }
        }
    }
} finally {if($null -ne $script:MainForm){$script:MainForm.Dispose()}}
Write-Output 'Presentation recovery tests OK'
