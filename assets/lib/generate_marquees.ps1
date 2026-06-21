param(
    [Parameter(Mandatory=$true)][string]$VideoPath,
    [Parameter(Mandatory=$true)][string]$DownloadDir,
    [string]$Standard = 'false',
    [string]$FullColor = 'false'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$GenerateStandard = $Standard -match '^(1|true|yes|on)$'
$GenerateFullColor = $FullColor -match '^(1|true|yes|on)$'
if (-not $GenerateStandard -and -not $GenerateFullColor) { return }
if (-not (Test-Path -LiteralPath $VideoPath)) { throw "Video not found: $VideoPath" }

Add-Type -AssemblyName System.Drawing
$AssetsDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$InternalRoot = Split-Path -Parent $AssetsDir
$PackageRoot = Split-Path -Parent $InternalRoot
$ResourceDir = Join-Path $PackageRoot 'resources'
$StandardLayerDir = Join-Path $AssetsDir 'images\marquee_template_layers'
$StandardLayerBgPath = Join-Path $StandardLayerDir 'marqueeTemplate_BG.png'
$StandardLayerFgPath = Join-Path $StandardLayerDir 'marqueeTemplate_FG.png'
$StandardLayerMidTextPath = Join-Path $StandardLayerDir 'marqueeTemplate_Mid_Text.png'
$FallbackLogoPath = Join-Path $AssetsDir 'images\one_sauce_merged.png'
$CacheDir = Join-Path $AssetsDir 'resources\cache\album_art'
$MetadataCacheDir = Join-Path $AssetsDir 'resources\cache\musicbrainz_metadata'
$ArtistArtCacheDir = Join-Path $AssetsDir 'resources\cache\artist_art'
$AlbumArtLookupScript = Join-Path $AssetsDir 'lib\album_art_lookup.ps1'
$MusicBrainzMetadataScript = Join-Path $AssetsDir 'lib\musicbrainz_metadata_lookup.ps1'
$ArtistArtLookupScript = Join-Path $AssetsDir 'lib\artist_art_lookup.ps1'
$FanartProjectKeyPath = Join-Path $ResourceDir 'fanart_project_api_key.txt'
$FanartPersonalKeyPath = Join-Path $ResourceDir 'fanart_personal_api_key.txt'
$PrivateFonts = New-Object Drawing.Text.PrivateFontCollection
$FontFiles = @(
    (Join-Path $AssetsDir 'fonts\BebasNeue\BebasNeue-Regular.ttf'),
    (Join-Path $AssetsDir 'fonts\BebasNeue\BebasNeue-Bold.ttf'),
    (Join-Path $AssetsDir 'fonts\Anton\Anton-Regular.ttf')
)
foreach ($fontPath in $FontFiles) {
    if (Test-Path -LiteralPath $fontPath) { $PrivateFonts.AddFontFile($fontPath) }
}
$baseName = [IO.Path]::GetFileNameWithoutExtension($VideoPath)
$marqueeRoot = Join-Path $DownloadDir 'marquee'
if ($GenerateStandard) { New-Item -ItemType Directory -Path $marqueeRoot -Force | Out-Null }

$tempDir = Join-Path ([IO.Path]::GetTempPath()) ('jdw_marquee_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$framePath = Join-Path $tempDir 'frame.png'

function Repair-TextEncoding {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $Value = $Value -replace ([string][char]0xfffd + '\??'), ''
    $Value = $Value -replace [string][char]0xfffd, ''
    $Value = $Value -replace ([string][char]0x00e2 + [char]0x0080 + [char]0x0099), "'"
    $Value = $Value -replace ([string][char]0x00e2 + [char]0x0080 + [char]0x0098), "'"
    $Value = $Value -replace ([string][char]0x00e2 + [char]0x0080 + [char]0x009c), '"'
    $Value = $Value -replace ([string][char]0x00e2 + [char]0x0080 + [char]0x009d), '"'
    $Value = $Value -replace ([string][char]0x00e2 + [char]0x0080 + [char]0x0090), '-'
    $Value = $Value -replace ([string][char]0x00e2 + [char]0x0080 + [char]0x0091), '-'
    $Value = $Value -replace ([string][char]0x00e2 + [char]0x0080 + [char]0x0092), '-'
    $Value = $Value -replace ([string][char]0x00e2 + [char]0x0080 + [char]0x0093), '-'
    $Value = $Value -replace ([string][char]0x00e2 + [char]0x0080 + [char]0x0094), '-'
    if ($Value.IndexOf([char]0x00c3) -lt 0 -and $Value.IndexOf([char]0x00c2) -lt 0) { return $Value }
    try {
        $bytes = [Text.Encoding]::GetEncoding(1252).GetBytes($Value)
        $fixed = [Text.Encoding]::UTF8.GetString($bytes)
        if (-not [string]::IsNullOrWhiteSpace($fixed)) { return $fixed }
    }
    catch {
    }
    return $Value
}
function Draw-ImageAtFullHeight {
    param(
        [Drawing.Graphics]$Graphics,
        [Drawing.Image]$Image,
        [Drawing.Rectangle]$TargetRect
    )

    $destRect = New-Object Drawing.Rectangle $TargetRect.X, $TargetRect.Y, $TargetRect.Width, $TargetRect.Height
    $Graphics.DrawImage($Image, $destRect)
}

function Draw-ImageFileAtFullHeight {
    param(
        [Drawing.Graphics]$Graphics,
        [string]$Path,
        [Drawing.Rectangle]$TargetRect
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $image = [Drawing.Image]::FromFile($Path)
        try { Draw-ImageAtFullHeight -Graphics $Graphics -Image $image -TargetRect $TargetRect }
        finally { $image.Dispose() }
        return $true
    }
    catch {
        return $false
    }
}

function Draw-FallbackLogo {
    param(
        [Drawing.Graphics]$Graphics,
        [Drawing.Rectangle]$TargetRect
    )
    return Draw-ImageFileAtFullHeight -Graphics $Graphics -Path $FallbackLogoPath -TargetRect $TargetRect
}

function Format-MarqueeDuration {
    param([double]$Seconds)
    if (-not $Seconds -or $Seconds -lt 0) { $Seconds = 0 }
    $span = [TimeSpan]::FromSeconds([int][Math]::Round($Seconds))
    if ($span.TotalHours -ge 1) {
        return '{0}:{1:00}:{2:00}' -f [int][Math]::Floor($span.TotalHours), $span.Minutes, $span.Seconds
    }
    return '{0}:{1:00}' -f [int]$span.TotalMinutes, $span.Seconds
}

function Get-VideoStats {
    param([string]$Path)
    $result = @{ Length = '0:00'; Resolution = 'UNKNOWN' }
    try {
        $durationText = (& ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 $Path 2>$null | Select-Object -First 1)
        if ($durationText) { $result.Length = Format-MarqueeDuration ([double]$durationText) }
    } catch {}

    try {
        $heightText = (& ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nk=1:nw=1 $Path 2>$null | Select-Object -First 1)
        if ($heightText) {
            $height = [int]$heightText
            if ($height -ge 1000) { $result.Resolution = '1080p' }
            elseif ($height -ge 600) { $result.Resolution = '720p' }
            elseif ($height -ge 400) { $result.Resolution = '480p' }
            else { $result.Resolution = ($height.ToString() + 'p') }
        }
    } catch {}
    return $result
}

function Get-AlbumCoverPath {
    param([hashtable]$Parts)
    if (-not (Test-Path -LiteralPath $AlbumArtLookupScript)) { return '' }
    try {
        if ([string]::IsNullOrWhiteSpace($Parts['Title']) -and [string]::IsNullOrWhiteSpace($Parts['ReleaseMbid'])) { return '' }
        $cover = & powershell -NoProfile -ExecutionPolicy Bypass -File $AlbumArtLookupScript -Artist $Parts['Artist'] -Title $Parts['Title'] -CacheDir $CacheDir -ReleaseMbid $Parts['ReleaseMbid'] 2>$null | Select-Object -First 1
        if ($cover -and (Test-Path -LiteralPath $cover)) { return [string]$cover }
    }
    catch {
    }
    return ''
}
function Get-MusicBrainzTextParts {
    param([hashtable]$Parts)
    if (-not (Test-Path -LiteralPath $MusicBrainzMetadataScript)) { return $Parts }
    try {
        if ([string]::IsNullOrWhiteSpace($Parts['Title'])) { return $Parts }
        $json = & powershell -NoProfile -ExecutionPolicy Bypass -File $MusicBrainzMetadataScript -Artist $Parts['Artist'] -Title $Parts['Title'] -CacheDir $MetadataCacheDir 2>$null | Select-Object -First 1
        if ([string]::IsNullOrWhiteSpace($json)) { return $Parts }
        $metadata = $json | ConvertFrom-Json
        $artist = Clean-MarqueeText ([string]$Parts['Artist'])
        $title = Clean-MarqueeTitle ([string]$Parts['Title'])
        $metadataArtist = Clean-MarqueeText ([string]$metadata.Artist)
        $metadataTitle = Clean-MarqueeTitle ([string]$metadata.Title)
        $releaseTitle = Clean-MarqueeText ([string]$metadata.ReleaseTitle)
        if (($artist -ieq 'UNKNOWN ARTIST' -or [string]::IsNullOrWhiteSpace($artist)) -and -not [string]::IsNullOrWhiteSpace($metadataArtist)) { $artist = $metadataArtist }
        if ([string]::IsNullOrWhiteSpace($title) -and -not [string]::IsNullOrWhiteSpace($metadataTitle)) { $title = $metadataTitle }
        if ($releaseTitle -ieq $title -or $releaseTitle -ieq $artist) { $releaseTitle = '' }
        return @{
            Artist = $artist.Trim().ToUpperInvariant()
            Title = $title.Trim().ToUpperInvariant()
            ReleaseTitle = $releaseTitle.Trim().ToUpperInvariant()
            ReleaseYear = (Get-ReleaseYear ([string]$metadata.ReleaseDate))
            ArtistMbid = ([string]$metadata.ArtistMbid).Trim()
            ReleaseMbid = ([string]$metadata.ReleaseMbid).Trim()
        }
    }
    catch {
    }
    return $Parts
}
function Clean-MarqueeText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $clean = Repair-TextEncoding $Text
    $noiseWords = 'official\s+music\s+video|official\s+video|official\s+audio|official\s+lyric\s+video|lyric\s+video|lyrics?|visuali[sz]er|music\s+video|audio|hd|4k|remaster(?:ed)?|karaoke|unreleased\s+video|new\s+unreleased\s+video|new\s+video|video'
    $clean = $clean -replace ('(?i)\s*[\[\(\{][^\]\)\}]*\b(' + $noiseWords + ')\b[^\]\)\}]*[\]\)\}]'), ''
    $clean = $clean -replace ('(?i)\s+[-|:]\s*(' + $noiseWords + ')\b.*$'), ''
    $clean = $clean -replace ('(?i)\b(' + $noiseWords + ')\b'), ''
    $clean = $clean -replace '\s+', ' '
    $clean = $clean.Trim(' ', '-', '|', ':', '.', '_')
    return $clean
}

function Clean-MarqueeTitle {
    param([string]$Text)
    $clean = Clean-MarqueeText $Text
    $clean = $clean -replace '(?i)\s+\b(ft\.?|feat\.?|featuring)\b\.?\s+.*$', ''
    $clean = $clean -replace '\s+', ' '
    return $clean.Trim(' ', '-', '|', ':', '.', '_')
}

function Get-ReleaseYear {
    param([string]$ReleaseDate)
    if ($ReleaseDate -match '(19|20)\d{2}') { return $Matches[0] }
    return 'UNKNOWN'
}

function Get-TextParts {
    param([string]$Name)
    $artist = 'UNKNOWN ARTIST'
    $title = $Name
    $parts = $Name -split '\s+-\s+', 2
    if ($parts.Count -eq 2) {
        $artist = $parts[0]
        $title = $parts[1]
    }
    $artist = Clean-MarqueeText $artist
    $title = Clean-MarqueeTitle $title
    return @{ Artist = $artist.Trim().ToUpperInvariant(); Title = $title.Trim().ToUpperInvariant(); ReleaseTitle = ''; ReleaseYear = 'UNKNOWN'; ArtistMbid = ''; ReleaseMbid = '' }
}

function Split-ArtistCandidates {
    param([string]$Artist)
    if ([string]::IsNullOrWhiteSpace($Artist)) { return @() }

    $clean = $Artist -replace '(?i)\s+\b(ft\.?|feat\.?|featuring)\b\.?\s+', ' & '
    $clean = $clean -replace '(?i)\s+\b(with|and|x)\b\s+', ' & '
    $parts = @($clean -split '\s*&\s+' | ForEach-Object {
        $candidate = Clean-MarqueeText $_
        $candidate.Trim()
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -ine 'UNKNOWN ARTIST' })

    return @($parts | Select-Object -Unique)
}

function Find-ArtistMbidByName {
    param([string]$Artist)
    if ([string]::IsNullOrWhiteSpace($Artist)) { return '' }

    try {
        $encodedArtist = [Uri]::EscapeDataString(('artist:"{0}"' -f $Artist))
        $uri = 'https://musicbrainz.org/ws/2/artist/?query={0}&fmt=json&limit=1' -f $encodedArtist
        $headers = @{ 'User-Agent' = 'JukeboxDownloadWizard/0.2.3.2 (marquee metadata lookup)' }
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 15
        if ($response.artists -and $response.artists.Count -gt 0 -and $response.artists[0].id) {
            return [string]$response.artists[0].id
        }
    }
    catch {
    }

    return ''
}

function Get-ArtistArtPath {
    param([hashtable]$Parts)
    if (-not (Test-Path -LiteralPath $ArtistArtLookupScript)) { return '' }
    try {
        if (-not [string]::IsNullOrWhiteSpace($Parts['ArtistMbid'])) {
            $art = & powershell -NoProfile -ExecutionPolicy Bypass -File $ArtistArtLookupScript -ArtistMbid $Parts['ArtistMbid'] -Artist $Parts['Artist'] -CacheDir $ArtistArtCacheDir -ProjectKeyPath $FanartProjectKeyPath -PersonalKeyPath $FanartPersonalKeyPath 2>$null | Select-Object -First 1
            if ($art -and (Test-Path -LiteralPath $art)) { return [string]$art }
        }

        foreach ($artistName in (Split-ArtistCandidates $Parts['Artist'])) {
            $artistMbid = Find-ArtistMbidByName $artistName
            if ([string]::IsNullOrWhiteSpace($artistMbid)) { continue }
            $art = & powershell -NoProfile -ExecutionPolicy Bypass -File $ArtistArtLookupScript -ArtistMbid $artistMbid -Artist $artistName -CacheDir $ArtistArtCacheDir -ProjectKeyPath $FanartProjectKeyPath -PersonalKeyPath $FanartPersonalKeyPath 2>$null | Select-Object -First 1
            if ($art -and (Test-Path -LiteralPath $art)) { return [string]$art }
        }
    }
    catch {
    }
    return ''
}

function Mix-Color {
    param([Drawing.Color]$A, [Drawing.Color]$B, [double]$Amount)
    $red = [int]($A.R + (($B.R - $A.R) * $Amount))
    $green = [int]($A.G + (($B.G - $A.G) * $Amount))
    $blueValue = [int]($A.B + (($B.B - $A.B) * $Amount))
    return [Drawing.Color]::FromArgb($red, $green, $blueValue)
}

function Get-ReadableTextColor {
    param([Drawing.Color]$Color)
    $luma = (0.2126 * $Color.R) + (0.7152 * $Color.G) + (0.0722 * $Color.B)
    if ($luma -gt 145) { return [Drawing.Color]::FromArgb(18, 24, 38) }
    return [Drawing.Color]::White
}

function Get-DefaultPalette {
    return @{ Primary = [Drawing.Color]::FromArgb(37, 99, 235); Accent = [Drawing.Color]::FromArgb(250, 204, 21); Dark = [Drawing.Color]::FromArgb(15, 23, 42); Light = [Drawing.Color]::FromArgb(226, 232, 240) }
}

function Get-ColorDistance {
    param([Drawing.Color]$A, [Drawing.Color]$B)
    $dr = $A.R - $B.R
    $dg = $A.G - $B.G
    $db = $A.B - $B.B
    return [Math]::Sqrt(($dr * $dr) + ($dg * $dg) + ($db * $db))
}

function Get-FramePalette {
    param([string]$ImagePath)
    if (-not (Test-Path -LiteralPath $ImagePath)) { return Get-DefaultPalette }
    try { $bmp = [Drawing.Bitmap]::FromFile($ImagePath) }
    catch { return Get-DefaultPalette }
    try {
        $buckets = @{}
        $stepX = [Math]::Max(1, [int]($bmp.Width / 48))
        $stepY = [Math]::Max(1, [int]($bmp.Height / 32))
        for ($y = 0; $y -lt $bmp.Height; $y += $stepY) {
            for ($x = 0; $x -lt $bmp.Width; $x += $stepX) {
                $c = $bmp.GetPixel($x, $y)
                $max = [Math]::Max($c.R, [Math]::Max($c.G, $c.B))
                $min = [Math]::Min($c.R, [Math]::Min($c.G, $c.B))
                $chroma = $max - $min
                $luma = (0.2126 * $c.R) + (0.7152 * $c.G) + (0.0722 * $c.B)
                if ($chroma -lt 28 -or $luma -lt 35 -or $luma -gt 232) { continue }

                $bucketR = [Math]::Min(255, [int]([Math]::Round($c.R / 32.0) * 32))
                $bucketG = [Math]::Min(255, [int]([Math]::Round($c.G / 32.0) * 32))
                $bucketB = [Math]::Min(255, [int]([Math]::Round($c.B / 32.0) * 32))
                $key = '{0},{1},{2}' -f $bucketR, $bucketG, $bucketB
                if (-not $buckets.ContainsKey($key)) {
                    $buckets[$key] = [pscustomobject]@{ R = 0L; G = 0L; B = 0L; Count = 0; Score = 0.0 }
                }
                $buckets[$key].R += $c.R
                $buckets[$key].G += $c.G
                $buckets[$key].B += $c.B
                $buckets[$key].Count += 1
                $buckets[$key].Score += ($chroma * 1.8) + ([Math]::Min($luma, 255 - $luma) * 0.55)
            }
        }

        if ($buckets.Count -eq 0) { return Get-DefaultPalette }
        $ranked = @($buckets.Values |
            Sort-Object @{ Expression = { ($_.Score * [Math]::Log([Math]::Max(2, $_.Count + 1))) }; Descending = $true })
        $selected = $ranked | Select-Object -First 1
        if (-not $selected -or $selected.Count -le 0) { return Get-DefaultPalette }
        $primary = [Drawing.Color]::FromArgb([int]($selected.R / $selected.Count), [int]($selected.G / $selected.Count), [int]($selected.B / $selected.Count))
        $backgroundSeed = $primary
        foreach ($candidate in $ranked | Select-Object -Skip 1) {
            if (-not $candidate -or $candidate.Count -le 0) { continue }
            $candidateColor = [Drawing.Color]::FromArgb([int]($candidate.R / $candidate.Count), [int]($candidate.G / $candidate.Count), [int]($candidate.B / $candidate.Count))
            if ((Get-ColorDistance -A $primary -B $candidateColor) -ge 60) {
                $backgroundSeed = $candidateColor
                break
            }
        }
        $accent = Mix-Color $primary ([Drawing.Color]::FromArgb(255, 214, 64)) 0.45
        $dark = Mix-Color $primary ([Drawing.Color]::Black) 0.52
        $light = Mix-Color $backgroundSeed ([Drawing.Color]::White) 0.70
        return @{ Primary = $primary; Accent = $accent; Dark = $dark; Light = $light }
    }
    finally { $bmp.Dispose() }
}

function New-MarqueeFont {
    param([string]$FontName, [float]$Size, [Drawing.FontStyle]$Style)

    foreach ($family in $PrivateFonts.Families) {
        if ($family.Name -ieq $FontName) {
            return New-Object Drawing.Font($family, $Size, $Style, [Drawing.GraphicsUnit]::Pixel)
        }
    }
    return New-Object Drawing.Font($FontName, $Size, $Style, [Drawing.GraphicsUnit]::Pixel)
}
function Get-MarqueeFontFamily {
    param([string]$FontName)

    foreach ($family in $PrivateFonts.Families) {
        if ($family.Name -ieq $FontName) { return $family }
    }
    return New-Object Drawing.FontFamily($FontName)
}
function Draw-CenteredText {
    param(
        [Drawing.Graphics]$Graphics,
        [string]$Text,
        [Drawing.RectangleF]$Rect,
        [string]$FontName,
        [float]$MaxSize,
        [Drawing.Color]$Color,
        [Drawing.Color]$ShadowColor,
        [bool]$Bold = $true
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return }

    $style = if ($Bold) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular }
    $family = Get-MarqueeFontFamily $FontName
    $format = [Drawing.StringFormat]::GenericTypographic.Clone()
    $format.Alignment = [Drawing.StringAlignment]::Near
    $format.LineAlignment = [Drawing.StringAlignment]::Near
    $format.FormatFlags = [Drawing.StringFormatFlags]::NoWrap -bor [Drawing.StringFormatFlags]::MeasureTrailingSpaces
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $shadowPath = $null
    $brush = $null
    $shadowBrush = $null

    try {
        $path.AddString($Text, $family, [int]$style, $MaxSize, (New-Object Drawing.PointF 0, 0), $format)
        $bounds = $path.GetBounds()
        if ($bounds.Width -le 0 -or $bounds.Height -le 0) { return }

        $scaleX = ($Rect.Width * 0.94) / $bounds.Width
        $scaleY = ($Rect.Height * 0.86) / $bounds.Height
        $scale = [Math]::Min($scaleX, $scaleY)
        $targetWidth = $bounds.Width * $scale
        $targetHeight = $bounds.Height * $scale
        $targetX = $Rect.X + (($Rect.Width - $targetWidth) / 2.0)
        $targetY = $Rect.Y + (($Rect.Height - $targetHeight) / 2.0)

        $matrix = New-Object Drawing.Drawing2D.Matrix
        $matrix.Translate(-$bounds.X, -$bounds.Y)
        $matrix.Scale([single]$scale, [single]$scale)
        $matrix.Translate([single]$targetX, [single]$targetY, [Drawing.Drawing2D.MatrixOrder]::Append)
        $path.Transform($matrix)
        $matrix.Dispose()

        $shadowPath = $path.Clone()
        $shadowMatrix = New-Object Drawing.Drawing2D.Matrix
        $shadowMatrix.Translate(3, 3)
        $shadowPath.Transform($shadowMatrix)
        $shadowMatrix.Dispose()

        $shadowBrush = New-Object Drawing.SolidBrush($ShadowColor)
        $brush = New-Object Drawing.SolidBrush($Color)
        if ($ShadowColor.A -gt 0) { $Graphics.FillPath($shadowBrush, $shadowPath) }
        $Graphics.FillPath($brush, $path)
    }
    finally {
        if ($brush) { $brush.Dispose() }
        if ($shadowBrush) { $shadowBrush.Dispose() }
        if ($shadowPath) { $shadowPath.Dispose() }
        $path.Dispose()
        $format.Dispose()
    }
}
function Get-TemplateColorNameFromPalette {
    param([Drawing.Color]$Color)

    $r = [double]$Color.R / 255.0
    $g = [double]$Color.G / 255.0
    $b = [double]$Color.B / 255.0
    $max = [Math]::Max($r, [Math]::Max($g, $b))
    $min = [Math]::Min($r, [Math]::Min($g, $b))
    $delta = $max - $min

    if ($max -lt 0.20 -or $delta -lt 0.08) { return 'Grey' }

    if ($delta -eq 0) { return 'Grey' }
    if ($max -eq $r) { $hue = 60.0 * ((($g - $b) / $delta) % 6.0) }
    elseif ($max -eq $g) { $hue = 60.0 * ((($b - $r) / $delta) + 2.0) }
    else { $hue = 60.0 * ((($r - $g) / $delta) + 4.0) }
    if ($hue -lt 0) { $hue += 360.0 }

    if ($hue -lt 20 -or $hue -ge 340) { return 'Red' }
    if ($hue -lt 45) { return 'Gold' }
    if ($hue -lt 70) { return 'Gold' }
    if ($hue -lt 160) { return 'Green' }
    if ($hue -lt 250) { return 'Blue' }
    if ($hue -lt 320) { return 'Purple' }
    return 'Red'
}
function Get-StandardColorScheme {
    $schemes = @(
        @{ Dark = [Drawing.Color]::FromArgb(128, 32, 36); Light = [Drawing.Color]::FromArgb(229, 142, 128) },
        @{ Dark = [Drawing.Color]::FromArgb(126, 67, 24); Light = [Drawing.Color]::FromArgb(237, 166, 83) },
        @{ Dark = [Drawing.Color]::FromArgb(52, 104, 58); Light = [Drawing.Color]::FromArgb(158, 202, 142) },
        @{ Dark = [Drawing.Color]::FromArgb(78, 58, 130); Light = [Drawing.Color]::FromArgb(177, 153, 226) },
        @{ Dark = [Drawing.Color]::FromArgb(127, 102, 31); Light = [Drawing.Color]::FromArgb(232, 202, 103) },
        @{ Dark = [Drawing.Color]::FromArgb(48, 93, 128); Light = [Drawing.Color]::FromArgb(164, 204, 235) }
    )
    return $schemes | Get-Random
}

