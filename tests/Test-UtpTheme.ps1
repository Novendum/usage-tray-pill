$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $repoRoot 'src'
$ErrorActionPreference = 'Stop'
. (Join-Path $sourceRoot 'Start-UsageTrayPill.ps1') -LibraryOnly
function Check { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
function Get-Rgb { param([System.Drawing.Color]$Color) return "$($Color.R),$($Color.G),$($Color.B)" }

$script:DataDir = Join-Path ([IO.Path]::GetTempPath()) ('UTP theme test ' + [guid]::NewGuid().ToString('N'))
function Save-State { }
$script:TestAppTheme = 'Dark'
function Get-UtpAppTheme { return $script:TestAppTheme }

# Overview palette: every role has a light and a dark value; unknown roles stand out.
$script:OverviewTheme = 'Light'
Check ((Get-Rgb (Get-OverviewColor 'surface')) -eq '255,255,255' -and (Get-Rgb (Get-OverviewColor 'ink')) -eq '36,39,46') 'Light palette values must match the original design'
$script:OverviewTheme = 'Dark'
Check ((Get-Rgb (Get-OverviewColor 'surface')) -eq '35,36,41' -and (Get-Rgb (Get-OverviewColor 'ink')) -eq '234,236,242') 'Dark palette values must be readable on dark surfaces'
Check ((Get-OverviewColor 'no-such-role') -eq [System.Drawing.Color]::Magenta) 'Unknown palette roles must be obvious'
$script:OverviewTheme = 'Light'

# A window built the way UTP builds its own, never shown.
$form = New-Object System.Windows.Forms.Form
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 244, 241)
$panel = New-Object System.Windows.Forms.Panel
$panel.BackColor = [System.Drawing.Color]::White
$label = New-Object System.Windows.Forms.Label
$label.ForeColor = [System.Drawing.Color]::FromArgb(36, 39, 46)
$accent = New-Object System.Windows.Forms.Label
$accent.ForeColor = [System.Drawing.Color]::FromArgb(208, 34, 121)
$textBox = New-Object System.Windows.Forms.TextBox
$combo = New-Object System.Windows.Forms.ComboBox
$combo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$secondary = New-Object System.Windows.Forms.Button
Set-MainWindowButtonStyle -Button $secondary
$primary = New-Object System.Windows.Forms.Button
Set-MainWindowButtonStyle -Button $primary -Kind Primary
$plain = New-Object System.Windows.Forms.Button
$list = New-ListView -X 0 -Y 0 -Width 200 -Height 100
$toggle = New-Object System.Windows.Forms.CheckBox
$toggle.Text = 'Also for weekly and monthly limits'
$toggle.Size = New-Object System.Drawing.Size 260, 24
$toggle.Enabled = $false
$panel.Controls.AddRange(@($label, $accent, $textBox, $combo, $secondary, $primary, $plain, $list, $toggle))
$form.Controls.Add($panel)
$textOriginal = $textBox.BackColor.ToArgb()
try {
    Set-UtpWindowTheme -Form $form
    Check ($script:OverviewTheme -eq 'Dark') 'The overview must follow the Windows app mode'
    Check ((Get-Rgb $form.BackColor) -eq '25,26,30' -and (Get-Rgb $panel.BackColor) -eq '35,36,41') 'Surfaces must turn dark'
    Check ((Get-Rgb $label.ForeColor) -eq '234,236,242') 'Body text must turn light'
    Check ((Get-Rgb $accent.ForeColor) -eq '208,34,121') 'Brand accents must keep their colour'
    Check ((Get-Rgb $textBox.BackColor) -eq '45,46,52') 'Inputs must use the dark input surface'
    Check ($combo.DrawMode -eq [System.Windows.Forms.DrawMode]::OwnerDrawFixed -and $combo.FlatStyle -eq [System.Windows.Forms.FlatStyle]::Standard) 'Drop-down lists must be drawn in the palette and keep the standard style for the native dark frame'
    $record = $null
    Check ($script:UtpThemeRecords.TryGetValue($toggle, [ref]$record) -and $record['TogglePaint']) 'Check boxes must be repainted in dark mode'
    foreach ($state in @(@{ Enabled = $false; Checked = $false }, @{ Enabled = $true; Checked = $true })) {
        $toggle.Enabled = $state.Enabled
        $toggle.Checked = $state.Checked
        $toggleBitmap = New-Object System.Drawing.Bitmap 260, 24
        $toggleGraphics = [System.Drawing.Graphics]::FromImage($toggleBitmap)
        try {
            Draw-UtpDarkToggle -Control $toggle -Graphics $toggleGraphics
            $glyph = [System.Windows.Forms.CheckBoxRenderer]::GetGlyphSize($toggleGraphics, [System.Windows.Forms.VisualStyles.CheckBoxState]::UncheckedNormal)
        }
        finally { $toggleGraphics.Dispose() }
        try {
            $top = [int][Math]::Floor((24 - [Math]::Max(12, $glyph.Width)) / 2)
            $boxPixel = $toggleBitmap.GetPixel(5, $top + 3)
            $light = @(for ($x = 0; $x -lt 260; $x++) { for ($y = 0; $y -lt 24; $y++) { $pixel = $toggleBitmap.GetPixel($x, $y); if ($pixel.R -gt 200 -and $pixel.G -gt 200 -and $pixel.B -gt 200) { 1 } } }).Count
            $textPixels = @(for ($x = 20; $x -lt 260; $x++) { for ($y = 0; $y -lt 24; $y++) { if ($toggleBitmap.GetPixel($x, $y).R -gt 90) { 1 } } }).Count
            if ($state.Checked) {
                Check ($boxPixel.R -gt 180 -and $boxPixel.G -lt 80) 'A checked box must fill with the UTP accent'
            }
            else {
                Check ((Get-Rgb $boxPixel) -eq '45,46,52' -and $light -eq 0) 'A disabled box must be dark without light, embossed text'
            }
            Check ($textPixels -gt 30) 'The option text must stay readable'
        }
        finally { $toggleBitmap.Dispose() }
    }
    $toggle.Enabled = $false
    $toggle.Checked = $false
    Check ((Get-Rgb $secondary.BackColor) -eq '50,52,59' -and (Get-Rgb $secondary.ForeColor) -eq '226,228,235' -and (Get-Rgb $secondary.FlatAppearance.BorderColor) -eq '74,77,87') 'Secondary buttons must follow the dark palette'
    Check ((Get-Rgb $primary.BackColor) -eq '208,34,121' -and $primary.ForeColor.ToArgb() -eq [System.Drawing.Color]::White.ToArgb()) 'Primary buttons must keep white text on the accent'
    Check ($plain.FlatStyle -eq [System.Windows.Forms.FlatStyle]::Flat -and (Get-Rgb $plain.BackColor) -eq '35,36,41') 'Standard buttons must become flat so the dark colour shows'

    # UTP code may assign a light colour while dark mode is on; the next pass maps it.
    $label.ForeColor = [System.Drawing.Color]::FromArgb(103, 108, 118)
    Set-UtpWindowTheme -Form $form
    Check ((Get-Rgb $label.ForeColor) -eq '160,165,178') 'Colours set while dark must be mapped on the next pass'

    # Back to light: every control returns to the colour UTP gave it.
    $script:TestAppTheme = 'Light'
    Set-UtpWindowTheme -Form $form
    Check ((Get-Rgb $form.BackColor) -eq '245,244,241' -and $panel.BackColor.ToArgb() -eq [System.Drawing.Color]::White.ToArgb()) 'Surfaces must return to light'
    Check ((Get-Rgb $label.ForeColor) -eq '103,108,118') 'Text must return to its latest light colour'
    Check ($textBox.BackColor.ToArgb() -eq $textOriginal) 'Inputs must return to their light surface'
    Check ((Get-Rgb $secondary.BackColor) -eq '239,238,235' -and $secondary.FlatStyle -eq [System.Windows.Forms.FlatStyle]::Flat) 'Flat buttons must keep their own light style'
    Check ($plain.FlatStyle -eq [System.Windows.Forms.FlatStyle]::Standard -and $plain.UseVisualStyleBackColor) 'Standard buttons must get their native look back'
    $script:TestAppTheme = 'Dark'
    Set-UtpWindowTheme -Form $form
    Set-UtpWindowTheme -Form $form
    Check ((Get-Rgb $panel.BackColor) -eq '35,36,41' -and (Get-Rgb $label.ForeColor) -eq '160,165,178') 'Repeated passes must be stable'
}
finally { $form.Dispose() }

