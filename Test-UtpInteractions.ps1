param([string]$OutputDirectory = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Start-UsageTrayPill.ps1') -LibraryOnly
Add-Type -WarningAction SilentlyContinue -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
public class UtpTestForm : System.Windows.Forms.Form {
    protected override bool ShowWithoutActivation { get { return true; } }
    public UtpTestForm() { Opacity = 0; ShowInTaskbar = false; }
}
'@
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('UtpInteractions-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testRoot)
$script:DataDir=$testRoot
$script:DataPath=Join-Path $testRoot 'data.json'
$script:CodexUsagePath=Join-Path $testRoot 'codex.json'
$script:ClaudeUsagePath=Join-Path $testRoot 'claude.json'
$script:AntigravityUsagePath=Join-Path $testRoot 'antigravity.json'
$script:OpenCodeGoUsagePath=Join-Path $testRoot 'open-code.json'
$script:QwenUsagePath=Join-Path $testRoot 'qwen.json'
$script:State=New-DefaultState
$script:State.liveUsage.lastCheckedAt=Format-DateForStorage (Get-Date)
$script:State.liveUsage.buckets=@([pscustomobject]@{limitId='codex';limitName='Codex';primaryRemainingPercent=75;primaryWindowDurationMins=300;primaryResetsAt=(Get-Date).AddHours(1).ToString('o');secondaryRemainingPercent=64;secondaryWindowDurationMins=10080;secondaryResetsAt=(Get-Date).AddDays(1).ToString('o')})
$script:State.resets=@([pscustomobject]@{id='fixture-reset';label='Test reset';used=$false;expiresAt=(Get-Date).AddDays(1).ToString('o');notes=''})
function Get-ClaudeDesktopUsageSnapshot { return $null }
function Refresh-Tray {}
function Ensure-ClaudeUsageKeeper {}
function Check { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw $Message } }
function Get-AllControls { param($Root) $Root; foreach ($child in $Root.Controls) { Get-AllControls $child } }

# Build the real window and handlers without showing a second UTP window on the desktop.
$body = (Get-Command Show-MainWindow).ScriptBlock.ToString().Replace('New-Object System.Windows.Forms.Form','New-Object UtpTestForm').Replace('$form.Show()', '$form.ShowInTaskbar=$false; $form.Show()').Replace('$form.Activate()', '')
Set-Item Function:Show-MainWindow -Value ([scriptblock]::Create($body))
$badgeBody=(Get-Command Ensure-TaskbarBadge).ScriptBlock.ToString().Replace('$badge = New-Object UtpPillForm', '$badge = New-Object UtpPillForm; $badge.PresentEnabled = $false')
Set-Item Function:Ensure-TaskbarBadge -Value ([scriptblock]::Create($badgeBody))
try {
    Show-MainWindow
    $controls=@(Get-AllControls $script:MainForm)
    $tabs=$controls | Where-Object { $_ -is [Windows.Forms.TabControl] } | Select-Object -First 1
    foreach ($size in @((New-Object Drawing.Size 900,620),(New-Object Drawing.Size 1200,800),(New-Object Drawing.Size 960,650))) {
        $script:MainForm.ClientSize=$size
        foreach ($page in $tabs.TabPages) {
            $tabs.SelectedTab=$page
            [Windows.Forms.Application]::DoEvents()
            foreach ($button in @($page.Controls | Where-Object { $_ -is [Windows.Forms.Button] })) {
                Check ($button.Left -ge 0 -and $button.Right -le $page.ClientSize.Width -and $button.Bottom -le $page.ClientSize.Height) 'Tab actions must remain inside resized pages'
            }
        }
    }
    $tabs.SelectedIndex=0
    $script:MainForm.Size=$script:MainForm.MinimumSize
    foreach ($page in $tabs.TabPages) {
        $tabs.SelectedTab=$page
        [Windows.Forms.Application]::DoEvents()
        foreach ($button in @($page.Controls | Where-Object { $_ -is [Windows.Forms.Button] })) {
            if ($page.AutoScroll) { $page.ScrollControlIntoView($button) }
            Check ($button.Top -ge 0 -and $button.Bottom -le $page.ClientSize.Height -and $button.Right -le $page.ClientSize.Width) 'Actions must remain reachable at the real outer minimum window size'
        }
    }
    $script:MainForm.ClientSize=New-Object Drawing.Size 960,650
    $tabs.SelectedIndex=0
    $script:MainWindowControls.Plan.Text='Changed plan'
    $save=$controls | Where-Object {$_ -is [Windows.Forms.Button] -and $_.Text -match '^Save'} | Select-Object -First 1
    Check ($null -ne $save) 'Plan save button exists'
    # Invoke OnClick because PerformClick ignores buttons in a hidden form.
    $click=[Windows.Forms.Control].GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic')
    $click.Invoke($save,@([EventArgs]::Empty)) | Out-Null
    Check ($script:State.planName -eq 'Changed plan') 'Post-return plan save handler must retain its text box'
    [void]$script:MainWindowControls.Resets.Handle
    $script:MainWindowControls.Resets.Items[0].Selected=$true
    & $script:RefreshMainWindow
    Check ($script:MainWindowControls.Resets.Items[0].Selected) 'Background refresh must preserve the selected reset'

    # A delayed synthetic provider exercises the real process lifecycle with no provider requests.
    $workerPath=Join-Path $testRoot 'worker.ps1'
    $workerCode=@'
param([string]$OutputPath)
Start-Sleep -Milliseconds 600
@{source='codex-app-server';lastCheckedAt=(Get-Date).ToString('o');lastError='';buckets=@()} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath
'@
    [IO.File]::WriteAllText($workerPath,$workerCode)
    function New-CollectorStartInfo {
        param([string]$Source)
        $info=New-Object Diagnostics.ProcessStartInfo
        $info.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $info.Arguments="-NoProfile -ExecutionPolicy Bypass -File `"$workerPath`" -OutputPath `"$script:CodexUsagePath`""
        $info.UseShellExecute=$false; $info.CreateNoWindow=$true
        return $info
    }
    $watch=[Diagnostics.Stopwatch]::StartNew()
    Start-ProviderUsageRefresh -Source codex
    Check ($watch.ElapsedMilliseconds -lt 500) 'Starting a provider must return without waiting for its response'
    $workerId=$script:CollectorProcess.Id
    Start-ProviderUsageRefresh -Source codex
    Check ($script:CollectorProcess.Id -eq $workerId) 'Repeated refresh reuses the in-flight worker'
    & $script:RefreshMainWindow
    $refresh=$controls | Where-Object {$_ -is [Windows.Forms.Button] -and $_.Text -eq 'Refreshing...'} | Select-Object -First 1
    Check ($null -ne $refresh -and -not $refresh.Enabled) 'Refresh button reflects an in-flight provider'
    $ticks=0
    while ($script:ProviderRefreshes.Count -gt 0 -and $watch.ElapsedMilliseconds -lt 8000) {
        [Windows.Forms.Application]::DoEvents()
        $ticks++
        Update-ProviderRefreshProcessState
        Start-Sleep -Milliseconds 20
    }
    Check ($script:ProviderRefreshes.Count -eq 0 -and $ticks -gt 5) 'UI message pump must continue while polling and worker must complete'
    Check ($script:State.planName -eq 'Changed plan') 'Worker completion must not overwrite user settings'
    Check ($refresh.Text -eq 'Refresh now' -and $refresh.Enabled) 'Refresh button recovers after completion'
    Check ($script:State.liveUsage.buckets.Count -eq 0) 'Fresh worker cache is imported immediately'

    $script:State.settings.qwenTokenPlanEnabled=$true
    @{available=$false;stale=$false;lastError='auth_expired';items=@()} | ConvertTo-Json | Set-Content $script:QwenUsagePath
    Check ((Get-ProviderStatusMessage qwen) -match 'Session expired.*Set up') 'Expired sessions explain how to reconnect'
    Ensure-TaskbarBadge
    $script:BadgeForm.Show()
    Set-TaskbarBadgeContent -Source qwen
    Check ($null -eq $script:BadgeToolTip -and $script:BadgeForm.AccessibleName -match 'Session expired') 'Pill has no hover popup but retains accessible status'
    $script:State.settings.taskbarBadgeDefaultSource='codex'
    $script:BadgeDisplayedSource='codex'
    $left=New-Object Windows.Forms.MouseEventArgs ([Windows.Forms.MouseButtons]::Left),1,1,1,0
    Invoke-TaskbarBadgeMouseUp -EventArgs $left
    Invoke-TaskbarBadgeMouseUp -EventArgs $left
    Invoke-TaskbarBadgeMouseUp -EventArgs $left
    $deadline=(Get-Date).AddSeconds(3)
    while ($script:BadgeAnimating -and (Get-Date) -lt $deadline) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10 }
    Check ($script:BadgeDisplayedSource -eq 'qwen' -and -not $script:BadgeAnimating) 'Rapid clicks finish at the latest selected provider'
    Check ($script:BadgeCurrentRow.Top -eq 0) 'Animation ends with text aligned in the pill'
    & $script:RefreshMainWindow
    Check ($script:UsageProviderRows.qwen.Groups[0].Value.Text -eq '--' -and $script:UsageProviderRows.qwen.Groups[0].Fill.Width -eq 0) 'Expired sessions must show neither invented numbers nor a filled meter'
    @{available=$true;stale=$false;lastError='';lastCheckedAt=(Get-Date).ToString('o');lastSuccessAt=(Get-Date).ToString('o');items=@(@{key='five_hour';remainingPercent=88;resetsAt=(Get-Date).AddHours(2).ToString('o')})} | ConvertTo-Json -Depth 5 | Set-Content $script:OpenCodeGoUsagePath
    & $script:RefreshMainWindow
    Check ($script:UsageProviderRows.opencodego.Groups[0].Value.Text -eq '--') 'Disabled providers must not display old cached quotas'

    if (-not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
        [void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
        # Deterministic visual fixtures, written only to the isolated test directory.
        $script:State.planName='Demo workspace'
        $script:State.resets=@()
        $script:State.liveUsage.lastCheckedAt=(Get-Date).ToString('o')
        $script:State.liveUsage.buckets=@([pscustomobject]@{limitId='codex';primaryRemainingPercent=82;primaryWindowDurationMins=300;primaryResetsAt=(Get-Date).AddHours(2).ToString('o');secondaryRemainingPercent=64;secondaryWindowDurationMins=10080;secondaryResetsAt=(Get-Date).AddDays(2).ToString('o')})
        $script:State.settings.openCodeGoEnabled=$true
        $script:State.settings.qwenTokenPlanEnabled=$false
        @{lastCheckedAt=(Get-Date).ToString('o');lastError='';fiveHourRemainingPercent=91;sevenDayRemainingPercent=48;fiveHourResetsAt=(Get-Date).AddHours(3).ToString('o');sevenDayResetsAt=(Get-Date).AddDays(2).ToString('o');limits=@()} | ConvertTo-Json | Set-Content $script:ClaudeUsagePath
        $script:MainForm.ClientSize=New-Object Drawing.Size 1040,760
        & $script:RefreshMainWindow
        Set-TaskbarBadgeContent -Source codex
        foreach ($entry in @(@{Name='overview';Form=$script:MainForm},@{Name='pill';Form=$script:BadgeForm})) {
            $bitmap=if($entry.Name -eq 'pill'){New-TaskbarBadgeBitmap}else{New-Object Drawing.Bitmap $entry.Form.Width,$entry.Form.Height}
            try { if($entry.Name -ne 'pill'){$entry.Form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle 0,0,$bitmap.Width,$bitmap.Height))}; $bitmap.Save((Join-Path $OutputDirectory ($entry.Name+'.png'))) } finally { $bitmap.Dispose() }
        }
        $tabs.SelectedTab=$tabs.TabPages | Where-Object Text -eq 'Preferences'
        [Windows.Forms.Application]::DoEvents()
        $bitmap=New-Object Drawing.Bitmap $script:MainForm.Width,$script:MainForm.Height
        try { $script:MainForm.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle 0,0,$bitmap.Width,$bitmap.Height)); $bitmap.Save((Join-Path $OutputDirectory 'preferences.png')) } finally { $bitmap.Dispose() }
        # Render the production pill at 200% DPI on an editorial comparison board.
        # No screenshot, account cache, or provider request is used for these pixels.
        $board=New-Object Drawing.Bitmap 1200,480
        $graphics=[Drawing.Graphics]::FromImage($board)
        $heading=New-Object Drawing.Font 'Segoe UI',28,([Drawing.FontStyle]::Bold),([Drawing.GraphicsUnit]::Pixel)
        $caption=New-Object Drawing.Font 'Segoe UI',18,([Drawing.FontStyle]::Regular),([Drawing.GraphicsUnit]::Pixel)
        $ink=New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(20,32,52))
        try {
            $graphics.Clear([Drawing.Color]::FromArgb(241,244,248))
            $graphics.FillRectangle([Drawing.Brushes]::Black,600,0,600,480)
            $script:BadgeDpiScale=2.0
            foreach($theme in @('Light','Dark')) {
                Dispose-TaskbarBadge
                $script:BadgeTheme=$theme
                Ensure-TaskbarBadge
                $x=if($theme -eq 'Light'){0}else{600}
                $brush=if($theme -eq 'Light'){$ink}else{[Drawing.Brushes]::White}
                $graphics.DrawString($theme+' theme',$heading,$brush,($x+44),40)
                $y=150
                foreach($source in @('codex','claude')) {
                    Set-TaskbarBadgeContent -Source $source
                    $frame=New-TaskbarBadgeBitmap
                    try {
                        $frame.Save((Join-Path $OutputDirectory ('pill-'+$source+'-'+$theme.ToLowerInvariant()+'.png')))
                        $graphics.DrawImageUnscaled($frame,($x+[int]((600-$frame.Width)/2)),$y)
                    } finally {$frame.Dispose()}
                    $y+=110
                }
                $graphics.DrawString('Actual UTP renderer / illustrative values',$caption,$brush,($x+44),400)
            }
            $board.Save((Join-Path $OutputDirectory 'pill-themes.png'))
        } finally {$graphics.Dispose();$board.Dispose();$heading.Dispose();$caption.Dispose();$ink.Dispose()}
    }
    Write-Output 'Interaction and background refresh tests OK'
} finally {
    Stop-UsageCollection
    Dispose-TaskbarBadge
    if ($null -ne $script:MainForm) { $script:MainForm.Dispose() }
    $resolved=[IO.Path]::GetFullPath($testRoot)
    if ($resolved.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'UtpInteractions-*') { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