function Get-StandardSchemeFromPalette {
    param([Drawing.Color]$Primary)

    $dark = Mix-Color -A $Primary -B ([Drawing.Color]::Black) -Amount 0.25
    $light = Mix-Color -A $Primary -B ([Drawing.Color]::White) -Amount 0.72
    return @{ Dark = $dark; Light = $light }
}

function Recolor-Layer {
    param([Drawing.Bitmap]$Bitmap, [Drawing.Color]$TargetColor)

    for ($y = 0; $y -lt $Bitmap.Height; $y++) {
        for ($x = 0; $x -lt $Bitmap.Width; $x++) {
            $c = $Bitmap.GetPixel($x, $y)
            if ($c.A -eq 0) { continue }
            $Bitmap.SetPixel($x, $y, [Drawing.Color]::FromArgb($c.A, $TargetColor.R, $TargetColor.G, $TargetColor.B))
        }
    }
}

function Draw-StandardTemplateLayers {
    param(
        [Drawing.Graphics]$Graphics,
        [hashtable]$Scheme
    )

    if (-not (Test-Path -LiteralPath $StandardLayerBgPath) -or -not (Test-Path -LiteralPath $StandardLayerFgPath) -or -not (Test-Path -LiteralPath $StandardLayerMidTextPath)) {
        return $false
    }

    $bg = [Drawing.Bitmap]::FromFile($StandardLayerBgPath)
    $fg = [Drawing.Bitmap]::FromFile($StandardLayerFgPath)
    $mid = [Drawing.Image]::FromFile($StandardLayerMidTextPath)
    try {
        Recolor-Layer -Bitmap $bg -TargetColor $Scheme.Light
        Recolor-Layer -Bitmap $fg -TargetColor $Scheme.Dark
        $Graphics.DrawImage($bg, 0, 0, 1920, 360)
        $Graphics.DrawImage($fg, 0, 0, 1920, 360)
        $Graphics.DrawImage($mid, 0, 0, 1920, 360)
        return $true
    }
    finally {
        $bg.Dispose()
        $fg.Dispose()
        $mid.Dispose()
    }
}
function Save-JpegUnderLimit {
    param([Drawing.Bitmap]$Bitmap, [string]$Path, [int]$MaxBytes)
    $codec = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
    for ($quality = 88; $quality -ge 50; $quality -= 4) {
        $params = New-Object Drawing.Imaging.EncoderParameters(1)
        $params.Param[0] = New-Object Drawing.Imaging.EncoderParameter([Drawing.Imaging.Encoder]::Quality, [int64]$quality)
        $Bitmap.Save($Path, $codec, $params)
        $params.Dispose()
        if ((Get-Item -LiteralPath $Path).Length -le $MaxBytes) { return }
    }
}