# App icon: all shell sizes, readable by Windows, and free of embedded metadata.
$iconPath = Join-Path $repoRoot 'assets\app-icon.ico'
$iconBytes = [IO.File]::ReadAllBytes($iconPath)
$frameCount = [BitConverter]::ToUInt16($iconBytes, 4)
$sizes = @()
$pngFrames = @()
for ($index = 0; $index -lt $frameCount; $index++) {
    $entry = 6 + 16 * $index
    $width = if ($iconBytes[$entry] -eq 0) { 256 } else { [int]$iconBytes[$entry] }
    $sizes += $width
    $length = [BitConverter]::ToUInt32($iconBytes, $entry + 8)
    $offset = [BitConverter]::ToUInt32($iconBytes, $entry + 12)
    if ($iconBytes[$offset] -eq 0x89 -and $iconBytes[$offset + 1] -eq 0x50) {
        $frame = New-Object byte[] $length
        [Array]::Copy($iconBytes, $offset, $frame, 0, $length)
        $pngFrames += ,$frame
    }
}
Check (($sizes -join ',') -eq '16,20,24,32,40,48,64,128,256') "The app icon must carry every shell size, got $($sizes -join ',')"
function Get-PngChunks {
    param([byte[]]$Bytes)
    $chunks = @()
    $position = 8
    while ($position + 8 -le $Bytes.Length) {
        $length = ([int]$Bytes[$position] -shl 24) -bor ([int]$Bytes[$position + 1] -shl 16) -bor ([int]$Bytes[$position + 2] -shl 8) -bor [int]$Bytes[$position + 3]
        $chunks += [Text.Encoding]::ASCII.GetString($Bytes, $position + 4, 4)
        $position += 12 + $length
    }
    return $chunks
}
$allowedChunks = @('IHDR', 'PLTE', 'tRNS', 'sRGB', 'gAMA', 'cHRM', 'pHYs', 'IDAT', 'IEND')
foreach ($png in @($pngFrames) + ,([IO.File]::ReadAllBytes((Join-Path $repoRoot 'assets\app-icon.png')))) {
    $unexpected = @(Get-PngChunks $png | Where-Object { $_ -notin $allowedChunks })
    Check ($unexpected.Count -eq 0) "App icon images must not carry metadata chunks: $($unexpected -join ',')"
}
$svg = Get-Content -LiteralPath (Join-Path $repoRoot 'assets\app-icon.svg') -Raw
Check ($svg -notmatch '(?i)<metadata|xlink:href|href="(?!#)|[a-z]:\\|/Users/') 'The SVG source must not reference files, metadata or local paths'
foreach ($size in @(16, 24, 32, 48)) {
    $icon = New-Object System.Drawing.Icon $iconPath, $size, $size
    try { Check ($icon.Width -eq $size) "Windows must load the $size px frame" } finally { $icon.Dispose() }
}
$appIcon = Get-UtpAppIcon -Size 20
try { Check ($null -ne $appIcon -and $appIcon.Width -eq 20) 'The runtime must load app-icon frames by size' } finally { if ($null -ne $appIcon) { $appIcon.Dispose() } }

