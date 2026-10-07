param([string]$OutputDirectory)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$builder = Join-Path $repoRoot 'scripts\Build-ReleasePackage.ps1'
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path ([IO.Path]::GetTempPath()) ('UTP package test ' + [guid]::NewGuid().ToString('N'))
}
$OutputDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Test output must be a new directory; existing data is never overwritten.' }
[void][IO.Directory]::CreateDirectory($OutputDirectory)
# Match the expanded paths returned by file enumeration and PSScriptRoot.
$OutputDirectory = (Get-Item -LiteralPath $OutputDirectory).FullName
$result = & $builder -Version '0.0.0-package-test' -OutputDirectory (Join-Path $OutputDirectory 'artifact')
$extractRoot = Join-Path $OutputDirectory 'Extracted user package with spaces'
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($result.ArchivePath, $extractRoot)

$actualFiles = @(Get-ChildItem -LiteralPath $extractRoot -Recurse -File | ForEach-Object {
    $_.FullName.Substring($extractRoot.Length + 1).Replace('\', '/')
} | Sort-Object)
$expectedFiles = @(
    'Start-UsageTrayPill.cmd', 'README.md', 'LICENSE', 'PRIVACY.md', 'SECURITY.md', 'SUPPORT.md',
    'THIRD_PARTY_NOTICES.md', 'CHANGELOG.md', 'docs/PROVIDERS.md', 'docs/ASSET_PROVENANCE.md',
    'THIRD_PARTY_LICENSES/QWEN_CODE_APACHE-2.0.txt',
    'assets/qwen-logo.png', 'assets/utp-logo.svg',
    'assets/tray-icon-dark.ico', 'assets/tray-icon-dark.png', 'assets/tray-icon-dark.svg',
    'assets/tray-icon-light.ico', 'assets/tray-icon-light.png', 'assets/tray-icon-light.svg',
    'src/BadgeVisibility.cs', 'src/CollectorPolicy.ps1', 'src/ExternalUsageAdapters.ps1',
    'src/Launch-UsageTrayPill.vbs', 'src/OpenCodeGo.ps1', 'src/OwnedUsageProcess.cs',
    'src/PillRenderer.cs', 'src/QwenTokenPlan.ps1', 'src/RequestDeadline.cs',
    'src/Start-ClaudeUsageKeeper.ps1', 'src/Start-UsageCollector.ps1', 'src/Start-UsageTrayPill.ps1',
    'src/Update-ClaudeUsageFromStatusline.ps1', 'src/UsageFileMonitor.cs',
    'scripts/Install-ClaudeStatusLine.ps1', 'scripts/Install-DesktopShortcut.ps1',
    'scripts/Install-StartMenuShortcut.ps1', 'scripts/Install-Startup.ps1',
    'scripts/Uninstall-ClaudeStatusLine.ps1', 'scripts/Uninstall-DesktopShortcut.ps1',
    'scripts/Uninstall-StartMenuShortcut.ps1', 'scripts/Uninstall-Startup.ps1',
    'scripts/UtpInstallationHelpers.ps1'
) | Sort-Object
if (@(Compare-Object $expectedFiles $actualFiles).Count -ne 0) { throw 'ZIP inventory differs from the reviewed user package.' }
if (@(Compare-Object $actualFiles @(Get-Content -LiteralPath $result.ManifestPath)).Count -ne 0) { throw 'File manifest differs from ZIP inventory.' }
$archiveHash = (Get-FileHash -LiteralPath $result.ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ((Get-Content -LiteralPath $result.ChecksumPath -Raw).Trim() -cne "$archiveHash  $([IO.Path]::GetFileName($result.ArchivePath))") { throw 'ZIP checksum does not match SHA256SUMS.txt.' }
foreach ($relative in $actualFiles) {
    if ($relative -eq 'README.md') {
        $expectedReadme = [IO.File]::ReadAllText((Join-Path $repoRoot 'docs\USER_GUIDE.md'))
        foreach ($rootDocument in @('SUPPORT.md', 'PRIVACY.md', 'SECURITY.md', 'CHANGELOG.md', 'THIRD_PARTY_NOTICES.md')) {
            $expectedReadme = $expectedReadme.Replace("](../$rootDocument)", "]($rootDocument)")
        }
        $expectedReadme = $expectedReadme.Replace('](PROVIDERS.md)', '](docs/PROVIDERS.md)')
        if ([IO.File]::ReadAllText((Join-Path $extractRoot $relative)) -cne $expectedReadme) { throw 'Packaged README differs from the guide beyond the approved link relocation.' }
    }
    elseif ((Get-FileHash -LiteralPath (Join-Path $extractRoot $relative)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $repoRoot $relative)).Hash) {
        throw "Package file changed during copying: $relative"
    }
}

# Fail on broken local Markdown links, including a developer-only document accidentally linked by the user guide.
$documents = @(Get-ChildItem -LiteralPath $extractRoot -Recurse -File -Filter '*.md')
$documents += Get-Item -LiteralPath (Join-Path $repoRoot 'docs\USER_GUIDE.md')
foreach ($document in $documents) {
    $content = Get-Content -LiteralPath $document.FullName -Raw
    foreach ($match in [regex]::Matches($content, '\]\(([^)]+)\)')) {
        $target = $match.Groups[1].Value
        if ($target -match '^(?:[a-z]+:|#)') { continue }
        $target = [Uri]::UnescapeDataString(($target -split '#', 2)[0])
        if (-not (Test-Path -LiteralPath (Join-Path $document.DirectoryName $target))) { throw "Broken documentation link in $($document.FullName): $target" }
    }
}

$launcher = Get-Content -LiteralPath (Join-Path $extractRoot 'Start-UsageTrayPill.cmd') -Raw
if ($launcher -notmatch '"%~dp0src\\Launch-UsageTrayPill\.vbs"') { throw 'Root launcher must quote the src VBS path.' }
$vbs = Get-Content -LiteralPath (Join-Path $extractRoot 'src\Launch-UsageTrayPill.vbs') -Raw
if ($vbs -notmatch 'scriptDirectory & "\\Start-UsageTrayPill.ps1"') { throw 'VBS launcher must target its sibling runtime.' }
. (Join-Path $extractRoot 'scripts\UtpInstallationHelpers.ps1')
$installation = Get-UtpInstallationPaths
if ($installation.Root -ne $extractRoot) { throw 'Setup helper resolved the wrong package root.' }
foreach ($path in @($installation.Launcher, $installation.Updater, (Join-Path $installation.Assets 'tray-icon-light.ico'), (Join-Path $installation.Assets 'tray-icon-dark.ico'))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'A setup helper dependency is missing from the extracted package.' }
}
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $extractRoot 'scripts') -File | Where-Object { $_.Name -match '^(Install|Uninstall)-' }) {
    if ((Get-Content -LiteralPath $file.FullName -Raw) -notmatch 'UtpInstallationHelpers.ps1') { throw "Setup script does not use canonical package paths: $($file.Name)" }
}

