# One-click updates from the project's GitHub releases. Runs only when the user asks.
# Destinations are fixed: api.github.com for the release list and asset metadata, plus
# GitHub's release-asset host for exactly one validated redirect per download.

$script:UtpUpdateRepository = 'Novendum/usage-tray-pill'
$script:UtpUpdateApiHost = 'api.github.com'
$script:UtpUpdateAssetHosts = @('release-assets.githubusercontent.com', 'objects.githubusercontent.com', 'github-releases.githubusercontent.com')
$script:UtpUpdateHttpGet = $null   # Tests replace this with an offline fake.

function New-UtpUpdateException {
    param([string]$Code, [string]$Message)
    $exception = New-Object System.InvalidOperationException $Message
    $exception.Data['UtpUpdateCode'] = $Code
    return $exception
}

function ConvertTo-UtpVersion {
    param([string]$Text)
    $match = [regex]::Match([string]$Text, '^v?(\d+)\.(\d+)\.(\d+)(?:-rc\.(\d+))?$')
    if (-not $match.Success) { return $null }
    return [pscustomobject]@{
        Major = [int]$match.Groups[1].Value
        Minor = [int]$match.Groups[2].Value
        Patch = [int]$match.Groups[3].Value
        # A final release sorts after every release candidate of the same version.
        Candidate = $(if ($match.Groups[4].Success) { [int]$match.Groups[4].Value } else { [int]::MaxValue })
        Text = ($Text -replace '^v', '')
    }
}

function Compare-UtpVersion {
    param([string]$Left, [string]$Right)
    $a = ConvertTo-UtpVersion $Left
    $b = ConvertTo-UtpVersion $Right
    if ($null -eq $a -or $null -eq $b) { throw (New-UtpUpdateException 'invalid_version' 'A version number could not be read.') }
    foreach ($part in 'Major', 'Minor', 'Patch', 'Candidate') {
        if ($a.$part -lt $b.$part) { return -1 }
        if ($a.$part -gt $b.$part) { return 1 }
    }
    return 0
}

function Get-UtpReleaseCandidates {
    param([object[]]$Releases)
    foreach ($release in @($Releases)) {
        if ($null -eq $release -or [bool]$release.draft) { continue }
        $version = ConvertTo-UtpVersion ([string]$release.tag_name)
        if ($null -eq $version) { continue }
        $zipName = "UsageTrayPill-$($version.Text)-windows.zip"
        $zip = @($release.assets | Where-Object { [string]$_.name -ceq $zipName }) | Select-Object -First 1
        $sums = @($release.assets | Where-Object { [string]$_.name -ceq 'SHA256SUMS.txt' }) | Select-Object -First 1
        if ($null -eq $zip -or $null -eq $sums) { continue }
        $digest = ''
        if ([string]$zip.digest -match '^sha256:([0-9a-fA-F]{64})$') { $digest = $Matches[1].ToLowerInvariant() }
        [pscustomobject]@{
            Version = $version.Text
            Tag = [string]$release.tag_name
            Name = [string]$release.name
            Page = "https://github.com/$($script:UtpUpdateRepository)/releases/tag/$([string]$release.tag_name)"
            ZipName = $zipName
            ZipApiUrl = "https://$($script:UtpUpdateApiHost)/repos/$($script:UtpUpdateRepository)/releases/assets/$([long]$zip.id)"
            ZipSize = [long]$zip.size
            ZipDigest = $digest
            SumsApiUrl = "https://$($script:UtpUpdateApiHost)/repos/$($script:UtpUpdateRepository)/releases/assets/$([long]$sums.id)"
        }
    }
}

function Select-UtpUpdate {
    param([object[]]$Candidates, [string]$CurrentVersion)
    $best = $null
    foreach ($candidate in @($Candidates)) {
        if ((Compare-UtpVersion $candidate.Version $CurrentVersion) -le 0) { continue }
        if ($null -eq $best -or (Compare-UtpVersion $candidate.Version $best.Version) -gt 0) { $best = $candidate }
    }
    return $best
}

function Test-UtpUpdateRedirectHost {
    param([string]$Url)
    try { $uri = [Uri]$Url } catch { return $false }
    return ($uri.Scheme -eq 'https' -and $uri.Host -in $script:UtpUpdateAssetHosts -and $uri.Port -eq 443)
}