# Windows identity: UTP's own taskbar group, Start-menu shortcut ID, and launch command.
Check (('UtpShellIdentity' -as [type]) -and [UtpShellIdentity]::AppId -eq 'Novendum.UsageTrayPill') 'The shell identity helper must load'
$launch = Get-UtpLaunchCommand
Check ($launch -match '^"[^"]*\\wscript\.exe" "[^"]*\\Launch-UsageTrayPill\.vbs"$') 'Pinned windows must relaunch UTP through its hidden launcher'
$testFolder = Join-Path ([IO.Path]::GetTempPath()) ('UTP shell identity ' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testFolder)
try {
    $shortcutPath = Join-Path $testFolder 'Usage Tray Pill.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $shortcut.Save()
    Check ([string]::IsNullOrEmpty([UtpShellIdentity]::GetShortcutAppId($shortcutPath))) 'A new shortcut has no app ID'
    Check ([UtpShellIdentity]::SetShortcutAppId($shortcutPath, [UtpShellIdentity]::AppId)) 'Setting the shortcut app ID must succeed'
    Check ([UtpShellIdentity]::GetShortcutAppId($shortcutPath) -eq 'Novendum.UsageTrayPill') 'The shortcut must carry the UTP app ID'
    Check ($shell.CreateShortcut($shortcutPath).TargetPath -ieq (Join-Path $env:SystemRoot 'System32\wscript.exe')) 'Writing the app ID must keep the shortcut target'
}
finally { Remove-Item -LiteralPath $testFolder -Recurse -Force -ErrorAction SilentlyContinue }
$dialog = New-Object System.Windows.Forms.Form
try {
    Initialize-UtpForm -Form $dialog
    Check ($null -ne $dialog.Icon -and $dialog.Icon.Width -gt 0) 'UTP windows must use the app icon instead of the PowerShell icon'
}
finally { $dialog.Dispose() }

Write-Host 'Theme and identity tests OK (palette, dark/light round trip, button and input styles, icon sizes and metadata, app ID, launch command).'
