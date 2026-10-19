$ErrorActionPreference = 'Stop'
$sourceRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
. (Join-Path $sourceRoot 'UtpUpdate.ps1')
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Check { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
function Assert-UpdateError {
    param([scriptblock]$Action, [string]$Code, [string]$Message)
    $actual = ''
    try { & $Action | Out-Null }
    catch {
        $actual = if ($_.Exception.Data.Contains('UtpUpdateCode')) { [string]$_.Exception.Data['UtpUpdateCode'] } else { 'unclassified: ' + $_.Exception.Message }
    }
    Check ($actual -eq $Code) "$Message (expected $Code, got '$actual')"
}
function New-TestArchive {
    param([string]$Path, [hashtable]$Entries)
    $zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in $Entries.Keys) {
            $stream = $zip.CreateEntry($name).Open()
            try { $bytes = [Text.Encoding]::UTF8.GetBytes([string]$Entries[$name]); $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
        }
    }
    finally { $zip.Dispose() }
}
function Get-PackageEntries {
    param([string]$Version)
    return @{
        'Start-UsageTrayPill.cmd' = '@echo off'
        'src/Start-UsageTrayPill.ps1' = "# runtime`r`n`$script:AppVersion = `"$Version`"`r`n"
        'src/Launch-UsageTrayPill.vbs' = "' launcher"
        'src/Start-UsageCollector.ps1' = '# collector'
        'assets/app-icon.ico' = 'icon'
        'README.md' = 'readme'
    }
}
function New-Release {
    param([string]$Tag, [long]$ZipId, [long]$SumsId, [string]$ZipName = '', [string]$Digest = '', [bool]$Draft = $false, [bool]$WithSums = $true)
    $version = $Tag -replace '^v', ''
    if (-not $ZipName) { $ZipName = "UsageTrayPill-$version-windows.zip" }
    $assets = @([pscustomobject]@{ id = $ZipId; name = $ZipName; size = 1234; digest = $Digest })
    if ($WithSums) { $assets += [pscustomobject]@{ id = $SumsId; name = 'SHA256SUMS.txt'; size = 90; digest = '' } }
    return [pscustomobject]@{ tag_name = $Tag; name = "Usage Tray Pill $version"; draft = $Draft; prerelease = $true; assets = $assets }
}

$temporaryRoot = (Get-Item -LiteralPath ([IO.Path]::GetTempPath())).FullName
$testRoot = Join-Path $temporaryRoot ('UTP updater test ' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$savedLocation = Get-Location
try {
    # Versions: numeric release-candidate order, final releases after their candidates, strict format.
    $parsed = ConvertTo-UtpVersion 'v0.1.0-rc.8'
    Check ($parsed.Major -eq 0 -and $parsed.Minor -eq 1 -and $parsed.Patch -eq 0 -and $parsed.Candidate -eq 8 -and $parsed.Text -eq '0.1.0-rc.8') 'A tagged release candidate must parse'
    Check ((ConvertTo-UtpVersion '0.1.0').Candidate -eq [int]::MaxValue) 'A final release must sort after its candidates'
    foreach ($invalid in @('', '0.1', '0.1.0-beta.1', '1.2.3-rc.x', 'v1.2.3 ', '1.2.3-rc.1-extra', '../1.2.3')) {
        Check ($null -eq (ConvertTo-UtpVersion $invalid)) "An unsupported version must be rejected: '$invalid'"
    }
    Check ((Compare-UtpVersion '0.1.0-rc.7' '0.1.0-rc.8') -eq -1) 'rc.7 must be older than rc.8'
    Check ((Compare-UtpVersion '0.1.0-rc.10' '0.1.0-rc.9') -eq 1) 'Candidates must compare numerically'
    Check ((Compare-UtpVersion '0.1.0' '0.1.0-rc.99') -eq 1) 'A final release must be newer than any of its candidates'
    Check ((Compare-UtpVersion '0.2.0-rc.1' '0.1.9') -eq 1) 'A newer minor version must win'
    Check ((Compare-UtpVersion 'v1.0.0' '1.0.0') -eq 0) 'A leading v must not change the version'
    Assert-UpdateError { Compare-UtpVersion 'latest' '0.1.0' } 'invalid_version' 'Unreadable versions must fail closed'

    # Release list: drafts, odd tags and incomplete releases are ignored; URLs stay on the API host.
    $upperDigest = 'sha256:' + ('AB' * 32)
    $releases = @(
        (New-Release -Tag 'v0.2.0' -ZipId 1 -SumsId 2 -Draft $true),
        (New-Release -Tag 'nightly' -ZipId 3 -SumsId 4),
        (New-Release -Tag 'v0.1.0-rc.12' -ZipId 5 -SumsId 6 -WithSums $false),
        (New-Release -Tag 'v0.1.0-rc.11' -ZipId 7 -SumsId 8 -ZipName 'UsageTrayPill-0.1.0-rc.10-windows.zip'),
        (New-Release -Tag 'v0.1.0-rc.9' -ZipId 9 -SumsId 10 -Digest $upperDigest),
        (New-Release -Tag 'v0.1.0-rc.8' -ZipId 11 -SumsId 12)
    )
    $candidates = @(Get-UtpReleaseCandidates -Releases $releases)
    Check ($candidates.Count -eq 2) 'Only complete, published releases with a matching ZIP and checksum list may be offered'
    $rc9 = $candidates | Where-Object Version -eq '0.1.0-rc.9'
    Check ($rc9.ZipApiUrl -eq 'https://api.github.com/repos/Novendum/usage-tray-pill/releases/assets/9') 'The ZIP must be read through the API asset URL'
    Check ($rc9.SumsApiUrl -eq 'https://api.github.com/repos/Novendum/usage-tray-pill/releases/assets/10') 'The checksum list must be read through the API asset URL'
    Check ($rc9.ZipDigest -eq ('ab' * 32)) 'The GitHub digest must be normalized to lowercase hex'
    Check ($rc9.Page -eq 'https://github.com/Novendum/usage-tray-pill/releases/tag/v0.1.0-rc.9') 'Release notes must open the project release page'
    Check ((Select-UtpUpdate -Candidates $candidates -CurrentVersion '0.1.0-rc.8').Version -eq '0.1.0-rc.9') 'The newest newer release must be offered'
    Check ($null -eq (Select-UtpUpdate -Candidates $candidates -CurrentVersion '0.1.0-rc.9')) 'The current version must not be offered again'
    Check ($null -eq (Select-UtpUpdate -Candidates $candidates -CurrentVersion '0.1.0')) 'An older candidate must never replace a newer installation'

    # Network destinations: the API host only, plus GitHub's asset hosts for one redirect.
    foreach ($allowed in @('https://release-assets.githubusercontent.com/a?b=c', 'https://objects.githubusercontent.com/x', 'https://github-releases.githubusercontent.com/x')) {
        Check (Test-UtpUpdateRedirectHost $allowed) "GitHub's release-asset host must be accepted: $allowed"
    }
    foreach ($rejected in @('http://release-assets.githubusercontent.com/x', 'https://release-assets.githubusercontent.com.example.net/x', 'https://example.com/x', 'https://objects.githubusercontent.com:8443/x', 'https://api.github.com/x', 'not a url', '')) {
        Check (-not (Test-UtpUpdateRedirectHost $rejected)) "A foreign redirect must be rejected: '$rejected'"
    }
    $script:UtpUpdateHttpGet = $null
    Assert-UpdateError { Invoke-UtpUpdateHttpGet -Url 'https://example.com/releases' -Accept 'application/json' -MaximumBytes 10 } 'destination_rejected' 'Only api.github.com may be contacted first'
    Assert-UpdateError { Invoke-UtpUpdateHttpGet -Url 'http://api.github.com/repos' -Accept 'application/json' -MaximumBytes 10 } 'destination_rejected' 'Plain HTTP must be refused'

    # Checksum list: exact file name, optional binary marker, CRLF and uppercase hex.
    $hash = 'C0FFEE' * 10 + 'C0FE'
    $sums = "$('1' * 64)  UsageTrayPill-0.1.0-rc.9-windows.zip.sig`r`n$hash *UsageTrayPill-0.1.0-rc.9-windows.zip`r`n"
    Check ((Get-UtpReleaseChecksum -Text $sums -FileName 'UsageTrayPill-0.1.0-rc.9-windows.zip') -eq $hash.ToLowerInvariant()) 'The checksum for the exact file name must be found'
    Assert-UpdateError { Get-UtpReleaseChecksum -Text $sums -FileName 'usagetraypill-0.1.0-rc.9-windows.zip' } 'checksum_missing' 'File names must match exactly'
    Assert-UpdateError { Get-UtpReleaseChecksum -Text 'garbage' -FileName 'UsageTrayPill-0.1.0-rc.9-windows.zip' } 'checksum_missing' 'A missing checksum must fail closed'

    # Archives: complete packages extract; unsafe paths, gaps and version mismatches never land.
    $validZip = Join-Path $testRoot 'valid.zip'
    New-TestArchive -Path $validZip -Entries (Get-PackageEntries '0.1.0-rc.9')
    $destination = Join-Path $testRoot 'extract-valid'
    Expand-UtpUpdateArchive -ArchivePath $validZip -Destination $destination -ExpectedVersion '0.1.0-rc.9'
    Check (Test-Path -LiteralPath (Join-Path $destination 'src\Start-UsageCollector.ps1')) 'A valid package must extract completely'
    $unsafeCases = @(
        @{ Name = 'parent'; Extra = @{ '../escaped.txt' = 'x' } },
        @{ Name = 'backslash-parent'; Extra = @{ 'src\..\..\escaped.txt' = 'x' } },
        @{ Name = 'rooted'; Extra = @{ '/escaped.txt' = 'x' } },
        @{ Name = 'drive'; Extra = @{ 'C:/escaped.txt' = 'x' } }
    )
    foreach ($case in $unsafeCases) {
        $entries = Get-PackageEntries '0.1.0-rc.9'
        foreach ($key in $case.Extra.Keys) { $entries[$key] = $case.Extra[$key] }
        $zipPath = Join-Path $testRoot "unsafe-$($case.Name).zip"
        New-TestArchive -Path $zipPath -Entries $entries
        $target = Join-Path $testRoot "extract-$($case.Name)"
        Assert-UpdateError { Expand-UtpUpdateArchive -ArchivePath $zipPath -Destination $target -ExpectedVersion '0.1.0-rc.9' } 'archive_rejected' "An unsafe entry must be rejected ($($case.Name))"
        Check (-not (Test-Path -LiteralPath $target)) "Nothing may be written before the archive is validated ($($case.Name))"
    }
    Check (-not (Test-Path -LiteralPath (Join-Path $testRoot 'escaped.txt'))) 'No file may escape the staging folder'
    $incomplete = Get-PackageEntries '0.1.0-rc.9'
    $incomplete.Remove('src/Start-UsageCollector.ps1')
    $incompleteZip = Join-Path $testRoot 'incomplete.zip'
    New-TestArchive -Path $incompleteZip -Entries $incomplete
    Assert-UpdateError { Expand-UtpUpdateArchive -ArchivePath $incompleteZip -Destination (Join-Path $testRoot 'extract-incomplete') -ExpectedVersion '0.1.0-rc.9' } 'archive_rejected' 'A package without its collector must be rejected'
    $emptyZip = Join-Path $testRoot 'empty.zip'
    New-TestArchive -Path $emptyZip -Entries @{}
    Assert-UpdateError { Expand-UtpUpdateArchive -ArchivePath $emptyZip -Destination (Join-Path $testRoot 'extract-empty') -ExpectedVersion '0.1.0-rc.9' } 'archive_rejected' 'An empty archive must be rejected'
    Assert-UpdateError { Expand-UtpUpdateArchive -ArchivePath $validZip -Destination (Join-Path $testRoot 'extract-version') -ExpectedVersion '0.1.0-rc.10' } 'archive_rejected' 'A package must contain the version its release names'

    # Messages: classified errors are shown as written; anything else stays generic.
    $friendly = try { throw (New-UtpUpdateException 'network_error' 'GitHub could not be reached.') } catch { Get-UtpUpdateExceptionMessage $_ }
    Check ($friendly -eq 'GitHub could not be reached.') 'Classified update errors must keep their message'
    $generic = try { throw 'Internal detail C:\Users\someone\secret' } catch { Get-UtpUpdateExceptionMessage $_ }
    Check ($generic -eq 'The update could not be completed.') 'Unclassified errors must not leak internal details'
    $checkout = Join-Path $testRoot 'checkout'
    [void][IO.Directory]::CreateDirectory((Join-Path $checkout '.git'))
    Check (Test-UtpSourceCheckout $checkout) 'A Git checkout must be recognized'
    Check (-not (Test-UtpSourceCheckout $destination)) 'An extracted package is not a source checkout'

    # Download flow with an offline transport: checksum list first, then the ZIP, staged beside the install.
    $packageBytes = [IO.File]::ReadAllBytes($validZip)
    $packageHash = (Get-FileHash -LiteralPath $validZip -Algorithm SHA256).Hash.ToLowerInvariant()
    $script:FakeResponses = @{}
    $script:Requests = New-Object System.Collections.ArrayList
    $script:UtpUpdateHttpGet = {
        param($Url, $Accept, $MaximumBytes)
        [void]$script:Requests.Add([pscustomobject]@{ Url = $Url; Accept = $Accept; MaximumBytes = $MaximumBytes })
        if (-not $script:FakeResponses.ContainsKey($Url)) { throw "Unexpected request: $Url" }
        return ,([byte[]]$script:FakeResponses[$Url])
    }
    $listUrl = 'https://api.github.com/repos/Novendum/usage-tray-pill/releases?per_page=20'
    $script:FakeResponses[$listUrl] = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @($releases) -Depth 6))
    $offered = Get-UtpAvailableUpdate -CurrentVersion '0.1.0-rc.8'
    Check ($offered.Version -eq '0.1.0-rc.9' -and $script:Requests[0].Url -eq $listUrl) 'The release list must come from the fixed API URL'
    $script:FakeResponses[$listUrl] = [Text.Encoding]::UTF8.GetBytes('<html>not json</html>')
    Assert-UpdateError { Get-UtpAvailableUpdate -CurrentVersion '0.1.0-rc.8' } 'parse_error' 'An unreadable release list must fail closed'

    $installParent = Join-Path $testRoot 'Programs'
    $installRoot = Join-Path $installParent 'Usage Tray Pill'
    [void][IO.Directory]::CreateDirectory($installRoot)
    $update = [pscustomobject]@{
        Version = '0.1.0-rc.9'; ZipName = 'UsageTrayPill-0.1.0-rc.9-windows.zip'; ZipDigest = $packageHash
        ZipApiUrl = 'https://api.github.com/repos/Novendum/usage-tray-pill/releases/assets/9'
        SumsApiUrl = 'https://api.github.com/repos/Novendum/usage-tray-pill/releases/assets/10'
    }
    $script:FakeResponses[$update.SumsApiUrl] = [Text.Encoding]::UTF8.GetBytes("$packageHash  $($update.ZipName)`n")
    $script:FakeResponses[$update.ZipApiUrl] = $packageBytes
    $script:Requests.Clear()
    $staged = Save-UtpUpdate -Update $update -InstallRoot $installRoot
    Check ((Split-Path $staged.WorkDirectory -Parent) -eq $installParent -and (Split-Path $staged.WorkDirectory -Leaf) -like '.utp-update-*') 'Updates must be staged beside the installation (same volume)'
    Check (Test-Path -LiteralPath (Join-Path $staged.StagedRoot 'src\Start-UsageTrayPill.ps1')) 'The staged package must be complete'
    Check ((@($script:Requests | ForEach-Object Url) -join '|') -eq "$($update.SumsApiUrl)|$($update.ZipApiUrl)") 'The checksum list must be read before the ZIP'
    Check ($script:Requests[0].MaximumBytes -eq 65536 -and $script:Requests[1].MaximumBytes -eq 20971520) 'Downloads must be size-limited'
    Remove-Item -LiteralPath $staged.WorkDirectory -Recurse -Force

    $script:Requests.Clear()
    $conflicting = $update.PSObject.Copy()
    $conflicting.ZipDigest = 'ab' * 32
    Assert-UpdateError { Save-UtpUpdate -Update $conflicting -InstallRoot $installRoot } 'checksum_mismatch' 'GitHub and the checksum list must agree'
    Check (@($script:Requests | Where-Object Url -eq $update.ZipApiUrl).Count -eq 0) 'A disagreeing digest must stop before the ZIP is downloaded'
    $script:FakeResponses[$update.SumsApiUrl] = [Text.Encoding]::UTF8.GetBytes("$('0' * 64)  $($update.ZipName)`n")
    $tampered = $update.PSObject.Copy()
    $tampered.ZipDigest = ''
    Assert-UpdateError { Save-UtpUpdate -Update $tampered -InstallRoot $installRoot } 'checksum_mismatch' 'A ZIP that does not match its checksum must be rejected'
    $script:FakeResponses[$update.SumsApiUrl] = [Text.Encoding]::UTF8.GetBytes("$packageHash  another.zip`n")
    Assert-UpdateError { Save-UtpUpdate -Update $update -InstallRoot $installRoot } 'checksum_missing' 'A checksum list without the ZIP must be rejected'
    $script:FakeResponses[$update.SumsApiUrl] = [Text.Encoding]::UTF8.GetBytes("$packageHash  $($update.ZipName)`n")
    $wrongVersion = $update.PSObject.Copy()
    $wrongVersion.Version = '0.1.0-rc.10'
    Assert-UpdateError { Save-UtpUpdate -Update $wrongVersion -InstallRoot $installRoot } 'archive_rejected' 'A package for another version must be rejected'
    Check (@(Get-ChildItem -LiteralPath $installParent -Directory -Force -Filter '.utp-update-*').Count -eq 0) 'Failed downloads must not leave staging folders behind'

    # Swap: in-process with a recorded launch, so no real UTP starts.
    $applier = Join-Path $sourceRoot 'Apply-UtpUpdate.ps1'
    function New-Installation {
        param([string]$Path, [string]$Marker)
        foreach ($folder in @('src', 'assets')) { [void][IO.Directory]::CreateDirectory((Join-Path $Path $folder)) }
        foreach ($file in @('Start-UsageTrayPill.cmd', 'src\Start-UsageTrayPill.ps1', 'src\Launch-UsageTrayPill.vbs')) { [IO.File]::WriteAllText((Join-Path $Path $file), $Marker) }
        [IO.File]::WriteAllText((Join-Path $Path "$Marker.txt"), $Marker)
    }
    function New-StagedUpdate {
        param([string]$Marker)
        $work = Join-Path $installParent ('.utp-update-' + [guid]::NewGuid().ToString('N'))
        New-Installation -Path (Join-Path $work 'app') -Marker $Marker
        return (Join-Path $work 'app')
    }
    # The applier runs in its own script scope, so the recorder appends to a shared list.
    $launched = New-Object System.Collections.ArrayList
    $launch = { param($Root) [void]$launched.Add($Root) }
    $log = Join-Path $testRoot 'update.log'
    Remove-Item -LiteralPath $installRoot -Recurse -Force
    New-Installation -Path $installRoot -Marker 'old'
    $manualBackup = "$installRoot.previous-3e93d66"
    New-Installation -Path $manualBackup -Marker 'manual'

    $waitFor = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\PING.EXE') -ArgumentList '-n', '2', '127.0.0.1' -WindowStyle Hidden -PassThru
    $stagedRoot = New-StagedUpdate -Marker 'rc9'
    $global:LASTEXITCODE = 0
    & $applier -InstallRoot $installRoot -StagedRoot $stagedRoot -WaitProcessId $waitFor.Id -PreviousVersion '0.1.0-rc.8' -NewVersion '0.1.0-rc.9' -LogPath $log -Launch $launch
    Check ($LASTEXITCODE -eq 0) 'A valid swap must succeed'
    Check ($waitFor.HasExited) 'The swap must wait for the running UTP process'
    Check ((Test-Path -LiteralPath (Join-Path $installRoot 'rc9.txt')) -and -not (Test-Path -LiteralPath (Join-Path $installRoot 'old.txt'))) 'The new version must replace the installation'
    $firstBackup = "$installRoot.previous-0.1.0-rc.8"
    Check ((Test-Path -LiteralPath (Join-Path $firstBackup 'old.txt')) -and (Test-Path -LiteralPath (Join-Path $firstBackup '.utp-backup'))) 'The previous version must be kept as a marked backup'
    Check (-not (Test-Path -LiteralPath (Split-Path $stagedRoot -Parent))) 'The work folder must be removed after the swap'
    Check ($launched.Count -eq 1 -and $launched[0] -eq $installRoot) 'The updated installation must be started once'
    Check ((Get-Content -LiteralPath $log -Raw) -match 'Installed 0\.1\.0-rc\.9') 'The swap must be logged'
    Set-Location -LiteralPath $savedLocation

    $launched.Clear()
    $stagedRoot = New-StagedUpdate -Marker 'rc10'
    & $applier -InstallRoot $installRoot -StagedRoot $stagedRoot -PreviousVersion '0.1.0-rc.9' -NewVersion '0.1.0-rc.10' -LogPath $log -Launch $launch
    Check (Test-Path -LiteralPath (Join-Path $installRoot 'rc10.txt')) 'A second update must apply'
    Check ((Test-Path -LiteralPath "$installRoot.previous-0.1.0-rc.9") -and -not (Test-Path -LiteralPath $firstBackup)) 'Only the newest updater backup may be kept'
    Check (Test-Path -LiteralPath (Join-Path $manualBackup 'manual.txt')) 'A backup the user made by hand must never be removed'
    Set-Location -LiteralPath $savedLocation

    # Failures restart the current version and leave it untouched.
    $launched.Clear()
    $stagedRoot = New-StagedUpdate -Marker 'broken'
    Remove-Item -LiteralPath (Join-Path $stagedRoot 'src\Launch-UsageTrayPill.vbs')
    $global:LASTEXITCODE = 0
    & $applier -InstallRoot $installRoot -StagedRoot $stagedRoot -PreviousVersion '0.1.0-rc.10' -NewVersion '0.1.0-rc.11' -LogPath $log -Launch $launch
    Check ($LASTEXITCODE -eq 1) 'An incomplete update must fail'
    Check ((Test-Path -LiteralPath (Join-Path $installRoot 'rc10.txt')) -and -not (Test-Path -LiteralPath "$installRoot.previous-0.1.0-rc.10")) 'An incomplete update must not touch the installation'
    Check ($launched.Count -eq 1 -and $launched[0] -eq $installRoot) 'The current version must be started again after a refused update'
    Check (-not (Test-Path -LiteralPath (Split-Path $stagedRoot -Parent))) 'A refused update must clean its work folder'
    Set-Location -LiteralPath $savedLocation

    $launched.Clear()
    [void][IO.Directory]::CreateDirectory((Join-Path $installRoot '.git'))
    $stagedRoot = New-StagedUpdate -Marker 'checkout'
    $global:LASTEXITCODE = 0
    & $applier -InstallRoot $installRoot -StagedRoot $stagedRoot -PreviousVersion '0.1.0-rc.10' -NewVersion '0.1.0-rc.11' -LogPath $log -Launch $launch
    Check ($LASTEXITCODE -eq 1 -and (Test-Path -LiteralPath (Join-Path $installRoot 'rc10.txt'))) 'A source checkout must never be replaced'
    Remove-Item -LiteralPath (Join-Path $installRoot '.git') -Recurse -Force
    Set-Location -LiteralPath $savedLocation

    # Rollback: when the new folder cannot be moved in, the previous installation goes back in place.
    $launched.Clear()
    $stagedRoot = New-StagedUpdate -Marker 'locked'
    $lock = [IO.File]::Open((Join-Path $stagedRoot 'locked.txt'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $global:LASTEXITCODE = 0
        & $applier -InstallRoot $installRoot -StagedRoot $stagedRoot -PreviousVersion '0.1.0-rc.10' -NewVersion '0.1.0-rc.11' -LogPath $log -Launch $launch
    }
    finally { $lock.Dispose() }
    Check ($LASTEXITCODE -eq 1) 'A blocked swap must fail'
    Check ((Test-Path -LiteralPath (Join-Path $installRoot 'rc10.txt')) -and -not (Test-Path -LiteralPath "$installRoot.previous-0.1.0-rc.10")) 'A blocked swap must roll back to the previous installation'
    Check ($launched.Count -eq 1 -and $launched[0] -eq $installRoot) 'The restored installation must be started again'
    Set-Location -LiteralPath $savedLocation
    Remove-Item -LiteralPath (Split-Path $stagedRoot -Parent) -Recurse -Force -ErrorAction SilentlyContinue

    # End to end: Start-UtpUpdateSwap from a separate process that exits, as UTP does. The
    # disposable launcher only writes a marker file, so no real UTP is started.
    $e2eParent = Join-Path $testRoot 'E2E Programs'
    $e2eInstall = Join-Path $e2eParent 'Usage Tray Pill'
    $markerVbs = @'
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName))
Set marker = fso.CreateTextFile(root & "\launched.txt", True)
marker.WriteLine "launched"
marker.Close
'@
    New-Installation -Path $e2eInstall -Marker 'old'
    $e2eWork = Join-Path $e2eParent ('.utp-update-' + [guid]::NewGuid().ToString('N'))
    New-Installation -Path (Join-Path $e2eWork 'app') -Marker 'new'
    [IO.File]::WriteAllText((Join-Path $e2eWork 'app\src\Launch-UsageTrayPill.vbs'), $markerVbs)
    $dataDirectory = Join-Path $testRoot 'data'
    [void][IO.Directory]::CreateDirectory($dataDirectory)
    $driver = Join-Path $testRoot 'driver.ps1'
    [IO.File]::WriteAllText($driver, @'
param([string]$Library, [string]$InstallRoot, [string]$WorkDirectory, [string]$DataDirectory)
$ErrorActionPreference = 'Stop'
. $Library
$script:DataDir = $DataDirectory
Start-UtpUpdateSwap -Staged ([pscustomobject]@{ WorkDirectory = $WorkDirectory; StagedRoot = (Join-Path $WorkDirectory 'app') }) -InstallRoot $InstallRoot -PreviousVersion '0.1.0-rc.8' -NewVersion '0.1.0-rc.9'
'@)
    $powerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $powerShell -NoProfile -ExecutionPolicy Bypass -File $driver -Library (Join-Path $sourceRoot 'UtpUpdate.ps1') -InstallRoot $e2eInstall -WorkDirectory $e2eWork -DataDirectory $dataDirectory
    Check ($LASTEXITCODE -eq 0) 'The update swap must start'
    $deadline = (Get-Date).AddSeconds(60)
    while (-not (Test-Path -LiteralPath (Join-Path $e2eInstall 'launched.txt')) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 250 }
    Check (Test-Path -LiteralPath (Join-Path $e2eInstall 'launched.txt')) 'The swapped installation must be launched by its own launcher'
    Check ((Test-Path -LiteralPath (Join-Path $e2eInstall 'new.txt')) -and (Test-Path -LiteralPath "$e2eInstall.previous-0.1.0-rc.8\old.txt")) 'The end-to-end swap must replace the installation and keep a backup'
    while ((Test-Path -LiteralPath $e2eWork) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 250 }
    Check (-not (Test-Path -LiteralPath $e2eWork)) 'The end-to-end swap must remove its work folder'
    Check ((Get-Content -LiteralPath (Join-Path $dataDirectory 'update.log') -Raw) -match 'Installed 0\.1\.0-rc\.9') 'The end-to-end swap must write its log to the data folder'

    Write-Host 'Updater tests OK (versions, release selection, fixed destinations, checksums, archive safety, offline download, swap, rollback, end-to-end restart).'
}
finally {
    Set-Location -LiteralPath $savedLocation
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if ($resolved.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'UTP updater test *') {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
