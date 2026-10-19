<#
.SYNOPSIS
Render the UTP application icon deterministically from vector geometry.

.DESCRIPTION
Writes assets/app-icon.ico (16-256 px), assets/app-icon.png (256 px) and
assets/app-icon-preview.png only when -Preview is passed. Every size is drawn
directly at its final pixel size; small sizes use heavier strokes and no depth
effects so they stay crisp. This is a developer tool and is not shipped.
#>
[CmdletBinding()]
param(
    [string]$AssetsDirectory = '',
    [string]$PreviewPath = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
if ([string]::IsNullOrWhiteSpace($AssetsDirectory)) { $AssetsDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets' }

function New-RoundedRectPath([float]$X, [float]$Y, [float]$W, [float]$H, [float]$R) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $R * 2
    $path.AddArc($X, $Y, $d, $d, 180, 90)
    $path.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
    $path.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
    $path.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-UPath {
    param([float]$Left = 62, [float]$Right = 194, [float]$Top = 66)
    # The U: two uprights joined by a half circle, in the 256-unit design grid.
    $diameter = $Right - $Left
    $center = 128
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddLine($Left, $Top, $Left, [float]$center)
    $path.AddArc($Left, [float]($center - $diameter / 2), $diameter, $diameter, [float]180, [float]-180)
    $path.AddLine($Right, [float]$center, $Right, $Top)
    return $path
}

function New-AppIconBitmap([int]$Size) {
    $bitmap = New-Object System.Drawing.Bitmap $Size, $Size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $g.Clear([System.Drawing.Color]::Transparent)
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.ScaleTransform([float]($Size / 256.0), [float]($Size / 256.0))
        $small = $Size -le 24
        $medium = $Size -le 48

        # Tile: Fluent-style rounded square with a teal-to-ocean gradient.
        $inset = if ($small) { 4 } else { 10 }
        $tile = New-RoundedRectPath $inset $inset (256 - 2 * $inset) (256 - 2 * $inset) ($(if ($small) { 52 } else { 58 }))
        $tileBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.PointF 40, 10), (New-Object System.Drawing.PointF 216, 246), ([System.Drawing.Color]::FromArgb(255, 58, 214, 226)), ([System.Drawing.Color]::FromArgb(255, 9, 104, 156))
        $g.FillPath($tileBrush, $tile)
        $tileBrush.Dispose()

        if (-not $small) {
            # Soft top highlight for depth, clipped to the tile.
            $state = $g.Save()
            $g.SetClip($tile)
            $glow = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.PointF 0, 10), (New-Object System.Drawing.PointF 0, 110), ([System.Drawing.Color]::FromArgb(38, 255, 255, 255)), ([System.Drawing.Color]::FromArgb(0, 255, 255, 255))
            $g.FillRectangle($glow, 0, 0, 256, 110)
            $glow.Dispose()
            $g.Restore($state)
            # Hairline edge so the tile holds its shape on light and dark taskbars.
            $edge = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(90, 4, 60, 92)), 2.5
            $g.DrawPath($edge, $tile)
            $edge.Dispose()
        }

        $uWidth = if ($small) { 40 } elseif ($medium) { 34 } else { 30 }
        $barWidth = if ($small) { 26 } elseif ($medium) { 21 } else { 18 }

        if (-not $small) {
            # Gentle shadow under the U and bars.
            $shadowPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(60, 3, 45, 70)), ($uWidth + 6)
            $shadowPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $shadowPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $state = $g.Save()
            $g.TranslateTransform(0, 7)
            $shadowPath = New-UPath
            $g.DrawPath($shadowPen, $shadowPath)
            $shadowPath.Dispose()
            $g.Restore($state)
            $shadowPen.Dispose()
        }

        $uPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), $uWidth
        $uPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $uPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $uPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
        # Small sizes open the U a little so three one-pixel bars keep their gaps.
        $uPath = if ($small) { New-UPath -Left 50 -Right 206 -Top 58 } else { New-UPath }
        $g.DrawPath($uPen, $uPath)
        $uPath.Dispose()
        $uPen.Dispose()

        if ($Size -le 32) {
            # Pixel-snapped bars: blurred sub-pixel strokes would merge into one blob.
            $g.ResetTransform()
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::None
            $w = if ($Size -ge 24) { 2 } else { 1 }
            $total = 3 * $w + 2
            $start = [int][Math]::Floor($Size / 2.0 - $total / 2.0 + 0.5)
            $bottom = [int][Math]::Round($Size * 140 / 256.0)
            $amber = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 250, 176, 32))
            $tops = @(72, 94, 114)
            for ($i = 0; $i -lt 3; $i++) {
                $top = [Math]::Min($bottom - 1, [int][Math]::Round($Size * $tops[$i] / 256.0))
                $g.FillRectangle($amber, $start + $i * ($w + 1), $top, $w, $bottom - $top)
            }
            $amber.Dispose()
            $tile.Dispose()
            return $bitmap
        }

        # Three descending usage bars in a warm amber gradient.
        $barBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.PointF 0, 76), (New-Object System.Drawing.PointF 0, 142), ([System.Drawing.Color]::FromArgb(255, 255, 214, 102)), ([System.Drawing.Color]::FromArgb(255, 247, 150, 18))
        $barPen = New-Object System.Drawing.Pen $barBrush, $barWidth
        $barPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $barPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        foreach ($bar in @(@(101, 82), @(128, 100), @(155, 118))) {
            $g.DrawLine($barPen, [float]$bar[0], [float]$bar[1], [float]$bar[0], [float]134)
        }
        $barPen.Dispose()
        $barBrush.Dispose()
        $tile.Dispose()
    }
    finally { $g.Dispose() }
    return $bitmap
}