function Invoke-UtpUpdateHttpGet {
    param([string]$Url, [string]$Accept, [long]$MaximumBytes, [int]$TimeoutMilliseconds = 15000)
    if ($null -ne $script:UtpUpdateHttpGet) { return ,([byte[]](& $script:UtpUpdateHttpGet $Url $Accept $MaximumBytes)) }
    $uri = [Uri]$Url
    if ($uri.Scheme -ne 'https' -or $uri.Host -ne $script:UtpUpdateApiHost) { throw (New-UtpUpdateException 'destination_rejected' 'Updates are only read from api.github.com.') }
    $current = $Url
    for ($hop = 0; $hop -lt 2; $hop++) {
        $request = [System.Net.HttpWebRequest]::Create($current)
        $request.Method = 'GET'
        $request.Accept = $Accept
        $request.UserAgent = 'UsageTrayPill-Updater'
        $request.AllowAutoRedirect = $false
        $request.Timeout = 12000
        $request.ReadWriteTimeout = 12000
        $request.KeepAlive = $false
        if ($hop -eq 0) { $request.Headers['X-GitHub-Api-Version'] = '2022-11-28' }
        $deadline = New-Object UtpRequestDeadline $request, $TimeoutMilliseconds
        $response = $null
        try {
            try { $response = [System.Net.HttpWebResponse]$request.GetResponse() }
            catch [System.Net.WebException] {
                $response = $_.Exception.Response
                if ($null -eq $response) { throw (New-UtpUpdateException 'network_error' 'GitHub could not be reached. Check your connection and try again.') }
            }
            $status = [int]$response.StatusCode
            if ($status -in 301, 302, 303, 307, 308) {
                $location = [string]$response.Headers['Location']
                # Exactly one redirect, and only from the API to GitHub's own release-asset host.
                if ($hop -ne 0 -or -not (Test-UtpUpdateRedirectHost $location)) { throw (New-UtpUpdateException 'destination_rejected' 'GitHub redirected the download to an unexpected address.') }
                $current = $location
                continue
            }
            if ($status -eq 403 -or $status -eq 429) { throw (New-UtpUpdateException 'rate_limited' 'GitHub asks to try again later.') }
            if ($status -ne 200) { throw (New-UtpUpdateException 'server_error' "GitHub returned an unexpected response ($status).") }
            if ($response.ContentLength -gt $MaximumBytes) { throw (New-UtpUpdateException 'response_too_large' 'The download is larger than expected.') }
            $stream = $response.GetResponseStream()
            $memory = New-Object System.IO.MemoryStream
            try {
                $buffer = New-Object byte[] 65536
                while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $memory.Write($buffer, 0, $read)
                    if ($memory.Length -gt $MaximumBytes) { throw (New-UtpUpdateException 'response_too_large' 'The download is larger than expected.') }
                }
                return ,([byte[]]$memory.ToArray())
            }
            finally { $memory.Dispose(); $stream.Dispose() }
        }
        finally {
            if ($null -ne $response) { $response.Dispose() }
            $deadline.Dispose()
        }
    }
    throw (New-UtpUpdateException 'destination_rejected' 'Too many redirects.')
}

function Get-UtpAvailableUpdate {
    param([string]$CurrentVersion)
    $url = "https://$($script:UtpUpdateApiHost)/repos/$($script:UtpUpdateRepository)/releases?per_page=20"
    $bytes = Invoke-UtpUpdateHttpGet -Url $url -Accept 'application/vnd.github+json' -MaximumBytes 2097152
    try { $releases = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json -ErrorAction Stop }
    catch { throw (New-UtpUpdateException 'parse_error' 'GitHub returned a release list UTP could not read.') }
    return Select-UtpUpdate -Candidates @(Get-UtpReleaseCandidates -Releases @($releases)) -CurrentVersion $CurrentVersion
}

function Get-UtpReleaseChecksum {
    param([string]$Text, [string]$FileName)
    foreach ($line in ($Text -split "`r?`n")) {
        $match = [regex]::Match($line.Trim(), '^([0-9a-fA-F]{64})\s+\*?(.+)$')
        if ($match.Success -and $match.Groups[2].Value -ceq $FileName) { return $match.Groups[1].Value.ToLowerInvariant() }
    }
    throw (New-UtpUpdateException 'checksum_missing' 'The release checksum list does not include the download.')
}

$script:UtpUpdateRequiredFiles = @('Start-UsageTrayPill.cmd', 'src/Start-UsageTrayPill.ps1', 'src/Launch-UsageTrayPill.vbs', 'src/Start-UsageCollector.ps1', 'assets/app-icon.ico')

