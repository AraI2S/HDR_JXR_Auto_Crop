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

    if ([Math]::Abs($current - $ratio) -lt 0.0000000001) {
        return [pscustomobject]@{ X=0; Y=0; W=$w; H=$h }
    }

    if ($current -gt $ratio) {
        $ideal = $h * $ratio
        $a = [Math]::Max(1, [int][Math]::Floor($ideal))
        $b = [Math]::Max(1, [int][Math]::Ceiling($ideal))
        $errA = [Math]::Abs(($a / [double]$h) - $ratio)
        $errB = [Math]::Abs(($b / [double]$h) - $ratio)
        $newW = if ($errB -lt $errA) { $b } else { $a }
        if ($newW -gt $w) { $newW = $w }
        $x = [int][Math]::Floor(($w - $newW) / 2.0)
        return [pscustomobject]@{ X=$x; Y=0; W=$newW; H=$h }
    }
    else {
        $ideal = $w / $ratio
        $a = [Math]::Max(1, [int][Math]::Floor($ideal))
        $b = [Math]::Max(1, [int][Math]::Ceiling($ideal))
        $errA = [Math]::Abs(($w / [double]$a) - $ratio)
        $errB = [Math]::Abs(($w / [double]$b) - $ratio)
        $newH = if ($errB -lt $errA) { $b } else { $a }
        if ($newH -gt $h) { $newH = $h }
        $y = [int][Math]::Floor(($h - $newH) / 2.0)
        return [pscustomobject]@{ X=0; Y=$y; W=$w; H=$newH }
    }
}

function Get-ImageKind([string]$path) {
    switch ([IO.Path]::GetExtension($path).ToLowerInvariant()) {
        '.jxr'  { return 'JXR' }
        '.png'  { return 'PNG' }
        '.jpg'  { return 'JPEG' }
        '.jpeg' { return 'JPEG' }
        default { throw "Unsupported image type: $path" }
    }
}

function Decode-Image([string]$path) {
    $kind = Get-ImageKind $path
    $stream = [IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $options = [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat
        $cache   = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        switch ($kind) {
            'JXR'  { $decoder = [System.Windows.Media.Imaging.WmpBitmapDecoder]::new($stream,$options,$cache) }
            'PNG'  { $decoder = [System.Windows.Media.Imaging.PngBitmapDecoder]::new($stream,$options,$cache) }
            'JPEG' { $decoder = [System.Windows.Media.Imaging.JpegBitmapDecoder]::new($stream,$options,$cache) }
        }
        return $decoder.Frames[0]
    }
    finally { $stream.Dispose() }
}

function Get-ColorContextsSafe($sourceFrame) {
    try {
        $contexts = $sourceFrame.ColorContexts
        if ($null -ne $contexts -and $contexts.Count -gt 0) { return $contexts }
    }
    catch { }
    return $null
}

function Save-EncoderToFile($encoder,[string]$path) {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    $stream = [IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $encoder.Save($stream) }
    finally { $stream.Dispose() }
}

function New-FrameWithOptionalColorContext($crop,$sourceFrame,[bool]$tryColorContext) {
    if ($tryColorContext) {
        $contexts = Get-ColorContextsSafe $sourceFrame
        if ($null -ne $contexts) {
            return [System.Windows.Media.Imaging.BitmapFrame]::Create($crop,$null,$null,$contexts)
        }
    }
    return [System.Windows.Media.Imaging.BitmapFrame]::Create($crop)
}

function Save-Jxr([string]$path,$crop,[bool]$compressedDomain) {
    $encoder = [System.Windows.Media.Imaging.WmpBitmapEncoder]::new()
    $encoder.UseCodecOptions = $true
    $encoder.CompressedDomainTranscode = $compressedDomain
    $encoder.Lossless = $true
    $encoder.ImageDataDiscardLevel = 0
    $encoder.AlphaDataDiscardLevel = 0
    $encoder.HorizontalTileSlices = 0
    $encoder.VerticalTileSlices = 0
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($crop))
    Save-EncoderToFile $encoder $path
}

function Save-Png([string]$path,$crop,$sourceFrame) {
    try {
        $encoder = [System.Windows.Media.Imaging.PngBitmapEncoder]::new()
        $encoder.Frames.Add((New-FrameWithOptionalColorContext $crop $sourceFrame $true))
        Save-EncoderToFile $encoder $path
    }
    catch {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        $encoder = [System.Windows.Media.Imaging.PngBitmapEncoder]::new()
        $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($crop))
        Save-EncoderToFile $encoder $path
    }
}

function Save-Jpeg([string]$path,$crop,$sourceFrame) {
    try {
        $encoder = [System.Windows.Media.Imaging.JpegBitmapEncoder]::new()
        $encoder.QualityLevel = 100
        $encoder.Frames.Add((New-FrameWithOptionalColorContext $crop $sourceFrame $true))
        Save-EncoderToFile $encoder $path
    }
    catch {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        $encoder = [System.Windows.Media.Imaging.JpegBitmapEncoder]::new()
        $encoder.QualityLevel = 100
        $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($crop))
        Save-EncoderToFile $encoder $path
    }
}

