<#
.SYNOPSIS
Build a local user ZIP from an explicit file allowlist. Does not publish a release.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$')]
    [string]$Version,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot "dist\$Version"
}
$outputRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
if ($outputRoot -eq [IO.Path]::GetPathRoot($outputRoot)) { throw 'OutputDirectory must be a dedicated folder, not a drive or share root.' }
$outputRoot = $outputRoot.TrimEnd([char[]]'\/')
if ($repoRoot.StartsWith($outputRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputDirectory must not be an ancestor of the repository.'
}
foreach ($protectedPath in @($repoRoot) + @('src', 'scripts', 'tests', 'docs', 'assets', 'THIRD_PARTY_LICENSES', '.github', '.git' | ForEach-Object { Join-Path $repoRoot $_ })) {
    if ($outputRoot -ieq $protectedPath -or ($protectedPath -ne $repoRoot -and $outputRoot.StartsWith($protectedPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase))) {
        throw 'OutputDirectory must not be the repository root or an included source/developer folder.'
    }
}

# Keep this list explicit: a new source, asset, or document requires review before shipping.
$packageFiles = @(
    'Start-UsageTrayPill.cmd',
    'LICENSE', 'PRIVACY.md', 'SECURITY.md', 'SUPPORT.md', 'THIRD_PARTY_NOTICES.md', 'CHANGELOG.md',
    'docs/PROVIDERS.md', 'docs/ASSET_PROVENANCE.md',
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
)
$entries = @($packageFiles | ForEach-Object { [pscustomobject]@{ Source = $_; Destination = $_ } })
$entries += [pscustomobject]@{ Source = 'docs/USER_GUIDE.md'; Destination = 'README.md' }
$entries = @($entries | Sort-Object Destination)
foreach ($entry in $entries) {
    $source = Join-Path $repoRoot $entry.Source
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Required package file missing: $($entry.Source)" }
    if ((Get-Item -LiteralPath $source).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Package files must not be links: $($entry.Source)" }
}

$archiveName = "UsageTrayPill-$Version-windows.zip"
$archivePath = Join-Path $outputRoot $archiveName
$checksumPath = Join-Path $outputRoot 'SHA256SUMS.txt'
$manifestPath = Join-Path $outputRoot 'FILE_MANIFEST.txt'
foreach ($path in @($archivePath, $checksumPath, $manifestPath)) {
    if (Test-Path -LiteralPath $path) { throw "Output already exists; choose a new output directory: $path" }
}
[void][IO.Directory]::CreateDirectory($outputRoot)
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$utf8 = New-Object Text.UTF8Encoding($false)
$stream = [IO.File]::Open($archivePath, [IO.FileMode]::CreateNew)
try {
    $zip = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
    try {
        foreach ($entry in $entries) {
            $sourcePath = Join-Path $repoRoot $entry.Source
            if ($entry.Destination -eq 'README.md') {
                # The canonical guide lives in docs; its packaged README lives at the root.
                $readme = [IO.File]::ReadAllText($sourcePath)
                $readme = $readme -replace '\]\(\.\./', ']('
                $readme = $readme.Replace('](PROVIDERS.md)', '](docs/PROVIDERS.md)')
                $readmeEntry = $zip.CreateEntry('README.md', [IO.Compression.CompressionLevel]::Optimal)
                $readmeEntry.LastWriteTime = (Get-Item -LiteralPath $sourcePath).LastWriteTime
                $readmeStream = $readmeEntry.Open()
                try {
                    $readmeBytes = $utf8.GetBytes($readme)
                    $readmeStream.Write($readmeBytes, 0, $readmeBytes.Length)
                }
                finally { $readmeStream.Dispose() }
            }
            else {
                [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $sourcePath, $entry.Destination, [IO.Compression.CompressionLevel]::Optimal)
            }
        }
    }
    finally { $zip.Dispose() }
}
finally { $stream.Dispose() }
$checksum = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
# CreateNew also protects against an output appearing between validation and writing.
foreach ($artifact in @(
    @{ Path = $checksumPath; Text = "$checksum  $archiveName`n" },
    @{ Path = $manifestPath; Text = (($entries.Destination -join "`n") + "`n") }
)) {
    $file = [IO.File]::Open($artifact.Path, [IO.FileMode]::CreateNew)
    try {
        $bytes = $utf8.GetBytes($artifact.Text)
        $file.Write($bytes, 0, $bytes.Length)
    }
    finally { $file.Dispose() }
}
[pscustomobject]@{ ArchivePath = $archivePath; ChecksumPath = $checksumPath; ManifestPath = $manifestPath; FileCount = $entries.Count; SHA256 = $checksum }
