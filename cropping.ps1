$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Working folder = folder containing this script.
# Input files are read only from .\i
# Finished files are written directly to this working folder.
$baseDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$inputDir  = Join-Path $baseDir 'i'
$outputDir = $baseDir

function Read-TargetRatio {
    while ($true) {
        Write-Host ''
        Write-Host 'Choose target aspect ratio:'
        Write-Host '  [1] 1.5:1'
        Write-Host '  [2] 1.78:1'
        Write-Host '  [3] 1.85:1'
        Write-Host '  [4] 1.9:1'
        Write-Host '  [5] 2.2:1'
        Write-Host '  [6] 2.39:1'
        Write-Host '  [7] 2.55:1'
        Write-Host '  [8] 2.76:1'
        Write-Host '  [X] Custom X:1'
        Write-Host ''

        $choice = (Read-Host 'Selection').Trim()

        switch -Regex ($choice) {
            '^(1|1\.5|1\.50)$' { return 1.50 }
            '^(2|1\.78)$'      { return 1.78 }
            '^(3|1\.85)$'      { return 1.85 }
            '^(4|1\.9|1\.90)$' { return 1.90 }
            '^(5|2\.2|2\.20)$' { return 2.20 }
            '^(6|2\.39)$'      { return 2.39 }
            '^(7|2\.55)$'      { return 2.55 }
            '^(8|2\.76)$'      { return 2.76 }

            '^[xX]$' {
                while ($true) {
                    $raw = (Read-Host 'Enter X for X:1 (example: 2.00)').Trim()
                    $value = 0.0

                    $ok = [double]::TryParse(
                        $raw,
                        [Globalization.NumberStyles]::Float,
                        [Globalization.CultureInfo]::InvariantCulture,
                        [ref]$value
                    )

                    if (-not $ok) {
                        $ok = [double]::TryParse($raw, [ref]$value)
                    }

                    if ($ok -and $value -gt 0.0) {
                        return $value
                    }

                    Write-Host 'Invalid ratio. Enter a positive number such as 2.00.' -ForegroundColor Yellow
                }
            }

            default {
                Write-Host 'Invalid selection. Use 1-8, X, or type one of the preset ratios directly.' -ForegroundColor Yellow
            }
        }
    }
}

function Get-BestCrop([int]$w, [int]$h, [double]$ratio) {
    $current = $w / [double]$h

    # Already at the requested ratio to floating-point precision.
    if ([Math]::Abs($current - $ratio) -lt 0.0000000001) {
        return [pscustomobject]@{
            X = 0
            Y = 0
            W = $w
            H = $h
        }
    }

    if ($current -gt $ratio) {
        # Too wide: preserve full height, crop left/right.
        $ideal = $h * $ratio
        $a = [Math]::Max(1, [int][Math]::Floor($ideal))
        $b = [Math]::Max(1, [int][Math]::Ceiling($ideal))

        $errA = [Math]::Abs(($a / [double]$h) - $ratio)
        $errB = [Math]::Abs(($b / [double]$h) - $ratio)
        $newW = if ($errB -lt $errA) { $b } else { $a }

        if ($newW -gt $w) { $newW = $w }

        $x = [int][Math]::Floor(($w - $newW) / 2.0)

        return [pscustomobject]@{
            X = $x
            Y = 0
            W = $newW
            H = $h
        }
    }
    else {
        # Too tall: preserve full width, crop top/bottom.
        $ideal = $w / $ratio
        $a = [Math]::Max(1, [int][Math]::Floor($ideal))
        $b = [Math]::Max(1, [int][Math]::Ceiling($ideal))

        $errA = [Math]::Abs(($w / [double]$a) - $ratio)
        $errB = [Math]::Abs(($w / [double]$b) - $ratio)
        $newH = if ($errB -lt $errA) { $b } else { $a }

        if ($newH -gt $h) { $newH = $h }

        $y = [int][Math]::Floor(($h - $newH) / 2.0)

        return [pscustomobject]@{
            X = 0
            Y = $y
            W = $w
            H = $newH
        }
    }
}

function Decode-Jxr([string]$path) {
    $stream = [IO.File]::Open(
        $path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::Read
    )

    try {
        $decoder = [System.Windows.Media.Imaging.WmpBitmapDecoder]::new(
            $stream,
            [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,
            [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        )

        return $decoder.Frames[0]
    }
    finally {
        $stream.Dispose()
    }
}

function Save-Jxr([string]$path, $crop, [bool]$compressedDomain) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
    }

    $encoder = [System.Windows.Media.Imaging.WmpBitmapEncoder]::new()
    $encoder.UseCodecOptions = $true
    $encoder.CompressedDomainTranscode = $compressedDomain
    $encoder.Lossless = $true
    $encoder.ImageDataDiscardLevel = 0
    $encoder.AlphaDataDiscardLevel = 0
    $encoder.HorizontalTileSlices = 0
    $encoder.VerticalTileSlices = 0

    # Keep the already-tested clean frame path.
    # Do not attach source Metadata / Thumbnail / ColorContexts here:
    # they can retain invalid native decoder handles after the source
    # stream has been closed.
    $encoder.Frames.Add(
        [System.Windows.Media.Imaging.BitmapFrame]::Create($crop)
    )

    $stream = [IO.File]::Open(
        $path,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None
    )

    try {
        $encoder.Save($stream)
    }
    finally {
        $stream.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $inputDir -PathType Container)) {
    Write-Host 'ERROR: Input folder "i" does not exist.' -ForegroundColor Red
    Write-Host ('Create this folder: ' + $inputDir)
    exit 1
}