function Try-ExtractFrame {
    param([string]$InputPath, [string]$OutputPath)

    $timestamps = @('00:00:05', '00:00:10', '00:00:20', '00:00:30', '00:01:00')
    for ($attempt = 0; $attempt -lt $timestamps.Count; $attempt++) {
        $stdoutPath = Join-Path $tempDir ('ffmpeg_frame_stdout_{0}.txt' -f $attempt)
        $stderrPath = Join-Path $tempDir ('ffmpeg_frame_stderr_{0}.txt' -f $attempt)
        if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue }
        try {
            $process = Start-Process -FilePath 'ffmpeg' -ArgumentList @(
                '-y',
                '-hide_banner',
                '-loglevel', 'error',
                '-ss', $timestamps[$attempt],
                '-i', $InputPath,
                '-frames:v', '1',
                $OutputPath
            ) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

            if ((Test-Path -LiteralPath $OutputPath) -and ((Get-Item -LiteralPath $OutputPath).Length -gt 0)) { return $true }
        }
        catch {
        }
    }

    if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue }
    return $false
}

try {
    Try-ExtractFrame -InputPath $VideoPath -OutputPath $framePath | Out-Null
    $parts = Get-TextParts -Name $baseName
    $parts = Get-MusicBrainzTextParts -Parts $parts
    $videoStats = Get-VideoStats -Path $VideoPath
    $palette = Get-FramePalette -ImagePath $framePath
    $albumCoverPath = Get-AlbumCoverPath -Parts $parts
    $artistArtPath = Get-ArtistArtPath -Parts $parts
    if ($albumCoverPath) { $palette = Get-FramePalette -ImagePath $albumCoverPath }
    $palettePrimary = $palette['Primary']
    $paletteAccent = $palette['Accent']
    $paletteDark = $palette['Dark']
    $paletteLight = $palette['Light']
    $paletteDarkR = $paletteDark.R
    $paletteDarkG = $paletteDark.G
    $paletteDarkB = $paletteDark.B

    if ($GenerateStandard) {
        $bmp = New-Object Drawing.Bitmap 1920, 360
        $g = [Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        try {
            $scheme = Get-StandardSchemeFromPalette -Primary $palettePrimary
            if (-not (Draw-StandardTemplateLayers -Graphics $g -Scheme $scheme)) { throw "Standard marquee layer files were not found: $StandardLayerDir" }
            $leftRect = New-Object Drawing.Rectangle 0, 0, 415, 360
            $rightRect = New-Object Drawing.Rectangle 1505, 0, 415, 360
            if (-not (Draw-ImageFileAtFullHeight -Graphics $g -Path $albumCoverPath -TargetRect $leftRect)) {
                if ($albumCoverPath -and (Test-Path -LiteralPath $albumCoverPath)) { Remove-Item -LiteralPath $albumCoverPath -Force -ErrorAction SilentlyContinue }
                Draw-FallbackLogo -Graphics $g -TargetRect $leftRect | Out-Null
            }
            if (-not (Draw-ImageFileAtFullHeight -Graphics $g -Path $artistArtPath -TargetRect $rightRect)) {
                if ($artistArtPath -and (Test-Path -LiteralPath $artistArtPath)) { Remove-Item -LiteralPath $artistArtPath -Force -ErrorAction SilentlyContinue }
                Draw-FallbackLogo -Graphics $g -TargetRect $rightRect | Out-Null
            }
            $black = [Drawing.Color]::Black
            $softShadow = [Drawing.Color]::FromArgb(25, 255, 255, 255)
            Draw-CenteredText $g $parts['Title'] (New-Object Drawing.RectangleF 430, 34, 1060, 104) 'Anton' 120 $black $softShadow $false
            Draw-CenteredText $g $parts['Artist'] (New-Object Drawing.RectangleF 540, 145, 840, 68) 'Anton' 58 $black $softShadow $false
            $bottomText = 'LENGTH: {0}  |  RELEASE DATE: {1}  |  RESOLUTION: {2}' -f $videoStats['Length'], $parts['ReleaseYear'], $videoStats['Resolution']
            Draw-CenteredText $g $bottomText (New-Object Drawing.RectangleF 430, 238, 1060, 94) 'Anton' 52 $black $softShadow $false
            Save-JpegUnderLimit $bmp (Join-Path $marqueeRoot ($baseName + ' (JUKE).jpg')) 200000
        }
        finally { $g.Dispose(); $bmp.Dispose() }
    }
    if ($GenerateFullColor) {
        $bmp = New-Object Drawing.Bitmap 1920, 360
        $g = [Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        try {
            if (Test-Path -LiteralPath $framePath) {
                $frame = [Drawing.Image]::FromFile($framePath)
                try {
                    $g.DrawImage($frame, -40, -220, 2000, 800)
                    $leftRect = New-Object Drawing.Rectangle 0, 0, 260, 360
                    $rightRect = New-Object Drawing.Rectangle 1660, 0, 260, 360
                    $g.DrawImage($frame, $leftRect)
                    $g.DrawImage($frame, $rightRect)
                } finally { $frame.Dispose() }
            }
            $overlay = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(155, $paletteDarkR, $paletteDarkG, $paletteDarkB))
            $g.FillRectangle($overlay, 0, 0, 1920, 360)
            $band = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(135, 0, 0, 0))
            $g.FillRectangle($band, 330, 44, 1260, 250)
            $accentPen = New-Object Drawing.Pen($paletteAccent, 6)
            $g.DrawLine($accentPen, 330, 44, 1590, 44)
            $g.DrawLine($accentPen, 330, 294, 1590, 294)
            $textColor = Get-ReadableTextColor $paletteDark
            Draw-CenteredText $g $parts['Artist'] (New-Object Drawing.RectangleF 360, 58, 1200, 92) 'Arial Narrow' 68 $paletteAccent ([Drawing.Color]::Black) $true
            Draw-CenteredText $g $parts['Title'] (New-Object Drawing.RectangleF 360, 145, 1200, 105) 'Arial Narrow' 64 $textColor ([Drawing.Color]::Black) $true
            $year = (Get-Date).Year.ToString()
            Draw-CenteredText $g $year (New-Object Drawing.RectangleF 1325, 242, 220, 46) 'Consolas' 40 (Mix-Color -A $paletteLight -B ([Drawing.Color]::White) -Amount 0.3) ([Drawing.Color]::Black) $false
            Save-JpegUnderLimit $bmp (Join-Path $marqueeRoot ($baseName + ' (JUKE).jpg')) 200000
        }
        finally { $g.Dispose(); $bmp.Dispose() }
    }

    Write-Host "Generated marquee artwork: $baseName"
}
finally {
    if ($PrivateFonts) { $PrivateFonts.Dispose() }
    if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
}
