<#
Swaps a staged UTP update into place after UTP has exited, then starts the new version.
Started hidden by UTP from the update work folder; never run against a source checkout.
On any failure the previous installation is put back and started again.
#>
param(
    [Parameter(Mandatory = $true)][string]$InstallRoot,
    [Parameter(Mandatory = $true)][string]$StagedRoot,
    [int]$WaitProcessId = 0,
    [string]$PreviousVersion = 'previous',
    [string]$NewVersion = '',
    [string]$LogPath = '',
    [scriptblock]$Launch = $null
)

$ErrorActionPreference = 'Stop'

function Write-UpdateLog {
    param([string]$Message)
    if ([string]::IsNullOrWhiteSpace($LogPath)) { return }
    try { Add-Content -LiteralPath $LogPath -Value ("{0} {1}" -f (Get-Date).ToString('o'), $Message) -Encoding UTF8 } catch { }
}

function Start-Installation {
    param([string]$Root)
    if ($null -ne $Launch) { & $Launch $Root; return }
    $wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
    Start-Process -FilePath $wscript -ArgumentList ('"' + (Join-Path $Root 'src\Launch-UsageTrayPill.vbs') + '"') -WorkingDirectory (Split-Path $Root -Parent)
}

function Wait-InstallationProcesses {
    param([string]$Root)
    if ($WaitProcessId -gt 0) {
        $owner = Get-Process -Id $WaitProcessId -ErrorAction SilentlyContinue
        if ($null -ne $owner -and -not $owner.WaitForExit(30000)) { throw 'UTP did not exit in time.' }
    }
    # The collector stops by itself once UTP has gone; give it a moment and verify.
    $pattern = [regex]::Escape((Join-Path $Root 'src\'))
    $deadline = (Get-Date).AddSeconds(20)
    do {
        $remaining = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { [string]$_.CommandLine -match $pattern })
        if ($remaining.Count -eq 0) { return }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)
    throw 'A UTP process is still running from the installation folder.'
}

function Move-WithRetry {
    param([string]$Source, [string]$Destination)
    for ($attempt = 1; $attempt -le 20; $attempt++) {
        try { [IO.Directory]::Move($Source, $Destination); return }
        catch { if ($attempt -eq 20) { throw }; Start-Sleep -Milliseconds 250 }
    }
}

$backup = $null
$swapped = $false
try {
    $InstallRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
    $StagedRoot = [IO.Path]::GetFullPath($StagedRoot).TrimEnd('\')
    if (Test-Path -LiteralPath (Join-Path $InstallRoot '.git')) { throw 'Refusing to replace a source checkout.' }
    foreach ($required in @('Start-UsageTrayPill.cmd', 'src\Start-UsageTrayPill.ps1', 'src\Launch-UsageTrayPill.vbs')) {
        if (-not (Test-Path -LiteralPath (Join-Path $StagedRoot $required))) { throw "The staged update is incomplete ($required)." }
    }
    Write-UpdateLog "Updating $PreviousVersion -> $NewVersion"
    Wait-InstallationProcesses -Root $InstallRoot

    $safeVersion = ($PreviousVersion -replace '[^0-9A-Za-z.\-]', '')
    $backup = "$InstallRoot.previous-$safeVersion"
    if (Test-Path -LiteralPath $backup) { $backup = "$backup-" + (Get-Date).ToString('yyyyMMddHHmmss') }
    Move-WithRetry -Source $InstallRoot -Destination $backup
    try {
        Move-WithRetry -Source $StagedRoot -Destination $InstallRoot
        $swapped = $true
    }
    catch {
        Move-WithRetry -Source $backup -Destination $InstallRoot
        $backup = $null
        throw
    }
    try {
        Set-Content -LiteralPath (Join-Path $backup '.utp-backup') -Value $PreviousVersion -Encoding ASCII
        # Keep one backup made by the updater; older updater backups are removed.
        $parent = Split-Path $InstallRoot -Parent
        $leaf = Split-Path $InstallRoot -Leaf
        foreach ($old in @(Get-ChildItem -LiteralPath $parent -Directory -Filter "$leaf.previous-*" -ErrorAction SilentlyContinue)) {
            if ($old.FullName -eq $backup) { continue }
            if (Test-Path -LiteralPath (Join-Path $old.FullName '.utp-backup')) { Remove-Item -LiteralPath $old.FullName -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    catch { Write-UpdateLog ("Backup housekeeping skipped: " + $_.Exception.Message) }
    Write-UpdateLog "Installed $NewVersion; previous version kept in $backup"
    Start-Installation -Root $InstallRoot
}
catch {
    Write-UpdateLog ("Update failed: " + $_.Exception.Message)
    if (-not $swapped -and (Test-Path -LiteralPath (Join-Path $InstallRoot 'src\Launch-UsageTrayPill.vbs'))) {
        Start-Installation -Root $InstallRoot
    }
    exit 1
}
finally {
    # The work folder holds the download and this script; remove it once the swap is done.
    $work = Split-Path $StagedRoot -Parent
    if ((Split-Path $work -Leaf) -like '.utp-update-*') {
        [Environment]::CurrentDirectory = [IO.Path]::GetTempPath()
        Set-Location -LiteralPath ([IO.Path]::GetTempPath())
        Start-Sleep -Milliseconds 200
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