$files = @(
    Get-ChildItem -LiteralPath $inputDir -File |
    Where-Object { $_.Extension -ieq '.jxr' } |
    Sort-Object {
        # Natural-ish sort: text + final numeric group if present.
        if ($_.BaseName -match '^(.*?)(\d+)\D*$') {
            '{0}{1:D12}' -f $matches[1], [int64]$matches[2]
        }
        else {
            $_.Name
        }
    }
)

if ($files.Count -eq 0) {
    Write-Host 'No .jxr files were found in the input folder "i".' -ForegroundColor Yellow
    exit 2
}

$ratio = Read-TargetRatio
$ratioText = $ratio.ToString('0.########', [Globalization.CultureInfo]::InvariantCulture)

Write-Host ''
Write-Host ('Target : ' + $ratioText + ':1')
Write-Host ('Input  : ' + $inputDir)
Write-Host ('Output : ' + $outputDir)
Write-Host ('Files  : ' + $files.Count)
Write-Host ''

$success = 0
$failed = @()
$compressedCount = 0
$fallbackCount = 0

for ($index = 0; $index -lt $files.Count; $index++) {
    $file = $files[$index]

    # Output filename is strictly identical to the input filename.
    $outputPath = Join-Path $outputDir $file.Name

    # Generate to a temporary JXR first. The final same-name file is
    # replaced only after the new file passes verification.
    $tempName = '.__jxrcrop_' + [Guid]::NewGuid().ToString('N') + '.jxr'
    $tempPath = Join-Path $outputDir $tempName

    Write-Host ("========== [{0}/{1}] {2} ==========" -f ($index + 1), $files.Count, $file.Name)

    try {
        $src = Decode-Jxr $file.FullName

        $w = $src.PixelWidth
        $h = $src.PixelHeight
        $sourceBpp = $src.Format.BitsPerPixel
        $sourceFormat = $src.Format.ToString()

        $r = Get-BestCrop $w $h $ratio

        if (
            $r.W -le 0 -or $r.H -le 0 -or
            $r.X -lt 0 -or $r.Y -lt 0 -or
            ($r.X + $r.W) -gt $w -or
            ($r.Y + $r.H) -gt $h
        ) {
            throw "Invalid crop rectangle X=$($r.X) Y=$($r.Y) W=$($r.W) H=$($r.H) for ${w}x${h}."
        }

        $rect = [System.Windows.Int32Rect]::new(
            $r.X, $r.Y, $r.W, $r.H
        )

        $crop = [System.Windows.Media.Imaging.CroppedBitmap]::new(
            $src, $rect
        )

        $actualRatio = $r.W / [double]$r.H

        Write-Host ("Input : {0}x{1} | {2} | {3} bpp" -f $w, $h, $sourceFormat, $sourceBpp)
        Write-Host ("Crop  : X={0} Y={1} W={2} H={3} | ratio={4}" -f `
            $r.X, $r.Y, $r.W, $r.H, ([Math]::Round($actualRatio, 6)))

        $mode = $null

        try {
            Save-Jxr $tempPath $crop $true
            $mode = 'compressed-domain transcode'
            $compressedCount++
        }
        catch {
            if (Test-Path -LiteralPath $tempPath) {
                Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
            }

            Write-Host 'Compressed-domain save failed; using lossless fallback.' -ForegroundColor DarkYellow

            Save-Jxr $tempPath $crop $false
            $mode = 'lossless floating-point re-encode'
            $fallbackCount++
        }

        # Verify the new file before touching an existing final output.
        $verify = Decode-Jxr $tempPath

        if (
            $verify.PixelWidth -ne $r.W -or
            $verify.PixelHeight -ne $r.H
        ) {
            throw "Verification failed: output is $($verify.PixelWidth)x$($verify.PixelHeight), expected $($r.W)x$($r.H)."
        }

        if ($verify.Format.BitsPerPixel -ne $sourceBpp) {
            throw "Verification failed: source is $sourceBpp bpp, output is $($verify.Format.BitsPerPixel) bpp."
        }

        if (Test-Path -LiteralPath $outputPath) {
            Remove-Item -LiteralPath $outputPath -Force
        }

        Move-Item -LiteralPath $tempPath -Destination $outputPath

        Write-Host ('Mode  : ' + $mode)
        Write-Host ('Saved : ' + $outputPath)
        Write-Host ''

        $success++
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }

        $failed += $file.Name
        Write-Host ('FAILED: ' + $_.Exception.Message) -ForegroundColor Red
        Write-Host ''
    }
}

Write-Host '=================================================='
Write-Host ("Finished. Success: {0}  Failed: {1}" -f $success, $failed.Count)
Write-Host ("Compressed-domain: {0}" -f $compressedCount)
Write-Host ("Lossless fallback : {0}" -f $fallbackCount)

if ($failed.Count -gt 0) {
    Write-Host ('Failed files: ' + ($failed -join ', ')) -ForegroundColor Yellow
    exit 3
}