function Expand-UtpUpdateArchive {
    param([string]$ArchivePath, [string]$Destination, [string]$ExpectedVersion)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $entries = @($archive.Entries)
        if ($entries.Count -eq 0 -or $entries.Count -gt 400) { throw (New-UtpUpdateException 'archive_rejected' 'The download does not look like a UTP package.') }
        $names = @()
        foreach ($entry in $entries) {
            $name = $entry.FullName.Replace('\', '/')
            # Reject absolute paths, drive letters and parent segments before anything is written.
            if ($name.StartsWith('/') -or $name.Contains(':') -or @($name -split '/' | Where-Object { $_ -eq '..' }).Count -gt 0) {
                throw (New-UtpUpdateException 'archive_rejected' 'The download contains an unsafe file path.')
            }
            $names += $name
        }
        foreach ($required in $script:UtpUpdateRequiredFiles) {
            if ($required -notin $names) { throw (New-UtpUpdateException 'archive_rejected' "The download is missing $required.") }
        }
        [void][IO.Directory]::CreateDirectory($Destination)
        $root = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
        foreach ($entry in $entries) {
            $target = [IO.Path]::GetFullPath((Join-Path $Destination $entry.FullName))
            if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw (New-UtpUpdateException 'archive_rejected' 'The download contains an unsafe file path.') }
            if ($entry.FullName.EndsWith('/')) { [void][IO.Directory]::CreateDirectory($target); continue }
            [void][IO.Directory]::CreateDirectory((Split-Path $target -Parent))
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $false)
        }
    }
    finally { $archive.Dispose() }
    $runtime = Get-Content -LiteralPath (Join-Path $Destination 'src\Start-UsageTrayPill.ps1') -Raw
    if ($runtime -notmatch ('(?m)^\$script:AppVersion = "' + [regex]::Escape($ExpectedVersion) + '"')) {
        throw (New-UtpUpdateException 'archive_rejected' 'The downloaded version does not match the release.')
    }
}

function Get-UtpUpdateExceptionMessage {
    param([object]$ErrorRecord)
    if ($null -ne $ErrorRecord.Exception -and $ErrorRecord.Exception.Data.Contains('UtpUpdateCode')) { return [string]$ErrorRecord.Exception.Message }
    return 'The update could not be completed.'
}

function Test-UtpSourceCheckout {
    param([string]$Root)
    return (Test-Path -LiteralPath (Join-Path $Root '.git'))
}

function Save-UtpUpdate {
    param([object]$Update, [string]$InstallRoot)
    # Stage next to the installation: same volume, so the final swap is an atomic rename.
    $parent = Split-Path $InstallRoot -Parent
    $work = Join-Path $parent ('.utp-update-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($work)
    try {
        $sumsBytes = Invoke-UtpUpdateHttpGet -Url $Update.SumsApiUrl -Accept 'application/octet-stream' -MaximumBytes 65536
        $expected = Get-UtpReleaseChecksum -Text ([Text.Encoding]::UTF8.GetString($sumsBytes)) -FileName $Update.ZipName
        if ($Update.ZipDigest -and $Update.ZipDigest -ne $expected) { throw (New-UtpUpdateException 'checksum_mismatch' 'GitHub and the release checksum list disagree.') }
        $zipBytes = Invoke-UtpUpdateHttpGet -Url $Update.ZipApiUrl -Accept 'application/octet-stream' -MaximumBytes 20971520 -TimeoutMilliseconds 90000
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $actual = ([BitConverter]::ToString($sha.ComputeHash($zipBytes)) -replace '-', '').ToLowerInvariant() } finally { $sha.Dispose() }
        if ($actual -ne $expected) { throw (New-UtpUpdateException 'checksum_mismatch' 'The download does not match its published checksum.') }
        $zipPath = Join-Path $work $Update.ZipName
        [IO.File]::WriteAllBytes($zipPath, $zipBytes)
        $staged = Join-Path $work 'app'
        Expand-UtpUpdateArchive -ArchivePath $zipPath -Destination $staged -ExpectedVersion $Update.Version
        return [pscustomobject]@{ WorkDirectory = $work; StagedRoot = $staged }
    }
    catch {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Start-UtpUpdateSwap {
    param([object]$Staged, [string]$InstallRoot, [string]$PreviousVersion, [string]$NewVersion)
    # The swap runs from the work folder, so no process keeps the installation folder open.
    $applier = Join-Path $Staged.WorkDirectory 'Apply-UtpUpdate.ps1'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Apply-UtpUpdate.ps1') -Destination $applier
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $info.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$applier`" -InstallRoot `"$InstallRoot`" -StagedRoot `"$($Staged.StagedRoot)`" -WaitProcessId $PID -PreviousVersion `"$PreviousVersion`" -NewVersion `"$NewVersion`" -LogPath `"$(Join-Path $script:DataDir 'update.log')`""
    $info.WorkingDirectory = $Staged.WorkDirectory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    [void][System.Diagnostics.Process]::Start($info)
}