# Rebuilding into the same destination must fail and preserve the original artifact.
$refusedOverwrite = $false
try { & $builder -Version '0.0.0-package-test' -OutputDirectory (Join-Path $OutputDirectory 'artifact') | Out-Null }
catch { $refusedOverwrite = $_.Exception.Message -like 'Output already exists*' }
if (-not $refusedOverwrite -or (Get-FileHash -LiteralPath $result.ArchivePath).Hash.ToLowerInvariant() -ne $archiveHash) { throw 'Builder did not safely refuse an existing output.' }
foreach ($unsafeDirectory in @($repoRoot, (Join-Path $repoRoot 'src\package-test'))) {
    $refusedSource = $false
    try { & $builder -Version '0.0.0-package-test' -OutputDirectory $unsafeDirectory | Out-Null }
    catch { $refusedSource = $_.Exception.Message -like 'OutputDirectory must not*' }
    if (-not $refusedSource) { throw 'Builder accepted a source directory as output.' }
}

# PowerShell location can differ from the process working directory after Push-Location.
Push-Location -LiteralPath $OutputDirectory
try { $relativeResult = & $builder -Version '0.0.0-package-test' -OutputDirectory 'dist-relative' }
finally { Pop-Location }
$expectedRelativeArchive = Join-Path $OutputDirectory 'dist-relative\UsageTrayPill-0.0.0-package-test-windows.zip'
if ($relativeResult.ArchivePath -ne $expectedRelativeArchive -or -not (Test-Path -LiteralPath $expectedRelativeArchive)) {
    throw 'Relative build output was not resolved against the PowerShell location.'
}

# Run only the explicit offline SelfTest, never the normal launcher or provider collectors.
$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$info.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $extractRoot 'src\Start-UsageTrayPill.ps1') + '" -SelfTest'
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
foreach ($variable in @('APPDATA', 'LOCALAPPDATA', 'USERPROFILE', 'TEMP', 'TMP')) {
    $isolatedPath = Join-Path $OutputDirectory ('isolated-' + $variable)
    [void][IO.Directory]::CreateDirectory($isolatedPath)
    $info.EnvironmentVariables[$variable] = $isolatedPath
}
$process = [Diagnostics.Process]::Start($info)
try {
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(60000)) { $process.Kill(); $process.WaitForExit(); throw 'Extracted-package self-test exceeded 60 seconds.' }
    $output = $stdout.Result + $stderr.Result
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'self-test.log'), $output)
    if ($process.ExitCode -ne 0 -or $output -notmatch 'Self-test OK') { throw "Extracted-package self-test failed. See $OutputDirectory\self-test.log" }
}
finally { $process.Dispose() }
Write-Host "Release package test OK: $($actualFiles.Count) files, checksum, source/package links, relative output, quoted launch paths, setup dependencies, overwrite protection and isolated extracted SelfTest."
Write-Host "Evidence: $OutputDirectory"