function Get-PngBytes([System.Drawing.Bitmap]$Bitmap) {
    $stream = New-Object System.IO.MemoryStream
    try { $Bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png); return ,([byte[]]$stream.ToArray()) }
    finally { $stream.Dispose() }
}

function Get-DibBytes([System.Drawing.Bitmap]$Bitmap) {
    # 32-bit BGRA DIB, bottom-up, followed by an all-zero AND mask (alpha carries transparency).
    $w = $Bitmap.Width; $h = $Bitmap.Height
    $maskStride = [int]([Math]::Ceiling($w / 32.0) * 4)
    $stream = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.BinaryWriter $stream
    try {
        $writer.Write([int]40); $writer.Write([int]$w); $writer.Write([int]($h * 2))
        $writer.Write([int16]1); $writer.Write([int16]32); $writer.Write([int]0)
        $writer.Write([int]($w * $h * 4 + $maskStride * $h)); $writer.Write([int]0); $writer.Write([int]0); $writer.Write([int]0); $writer.Write([int]0)
        for ($y = $h - 1; $y -ge 0; $y--) {
            for ($x = 0; $x -lt $w; $x++) {
                $c = $Bitmap.GetPixel($x, $y)
                $writer.Write([byte]$c.B); $writer.Write([byte]$c.G); $writer.Write([byte]$c.R); $writer.Write([byte]$c.A)
            }
        }
        $writer.Write((New-Object byte[] ($maskStride * $h)))
        $writer.Flush()
        return ,([byte[]]$stream.ToArray())
    }
    finally { $writer.Dispose(); $stream.Dispose() }
}

$sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
$frames = @()
foreach ($size in $sizes) {
    $bitmap = New-AppIconBitmap $size
    try {
        [byte[]]$bytes = if ($size -ge 128) { Get-PngBytes $bitmap } else { Get-DibBytes $bitmap }
        $frames += [pscustomobject]@{ Size = $size; Bytes = $bytes }
        if ($size -eq 256) { [IO.File]::WriteAllBytes((Join-Path $AssetsDirectory 'app-icon.png'), (Get-PngBytes $bitmap)) }
    }
    finally { $bitmap.Dispose() }
}

$ico = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter $ico
try {
    $writer.Write([int16]0); $writer.Write([int16]1); $writer.Write([int16]$frames.Count)
    $offset = 6 + 16 * $frames.Count
    foreach ($frame in $frames) {
        $dimension = if ($frame.Size -ge 256) { 0 } else { $frame.Size }
        $writer.Write([byte]$dimension); $writer.Write([byte]$dimension); $writer.Write([byte]0); $writer.Write([byte]0)
        $writer.Write([int16]1); $writer.Write([int16]32); $writer.Write([int]$frame.Bytes.Length); $writer.Write([int]$offset)
        $offset += $frame.Bytes.Length
    }
    foreach ($frame in $frames) { $writer.Write($frame.Bytes) }
    $writer.Flush()
    [IO.File]::WriteAllBytes((Join-Path $AssetsDirectory 'app-icon.ico'), $ico.ToArray())
}
finally { $writer.Dispose(); $ico.Dispose() }

if (-not [string]::IsNullOrWhiteSpace($PreviewPath)) {
    # Review board: every size on light and dark taskbar colours, plus a 4x zoom of the small sizes.
    $board = New-Object System.Drawing.Bitmap 1040, 420
    $g = [System.Drawing.Graphics]::FromImage($board)
    try {
        $g.Clear([System.Drawing.Color]::FromArgb(243, 243, 243))
        $g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(32, 32, 32))), 0, 210, 1040, 210)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
        foreach ($band in @(0, 210)) {
            $x = 20
            foreach ($size in @(256, 64, 48, 32, 24, 16)) {
                $bmp = New-AppIconBitmap $size
                $show = if ($size -eq 256) { 170 } else { $size }
                $g.DrawImage($bmp, $x, $band + [int]((210 - $show) / 2), $show, $show)
                $x += $show + 24
                if ($size -le 32) {
                    $zoomX = switch ($size) { 24 { 690 } 16 { 800 } default { 880 } }
                    $g.DrawImage($bmp, $zoomX, $band + 41, $size * 4, $size * 4)
                }
                $bmp.Dispose()
            }
        }
        $board.Save($PreviewPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally { $g.Dispose(); $board.Dispose() }
}
[pscustomobject]@{ Ico = (Join-Path $AssetsDirectory 'app-icon.ico'); Png = (Join-Path $AssetsDirectory 'app-icon.png'); Sizes = ($sizes -join ',') }