if (-not (Test-Path -LiteralPath $inputDir -PathType Container)) {
    Write-Host 'ERROR: Input folder "i" does not exist.' -ForegroundColor Red
    Write-Host ('Create this folder: ' + $inputDir)
    exit 1
}

$files = @(
    Get-ChildItem -LiteralPath $inputDir -File |
    Where-Object {
        $_.Extension -ieq '.jxr' -or
        $_.Extension -ieq '.png' -or
        $_.Extension -ieq '.jpg' -or
        $_.Extension -ieq '.jpeg'
    } |
    Sort-Object {
        if ($_.BaseName -match '^(.*?)(\d+)\D*$') {
            '{0}{1:D12}' -f $matches[1], [int64]$matches[2]
        }
        else { $_.Name }
    }
)

if ($files.Count -eq 0) {
    Write-Host 'No supported image files were found in the input folder "i".' -ForegroundColor Yellow
    exit 2
}

$ratio = Read-TargetRatio
$ratioText = $ratio.ToString('0.########',[Globalization.CultureInfo]::InvariantCulture)

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
    $kind = Get-ImageKind $file.FullName
    $outputPath = Join-Path $outputDir $file.Name
    $tempName = '.__crop_' + [Guid]::NewGuid().ToString('N') + $file.Extension
    $tempPath = Join-Path $outputDir $tempName

    Write-Host ("========== [{0}/{1}] {2} ==========" -f ($index + 1),$files.Count,$file.Name)

    try {
        $src = Decode-Image $file.FullName
        $w = $src.PixelWidth
        $h = $src.PixelHeight
        $sourceBpp = $src.Format.BitsPerPixel
        $sourceFormat = $src.Format.ToString()
        $r = Get-BestCrop $w $h $ratio

        if ($r.W -le 0 -or $r.H -le 0 -or $r.X -lt 0 -or $r.Y -lt 0 -or ($r.X + $r.W) -gt $w -or ($r.Y + $r.H) -gt $h) {
            throw "Invalid crop rectangle X=$($r.X) Y=$($r.Y) W=$($r.W) H=$($r.H) for ${w}x${h}."
        }

        $rect = [System.Windows.Int32Rect]::new($r.X,$r.Y,$r.W,$r.H)
        $crop = [System.Windows.Media.Imaging.CroppedBitmap]::new($src,$rect)
        $actualRatio = $r.W / [double]$r.H

        Write-Host ("Input : {0}x{1} | {2} | {3} bpp" -f $w,$h,$sourceFormat,$sourceBpp)
        Write-Host ("Crop  : X={0} Y={1} W={2} H={3} | ratio={4}" -f $r.X,$r.Y,$r.W,$r.H,([Math]::Round($actualRatio,6)))

        $mode = $null
        switch ($kind) {
            'JXR' {
                try {
                    Save-Jxr $tempPath $crop $true
                    $mode = 'compressed-domain transcode'
                    $compressedCount++
                }
                catch {
                    if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
                    Write-Host 'Compressed-domain save failed; using lossless fallback.' -ForegroundColor DarkYellow
                    Save-Jxr $tempPath $crop $false
                    $mode = 'lossless floating-point re-encode'
                    $fallbackCount++
                }
            }
            'PNG' {
                Save-Png $tempPath $crop $src
                $mode = 'lossless PNG encode'
            }
            'JPEG' {
                Save-Jpeg $tempPath $crop $src
                $mode = 'JPEG quality 100 encode'
            }
        }

        $verify = Decode-Image $tempPath
        if ($verify.PixelWidth -ne $r.W -or $verify.PixelHeight -ne $r.H) {
            throw "Verification failed: output is $($verify.PixelWidth)x$($verify.PixelHeight), expected $($r.W)x$($r.H)."
        }

        if (($kind -eq 'JXR' -or $kind -eq 'PNG') -and $verify.Format.BitsPerPixel -ne $sourceBpp) {
            throw "Verification failed: source is $sourceBpp bpp, output is $($verify.Format.BitsPerPixel) bpp."
        }

        if (Test-Path -LiteralPath $outputPath) { Remove-Item -LiteralPath $outputPath -Force }
        Move-Item -LiteralPath $tempPath -Destination $outputPath

        Write-Host ('Mode  : ' + $mode)
        Write-Host ('Saved : ' + $outputPath)
        Write-Host ''
        $success++
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
        $failed += $file.Name
        Write-Host ('FAILED: ' + $_.Exception.Message) -ForegroundColor Red
        Write-Host ''
    }
}

Write-Host '=================================================='
Write-Host ("Finished. Success: {0}  Failed: {1}" -f $success,$failed.Count)
Write-Host ("Compressed-domain: {0}" -f $compressedCount)
Write-Host ("Lossless fallback : {0}" -f $fallbackCount)

if ($failed.Count -gt 0) {
    Write-Host ('Failed files: ' + ($failed -join ', ')) -ForegroundColor Yellow
    exit 3
}
