param(
    [Parameter(Mandatory=$true)][string]$VideoPath,
    [Parameter(Mandatory=$true)][string]$DownloadDir,
    [string]$Animated = 'true',
    [string]$FullColorStill = 'false',
    [string]$TemplateName = '',
    [int]$TemplateVariant = -1,
    [string]$WordArtStyle = '',
    [string]$MotionStyle = '',
    [string]$VisualizerStyle = '',
    [string]$RandomSeed = ''
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding

if (-not (Test-Path -LiteralPath $VideoPath)) { throw "Video not found: $VideoPath" }
$GenerateAnimated = $Animated -match '^(1|true|yes|on)$'
$GenerateFullColorStill = $FullColorStill -match '^(1|true|yes|on)$'
if (-not $GenerateAnimated -and -not $GenerateFullColorStill) { return }

Add-Type -AssemblyName System.Drawing

$AssetsDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$InternalRoot = Split-Path -Parent $AssetsDir
$PackageRoot = Split-Path -Parent $InternalRoot
$ResourceDir = Join-Path $PackageRoot 'resources'
$ToolsDir = Join-Path $AssetsDir 'tools'
$FfmpegPortableBinDir = Join-Path $ToolsDir 'ffmpeg\bin'
$FfmpegPath = Join-Path $FfmpegPortableBinDir 'ffmpeg.exe'
$FfprobePath = Join-Path $FfmpegPortableBinDir 'ffprobe.exe'
$FallbackLogoPath = Join-Path $AssetsDir 'images\one_sauce_merged.png'
$OneSauceLogoPath = Join-Path $AssetsDir 'images\One_saUCE_Logo.png'
$CacheDir = Join-Path $AssetsDir 'resources\cache\album_art'
$MetadataCacheDir = Join-Path $AssetsDir 'resources\cache\musicbrainz_metadata'
$ArtistArtCacheDir = Join-Path $AssetsDir 'resources\cache\artist_art'
$UrlMetadataCacheFile = Join-Path $AssetsDir 'resources\cache\jukebox_url_metadata_cache.json'
$AlbumArtLookupScript = Join-Path $AssetsDir 'lib\album_art_lookup.ps1'
$MusicBrainzMetadataScript = Join-Path $AssetsDir 'lib\musicbrainz_metadata_lookup.ps1'
$ArtistArtLookupScript = Join-Path $AssetsDir 'lib\artist_art_lookup.ps1'
$FanartProjectKeyPath = Join-Path $ResourceDir 'fanart_project_api_key.txt'
$FanartPersonalKeyPath = Join-Path $ResourceDir 'fanart_personal_api_key.txt'
$PrivateFonts = New-Object Drawing.Text.PrivateFontCollection
$FontFiles = @(
    (Join-Path $AssetsDir 'fonts\Anton\Anton-Regular.ttf'),
    (Join-Path $AssetsDir 'fonts\BebasNeue\BebasNeue-Regular.ttf'),
    (Join-Path $AssetsDir 'fonts\BebasNeue\BebasNeue-Bold.ttf'),
    (Join-Path $AssetsDir 'fonts\Bangers\Bangers-Regular.ttf'),
    (Join-Path $AssetsDir 'fonts\Bungee\Bungee-Regular.ttf'),
    (Join-Path $AssetsDir 'fonts\FugazOne\FugazOne-Regular.ttf'),
    (Join-Path $AssetsDir 'fonts\Righteous\Righteous-Regular.ttf'),
    (Join-Path $AssetsDir 'fonts\Monoton\Monoton-Regular.ttf'),
    (Join-Path $AssetsDir 'fonts\Shrikhand\Shrikhand-Regular.ttf'),
    (Join-Path $AssetsDir 'fonts\LilitaOne\LilitaOne-Regular.ttf'),
    (Join-Path $AssetsDir 'fonts\BlackOpsOne\BlackOpsOne-Regular.ttf'),
    (Join-Path $AssetsDir 'fonts\LuckiestGuy\LuckiestGuy-Regular.ttf'),
    (Join-Path $AssetsDir 'fonts\TitanOne\TitanOne-Regular.ttf'),
    (Join-Path $AssetsDir 'fonts\Rowdies\Rowdies-Bold.ttf'),
    (Join-Path $AssetsDir 'fonts\CarterOne\CarterOne.ttf'),
    (Join-Path $AssetsDir 'fonts\Ultra\Ultra-Regular.ttf'),
    (Join-Path $AssetsDir 'fonts\Bevan\Bevan-Regular.ttf')
)
foreach ($fontPath in $FontFiles) {
    if (Test-Path -LiteralPath $fontPath) { $PrivateFonts.AddFontFile($fontPath) }
}
$marqueesRoot = Join-Path $DownloadDir 'marquees'
$animatedRoot = Join-Path $marqueesRoot 'animated'
$fullColorRoot = Join-Path $marqueesRoot 'full_color'
if ($GenerateAnimated) { New-Item -ItemType Directory -Path $animatedRoot -Force | Out-Null }
if ($GenerateFullColorStill) { New-Item -ItemType Directory -Path $fullColorRoot -Force | Out-Null }

if (Test-Path -LiteralPath $FfmpegPortableBinDir) {
    $env:PATH = $FfmpegPortableBinDir + ';' + $env:PATH
}

function Invoke-Ffmpeg {
    param([string[]]$Arguments)

    if (Test-Path -LiteralPath $FfmpegPath) {
        & $FfmpegPath @Arguments
    } else {
        & ffmpeg @Arguments
    }
}

function Invoke-Ffprobe {
    param([string[]]$Arguments)

    if (Test-Path -LiteralPath $FfprobePath) {
        & $FfprobePath @Arguments
    } else {
        & ffprobe @Arguments
    }
}

$baseName = [IO.Path]::GetFileNameWithoutExtension($VideoPath)
$outputBaseName = $baseName -replace '\s+\(JUKE\)$', ''
$MarqueeFileNameTotalLimit = 104
function Get-MarqueeOutputFileName {
    param([string]$BaseName, [string]$Extension)
    $suffix = ' (JUKE)'
    $cleanBase = $BaseName
    if ([string]::IsNullOrWhiteSpace($cleanBase)) { $cleanBase = 'marquee' }
    $baseLimit = [Math]::Max(1, $MarqueeFileNameTotalLimit - $suffix.Length - $Extension.Length)
    if ($cleanBase.Length -gt $baseLimit) { $cleanBase = $cleanBase.Substring(0, $baseLimit) }
    if ([string]::IsNullOrWhiteSpace($cleanBase)) { $cleanBase = 'marquee' }
    return ($cleanBase + $suffix + $Extension)
}
$outputPath = Join-Path $animatedRoot (Get-MarqueeOutputFileName -BaseName $outputBaseName -Extension '.mp4')
$fullColorStillPath = Join-Path $fullColorRoot (Get-MarqueeOutputFileName -BaseName $outputBaseName -Extension '.jpg')
$tempDir = Join-Path ([IO.Path]::GetTempPath()) ('jdw_video_marquee_' + [Guid]::NewGuid().ToString('N'))
$frameDir = Join-Path $tempDir 'frames'
$sourceFramePath = Join-Path $tempDir 'source_frame.png'
New-Item -ItemType Directory -Path $frameDir -Force | Out-Null

$Width = 1920
$Height = 360
$Fps = 30
$Seconds = 7
$FrameCount = $Fps * $Seconds
$FullColorStillFrame = [int][Math]::Round(3.5 * $Fps)
$PanelArtSize = 320
$PanelEdgeMargin = 48

function New-Color {
    param([int]$R, [int]$G, [int]$B, [int]$A = 255)
    return [Drawing.Color]::FromArgb($A, $R, $G, $B)
}

function Clamp01 {
    param([double]$Value)
    if ($Value -lt 0) { return 0.0 }
    if ($Value -gt 1) { return 1.0 }
    return $Value
}

function Ease-OutCubic {
    param([double]$T)
    $t = Clamp01 $T
    return 1.0 - [Math]::Pow(1.0 - $t, 3.0)
}

function Ease-OutBack {
    param([double]$T, [double]$Overshoot = 1.55)
    $t = (Clamp01 $T) - 1.0
    return 1.0 + ($t * $t * (($Overshoot + 1.0) * $t + $Overshoot))
}

function Lerp {
    param([double]$A, [double]$B, [double]$T)
    return $A + (($B - $A) * $T)
}

function Scale-RectFromCenter {
    param([Drawing.RectangleF]$Rect, [double]$Scale)
    $scaleValue = [Math]::Max(0.1, $Scale)
    $newW = [float]($Rect.Width * $scaleValue)
    $newH = [float]($Rect.Height * $scaleValue)
    $newX = [float]($Rect.X + (($Rect.Width - $newW) / 2.0))
    $newY = [float]($Rect.Y + (($Rect.Height - $newH) / 2.0))
    return New-Object Drawing.RectangleF -ArgumentList $newX, $newY, $newW, $newH
}

function Get-DeterministicSeed {
    param([string]$Text)
    [long]$hash = 17
    foreach ($ch in $Text.ToCharArray()) {
        $hash = (($hash * 31) + [int][char]$ch) % 2147483647
    }
    return [int]$hash
}

function Blend-Color {
    param([Drawing.Color]$A, [Drawing.Color]$B, [double]$T, [int]$Alpha = 255)
    $t = Clamp01 $T
    return New-Color `
        ([int](Lerp -A $A.R -B $B.R -T $t)) `
        ([int](Lerp -A $A.G -B $B.G -T $t)) `
        ([int](Lerp -A $A.B -B $B.B -T $t)) `
        $Alpha
}

function Get-ReadableAccent {
    param([Drawing.Color]$Color, [Drawing.Color]$Fallback)
    $brightness = (($Color.R * 0.299) + ($Color.G * 0.587) + ($Color.B * 0.114))
    $saturation = ([Math]::Max($Color.R, [Math]::Max($Color.G, $Color.B)) - [Math]::Min($Color.R, [Math]::Min($Color.G, $Color.B)))
    if ($saturation -lt 34) { return $Fallback }
    if ($brightness -lt 58) { return Blend-Color $Color (New-Color 135 210 255) 0.42 }
    return $Color
}

function Get-ColorBrightness {
    param([Drawing.Color]$Color)
    return (($Color.R * 0.299) + ($Color.G * 0.587) + ($Color.B * 0.114))
}

function Get-ReadableWordArtColor {
    param([Drawing.Color]$Color)

    $brightness = Get-ColorBrightness $Color
    if ($brightness -lt 78) { return Blend-Color $Color (New-Color 255 255 255) 0.36 }
    if ($brightness -gt 224) { return Blend-Color $Color (New-Color 0 0 0) 0.18 }
    return $Color
}

function Get-AlbumDrivenWordArtColor {
    param(
        [Drawing.Color]$Accent,
        [Drawing.Color]$StyleColor,
        [double]$AlbumWeight = 0.74
    )

    $accentBrightness = Get-ColorBrightness $Accent
    $accentSaturation = ([Math]::Max($Accent.R, [Math]::Max($Accent.G, $Accent.B)) - [Math]::Min($Accent.R, [Math]::Min($Accent.G, $Accent.B)))
    $weight = $AlbumWeight
    if ($accentSaturation -ge 92) { $weight = [Math]::Max($weight, 0.84) }
    if ($accentBrightness -lt 76) { $weight = [Math]::Min($weight, 0.68) }

    $mixed = Blend-Color $StyleColor $Accent $weight
    if ($accentBrightness -lt 92) { $mixed = Blend-Color $mixed (New-Color 130 210 255) 0.18 }
    return Get-ReadableWordArtColor $mixed
}

function Get-AlbumSecondaryAccent {
    param([Drawing.Color]$Accent)

    $warmOrange = New-Color 255 132 62
    $gold = New-Color 255 206 76
    $hotPink = New-Color 255 76 150
    $blueDominant = ($Accent.B -gt ($Accent.R + 34) -and $Accent.B -gt ($Accent.G + 22))
    $greenDominant = ($Accent.G -gt ($Accent.R + 28) -and $Accent.G -gt ($Accent.B + 20))
    $redDominant = ($Accent.R -gt ($Accent.G + 24) -and $Accent.R -gt ($Accent.B + 20))

    if ($blueDominant) { return Get-ReadableWordArtColor (Blend-Color $Accent $warmOrange 0.54) }
    if ($greenDominant) { return Get-ReadableWordArtColor (Blend-Color $Accent $hotPink 0.58) }
    if ($redDominant) { return Get-ReadableWordArtColor (Blend-Color $Accent $gold 0.42) }
    return Get-ReadableWordArtColor (Blend-Color $Accent $warmOrange 0.44)
}

function Get-ColorDistance {
    param([Drawing.Color]$A, [Drawing.Color]$B)
    $dr = [double]($A.R - $B.R)
    $dg = [double]($A.G - $B.G)
    $db = [double]($A.B - $B.B)
    return [Math]::Sqrt(($dr * $dr) + ($dg * $dg) + ($db * $db))
}

function Get-MinColorDistance {
    param(
        [Drawing.Color]$Color,
        [object[]]$Colors
    )

    $minDistance = 999.0
    foreach ($candidate in @($Colors)) {
        if ($null -eq $candidate) { continue }
        $minDistance = [Math]::Min($minDistance, (Get-ColorDistance $Color $candidate))
    }
    return $minDistance
}

function Get-ContrastSafeWordArtColor {
    param(
        [Drawing.Color]$Color,
        [object[]]$AvoidColors,
        [object[]]$PreferredAlternates
    )

    $current = Get-ReadableWordArtColor $Color
    if ((Get-MinColorDistance -Color $current -Colors $AvoidColors) -ge 104) { return $current }

    $candidates = @($current)
    foreach ($alt in @($PreferredAlternates)) {
        if ($null -ne $alt) {
            $candidates += (Get-ReadableWordArtColor $alt)
            $candidates += (Get-ReadableWordArtColor (Blend-Color $alt (New-Color 255 255 255) 0.24))
        }
    }
    $candidates += (Get-ReadableWordArtColor (Blend-Color $current (New-Color 255 255 255) 0.42))
    $candidates += (Get-ReadableWordArtColor (New-Color 255 96 72))
    $candidates += (Get-ReadableWordArtColor (New-Color 255 150 58))
    $candidates += (Get-ReadableWordArtColor (New-Color 255 206 76))
    $candidates += (Get-ReadableWordArtColor (New-Color 255 78 150))
    $candidates += (Get-ReadableWordArtColor (New-Color 90 210 255))
    $candidates += (New-Color 245 250 255)
    $candidates += (New-Color 255 218 92)

    $best = $current
    $bestScore = -9999.0
    foreach ($candidate in @($candidates)) {
        $safe = Get-ReadableWordArtColor $candidate
        $distanceFromBackground = Get-MinColorDistance -Color $safe -Colors $AvoidColors
        $distanceFromOriginal = Get-ColorDistance $safe $current
        $brightness = Get-ColorBrightness $safe
        $brightnessPenalty = if ($brightness -lt 92) { (92 - $brightness) * 0.55 } elseif ($brightness -gt 232) { ($brightness - 232) * 0.35 } else { 0.0 }
        $score = $distanceFromBackground - ($distanceFromOriginal * 0.10) - $brightnessPenalty
        if ($score -gt $bestScore) {
            $bestScore = $score
            $best = $safe
        }
    }
    return $best
}

function Repair-TextEncoding {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $Value = $Value -replace ([string][char]0xfffd + '\??'), ''
    $Value = $Value -replace [string][char]0xfffd, ''
    $Value = $Value -replace ([string][char]0x00c2 + [char]0x00a0), ' '
    $Value = $Value -replace [string][char]0x00a0, ' '
    $Value = $Value -replace ([string][char]0x00e2 + [char]0x0080 + [char]0x00a6), '...'
    $Value = $Value -replace ([string][char]0x00e2 + [char]0x0080 + [char]0x00a2), '-'
    $Value = $Value -replace ([string][char]0x00e2 + [char]0x0080 + [char]0x0099), "'"
    $Value = $Value -replace ([string][char]0x00e2 + [char]0x0080 + [char]0x0098), "'"
    $Value = $Value -replace ([string][char]0x00e2 + [char]0x0080 + [char]0x009c), '"'
    $Value = $Value -replace ([string][char]0x00e2 + [char]0x0080 + [char]0x009d), '"'
    $Value = $Value -replace ([string][char]0x00e2 + [char]0x0080 + [char]0x0090), '-'
    $Value = $Value -replace ([string][char]0x00e2 + [char]0x0080 + [char]0x0091), '-'
    $Value = $Value -replace ([string][char]0x00e2 + [char]0x0080 + [char]0x0092), '-'
    $Value = $Value -replace ([string][char]0x00e2 + [char]0x0080 + [char]0x0093), '-'
    $Value = $Value -replace ([string][char]0x00e2 + [char]0x0080 + [char]0x0094), '-'
    $Value = $Value -replace [string][char]0x00b4, "'"
    $Value = $Value -replace [string][char]0x0060, "'"
    $Value = $Value -replace [string][char]0x02bc, "'"
    $Value = $Value -replace [string][char]0x2018, "'"
    $Value = $Value -replace [string][char]0x2019, "'"
    $Value = $Value -replace [string][char]0x201c, '"'
    $Value = $Value -replace [string][char]0x201d, '"'
    $Value = $Value -replace [string][char]0x2010, '-'
    $Value = $Value -replace [string][char]0x2011, '-'
    $Value = $Value -replace [string][char]0x2012, '-'
    $Value = $Value -replace [string][char]0x2013, '-'
    $Value = $Value -replace [string][char]0x2014, '-'
    $Value = $Value -replace [string][char]0x2212, '-'
    $Value = $Value -replace '[\p{Cc}\p{Cf}]', ' '
    $Value = $Value -replace '\s+', ' '
    if ($Value.IndexOf([char]0x00c3) -lt 0 -and $Value.IndexOf([char]0x00c2) -lt 0) { return $Value.Trim() }
    try {
        $bytes = [Text.Encoding]::GetEncoding(1252).GetBytes($Value)
        $fixed = [Text.Encoding]::UTF8.GetString($bytes)
        if (-not [string]::IsNullOrWhiteSpace($fixed)) { return $fixed.Trim() }
    }
    catch {
    }
    return $Value.Trim()
}

function Clean-MarqueeText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $noiseWords = 'official\s+music\s+video|official\s+video|official\s+audio|official\s+lyric\s+video|official|lyric\s+video|lyrics?|visuali[sz]er|performance\s+video|music\s+video|audio|hd|hq|sd|4k|[0-9]{3,4}p|remaster(?:ed)?|karaoke|unreleased\s+video|new\s+unreleased\s+video|new\s+video'
    $contextNoiseWords = $noiseWords + '|live\s+(?:at|from|in|on)\b.*|sub(?:titula[dd][ao]?|itula[dd][ao]?|t[ií]tulos?)|espa[nñ]ol|ingl[eé]s|legendado|tradu[cç][aã]o|traducao|translated|translation'
    $clean = (Repair-TextEncoding $Text) -replace '(?i)\s+\(JUKE\)\s*$', ''
    $clean = $clean -replace '[\p{Cc}\p{Cf}]', ' '
    $clean = $clean -replace '(?i)\s+\b(with|w/)\s+lyrics?\b.*$', ''
    $clean = $clean -replace '(?i)\s*[\[\(\{]\s*(tv|mv|hd|hq|sd|4k|[0-9]{3,4}p|live)\s*[\]\)\}]', ''
    $clean = $clean -replace ('(?i)\s*[\[\(\{][^\]\)\}]*\b(' + $contextNoiseWords + ')\b[^\]\)\}]*[\]\)\}]'), ''
    $clean = $clean -replace ('(?i)\s+[-|:]\s*(' + $contextNoiseWords + ')\b.*$'), ''
    $clean = $clean -replace ('(?i)\s+\b(live\s+(?:at|from|in|on)\b.*)$'), ''
    $clean = $clean -replace ('(?i)\s+\b(' + $contextNoiseWords + ')\b.*$'), ''
    $clean = $clean -replace ('(?i)\b(' + $noiseWords + ')\b'), ''
    $clean = $clean -replace '\s+', ' '
    return $clean.Trim(' ', '-', '|', ':', '_')
}

function Clean-MarqueeTitle {
    param([string]$Text)
    $clean = Clean-MarqueeText $Text
    $clean = $clean -replace '\s*[\(\[]\s*(19|20)\d{2}\s*[\)\]]\s*', ' '
    $clean = $clean -replace '(?i)\s+\b(ft\.?|feat\.?|featuring)\b\.?\s+.*$', ''
    $clean = $clean -replace '\s+', ' '
    return $clean.Trim(' ', '-', '|', ':', '_')
}

function Normalize-MarqueeArtist {
    param([string]$Artist)
    $clean = Clean-MarqueeText $Artist
    if ($clean -match '^\s*(?<name>.+?)\s*,\s*(?<article>The|A|An)\s*$') {
        $clean = ('{0} {1}' -f $Matches['article'], $Matches['name'])
    }
    if ($clean -match '(?i)^\s*AC\s*/?\s*DC\s*$') { return 'AC/DC' }
    if ($clean -match '(?i)^\s*(A\s*\$?\s*AP|ASAP)\s+ROCKY\s*$') { return 'A$AP Rocky' }
    if ($clean -match '(?i)^\s*DESTINYS\s+CHILD\s*$') { return "Destiny's Child" }
    if ($clean -match '^\s*(?<thousands>\d{1,2})\s+(?<hundreds>\d{3})(?<rest>\s+\S.*)$') {
        $clean = ('{0},{1}{2}' -f $Matches['thousands'], $Matches['hundreds'], $Matches['rest'])
    }
    return $clean
}

function Get-ParentheticalReleaseYear {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $nowYear = [int](Get-Date).Year + 1
    foreach ($match in [regex]::Matches($Text, '\((?<year>(19|20)\d{2})\)')) {
        $year = [int]$match.Groups['year'].Value
        if ($year -ge 1900 -and $year -le $nowYear) { return $year.ToString() }
    }
    return ''
}

function Convert-TitleToDownloadBaseName {
    param([string]$Title)
    if ([string]::IsNullOrWhiteSpace($Title)) { return '' }
    $name = $Title
    $name = $name -replace ([string][char]0xfffd + '\??'), ''
    $name = $name -replace [string][char]0xfffd, ''
    $name = $name.Normalize('FormD') -replace '\p{Mn}', ''
    $name = $name -replace '\[', '(' -replace '\]', ')'
    $name = $name -replace '_+', ' '
    $name = $name -replace "[^A-Za-z0-9 '`$!&,@\-\._\(\)]", ' '
    $name = $name -replace '\s+', ' '
    return $name.Trim(' ', '.', '_', '-')
}

function Get-CachedSourceTitle {
    param([string]$BaseName)
    if ([string]::IsNullOrWhiteSpace($BaseName) -or -not (Test-Path -LiteralPath $UrlMetadataCacheFile)) { return '' }
    try {
        $cache = Get-Content -LiteralPath $UrlMetadataCacheFile -Raw | ConvertFrom-Json
        if (-not $cache -or -not $cache.videos) { return '' }
        foreach ($property in @($cache.videos.PSObject.Properties)) {
            $title = [string]$property.Value.title
            if ([string]::IsNullOrWhiteSpace($title)) { continue }
            $candidate = Convert-TitleToDownloadBaseName -Title $title
            if ($candidate -ieq $BaseName) { return $title }
            if ($candidate.Length -gt $BaseName.Length -and $candidate.Substring(0, $BaseName.Length) -ieq $BaseName) { return $title }
        }
    }
    catch {
    }
    return ''
}

function Test-SourceOrChannelText {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value -match '(?i)\b(sony\s+animation|sony\s+pictures\s+animation|disney|netflix|warner|vevo|records?|recordings|entertainment|pictures|studios?|animation|official|youtube)\b')
}

function Remove-KnownSourceTail {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $clean = $Value
    $sourceTails = @(
        'Sony Pictures Animation',
        'Sony Animation',
        'SonyPicturesAnimation',
        'DisneyMusicVEVO',
        'Atlantic Records',
        'Republic Records',
        'Interscope Records',
        'Warner Records',
        'Universal Music',
        'Netflix',
        'Disney'
    )
    foreach ($tail in $sourceTails) {
        $clean = $clean -replace ('(?i)\s+' + [regex]::Escape($tail) + '\s*$'), ''
    }
    return ($clean -replace '\s+', ' ').Trim()
}

function Split-AmbiguousTitleContext {
    param([string]$Value)
    $titleValue = Clean-MarqueeTitle (Remove-KnownSourceTail $Value)
    $releaseValue = ''

    $releaseContexts = @(
        'KPop Demon Hunters'
    )
    foreach ($context in $releaseContexts) {
        if ($titleValue -match ('(?i)^(?<title>.+?)\s+' + [regex]::Escape($context) + '\s*$')) {
            $titleValue = $Matches['title'].Trim()
            $releaseValue = $context
            break
        }
    }

    return @{ Title = $titleValue; ReleaseTitle = $releaseValue }
}

function Split-KnownNoDashArtistTitle {
    param([string]$Value)
    $clean = Clean-MarqueeTitle (Remove-KnownSourceTail $Value)
    $knownTitles = @(
        'Eastside'
        'Whiskey Black Demarco'
    )
    foreach ($knownTitle in $knownTitles) {
        if ($clean -match ('(?i)^(?<artist>.+?)\s+' + [regex]::Escape($knownTitle) + '\s*$')) {
            return @{
                Artist = $Matches['artist'].Trim()
                Title = $knownTitle
                Matched = $true
            }
        }
    }
    return @{ Artist = ''; Title = $clean; Matched = $false }
}

function Get-TextParts {
    param([string]$Name)
    $artist = 'UNKNOWN ARTIST'
    $title = $Name
    $releaseTitle = ''
    $releaseYear = Get-ParentheticalReleaseYear -Text $Name
    $cacheBaseName = ($Name -replace '\s+\(JUKE\)$', '').Trim()
    $sourceName = Get-CachedSourceTitle -BaseName $cacheBaseName
    if (-not [string]::IsNullOrWhiteSpace($sourceName)) {
        if ([string]::IsNullOrWhiteSpace($releaseYear)) { $releaseYear = Get-ParentheticalReleaseYear -Text $sourceName }
        $title = $sourceName
    }

    $pipeParts = @($title -split '\s+\|\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($pipeParts.Count -ge 3) {
        $title = $pipeParts[0]
        $releaseTitle = Clean-MarqueeText $pipeParts[1]
        if (-not (Test-SourceOrChannelText $pipeParts[1])) {
            $artist = $pipeParts[1]
            $releaseTitle = ''
        }
    } elseif ($pipeParts.Count -eq 2) {
        $title = $pipeParts[0]
        if (Test-SourceOrChannelText $pipeParts[1]) {
            $releaseTitle = Clean-MarqueeText $pipeParts[1]
        } else {
            $artist = $pipeParts[1]
        }
    } else {
        $parts = $title -split '\s+-\s+', 2
        if ($parts.Count -eq 2) {
            $artist = $parts[0]
            $title = $parts[1]
        } else {
            $knownNoDash = Split-KnownNoDashArtistTitle -Value $title
            if ($knownNoDash['Matched']) {
                $artist = $knownNoDash['Artist']
                $title = $knownNoDash['Title']
            } else {
                $ambiguous = Split-AmbiguousTitleContext -Value $title
                $title = $ambiguous['Title']
                $releaseTitle = $ambiguous['ReleaseTitle']
            }
        }
    }
    $artist = Normalize-MarqueeArtist $artist
    $title = Clean-MarqueeTitle $title
    $releaseTitle = Clean-MarqueeText $releaseTitle
    return @{ Artist = $artist.Trim().ToUpperInvariant(); Title = $title.Trim().ToUpperInvariant(); ReleaseTitle = $releaseTitle.Trim().ToUpperInvariant(); ReleaseYear = $releaseYear; ReleaseMbid = ''; ReleaseMatchSource = ''; ArtistMbid = '' }
}

function Get-VideoReleaseTitle {
    param([string]$Path)

    try {
        $json = Invoke-Ffprobe @(
            '-v', 'error',
            '-show_entries', 'format_tags',
            '-of', 'json',
            $Path
        ) 2>$null | Out-String
        if ([string]::IsNullOrWhiteSpace($json)) { return '' }
        $metadata = $json | ConvertFrom-Json
        if (-not $metadata.format -or -not $metadata.format.tags) { return '' }
        $tags = $metadata.format.tags
        $tagNames = @('album', 'release', 'album_title')
        foreach ($tagName in $tagNames) {
            foreach ($property in @($tags.PSObject.Properties)) {
                if ($property.Name -ieq $tagName) {
                    $candidate = Clean-MarqueeText ([string]$property.Value)
                    if (-not [string]::IsNullOrWhiteSpace($candidate)) { return $candidate }
                }
            }
        }
    }
    catch {
    }
    return ''
}

function Get-MusicBrainzTextParts {
    param([hashtable]$Parts)
    if (-not (Test-Path -LiteralPath $MusicBrainzMetadataScript)) { return $Parts }
    $candidates = @(Get-MusicBrainzCandidateParts -Parts $Parts)
    try {
        foreach ($candidate in $candidates) {
            if ([string]::IsNullOrWhiteSpace($candidate['Title'])) { continue }
            $releaseCandidate = [string]$candidate['ReleaseTitle']
            $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $MusicBrainzMetadataScript, '-Artist', $candidate['Artist'], '-Title', $candidate['Title'], '-CacheDir', $MetadataCacheDir, '-LookupMode', 'standard')
            if (-not [string]::IsNullOrWhiteSpace($releaseCandidate)) {
                $args += @('-ReleaseTitle', $releaseCandidate)
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$candidate['ReleaseYear'])) {
                $args += @('-ReleaseYear', [string]$candidate['ReleaseYear'])
            }
            $json = & powershell @args 2>$null | Select-Object -First 1
            if ([string]::IsNullOrWhiteSpace($json)) { continue }
            $metadata = $json | ConvertFrom-Json
            $artist = Normalize-MarqueeArtist ([string]$metadata.Artist)
            $filenameArtist = Normalize-MarqueeArtist ([string]$Parts['Artist'])
            $title = Clean-MarqueeTitle ([string]$Parts['Title'])
            if ([string]::IsNullOrWhiteSpace($artist)) { $artist = [string]$candidate['Artist'] }
            if ((-not [string]::IsNullOrWhiteSpace($filenameArtist)) -and $filenameArtist -ine 'UNKNOWN ARTIST') {
                $foldedArtist = (($artist.Normalize('FormD') -replace '\p{Mn}', '').ToLowerInvariant() -replace '\bac\s*/?\s*dc\b', 'acdc' -replace '\b(ft|feat|featuring|with|and|y|con|x)\b', ' ' -replace '[^\p{L}\p{Nd}]+', ' ' -replace '\ba\s+ap\b', 'asap' -replace '\s+', ' ').Trim()
                $foldedFilenameArtist = (($filenameArtist.Normalize('FormD') -replace '\p{Mn}', '').ToLowerInvariant() -replace '\bac\s*/?\s*dc\b', 'acdc' -replace '\b(ft|feat|featuring|with|and|y|con|x)\b', ' ' -replace '[^\p{L}\p{Nd}]+', ' ' -replace '\ba\s+ap\b', 'asap' -replace '\s+', ' ').Trim()
                if ([string]::IsNullOrWhiteSpace($foldedArtist) -or [string]::IsNullOrWhiteSpace($foldedFilenameArtist) -or (($foldedArtist -ne $foldedFilenameArtist) -and ($foldedArtist -notmatch ('(^| )' + [regex]::Escape($foldedFilenameArtist) + '( |$)')) -and ($foldedFilenameArtist -notmatch ('(^| )' + [regex]::Escape($foldedArtist) + '( |$)')))) { $artist = $filenameArtist }
            }
            if ([string]::IsNullOrWhiteSpace($title)) { $title = [string]$candidate['Title'] }
            return @{
                Artist = $artist.Trim().ToUpperInvariant()
                Title = $title.Trim().ToUpperInvariant()
                ReleaseTitle = ([string]$metadata.ReleaseTitle).Trim().ToUpperInvariant()
                ReleaseYear = if (-not [string]::IsNullOrWhiteSpace([string]$metadata.ReleaseDate)) { ([string]$metadata.ReleaseDate -replace '^((19|20)\d{2}).*$', '$1') } else { [string]$candidate['ReleaseYear'] }
                ReleaseMbid = ([string]$metadata.ReleaseMbid).Trim()
                ReleaseMatchSource = ([string]$metadata.ReleaseMatchSource).Trim()
                ArtistMbid = ([string]$metadata.ArtistMbid).Trim()
            }
        }
    }
    catch {
    }
    return $Parts
}

function Get-MusicBrainzCandidateParts {
    param([hashtable]$Parts)

    $seen = @{}
    $candidates = @()
    foreach ($titleCandidate in (Get-TitleLookupCandidates -Title ([string]$Parts['Title']))) {
        $candidate = @{}
        foreach ($key in $Parts.Keys) { $candidate[$key] = $Parts[$key] }
        $candidate['Title'] = $titleCandidate.Trim().ToUpperInvariant()
        $key = (([string]$candidate['Artist']) + '|' + ([string]$candidate['Title']) + '|' + ([string]$candidate['ReleaseTitle']) + '|' + ([string]$candidate['ReleaseYear'])).ToUpperInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $candidates += $candidate
    }
    return @($candidates)
}

function Get-TitleLookupCandidates {
    param([string]$Title)

    $clean = Clean-MarqueeTitle $Title
    if ([string]::IsNullOrWhiteSpace($clean)) { return @() }
    $results = New-Object System.Collections.Generic.List[string]
    $results.Add($clean)
    $foldedCleanTitle = (($clean.Normalize('FormD') -replace '\p{Mn}', '').ToLowerInvariant() -replace '[^\p{L}\p{Nd}]+', ' ' -replace '\ba\s+ap\b', 'asap' -replace '\s+', ' ').Trim()
    if ($foldedCleanTitle -eq 'whiskey black demarco') {
        $results.Add('WHISKEY (RELEASE ME)')
        $results.Add('AIR FORCE (BLACK DEMARCO)')
        $results.Add('WHISKEY / BLACK DEMARCO')
    }
    $dashParts = @($clean -split '\s*[-–—]+\s*' | ForEach-Object { Clean-MarqueeTitle $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_.Length -ge 2 })
    if ($dashParts.Count -gt 1) {
        foreach ($part in $dashParts) { $results.Add($part) }
    }
    $deduped = @()
    $seen = @{}
    foreach ($item in $results) {
        $key = $item.ToUpperInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $deduped += $item
    }
    return @($deduped)
}

function Split-ArtistCandidates {
    param([string]$Artist)
    if ([string]::IsNullOrWhiteSpace($Artist)) { return @() }
    $clean = $Artist -replace '(?i)\s+\b(ft\.?|feat\.?|featuring)\b\.?\s+', ' & '
    $clean = $clean -replace '(?i)\s+\b(with|and|x|y|con)\b\s+', ' & '
    return @($clean -split '\s*&\s+' | ForEach-Object {
        $candidate = Clean-MarqueeText $_
        $candidate.Trim()
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -ine 'UNKNOWN ARTIST' } | Select-Object -Unique)
}

function Find-ArtistMbidByName {
    param([string]$Artist)
    if ([string]::IsNullOrWhiteSpace($Artist)) { return '' }
    try {
        $encodedArtist = [Uri]::EscapeDataString(('artist:"{0}"' -f $Artist))
        $uri = 'https://musicbrainz.org/ws/2/artist/?query={0}&fmt=json&limit=8' -f $encodedArtist
        $headers = @{ 'User-Agent' = 'JukeboxDownloadWizard/0.3.0.0 (animated marquee artist lookup)' }
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 15
        $foldedArtist = (($Artist.Normalize('FormD') -replace '\p{Mn}', '').ToLowerInvariant() -replace '\bac\s*/?\s*dc\b', 'acdc' -replace '\b(ft|feat|featuring|with|and|y|con|x)\b', ' ' -replace '[^\p{L}\p{Nd}]+', ' ' -replace '\ba\s+ap\b', 'asap' -replace '\s+', ' ').Trim()
        $match = @($response.artists) | Sort-Object @{ Expression = {
            $score = [int]($_.score -as [int])
            $name = ((([string]$_.name).Normalize('FormD') -replace '\p{Mn}', '').ToLowerInvariant() -replace '\bac\s*/?\s*dc\b', 'acdc' -replace '\b(ft|feat|featuring|with|and|y|con|x)\b', ' ' -replace '[^\p{L}\p{Nd}]+', ' ' -replace '\ba\s+ap\b', 'asap' -replace '\s+', ' ').Trim()
            if ($name -eq $foldedArtist) { $score += 100 }
            $score
        }; Descending = $true } | Select-Object -First 1
        if ($match -and $match.id) {
            return [string]$match.id
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

function Get-ArtistLogoPath {
    param([hashtable]$Parts)
    if (-not (Test-Path -LiteralPath $ArtistArtLookupScript)) { return '' }
    try {
        if (-not [string]::IsNullOrWhiteSpace($Parts['ArtistMbid'])) {
            $logo = & powershell -NoProfile -ExecutionPolicy Bypass -File $ArtistArtLookupScript -ArtistMbid $Parts['ArtistMbid'] -Artist $Parts['Artist'] -CacheDir $ArtistArtCacheDir -ProjectKeyPath $FanartProjectKeyPath -PersonalKeyPath $FanartPersonalKeyPath -AssetType Logo 2>$null | Select-Object -First 1
            if ($logo -and (Test-Path -LiteralPath $logo)) { return [string]$logo }
        }
        foreach ($artistName in (Split-ArtistCandidates $Parts['Artist'])) {
            $artistMbid = Find-ArtistMbidByName $artistName
            if ([string]::IsNullOrWhiteSpace($artistMbid)) { continue }
            $logo = & powershell -NoProfile -ExecutionPolicy Bypass -File $ArtistArtLookupScript -ArtistMbid $artistMbid -Artist $artistName -CacheDir $ArtistArtCacheDir -ProjectKeyPath $FanartProjectKeyPath -PersonalKeyPath $FanartPersonalKeyPath -AssetType Logo 2>$null | Select-Object -First 1
            if ($logo -and (Test-Path -LiteralPath $logo)) { return [string]$logo }
        }
    }
    catch {
    }
    return ''
}

function Test-ConfidentAlbumCover {
    param([hashtable]$Parts)
    if (-not [string]::IsNullOrWhiteSpace([string]$Parts['ReleaseMbid'])) { return $true }
    if ([string]$Parts['ReleaseMatchSource'] -ieq 'release_tag') { return $true }
    $releaseTitle = Clean-MarqueeText ([string]$Parts['ReleaseTitle'])
    $title = Clean-MarqueeText ([string]$Parts['Title'])
    if ([string]::IsNullOrWhiteSpace($releaseTitle) -or [string]::IsNullOrWhiteSpace($title)) { return $false }
    if ($releaseTitle -ieq $title) { return $true }
    if ($releaseTitle -match ('(?i)^' + [regex]::Escape($title) + '\s*[\(\[]')) { return $true }
    return $false
}

function Test-AlbumCoverLookupAllowed {
    param([hashtable]$Parts)
    if (Test-ConfidentAlbumCover -Parts $Parts) { return $true }

    $artist = [string]$Parts['Artist']
    $title = [string]$Parts['Title']
    $releaseYear = [string]$Parts['ReleaseYear']
    return (
        -not [string]::IsNullOrWhiteSpace($artist) -and
        $artist -ine 'UNKNOWN ARTIST' -and
        -not [string]::IsNullOrWhiteSpace($title) -and
        $releaseYear -match '^(19|20)\d{2}$'
    )
}
function Get-AlbumCoverPath {
    param([hashtable]$Parts)
    if (-not (Test-Path -LiteralPath $AlbumArtLookupScript)) { return '' }
    try {
        $artist = [string]$Parts['Artist']
        $title = [string]$Parts['Title']
        $releaseMbid = [string]$Parts['ReleaseMbid']
        $releaseTitle = [string]$Parts['ReleaseTitle']
        if ([string]::IsNullOrWhiteSpace($title) -and [string]::IsNullOrWhiteSpace($releaseMbid)) { return '' }
        $cover = & powershell -NoProfile -ExecutionPolicy Bypass -File $AlbumArtLookupScript -Artist $artist -Title $title -CacheDir $CacheDir -ReleaseMbid $releaseMbid -ReleaseTitle $releaseTitle -LookupMode 'standard' 2>$null | Select-Object -First 1
        if ($cover -and (Test-Path -LiteralPath $cover)) { return [string]$cover }
    }
    catch {
    }
    return ''
}

function Get-FitFont {
    param(
        [Drawing.Graphics]$Graphics,
        [string]$Text,
        [string]$FamilyName,
        [Drawing.FontStyle]$Style,
        [int]$StartSize,
        [int]$MaxWidth
    )

    for ($size = $StartSize; $size -ge 12; $size -= 2) {
        $font = New-MarqueeFont $FamilyName $size $Style
        $measured = $Graphics.MeasureString($Text, $font)
        if ($measured.Width -le $MaxWidth) { return $font }
        $font.Dispose()
    }
    return New-MarqueeFont $FamilyName 12 $Style
}

function Get-FitFontForRect {
    param(
        [Drawing.Graphics]$Graphics,
        [string]$Text,
        [string]$FamilyName,
        [Drawing.FontStyle]$Style,
        [int]$StartSize,
        [Drawing.RectangleF]$Rect,
        [int]$MaxLines = 1,
        [switch]$PreferWrap
    )

    $textWordCount = @($Text -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
    $wrapByCharacters = ($MaxLines -gt 1 -and $Text.Length -ge 28 -and $textWordCount -ge 3)
    $allowWrap = ($MaxLines -gt 1 -and ($PreferWrap -or $wrapByCharacters))
    $effectiveStartSize = if ($allowWrap) { [int]($StartSize * 0.98) } else { $StartSize }
    $effectPad = if ($allowWrap) { [Math]::Max(10.0, [double]($effectiveStartSize * 0.12)) } else { [Math]::Max(10.0, [double]($effectiveStartSize * 0.10)) }
    $maxWidth = [Math]::Max(12.0, ($Rect.Width - (28.0 + ($effectPad * 2.0))))
    $maxHeight = [Math]::Max(12.0, ($Rect.Height - (4.0 + ($effectPad * 0.45))))
    for ($fontSize = $effectiveStartSize; $fontSize -ge 12; $fontSize -= 2) {
        $font = New-MarqueeFont $FamilyName $fontSize $Style
        $keepFont = $false
        try {
            $oneLineWidth = [double]($Graphics.MeasureString($Text, $font).Width)
            $allowWrap = ($MaxLines -gt 1 -and ($PreferWrap -or $wrapByCharacters -or ($Text.Length -ge 34 -and $oneLineWidth -gt ($maxWidth * 1.08))))
            $fitMaxLines = if ($allowWrap) { $MaxLines } else { 1 }
            $lines = Split-MarqueeTextLinesForWidth -Graphics $Graphics -Text $Text -Font $font -MaxWidth $maxWidth -MaxLines $fitMaxLines -PreferWrap:$allowWrap
            $lineHeightScale = if ($allowWrap) { 1.04 } else { 1.05 }
            $lineHeight = [Math]::Max(1.0, $font.GetHeight($Graphics) * $lineHeightScale)
            $totalHeight = $lineHeight * $lines.Count
            $widest = 0.0
            foreach ($line in $lines) {
                $size = $Graphics.MeasureString($line, $font)
                $widest = [Math]::Max($widest, [double]$size.Width)
            }
            if ($widest -le $maxWidth -and $totalHeight -le $maxHeight) {
                $keepFont = $true
                return $font
            }
        }
        finally {
            if (-not $keepFont) { $font.Dispose() }
        }
    }
    return New-MarqueeFont $FamilyName 12 $Style
}

function Get-OneLineTextStartSize {
    param(
        [string]$Text,
        [int]$BaseSize,
        [int]$ShortSize,
        [int]$VeryShortSize
    )

    $clean = if ([string]::IsNullOrWhiteSpace($Text)) { '' } else { ($Text -replace '\s+', ' ').Trim() }
    $lettersAndNumbers = ($clean -replace '[^\p{L}\p{Nd}]', '')
    if ($lettersAndNumbers.Length -le 0) { return $BaseSize }
    if ($lettersAndNumbers.Length -le 6) { return $VeryShortSize }
    if ($lettersAndNumbers.Length -le 13) { return $ShortSize }
    return $BaseSize
}

function Split-MarqueeTextLinesForWidth {
    param(
        [Drawing.Graphics]$Graphics,
        [string]$Text,
        [Drawing.Font]$Font,
        [double]$MaxWidth,
        [int]$MaxLines = 2,
        [switch]$PreferWrap
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return @('') }
    $words = @($Text -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($words.Count -le 1 -or $MaxLines -le 1) { return @($Text) }

    if ($PreferWrap -and $MaxLines -ge 2 -and $words.Count -ge 3) {
        $best = $null
        for ($splitIndex = 1; $splitIndex -lt $words.Count; $splitIndex++) {
            $lineA = ($words[0..($splitIndex - 1)] -join ' ')
            $lineB = ($words[$splitIndex..($words.Count - 1)] -join ' ')
            $widthA = [double]($Graphics.MeasureString($lineA, $Font).Width)
            $widthB = [double]($Graphics.MeasureString($lineB, $Font).Width)
            if ($widthA -le $MaxWidth -and $widthB -le $MaxWidth) {
                $widest = [Math]::Max($widthA, $widthB)
                $balancePenalty = [Math]::Abs($widthA - $widthB) * 0.22
                $score = $widest + $balancePenalty
                if ($null -eq $best -or $score -lt $best.Score) {
                    $best = [pscustomobject]@{ Lines = @($lineA, $lineB); Score = $score }
                }
            }
        }
        if ($best) { return @($best.Lines) }
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $current = ''
    foreach ($word in $words) {
        $candidate = if ([string]::IsNullOrWhiteSpace($current)) { $word } else { $current + ' ' + $word }
        $candidateSize = $Graphics.MeasureString($candidate, $Font)
        if ($current.Length -gt 0 -and $lines.Count -lt ($MaxLines - 1) -and $candidateSize.Width -gt $MaxWidth) {
            $lines.Add($current)
            $current = $word
        } else {
            $current = $candidate
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($current)) { $lines.Add($current) }
    while ($lines.Count -gt $MaxLines) {
        $last = $lines[$lines.Count - 1]
        $lines.RemoveAt($lines.Count - 1)
        $lines[$lines.Count - 1] = ($lines[$lines.Count - 1] + ' ' + $last).Trim()
    }
    return @($lines.ToArray())
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

function Get-AverageColor {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return New-Color 255 68 210 }

    $img = [Drawing.Image]::FromFile($Path)
    try {
        $bmp = New-Object Drawing.Bitmap $img, 32, 32
        try {
            [long]$r = 0; [long]$g = 0; [long]$b = 0; [long]$count = 0
            for ($y = 0; $y -lt $bmp.Height; $y++) {
                for ($x = 0; $x -lt $bmp.Width; $x++) {
                    $c = $bmp.GetPixel($x, $y)
                    if ($c.A -gt 20) {
                        $r += $c.R; $g += $c.G; $b += $c.B; $count++
                    }
                }
            }
            if ($count -le 0) { return New-Color 255 68 210 }
            return New-Color ([int]($r / $count)) ([int]($g / $count)) ([int]($b / $count))
        }
        finally { $bmp.Dispose() }
    }
    finally { $img.Dispose() }
}

function Save-JpegUnderLimit {
    param([Drawing.Bitmap]$Bitmap, [string]$Path, [int]$MaxBytes)
    $codec = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
    for ($quality = 92; $quality -ge 50; $quality -= 4) {
        $params = New-Object Drawing.Imaging.EncoderParameters(1)
        try {
            $params.Param[0] = New-Object Drawing.Imaging.EncoderParameter([Drawing.Imaging.Encoder]::Quality, [int64]$quality)
            $Bitmap.Save($Path, $codec, $params)
        }
        finally {
            $params.Dispose()
        }
        if ((Get-Item -LiteralPath $Path).Length -le $MaxBytes) { return }
    }
}

function Draw-GlowLine {
    param(
        [Drawing.Graphics]$Graphics,
        [Drawing.PointF[]]$Points,
        [Drawing.Color]$Color,
        [float]$Width
    )

    foreach ($spec in @(
        @{ W = $Width * 7; A = 26 },
        @{ W = $Width * 4; A = 58 },
        @{ W = $Width * 2; A = 120 },
        @{ W = $Width; A = 230 }
    )) {
        $pen = New-Object Drawing.Pen (New-Color $Color.R $Color.G $Color.B $spec.A), ([float]$spec.W)
        try {
            $pen.StartCap = [Drawing.Drawing2D.LineCap]::Round
            $pen.EndCap = [Drawing.Drawing2D.LineCap]::Round
            $pen.LineJoin = [Drawing.Drawing2D.LineJoin]::Round
            $Graphics.DrawLines($pen, $Points)
        }
        finally { $pen.Dispose() }
    }
}

function Fill-SoftEllipse {
    param(
        [Drawing.Graphics]$Graphics,
        [int]$X,
        [int]$Y,
        [int]$W,
        [int]$H,
        [Drawing.Color]$Color,
        [int]$Alpha
    )

    if ($Alpha -le 0) { return }
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    try {
        $path.AddEllipse($X, $Y, $W, $H)
        $brush = New-Object Drawing.Drawing2D.PathGradientBrush $path
        try {
            $brush.CenterColor = New-Color $Color.R $Color.G $Color.B $Alpha
            $brush.SurroundColors = @(New-Color 0 0 0 0)
            $Graphics.FillPath($brush, $path)
        }
        finally { $brush.Dispose() }
    }
    finally { $path.Dispose() }
}

function Draw-NeonTubeRect {
    param(
        [Drawing.Graphics]$Graphics,
        [Drawing.Rectangle]$Rect,
        [Drawing.Color]$Color,
        [float]$Width,
        [int]$Alpha = 255
    )

    foreach ($spec in @(
        @{ W = $Width * 5; A = [int]($Alpha * 0.16) },
        @{ W = $Width * 2.5; A = [int]($Alpha * 0.34) },
        @{ W = $Width; A = $Alpha }
    )) {
        $pen = New-Object Drawing.Pen (New-Color $Color.R $Color.G $Color.B ([Math]::Min(255, $spec.A))), ([float]$spec.W)
        try {
            $pen.LineJoin = [Drawing.Drawing2D.LineJoin]::Round
            $Graphics.DrawRectangle($pen, $Rect)
        }
        finally { $pen.Dispose() }
    }
}

function Draw-RotatedLine {
    param(
        [Drawing.Graphics]$Graphics,
        [float]$X1,
        [float]$Y1,
        [float]$X2,
        [float]$Y2,
        [Drawing.Color]$Color,
        [float]$Width
    )

    $pen = New-Object Drawing.Pen $Color, $Width
    try {
        $pen.StartCap = [Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [Drawing.Drawing2D.LineCap]::Round
        $Graphics.DrawLine($pen, $X1, $Y1, $X2, $Y2)
    }
    finally { $pen.Dispose() }
}

function Draw-VinylRecord {
    param(
        [Drawing.Graphics]$Graphics,
        [int]$Cx,
        [int]$Cy,
        [int]$Radius,
        [Drawing.Color]$Accent,
        [double]$T,
        [int]$Alpha = 180
    )

    Fill-SoftEllipse $Graphics ($Cx - $Radius - 16) ($Cy - $Radius - 16) (($Radius + 16) * 2) (($Radius + 16) * 2) $Accent ([int]($Alpha * 0.20))
    $blackBrush = New-Object Drawing.SolidBrush (New-Color 4 4 10 $Alpha)
    try { $Graphics.FillEllipse($blackBrush, $Cx - $Radius, $Cy - $Radius, $Radius * 2, $Radius * 2) } finally { $blackBrush.Dispose() }
    for ($r = [int]($Radius * 0.32); $r -lt $Radius; $r += 18) {
        $grooveAlpha = [Math]::Max(18, [Math]::Min(72, [int]($Alpha * (0.18 + (($r % 36) / 180.0)))))
        $pen = New-Object Drawing.Pen (New-Color 255 255 255 $grooveAlpha), 2
        try { $Graphics.DrawEllipse($pen, $Cx - $r, $Cy - $r, $r * 2, $r * 2) } finally { $pen.Dispose() }
    }
    $labelR = [int]($Radius * 0.30)
    $label = Blend-Color $Accent (New-Color 255 255 255) 0.18
    $labelBrush = New-Object Drawing.SolidBrush (New-Color $label.R $label.G $label.B ([Math]::Min(235, $Alpha)))
    try { $Graphics.FillEllipse($labelBrush, $Cx - $labelR, $Cy - $labelR, $labelR * 2, $labelR * 2) } finally { $labelBrush.Dispose() }
    $holeBrush = New-Object Drawing.SolidBrush (New-Color 10 8 16 ([Math]::Min(255, $Alpha)))
    try { $Graphics.FillEllipse($holeBrush, $Cx - 8, $Cy - 8, 16, 16) } finally { $holeBrush.Dispose() }
    $shineAngle = ($T * [Math]::PI * 2.0)
    Draw-RotatedLine $Graphics $Cx $Cy ([float]($Cx + ([Math]::Cos($shineAngle) * $Radius))) ([float]($Cy + ([Math]::Sin($shineAngle) * $Radius))) (New-Color 255 255 255 ([Math]::Min(92, [int]($Alpha * 0.28)))) 5
}

function Draw-SpeakerCab {
    param(
        [Drawing.Graphics]$Graphics,
        [Drawing.Rectangle]$Rect,
        [Drawing.Color]$Accent,
        [Drawing.Color]$Accent2,
        [double]$Pulse,
        [int]$Alpha = 185
    )

    $cabBrush = New-Object Drawing.SolidBrush (New-Color 5 6 16 $Alpha)
    try { $Graphics.FillRectangle($cabBrush, $Rect) } finally { $cabBrush.Dispose() }
    $edgePen = New-Object Drawing.Pen (New-Color $Accent.R $Accent.G $Accent.B ([Math]::Min(180, [int]($Alpha * 0.65)))), 3
    try { $Graphics.DrawRectangle($edgePen, $Rect) } finally { $edgePen.Dispose() }
    foreach ($spec in @(
        @{ Y = 0.32; R = 0.23; C = $Accent },
        @{ Y = 0.70; R = 0.18; C = $Accent2 }
    )) {
        $cx = $Rect.X + [int]($Rect.Width / 2)
        $cy = $Rect.Y + [int]($Rect.Height * $spec.Y)
        $r = [int]([Math]::Min($Rect.Width, $Rect.Height) * ($spec.R + (0.035 * $Pulse)))
        Fill-SoftEllipse $Graphics ($cx - $r - 20) ($cy - $r - 20) (($r + 20) * 2) (($r + 20) * 2) $spec.C ([int](38 + 42 * $Pulse))
        $coneBrush = New-Object Drawing.SolidBrush (New-Color 12 12 22 ([Math]::Min(230, $Alpha)))
        try { $Graphics.FillEllipse($coneBrush, $cx - $r, $cy - $r, $r * 2, $r * 2) } finally { $coneBrush.Dispose() }
        $ringPen = New-Object Drawing.Pen (New-Color $spec.C.R $spec.C.G $spec.C.B ([Math]::Min(210, $Alpha))), 5
        try { $Graphics.DrawEllipse($ringPen, $cx - $r, $cy - $r, $r * 2, $r * 2) } finally { $ringPen.Dispose() }
        $dust = [int]($r * 0.34)
        $dustBrush = New-Object Drawing.SolidBrush (New-Color $spec.C.R $spec.C.G $spec.C.B ([Math]::Min(190, [int]($Alpha * 0.72))))
        try { $Graphics.FillEllipse($dustBrush, $cx - $dust, $cy - $dust, $dust * 2, $dust * 2) } finally { $dustBrush.Dispose() }
    }
}

function Draw-MusicNoteShape {
    param(
        [Drawing.Graphics]$Graphics,
        [int]$X,
        [int]$Y,
        [int]$Size,
        [Drawing.Color]$Color,
        [int]$Alpha = 170
    )

    $brush = New-Object Drawing.SolidBrush (New-Color $Color.R $Color.G $Color.B $Alpha)
    $pen = New-Object Drawing.Pen (New-Color $Color.R $Color.G $Color.B $Alpha), ([Math]::Max(3, [int]($Size / 9)))
    try {
        $Graphics.FillEllipse($brush, $X, ($Y + [int]($Size * 0.62)), ([int]($Size * 0.46)), ([int]($Size * 0.30)))
        $Graphics.DrawLine($pen, ($X + [int]($Size * 0.42)), ($Y + [int]($Size * 0.72)), ($X + [int]($Size * 0.42)), $Y)
        $Graphics.DrawLine($pen, ($X + [int]($Size * 0.42)), $Y, ($X + [int]($Size * 0.86)), ($Y + [int]($Size * 0.16)))
    }
    finally {
        $pen.Dispose()
        $brush.Dispose()
    }
}

function Draw-MicrophoneSilhouette {
    param(
        [Drawing.Graphics]$Graphics,
        [int]$X,
        [int]$Y,
        [int]$W,
        [int]$H,
        [Drawing.Color]$Accent,
        [double]$Tilt
    )

    $state = $Graphics.Save()
    try {
        $Graphics.TranslateTransform($X + [int]($W / 2), $Y + [int]($H / 2))
        $Graphics.RotateTransform([float]$Tilt)
        $Graphics.TranslateTransform(-($X + [int]($W / 2)), -($Y + [int]($H / 2)))
        Fill-SoftEllipse $Graphics ($X - 20) ($Y - 20) ($W + 40) ([int]($H * 0.55)) $Accent 72
        $micBrush = New-Object Drawing.SolidBrush (New-Color 14 14 24 210)
        try {
            $Graphics.FillEllipse($micBrush, $X, $Y, $W, ([int]($H * 0.44)))
            $Graphics.FillRectangle($micBrush, ($X + [int]($W * 0.42)), ($Y + [int]($H * 0.36)), ([int]($W * 0.16)), ([int]($H * 0.46)))
        }
        finally { $micBrush.Dispose() }
        for ($n = 1; $n -le 4; $n++) {
            Draw-RotatedLine $Graphics ($X + 8) ($Y + ($n * 16)) ($X + $W - 8) ($Y + ($n * 16)) (New-Color $Accent.R $Accent.G $Accent.B 118) 2
        }
        Draw-RotatedLine $Graphics ($X + [int]($W / 2)) ($Y + [int]($H * 0.78)) ($X + [int]($W / 2)) ($Y + $H) (New-Color 255 255 255 70) 7
        Draw-RotatedLine $Graphics ($X + [int]($W * 0.24)) ($Y + $H) ($X + [int]($W * 0.76)) ($Y + $H) (New-Color 255 255 255 70) 7
    }
    finally {
        $Graphics.Restore($state)
    }
}

function Draw-DrumKitSilhouette {
    param(
        [Drawing.Graphics]$Graphics,
        [int]$X,
        [int]$Y,
        [int]$Scale,
        [Drawing.Color]$Accent,
        [Drawing.Color]$Accent2,
        [double]$Pulse
    )

    Fill-SoftEllipse $Graphics ($X - 32) ($Y + [int]($Scale * 0.22)) ([int]($Scale * 2.65)) ([int]($Scale * 0.92)) $Accent ([int](42 + 32 * $Pulse))
    $brush = New-Object Drawing.SolidBrush (New-Color 8 9 18 205)
    $pen = New-Object Drawing.Pen (New-Color $Accent.R $Accent.G $Accent.B 150), ([Math]::Max(3, [int]($Scale * 0.04)))
    try {
        $Graphics.FillEllipse($brush, $X, ($Y + [int]($Scale * 0.34)), $Scale, $Scale)
        $Graphics.DrawEllipse($pen, $X, ($Y + [int]($Scale * 0.34)), $Scale, $Scale)
        $Graphics.FillEllipse($brush, ($X + [int]($Scale * 1.12)), ($Y + [int]($Scale * 0.22)), ([int]($Scale * 0.74)), ([int]($Scale * 0.48)))
        $Graphics.DrawEllipse($pen, ($X + [int]($Scale * 1.12)), ($Y + [int]($Scale * 0.22)), ([int]($Scale * 0.74)), ([int]($Scale * 0.48)))
        $Graphics.FillEllipse($brush, ($X + [int]($Scale * 1.78)), ($Y + [int]($Scale * 0.02)), ([int]($Scale * 0.52)), ([int]($Scale * 0.20)))
    }
    finally {
        $pen.Dispose()
        $brush.Dispose()
    }
    Draw-RotatedLine $Graphics ($X + [int]($Scale * 1.92)) ($Y + [int]($Scale * 0.22)) ($X + [int]($Scale * 1.72)) ($Y + [int]($Scale * 1.10)) (New-Color 255 255 255 74) 4
    Draw-RotatedLine $Graphics ($X + [int]($Scale * 2.08)) ($Y + [int]($Scale * 0.22)) ($X + [int]($Scale * 2.30)) ($Y + [int]($Scale * 1.08)) (New-Color 255 255 255 74) 4
    Draw-RotatedLine $Graphics ($X + [int]($Scale * 1.20)) ($Y + [int]($Scale * 0.12)) ($X + [int]($Scale * 1.78)) ($Y - [int]($Scale * 0.10)) (New-Color $Accent2.R $Accent2.G $Accent2.B 132) 5
    Draw-RotatedLine $Graphics ($X + [int]($Scale * 1.22)) ($Y + [int]($Scale * 0.00)) ($X + [int]($Scale * 1.80)) ($Y + [int]($Scale * 0.18)) (New-Color $Accent2.R $Accent2.G $Accent2.B 132) 5
}

function Draw-GuitarSilhouette {
    param(
        [Drawing.Graphics]$Graphics,
        [int]$X,
        [int]$Y,
        [int]$W,
        [int]$H,
        [Drawing.Color]$Accent,
        [double]$Tilt
    )

    $state = $Graphics.Save()
    try {
        $Graphics.TranslateTransform($X + [int]($W / 2), $Y + [int]($H / 2))
        $Graphics.RotateTransform([float]$Tilt)
        $Graphics.TranslateTransform(-($X + [int]($W / 2)), -($Y + [int]($H / 2)))
        Fill-SoftEllipse $Graphics ($X - 28) ($Y + [int]($H * 0.42)) ([int]($W * 1.10)) ([int]($H * 0.55)) $Accent 58
        $brush = New-Object Drawing.SolidBrush (New-Color 10 9 18 205)
        $pen = New-Object Drawing.Pen (New-Color $Accent.R $Accent.G $Accent.B 154), 4
        try {
            $Graphics.FillEllipse($brush, $X, ($Y + [int]($H * 0.54)), ([int]($W * 0.54)), ([int]($H * 0.32)))
            $Graphics.FillEllipse($brush, ($X + [int]($W * 0.30)), ($Y + [int]($H * 0.42)), ([int]($W * 0.48)), ([int]($H * 0.28)))
            $Graphics.DrawEllipse($pen, $X, ($Y + [int]($H * 0.54)), ([int]($W * 0.54)), ([int]($H * 0.32)))
            $Graphics.DrawEllipse($pen, ($X + [int]($W * 0.30)), ($Y + [int]($H * 0.42)), ([int]($W * 0.48)), ([int]($H * 0.28)))
            $Graphics.FillRectangle($brush, ($X + [int]($W * 0.60)), ($Y + [int]($H * 0.48)), ([int]($W * 0.82)), ([int]($H * 0.08)))
            $Graphics.FillRectangle($brush, ($X + [int]($W * 1.34)), ($Y + [int]($H * 0.40)), ([int]($W * 0.22)), ([int]($H * 0.22)))
        }
        finally {
            $pen.Dispose()
            $brush.Dispose()
        }
        for ($s = 0; $s -lt 4; $s++) {
            $yy = $Y + [int]($H * (0.50 + ($s * 0.018)))
            Draw-RotatedLine $Graphics ($X + [int]($W * 0.18)) $yy ($X + [int]($W * 1.50)) $yy (New-Color 255 255 255 66) 1.4
        }
    }
    finally {
        $Graphics.Restore($state)
    }
}

function Draw-HeadphonesSilhouette {
    param(
        [Drawing.Graphics]$Graphics,
        [int]$X,
        [int]$Y,
        [int]$W,
        [int]$H,
        [Drawing.Color]$Accent,
        [double]$Pulse
    )

    Fill-SoftEllipse $Graphics ($X - 34) ($Y - 20) ($W + 68) ($H + 70) $Accent ([int](38 + 34 * $Pulse))
    $pen = New-Object Drawing.Pen (New-Color $Accent.R $Accent.G $Accent.B 170), ([Math]::Max(8, [int]($W * 0.055)))
    try {
        $Graphics.DrawArc($pen, $X, $Y, $W, $H, 200, 140)
    }
    finally { $pen.Dispose() }
    $brush = New-Object Drawing.SolidBrush (New-Color 8 9 18 218)
    try {
        $Graphics.FillRectangle($brush, ($X + [int]($W * 0.06)), ($Y + [int]($H * 0.46)), ([int]($W * 0.20)), ([int]($H * 0.38)))
        $Graphics.FillRectangle($brush, ($X + [int]($W * 0.74)), ($Y + [int]($H * 0.46)), ([int]($W * 0.20)), ([int]($H * 0.38)))
    }
    finally { $brush.Dispose() }
    Draw-RotatedLine $Graphics ($X + [int]($W * 0.20)) ($Y + [int]($H * 0.86)) ($X + [int]($W * 0.80)) ($Y + [int]($H * 0.86)) (New-Color 255 255 255 50) 3
}

function Draw-KeyboardShape {
    param(
        [Drawing.Graphics]$Graphics,
        [Drawing.Rectangle]$Rect,
        [Drawing.Color]$Accent,
        [double]$Pulse
    )

    Fill-SoftEllipse $Graphics ($Rect.X - 30) ($Rect.Y - 26) ($Rect.Width + 60) ($Rect.Height + 58) $Accent ([int](24 + 22 * $Pulse))
    $body = New-Object Drawing.SolidBrush (New-Color 245 245 255 178)
    try { $Graphics.FillRectangle($body, $Rect) } finally { $body.Dispose() }
    $whiteKeyW = [Math]::Max(8, [int]($Rect.Width / 18))
    for ($n = 0; $n -lt 18; $n++) {
        $x = $Rect.X + ($n * $whiteKeyW)
        $pen = New-Object Drawing.Pen (New-Color 12 10 20 96), 1
        try { $Graphics.DrawLine($pen, $x, $Rect.Y, $x, ($Rect.Y + $Rect.Height)) } finally { $pen.Dispose() }
    }
    $black = New-Object Drawing.SolidBrush (New-Color 5 5 14 215)
    try {
        foreach ($n in @(0,1,3,4,5,7,8,10,11,12,14,15)) {
            $x = $Rect.X + [int](($n + 0.68) * $whiteKeyW)
            $Graphics.FillRectangle($black, $x, $Rect.Y, ([int]($whiteKeyW * 0.62)), ([int]($Rect.Height * 0.62)))
        }
    }
    finally { $black.Dispose() }
}

function Draw-TemplateBackground {
    param(
        [Drawing.Graphics]$Graphics,
        [string]$TemplateName,
        [double]$T,
        [Drawing.Color]$Accent,
        [Drawing.Color]$Accent2,
        [Drawing.Color]$Pink,
        [Drawing.Color]$Cyan,
        [Drawing.Color]$DarkStroke,
        [int]$Width,
        [int]$Height,
        [int]$TemplateVariant = 0
    )

    $variant = [Math]::Abs($TemplateVariant) % 8
    $T = $T % 1.0
    switch ($variant) {
        1 {
            $tmp = $Accent
            $Accent = $Accent2
            $Accent2 = $tmp
        }
        2 {
            $Accent = Blend-Color $Accent $Cyan 0.42
            $Accent2 = Blend-Color $Accent2 $Pink 0.30
        }
        3 {
            $Accent = Blend-Color $Accent $Pink 0.42
            $Accent2 = Blend-Color $Accent2 $Cyan 0.34
        }
        4 {
            $tmp = $Pink
            $Pink = $Cyan
            $Cyan = $tmp
        }
        5 {
            $Accent = Blend-Color $Accent (New-Color 255 178 60) 0.42
            $Accent2 = Blend-Color $Accent2 (New-Color 90 235 255) 0.26
        }
        6 {
            $Accent = Blend-Color $Accent (New-Color 150 90 255) 0.38
            $Cyan = Blend-Color $Cyan (New-Color 255 255 255) 0.20
        }
        7 {
            $Accent2 = Blend-Color $Accent2 (New-Color 255 70 130) 0.38
            $Pink = Blend-Color $Pink $Accent 0.25
        }
    }

    $loopPhase = $T * [Math]::PI * 2.0
    $pulse = 0.5 + 0.5 * [Math]::Sin($loopPhase)
    $altPulse = 0.5 + 0.5 * [Math]::Sin($loopPhase + 1.7)
    $rect = New-Object Drawing.Rectangle 0, 0, $Width, $Height

    switch ($TemplateName) {
        'NeonEqualizer' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 4 3 18), (New-Color 7 32 54), ([Drawing.Drawing2D.LinearGradientMode]::Vertical)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            Fill-SoftEllipse $Graphics 220 -160 680 520 $Accent ([int](46 + 26 * $pulse))
            Fill-SoftEllipse $Graphics 1040 -130 720 520 $Accent2 ([int](40 + 24 * $altPulse))
            for ($x = 36; $x -lt $Width; $x += 42) {
                $barH = 42 + 126 * (0.5 + 0.5 * [Math]::Sin(($x * 0.035) + $loopPhase))
                $color = if (($x / 42) % 3 -eq 0) { $Accent } elseif (($x / 42) % 3 -eq 1) { $Cyan } else { $Pink }
                $pen = New-Object Drawing.Pen (New-Color $color.R $color.G $color.B 138), 12
                try {
                    $pen.StartCap = [Drawing.Drawing2D.LineCap]::Round
                    $pen.EndCap = [Drawing.Drawing2D.LineCap]::Round
                    $Graphics.DrawLine($pen, $x, ([float](330 - $barH)), $x, 330)
                }
                finally { $pen.Dispose() }
            }
        }
        'CrtWall' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 5 8 18), (New-Color 18 5 32), ([Drawing.Drawing2D.LinearGradientMode]::Horizontal)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            for ($y = -12; $y -lt $Height; $y += 18) {
                $brush = New-Object Drawing.SolidBrush (New-Color 255 255 255 16)
                try { $Graphics.FillRectangle($brush, 0, $y, $Width, 2) } finally { $brush.Dispose() }
            }
            for ($row = 0; $row -lt 3; $row++) {
                for ($col = 0; $col -lt 9; $col++) {
                    $x = 24 + ($col * 218)
                    $y = 22 + ($row * 108)
                    $c = if (($row + $col) % 2 -eq 0) { $Accent } else { $Accent2 }
                    Draw-NeonTubeRect $Graphics (New-Object Drawing.Rectangle $x, $y, 160, 72) $c 3 ([int](108 + 40 * $pulse))
                    Fill-SoftEllipse $Graphics ($x + 20) ($y + 8) 120 58 $c ([int](20 + 10 * $altPulse))
                }
            }
        }
        'JukeboxLightbox' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 38 8 12), (New-Color 6 8 28), ([Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            for ($x = -180; $x -lt $Width + 180; $x += 150) {
                $c = if (($x / 150) % 2 -eq 0) { $Accent } else { $Pink }
                $offset = $T * 150.0
                Draw-RotatedLine $Graphics ([float]($x + $offset)) 380 ([float]($x + 260 + $offset)) -20 (New-Color $c.R $c.G $c.B 76) 22
            }
            foreach ($x in @(60, 260, 460, 1460, 1660, 1860)) {
                Fill-SoftEllipse $Graphics ($x - 54) 20 108 108 $Accent ([int](64 + 34 * $pulse))
                Fill-SoftEllipse $Graphics ($x - 54) 230 108 108 $Cyan ([int](54 + 28 * $altPulse))
            }
        }
        'ConcertStage' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 2 2 10), (New-Color 28 10 40), ([Drawing.Drawing2D.LinearGradientMode]::Vertical)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            foreach ($spot in @(
                @{ X = 180; C = $Accent; Phase = 0.0 },
                @{ X = 960; C = $Cyan; Phase = 1.4 },
                @{ X = 1660; C = $Pink; Phase = 2.7 }
            )) {
                $angle = [Math]::Sin($loopPhase + $spot.Phase) * 42
                $path = New-Object Drawing.Drawing2D.GraphicsPath
                try {
                    $path.AddPolygon(@(
                        (New-Object Drawing.PointF ([float]$spot.X), -20),
                        (New-Object Drawing.PointF ([float]($spot.X + $angle - 210)), 380),
                        (New-Object Drawing.PointF ([float]($spot.X + $angle + 210)), 380)
                    ))
                    $brush = New-Object Drawing.SolidBrush (New-Color $spot.C.R $spot.C.G $spot.C.B 44)
                    try { $Graphics.FillPath($brush, $path) } finally { $brush.Dispose() }
                }
                finally { $path.Dispose() }
            }
            for ($y = 285; $y -le 350; $y += 18) {
                Draw-RotatedLine $Graphics 0 $y $Width $y (New-Color 255 255 255 18) 1
            }
        }
        'VinylSpin' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 7 4 18), (New-Color 34 20 8), ([Drawing.Drawing2D.LinearGradientMode]::Horizontal)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            foreach ($cx in @(260, 1630)) {
                for ($r = 64; $r -le 310; $r += 32) {
                    $pen = New-Object Drawing.Pen (New-Color $Accent.R $Accent.G $Accent.B ([int](42 - ($r / 11)))), 3
                    try { $Graphics.DrawEllipse($pen, $cx - $r, 180 - $r, $r * 2, $r * 2) } finally { $pen.Dispose() }
                }
                $start = [float](($T * 360.0) % 360)
                $pen2 = New-Object Drawing.Pen (New-Color $Cyan.R $Cyan.G $Cyan.B 128), 8
                try { $Graphics.DrawArc($pen2, $cx - 190, -10, 380, 380, $start, 72) } finally { $pen2.Dispose() }
            }
            Fill-SoftEllipse $Graphics 620 -160 680 520 $Accent2 ([int](34 + 22 * $pulse))
        }
        'ArcadeMarquee' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 12 0 32), (New-Color 0 28 50), ([Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            for ($x = 0; $x -lt $Width; $x += 80) {
                $color = if (($x / 80) % 2 -eq 0) { $Accent } else { $Cyan }
                $brush = New-Object Drawing.SolidBrush (New-Color $color.R $color.G $color.B 64)
                try { $Graphics.FillPolygon($brush, @(
                    (New-Object Drawing.Point -ArgumentList ([int]$x), 0),
                    (New-Object Drawing.Point -ArgumentList ([int]($x + 48)), 0),
                    (New-Object Drawing.Point -ArgumentList ([int]($x + 128)), ([int]$Height)),
                    (New-Object Drawing.Point -ArgumentList ([int]($x + 80)), ([int]$Height))
                )) } finally { $brush.Dispose() }
            }
        }
        'SmokeNeon' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 3 5 13), (New-Color 22 8 31), ([Drawing.Drawing2D.LinearGradientMode]::BackwardDiagonal)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            for ($n = 0; $n -lt 9; $n++) {
                $x = [int](80 + ($n * 230) + (24 * [Math]::Sin($loopPhase + $n)))
                $y = [int](-80 + (46 * [Math]::Sin($loopPhase + ($n * 0.8))))
                $c = if ($n % 2 -eq 0) { $Accent } else { $Accent2 }
                Fill-SoftEllipse $Graphics $x $y 420 260 $c ([int](18 + 16 * $pulse))
            }
            for ($y = 42; $y -le 330; $y += 72) {
                $wave = New-Object 'Drawing.PointF[]' 5
                $wave[0] = New-Object Drawing.PointF 0, ([float]($y + 8 * [Math]::Sin($loopPhase)))
                $wave[1] = New-Object Drawing.PointF 480, ([float]($y - 18 + 9 * [Math]::Sin($loopPhase + 1)))
                $wave[2] = New-Object Drawing.PointF 960, ([float]($y + 10 * [Math]::Sin($loopPhase + 2)))
                $wave[3] = New-Object Drawing.PointF 1440, ([float]($y + 18 + 9 * [Math]::Sin($loopPhase + 3)))
                $wave[4] = New-Object Drawing.PointF $Width, ([float]($y + 8 * [Math]::Sin($loopPhase + 4)))
                $lineColor = if (($y / 72) % 2 -eq 0) { $Cyan } else { $Pink }
                Draw-GlowLine $Graphics $wave $lineColor 2.0
            }
        }
        'LaserGrid' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 2 4 20), (New-Color 28 2 42), ([Drawing.Drawing2D.LinearGradientMode]::Vertical)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            Fill-SoftEllipse $Graphics 520 -180 920 560 $Accent ([int](34 + 20 * $pulse))
            for ($x = -220; $x -lt $Width + 220; $x += 92) {
                $offset = ($T * 92) % 92
                Draw-RotatedLine $Graphics ([float]($x + $offset)) 350 ([float]($x + 360 + $offset)) 20 (New-Color $Cyan.R $Cyan.G $Cyan.B 92) 3
                Draw-RotatedLine $Graphics ([float]($x - $offset)) 20 ([float]($x - 360 - $offset)) 350 (New-Color $Pink.R $Pink.G $Pink.B 76) 3
            }
            for ($y = 260; $y -le 350; $y += 22) {
                Draw-RotatedLine $Graphics 0 $y $Width $y (New-Color 255 255 255 20) 1
            }
        }
        'PrismBands' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 8 0 24), (New-Color 0 24 34), ([Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            for ($x = -260; $x -lt $Width + 260; $x += 140) {
                $shift = [int](80 * [Math]::Sin($loopPhase + ($x * 0.01)))
                foreach ($band in @(
                    @{ C = $Accent; O = 0 },
                    @{ C = $Cyan; O = 34 },
                    @{ C = $Pink; O = 68 }
                )) {
                    $brush = New-Object Drawing.SolidBrush (New-Color $band.C.R $band.C.G $band.C.B 50)
                    try {
                        $Graphics.FillPolygon($brush, @(
                            (New-Object Drawing.Point -ArgumentList ([int]($x + $shift + $band.O)), 0),
                            (New-Object Drawing.Point -ArgumentList ([int]($x + $shift + 62 + $band.O)), 0),
                            (New-Object Drawing.Point -ArgumentList ([int]($x + $shift + 238 + $band.O)), $Height),
                            (New-Object Drawing.Point -ArgumentList ([int]($x + $shift + 176 + $band.O)), $Height)
                        ))
                    }
                    finally { $brush.Dispose() }
                }
            }
        }
        'Starburst' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 14 4 24), (New-Color 4 8 30), ([Drawing.Drawing2D.LinearGradientMode]::Horizontal)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            Fill-SoftEllipse $Graphics 610 -190 700 700 $Accent ([int](50 + 20 * $pulse))
            $cx = 960
            $cy = 180
            for ($n = 0; $n -lt 40; $n++) {
                $angle = (($n / 40.0) * [Math]::PI * 2.0) + $loopPhase
                $len = 1100 + (120 * [Math]::Sin($loopPhase + $n))
                $x2 = [float]($cx + ([Math]::Cos($angle) * $len))
                $y2 = [float]($cy + ([Math]::Sin($angle) * $len))
                $c = if ($n % 3 -eq 0) { $Accent } elseif ($n % 3 -eq 1) { $Cyan } else { $Pink }
                Draw-RotatedLine $Graphics $cx $cy $x2 $y2 (New-Color $c.R $c.G $c.B 34) 7
            }
        }
        'CassetteDeck' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 10 10 18), (New-Color 34 20 18), ([Drawing.Drawing2D.LinearGradientMode]::Vertical)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            foreach ($cx in @(360, 1560)) {
                Fill-SoftEllipse $Graphics ($cx - 124) 56 248 248 (New-Color 0 0 0) 120
                for ($r = 30; $r -le 116; $r += 22) {
                    $pen = New-Object Drawing.Pen (New-Color $Cyan.R $Cyan.G $Cyan.B ([int](112 - $r / 2))), 4
                    try { $Graphics.DrawEllipse($pen, $cx - $r, 180 - $r, $r * 2, $r * 2) } finally { $pen.Dispose() }
                }
                $angle = $loopPhase
                Draw-RotatedLine $Graphics $cx 180 ([float]($cx + 98 * [Math]::Cos($angle))) ([float](180 + 98 * [Math]::Sin($angle))) (New-Color $Pink.R $Pink.G $Pink.B 128) 6
            }
            Draw-RotatedLine $Graphics 480 180 1440 180 (New-Color 255 255 255 32) 12
        }
        'CityLights' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 2 4 18), (New-Color 20 4 38), ([Drawing.Drawing2D.LinearGradientMode]::Vertical)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            Fill-SoftEllipse $Graphics 720 -160 640 420 $Accent2 ([int](36 + 18 * $altPulse))
            for ($x = 0; $x -lt $Width; $x += 52) {
                $h = 60 + (($x * 37) % 160)
                $brush = New-Object Drawing.SolidBrush (New-Color 4 8 22 180)
                try { $Graphics.FillRectangle($brush, $x, ($Height - $h), 44, $h) } finally { $brush.Dispose() }
                for ($y = $Height - $h + 14; $y -lt $Height - 12; $y += 24) {
                    $c = if ((($x + $y) / 24) % 2 -eq 0) { $Accent } else { $Cyan }
                    $windowBrush = New-Object Drawing.SolidBrush (New-Color $c.R $c.G $c.B ([int](42 + 38 * $pulse)))
                    try { $Graphics.FillRectangle($windowBrush, ($x + 12), $y, 10, 8) } finally { $windowBrush.Dispose() }
                }
            }
        }
        'RetroSunset' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 8 4 30), (New-Color 34 8 18), ([Drawing.Drawing2D.LinearGradientMode]::Vertical)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            Fill-SoftEllipse $Graphics 590 -80 740 420 (New-Color 255 122 64) ([int](74 + 20 * $pulse))
            for ($y = 80; $y -lt 245; $y += 20) {
                $pen = New-Object Drawing.Pen (New-Color 8 4 30 150), 8
                try { $Graphics.DrawLine($pen, 620, $y, 1300, $y) } finally { $pen.Dispose() }
            }
            for ($x = -120; $x -lt $Width + 120; $x += 80) {
                $offset = $T * 80.0
                Draw-RotatedLine $Graphics ([float]($x + $offset)) 350 960 210 (New-Color $Cyan.R $Cyan.G $Cyan.B 52) 2
                Draw-RotatedLine $Graphics ([float]($x - $offset)) 350 960 210 (New-Color $Pink.R $Pink.G $Pink.B 52) 2
            }
        }
        'SoundwaveTunnel' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 0 6 18), (New-Color 20 0 38), ([Drawing.Drawing2D.LinearGradientMode]::Horizontal)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            for ($n = 0; $n -lt 18; $n++) {
                $scale = 1.0 - ($n * 0.045)
                $w = [int]($Width * $scale)
                $h = [int]($Height * $scale)
                $x = [int](($Width - $w) / 2)
                $y = [int](($Height - $h) / 2)
                $c = if ($n % 2 -eq 0) { $Accent } else { $Cyan }
                Fill-SoftEllipse $Graphics ($x + [int]($w * 0.28)) ($y + [int]($h * 0.18)) ([int]($w * 0.44)) ([int]($h * 0.64)) $c ([int](10 + 8 * [Math]::Sin($loopPhase + $n)))
            }
            Fill-SoftEllipse $Graphics 760 20 420 320 $Pink ([int](28 + 16 * $pulse))
        }
        'AuroraCurtain' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 1 8 20), (New-Color 12 2 30), ([Drawing.Drawing2D.LinearGradientMode]::Vertical)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            for ($n = 0; $n -lt 7; $n++) {
                $path = New-Object Drawing.Drawing2D.GraphicsPath
                try {
                    $x0 = -180 + ($n * 340)
                    $path.AddBezier(
                        (New-Object Drawing.PointF ([float]$x0), -40),
                        (New-Object Drawing.PointF ([float]($x0 + 120 + 80 * [Math]::Sin($loopPhase + $n))), 70),
                        (New-Object Drawing.PointF ([float]($x0 - 80 + 90 * [Math]::Cos($loopPhase + $n))), 260),
                        (New-Object Drawing.PointF ([float]($x0 + 180)), 410)
                    )
                    $c = if ($n % 2 -eq 0) { $Accent2 } else { $Cyan }
                    $pen = New-Object Drawing.Pen (New-Color $c.R $c.G $c.B 68), 90
                    try {
                        $pen.StartCap = [Drawing.Drawing2D.LineCap]::Round
                        $pen.EndCap = [Drawing.Drawing2D.LineCap]::Round
                        $Graphics.DrawPath($pen, $path)
                    }
                    finally { $pen.Dispose() }
                }
                finally { $path.Dispose() }
            }
        }
        'VinylShelf' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 6 4 10), (New-Color 28 12 24), ([Drawing.Drawing2D.LinearGradientMode]::Vertical)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            Fill-SoftEllipse $Graphics 420 -150 720 500 $Accent ([int](34 + 18 * $pulse))
            Fill-SoftEllipse $Graphics 1080 -130 640 460 $Accent2 ([int](28 + 18 * $altPulse))
            for ($x = -140; $x -lt $Width + 180; $x += 210) {
                $bob = [int](10 * [Math]::Sin($loopPhase + ($x * 0.012)))
                $recordColor = if (($x / 210) % 2 -eq 0) { $Accent } else { $Cyan }
                Draw-VinylRecord $Graphics ($x + 90) (188 + $bob) 108 $recordColor $T 168
            }
            for ($x = 0; $x -lt $Width; $x += 58) {
                $sleeveColor = if (($x / 58) % 3 -eq 0) { $Pink } elseif (($x / 58) % 3 -eq 1) { $Accent } else { $Cyan }
                $brush = New-Object Drawing.SolidBrush (New-Color $sleeveColor.R $sleeveColor.G $sleeveColor.B 36)
                try { $Graphics.FillRectangle($brush, $x, 292, 36, 58) } finally { $brush.Dispose() }
            }
            Draw-RotatedLine $Graphics 0 292 $Width 292 (New-Color 255 255 255 28) 4
        }
        'SpeakerStack' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 4 4 12), (New-Color 14 8 28), ([Drawing.Drawing2D.LinearGradientMode]::Horizontal)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            for ($x = 0; $x -lt $Width; $x += 96) {
                Draw-RotatedLine $Graphics $x 0 ($x + 160) $Height (New-Color $Accent.R $Accent.G $Accent.B 18) 10
            }
            foreach ($cab in @(
                (New-Object Drawing.Rectangle 40, 24, 210, 312),
                (New-Object Drawing.Rectangle 272, 48, 178, 270),
                (New-Object Drawing.Rectangle 1470, 42, 178, 276),
                (New-Object Drawing.Rectangle 1672, 20, 214, 316)
            )) {
                Draw-SpeakerCab $Graphics $cab $Accent $Cyan $pulse 190
            }
            for ($n = 0; $n -lt 5; $n++) {
                $r = 130 + ($n * 72) + [int](18 * $pulse)
                $pen = New-Object Drawing.Pen (New-Color $Pink.R $Pink.G $Pink.B ([Math]::Max(10, 42 - ($n * 6)))), 3
                try { $Graphics.DrawEllipse($pen, 960 - $r, 180 - [int]($r / 3), $r * 2, [int]($r * 0.66)) } finally { $pen.Dispose() }
            }
        }
        'MicStage' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 2 2 9), (New-Color 32 8 30), ([Drawing.Drawing2D.LinearGradientMode]::Vertical)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            foreach ($spot in @(
                @{ X = 420; C = $Accent; Phase = 0.0 },
                @{ X = 960; C = $Cyan; Phase = 1.8 },
                @{ X = 1500; C = $Pink; Phase = 3.2 }
            )) {
                $sway = [Math]::Sin($loopPhase + $spot.Phase) * 52
                $path = New-Object Drawing.Drawing2D.GraphicsPath
                try {
                    $path.AddPolygon(@(
                        (New-Object Drawing.PointF ([float]$spot.X), -20),
                        (New-Object Drawing.PointF ([float]($spot.X + $sway - 260)), $Height),
                        (New-Object Drawing.PointF ([float]($spot.X + $sway + 260)), $Height)
                    ))
                    $brush = New-Object Drawing.SolidBrush (New-Color $spot.C.R $spot.C.G $spot.C.B 38)
                    try { $Graphics.FillPath($brush, $path) } finally { $brush.Dispose() }
                }
                finally { $path.Dispose() }
            }
            Draw-MicrophoneSilhouette $Graphics 116 58 120 238 $Accent ([Math]::Sin($loopPhase) * 7)
            Draw-MicrophoneSilhouette $Graphics 1664 52 126 248 $Cyan ([Math]::Sin($loopPhase + 2.2) * -7)
            for ($y = 292; $y -le 350; $y += 18) {
                Draw-RotatedLine $Graphics 0 $y $Width $y (New-Color 255 255 255 18) 1
            }
        }
        'NoteStream' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 5 2 18), (New-Color 0 22 34), ([Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            Fill-SoftEllipse $Graphics 520 -150 760 540 $Accent2 ([int](34 + 18 * $pulse))
            $tile = 260.0
            $offset = $T * $tile * 3.0
            for ($n = -4; $n -lt 11; $n++) {
                $slot = (($n % 3) + 3) % 3
                $x = [int]($n * $tile + $offset) - 120
                $y = [int](58 + (110 * (0.5 + 0.5 * [Math]::Sin($loopPhase + ($slot * 0.82)))))
                $size = 62 + ($slot * 16)
                $c = if ($slot -eq 0) { $Pink } elseif ($slot -eq 1) { $Cyan } else { $Accent }
                Fill-SoftEllipse $Graphics ($x - 20) ($y - 20) ($size + 54) ($size + 54) $c 28
                Draw-MusicNoteShape $Graphics $x $y $size $c 148
            }
            for ($y = 82; $y -le 278; $y += 46) {
                $wave = New-Object 'Drawing.PointF[]' 5
                $wave[0] = New-Object Drawing.PointF 0, ([float]($y + 5 * [Math]::Sin($loopPhase + $y)))
                $wave[1] = New-Object Drawing.PointF 480, ([float]($y + 10 * [Math]::Sin($loopPhase + 1)))
                $wave[2] = New-Object Drawing.PointF 960, ([float]($y + 5 * [Math]::Sin($loopPhase + 2)))
                $wave[3] = New-Object Drawing.PointF 1440, ([float]($y - 10 * [Math]::Sin($loopPhase + 3)))
                $wave[4] = New-Object Drawing.PointF $Width, ([float]($y + 5 * [Math]::Sin($loopPhase + 4)))
                Draw-GlowLine $Graphics $wave (New-Color 255 255 255 70) 1.2
            }
        }
        'RecordWall' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 8 6 14), (New-Color 24 8 28), ([Drawing.Drawing2D.LinearGradientMode]::BackwardDiagonal)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            $shift = [int](16 * [Math]::Sin($loopPhase))
            for ($row = 0; $row -lt 3; $row++) {
                for ($col = -1; $col -lt 12; $col++) {
                    $cx = 80 + ($col * 178) + (($row % 2) * 74) + $shift
                    $cy = 60 + ($row * 116) + [int](8 * [Math]::Sin($loopPhase + $col))
                    $c = if (($row + $col) % 3 -eq 0) { $Accent } elseif (($row + $col) % 3 -eq 1) { $Pink } else { $Cyan }
                    Draw-VinylRecord $Graphics $cx $cy 54 $c $T 118
                }
            }
            Fill-SoftEllipse $Graphics 720 20 500 320 $Accent2 ([int](26 + 12 * $altPulse))
        }
        'DrumRoom' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 5 4 10), (New-Color 28 10 18), ([Drawing.Drawing2D.LinearGradientMode]::Vertical)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            for ($x = 0; $x -lt $Width; $x += 120) {
                Draw-RotatedLine $Graphics $x 0 ($x + 90) $Height (New-Color $Accent.R $Accent.G $Accent.B 18) 8
            }
            Draw-DrumKitSilhouette $Graphics 98 112 130 $Accent $Cyan $pulse
            Draw-DrumKitSilhouette $Graphics 1498 108 136 $Pink $Accent2 $altPulse
            for ($n = 0; $n -lt 9; $n++) {
                $cx = 350 + ($n * 150)
                $cy = 88 + [int](24 * [Math]::Sin($loopPhase + $n))
                $hitColor = if ($n % 2 -eq 0) { $Accent } else { $Cyan }
                Fill-SoftEllipse $Graphics ($cx - 28) ($cy - 12) 56 24 $hitColor 28
            }
            Draw-RotatedLine $Graphics 0 302 $Width 302 (New-Color 255 255 255 20) 3
        }
        'GuitarWall' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 4 6 16), (New-Color 32 8 32), ([Drawing.Drawing2D.LinearGradientMode]::Horizontal)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            Fill-SoftEllipse $Graphics 620 -160 700 520 $Accent ([int](32 + 20 * $pulse))
            Draw-GuitarSilhouette $Graphics 110 40 150 250 $Accent (-14 + (5 * [Math]::Sin($loopPhase)))
            Draw-GuitarSilhouette $Graphics 340 58 130 226 $Cyan (12 + (4 * [Math]::Sin($loopPhase + 1.2)))
            Draw-GuitarSilhouette $Graphics 1450 42 150 250 $Pink (-12 + (5 * [Math]::Sin($loopPhase + 2.0)))
            Draw-GuitarSilhouette $Graphics 1660 52 136 234 $Accent2 (14 + (4 * [Math]::Sin($loopPhase + 3.0)))
            for ($y = 72; $y -le 280; $y += 52) {
                Draw-RotatedLine $Graphics 0 $y $Width ($y + [int](12 * [Math]::Sin($loopPhase + $y))) (New-Color 255 255 255 18) 1.5
            }
        }
        'HeadphoneGlow' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 2 8 18), (New-Color 20 4 34), ([Drawing.Drawing2D.LinearGradientMode]::BackwardDiagonal)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            for ($n = 0; $n -lt 7; $n++) {
                $x = 120 + ($n * 285)
                $y = 52 + [int](24 * [Math]::Sin($loopPhase + ($n * 0.9)))
                $c = if ($n % 3 -eq 0) { $Accent } elseif ($n % 3 -eq 1) { $Cyan } else { $Pink }
                Draw-HeadphonesSilhouette $Graphics $x $y 170 220 $c (0.35 + (0.65 * (0.5 + 0.5 * [Math]::Sin($loopPhase + $n))))
            }
            for ($r = 140; $r -lt 1120; $r += 150) {
                $pen = New-Object Drawing.Pen (New-Color $Accent2.R $Accent2.G $Accent2.B 14), 3
                try { $Graphics.DrawEllipse($pen, 960 - $r, 180 - [int]($r / 5), $r * 2, [int]($r * 0.40)) } finally { $pen.Dispose() }
            }
        }
        'KeyboardWave' {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 8 4 18), (New-Color 8 22 30), ([Drawing.Drawing2D.LinearGradientMode]::Vertical)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            Fill-SoftEllipse $Graphics 480 -130 820 520 $Accent2 ([int](34 + 18 * $pulse))
            $tile = 460.0
            $offset = $T * $tile * 2.0
            for ($n = -3; $n -lt 7; $n++) {
                $x = [int]($n * $tile + $offset) - 180
                $slot = (($n % 2) + 2) % 2
                $y = 292 + [int](5 * [Math]::Sin($loopPhase + $slot))
                $keyColor = if ($slot -eq 0) { $Accent } else { $Cyan }
                Draw-KeyboardShape $Graphics (New-Object Drawing.Rectangle $x, $y, 380, 62) $keyColor (0.5 + (0.5 * [Math]::Sin($loopPhase + $n)))
            }
            for ($n = 0; $n -lt 12; $n++) {
                $noteSlot = (($n % 3) + 3) % 3
                $noteX = [int](($n * 170 + ($T * 170 * 3)) % ($Width + 510)) - 240
                $noteY = 28 + (($noteSlot * 31) % 96)
                $c = if ($noteSlot -eq 0) { $Pink } elseif ($noteSlot -eq 1) { $Accent } else { $Cyan }
                Draw-MusicNoteShape $Graphics $noteX $noteY 42 $c 82
            }
        }
        default {
            $bgBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (New-Color 8 1 28), (New-Color 4 22 46), ([Drawing.Drawing2D.LinearGradientMode]::Horizontal)
            try { $Graphics.FillRectangle($bgBrush, $rect) } finally { $bgBrush.Dispose() }
            Fill-SoftEllipse $Graphics 190 -80 880 520 $Accent ([int](55 + 22 * $pulse))
            Fill-SoftEllipse $Graphics 920 -120 820 560 $Accent2 ([int](48 + 18 * (1.0 - $pulse)))
            for ($y = 36; $y -le 330; $y += 58) {
                $wave = New-Object 'Drawing.PointF[]' 5
                $wave[0] = New-Object Drawing.PointF 0, ([float]($y + 4 * [Math]::Sin($loopPhase + $y)))
                $wave[1] = New-Object Drawing.PointF 480, ([float]($y - 10 + 5 * [Math]::Sin($loopPhase + 1)))
                $wave[2] = New-Object Drawing.PointF 960, ([float]($y + 6 * [Math]::Sin($loopPhase + 2)))
                $wave[3] = New-Object Drawing.PointF 1440, ([float]($y + 10 + 5 * [Math]::Sin($loopPhase + 3)))
                $wave[4] = New-Object Drawing.PointF $Width, ([float]($y + 4 * [Math]::Sin($loopPhase + 4)))
                $lineColor = if (($y / 58) % 2 -eq 0) { $Cyan } else { $Pink }
                Draw-GlowLine $Graphics $wave $lineColor 2.2
            }
        }
    }

    switch ($variant) {
        1 {
            for ($y = 14; $y -lt $Height; $y += 28) {
                Draw-RotatedLine $Graphics 0 $y $Width $y (New-Color 255 255 255 14) 1
            }
        }
        2 {
            for ($x = 32; $x -lt $Width; $x += 128) {
                Fill-SoftEllipse $Graphics ($x - 18) ([int](28 + 18 * [Math]::Sin($loopPhase + $x))) 36 36 $Accent 24
            }
        }
        3 {
            for ($x = -80; $x -lt $Width + 80; $x += 170) {
                $offset = $T * 170.0
                Draw-RotatedLine $Graphics ([float]($x + $offset)) 0 ([float]($x + 100 + $offset)) $Height (New-Color $Pink.R $Pink.G $Pink.B 20) 18
            }
        }
        4 {
            # Keep the full marquee edge clean; foreground elements provide the neon structure.
        }
        5 {
            for ($n = 0; $n -lt 12; $n++) {
                $x = [int](42 + ($n * (($Width - 84) / 11.0)))
                $y = [int](42 + (($n * 47) % 230) + (12 * [Math]::Sin($loopPhase + ($n * 0.71))))
                $discColor = if ($n % 3 -eq 0) { $Cyan } elseif ($n % 3 -eq 1) { $Accent } else { $Pink }
                Fill-SoftEllipse $Graphics ($x - 55) ($y - 23) 110 46 $discColor 15
            }
        }
        6 {
            for ($r = 180; $r -lt 1280; $r += 180) {
                $pen = New-Object Drawing.Pen (New-Color $Accent.R $Accent.G $Accent.B 15), 3
                try { $Graphics.DrawEllipse($pen, 960 - $r, 180 - [int]($r / 4), $r * 2, [int]($r / 2)) } finally { $pen.Dispose() }
            }
        }
        7 {
            for ($x = 0; $x -lt $Width; $x += 64) {
                $brush = New-Object Drawing.SolidBrush (New-Color 0 0 0 22)
                try { $Graphics.FillRectangle($brush, $x, 0, 18, $Height) } finally { $brush.Dispose() }
            }
        }
    }
}

function Get-WordArtPalette {
    param(
        [string]$StyleName,
        [Drawing.Color]$Accent,
        [Drawing.Color]$Accent2,
        [Drawing.Color]$Pink,
        [Drawing.Color]$Cyan,
        [Drawing.Color]$DarkStroke
    )

    switch ($StyleName) {
        'CooperPop' {
            return @{
                TitleTop = New-Color 255 255 245
                TitleBottom = New-Color 255 174 64
                TitleStroke = New-Color 64 22 0
                TitleGlow = New-Color 255 196 80
                ArtistTop = New-Color 255 255 255
                ArtistBottom = $Pink
                ArtistStroke = $DarkStroke
                ArtistGlow = $Pink
                TitleFont = 'Bangers'
                ArtistFont = 'Lilita One'
                Stroke = 8.5
            }
        }
        'BroadwayLights' {
            return @{
                TitleTop = New-Color 255 255 255
                TitleBottom = New-Color 255 220 96
                TitleStroke = New-Color 45 14 0
                TitleGlow = New-Color 255 180 72
                ArtistTop = New-Color 255 255 255
                ArtistBottom = $Cyan
                ArtistStroke = New-Color 0 14 50
                ArtistGlow = $Accent2
                TitleFont = 'Bevan'
                ArtistFont = 'Righteous'
                Stroke = 8.0
            }
        }
        'StencilRock' {
            return @{
                TitleTop = New-Color 255 255 255
                TitleBottom = New-Color 255 86 58
                TitleStroke = New-Color 46 0 10
                TitleGlow = $Pink
                ArtistTop = New-Color 255 255 255
                ArtistBottom = $Accent
                ArtistStroke = New-Color 0 0 0
                ArtistGlow = $Accent
                TitleFont = 'Black Ops One'
                ArtistFont = 'Bungee'
                Stroke = 8.5
            }
        }
        'BauhausGlow' {
            return @{
                TitleTop = New-Color 255 255 255
                TitleBottom = $Cyan
                TitleStroke = New-Color 0 20 58
                TitleGlow = $Cyan
                ArtistTop = New-Color 255 255 255
                ArtistBottom = New-Color 255 116 200
                ArtistStroke = New-Color 56 0 58
                ArtistGlow = $Pink
                TitleFont = 'Bungee'
                ArtistFont = 'Righteous'
                Stroke = 8.0
            }
        }
        'ShowcardBlast' {
            return @{
                TitleTop = New-Color 255 255 255
                TitleBottom = New-Color 255 122 42
                TitleStroke = New-Color 68 16 0
                TitleGlow = New-Color 255 112 48
                ArtistTop = New-Color 255 255 255
                ArtistBottom = $Cyan
                ArtistStroke = New-Color 0 18 60
                ArtistGlow = $Cyan
                TitleFont = 'Luckiest Guy'
                ArtistFont = 'Lilita One'
                Stroke = 8.0
            }
        }
        'MagnetoNeon' {
            return @{
                TitleTop = New-Color 255 255 255
                TitleBottom = $Pink
                TitleStroke = New-Color 44 0 58
                TitleGlow = $Pink
                ArtistTop = New-Color 255 255 255
                ArtistBottom = $Accent2
                ArtistStroke = New-Color 0 12 50
                ArtistGlow = $Accent2
                TitleFont = 'Fugaz One'
                ArtistFont = 'Shrikhand'
                Stroke = 7.5
            }
        }
        'BookmanClassic' {
            return @{
                TitleTop = New-Color 255 255 238
                TitleBottom = New-Color 255 190 92
                TitleStroke = New-Color 52 22 0
                TitleGlow = New-Color 255 188 76
                ArtistTop = New-Color 255 255 255
                ArtistBottom = $Accent
                ArtistStroke = New-Color 0 16 52
                ArtistGlow = $Accent
                TitleFont = 'Bevan'
                ArtistFont = 'Righteous'
                Stroke = 8.5
            }
        }
        'RavieParty' {
            return @{
                TitleTop = New-Color 255 255 255
                TitleBottom = New-Color 150 255 255
                TitleStroke = New-Color 0 22 58
                TitleGlow = $Cyan
                ArtistTop = New-Color 255 255 255
                ArtistBottom = New-Color 255 100 210
                ArtistStroke = New-Color 62 0 62
                ArtistGlow = $Pink
                TitleFont = 'Fugaz One'
                ArtistFont = 'Bangers'
                Stroke = 7.5
            }
        }
        'PosterPop' {
            return @{
                TitleTop = New-Color 255 255 245
                TitleBottom = New-Color 255 116 190
                TitleStroke = New-Color 48 0 58
                TitleGlow = $Pink
                ArtistTop = New-Color 255 255 255
                ArtistBottom = $Cyan
                ArtistStroke = New-Color 0 18 54
                ArtistGlow = $Accent2
                TitleFont = 'Bangers'
                ArtistFont = 'Righteous'
                Stroke = 8.5
            }
        }
        'DiscoChrome' {
            return @{
                TitleTop = New-Color 255 255 255
                TitleBottom = New-Color 176 176 210
                TitleStroke = New-Color 10 10 40
                TitleGlow = $Accent2
                ArtistTop = New-Color 255 255 255
                ArtistBottom = New-Color 255 215 88
                ArtistStroke = New-Color 54 22 0
                ArtistGlow = New-Color 255 220 112
                TitleFont = 'Bungee'
                ArtistFont = 'Ultra'
                Stroke = 8.0
            }
        }
        'RetroScript' {
            return @{
                TitleTop = New-Color 255 255 255
                TitleBottom = New-Color 255 146 76
                TitleStroke = New-Color 66 8 0
                TitleGlow = New-Color 255 110 82
                ArtistTop = New-Color 255 255 255
                ArtistBottom = $Cyan
                ArtistStroke = New-Color 0 20 58
                ArtistGlow = $Cyan
                TitleFont = 'Fugaz One'
                ArtistFont = 'Bangers'
                Stroke = 7.5
            }
        }
        'BlockParty' {
            return @{
                TitleTop = New-Color 255 255 255
                TitleBottom = $Accent
                TitleStroke = New-Color 0 0 0
                TitleGlow = $Accent
                ArtistTop = New-Color 255 255 255
                ArtistBottom = $Pink
                ArtistStroke = $DarkStroke
                ArtistGlow = $Pink
                TitleFont = 'Titan One'
                ArtistFont = 'Bungee'
                Stroke = 10.0
            }
        }
        'NeonSign' {
            return @{
                TitleTop = New-Color 255 255 255
                TitleBottom = $Cyan
                TitleStroke = New-Color 0 12 44
                TitleGlow = $Cyan
                ArtistTop = New-Color 255 255 255
                ArtistBottom = $Pink
                ArtistStroke = New-Color 48 0 54
                ArtistGlow = $Pink
                TitleFont = 'Bungee'
                ArtistFont = 'Righteous'
                Stroke = 8.0
            }
        }
        'ClassicSerif' {
            return @{
                TitleTop = New-Color 255 255 235
                TitleBottom = New-Color 255 194 88
                TitleStroke = New-Color 62 24 0
                TitleGlow = New-Color 255 190 90
                ArtistTop = New-Color 255 255 255
                ArtistBottom = $Accent2
                ArtistStroke = New-Color 0 18 58
                ArtistGlow = $Accent
                TitleFont = 'Ultra'
                ArtistFont = 'Lilita One'
                Stroke = 8.5
            }
        }
        'ChromeArcade' {
            return @{
                TitleTop = New-Color 255 255 255
                TitleBottom = New-Color 170 205 255
                TitleStroke = New-Color 5 18 68
                TitleGlow = $Cyan
                ArtistTop = New-Color 255 255 255
                ArtistBottom = $Accent
                ArtistStroke = New-Color 0 10 46
                ArtistGlow = $Accent2
                TitleFont = 'Rowdies'
                ArtistFont = 'Bungee'
                Stroke = 8.5
            }
        }
        'GoldMarquee' {
            return @{
                TitleTop = New-Color 255 255 228
                TitleBottom = New-Color 255 166 42
                TitleStroke = New-Color 70 25 0
                TitleGlow = New-Color 255 190 60
                ArtistTop = New-Color 255 255 255
                ArtistBottom = $Accent
                ArtistStroke = New-Color 50 14 0
                ArtistGlow = New-Color 255 194 72
                TitleFont = 'Shrikhand'
                ArtistFont = 'Bevan'
                Stroke = 8.5
            }
        }
        'ElectricBlue' {
            return @{
                TitleTop = New-Color 245 255 255
                TitleBottom = $Cyan
                TitleStroke = New-Color 0 20 64
                TitleGlow = $Accent2
                ArtistTop = New-Color 255 255 255
                ArtistBottom = $Accent
                ArtistStroke = New-Color 0 15 52
                ArtistGlow = $Cyan
                TitleFont = 'Righteous'
                ArtistFont = 'Titan One'
                Stroke = 7.5
            }
        }
        'RockGlow' {
            return @{
                TitleTop = New-Color 255 255 255
                TitleBottom = New-Color 255 80 60
                TitleStroke = New-Color 55 0 18
                TitleGlow = $Pink
                ArtistTop = New-Color 255 255 225
                ArtistBottom = $Accent2
                ArtistStroke = $DarkStroke
                ArtistGlow = $Accent
                TitleFont = 'Bangers'
                ArtistFont = 'Black Ops One'
                Stroke = 9.5
            }
        }
        'ActionOps' {
            return @{
                TitleTop = New-Color 255 255 255
                TitleBottom = New-Color 255 92 64
                TitleStroke = New-Color 44 0 12
                TitleGlow = $Pink
                ArtistTop = New-Color 255 255 255
                ArtistBottom = $Accent
                ArtistStroke = New-Color 0 0 0
                ArtistGlow = $Accent
                TitleFont = 'Black Ops One'
                ArtistFont = 'Rowdies'
                Stroke = 8.5
            }
        }
        'LuckyPop' {
            return @{
                TitleTop = New-Color 255 255 245
                TitleBottom = New-Color 255 188 60
                TitleStroke = New-Color 54 16 0
                TitleGlow = New-Color 255 204 72
                ArtistTop = New-Color 255 255 255
                ArtistBottom = $Pink
                ArtistStroke = New-Color 52 0 58
                ArtistGlow = $Pink
                TitleFont = 'Luckiest Guy'
                ArtistFont = 'Carter One'
                Stroke = 8.5
            }
        }
        'TitanBurst' {
            return @{
                TitleTop = New-Color 255 255 255
                TitleBottom = $Cyan
                TitleStroke = New-Color 0 16 54
                TitleGlow = $Cyan
                ArtistTop = New-Color 255 255 255
                ArtistBottom = $Accent2
                ArtistStroke = $DarkStroke
                ArtistGlow = $Accent2
                TitleFont = 'Titan One'
                ArtistFont = 'Bangers'
                Stroke = 9.0
            }
        }
        'RowdyGlow' {
            return @{
                TitleTop = New-Color 255 255 255
                TitleBottom = $Accent
                TitleStroke = New-Color 0 18 40
                TitleGlow = $Accent
                ArtistTop = New-Color 255 255 255
                ArtistBottom = $Cyan
                ArtistStroke = New-Color 0 15 52
                ArtistGlow = $Cyan
                TitleFont = 'Rowdies'
                ArtistFont = 'Righteous'
                Stroke = 8.0
            }
        }
        'CarterRetro' {
            return @{
                TitleTop = New-Color 255 255 255
                TitleBottom = New-Color 255 142 74
                TitleStroke = New-Color 62 10 0
                TitleGlow = New-Color 255 112 74
                ArtistTop = New-Color 255 255 255
                ArtistBottom = $Cyan
                ArtistStroke = New-Color 0 20 58
                ArtistGlow = $Cyan
                TitleFont = 'Carter One'
                ArtistFont = 'Fugaz One'
                Stroke = 8.0
            }
        }
        'UltraPoster' {
            return @{
                TitleTop = New-Color 255 255 236
                TitleBottom = New-Color 255 180 66
                TitleStroke = New-Color 66 22 0
                TitleGlow = New-Color 255 188 76
                ArtistTop = New-Color 255 255 255
                ArtistBottom = $Accent2
                ArtistStroke = New-Color 0 18 58
                ArtistGlow = $Accent
                TitleFont = 'Ultra'
                ArtistFont = 'Lilita One'
                Stroke = 8.5
            }
        }
        'BevanChrome' {
            return @{
                TitleTop = New-Color 255 255 255
                TitleBottom = New-Color 170 205 255
                TitleStroke = New-Color 5 18 68
                TitleGlow = $Accent2
                ArtistTop = New-Color 255 255 255
                ArtistBottom = New-Color 255 216 92
                ArtistStroke = New-Color 56 20 0
                ArtistGlow = New-Color 255 220 112
                TitleFont = 'Bevan'
                ArtistFont = 'Ultra'
                Stroke = 8.0
            }
        }
        default {
            return @{
                TitleTop = New-Color 255 255 255
                TitleBottom = $Pink
                TitleStroke = $DarkStroke
                TitleGlow = $Accent
                ArtistTop = New-Color 255 255 255
                ArtistBottom = $Cyan
                ArtistStroke = New-Color 0 16 58
                ArtistGlow = $Cyan
                TitleFont = 'Bungee'
                ArtistFont = 'Righteous'
                Stroke = 9.0
            }
        }
    }
}

function Get-AlbumAdaptiveWordArtPalette {
    param(
        [hashtable]$Palette,
        [Drawing.Color]$Accent,
        [Drawing.Color]$Accent2,
        [Drawing.Color]$DarkStroke,
        [Drawing.Color]$Pink,
        [Drawing.Color]$Cyan
    )

    $titleBody = Get-AlbumDrivenWordArtColor -Accent $Accent -StyleColor $Palette.TitleBottom -AlbumWeight 0.82
    $artistBody = Get-AlbumDrivenWordArtColor -Accent $Accent2 -StyleColor $Palette.ArtistBottom -AlbumWeight 0.58
    $blueDominant = ($Accent.B -gt ($Accent.R + 34) -and $Accent.B -gt ($Accent.G + 22))
    $albumBlueTop = $null
    $albumBlueBottom = $null
    $albumBlueGlow = $null
    if ($blueDominant) {
        $albumBlueBottom = Get-ReadableWordArtColor (Blend-Color $Accent (New-Color 40 95 210) 0.16)
        $albumBlueTop = Get-ReadableWordArtColor (Blend-Color $Accent (New-Color 165 225 255) 0.52)
        $albumBlueGlow = Get-ReadableWordArtColor (Blend-Color $Accent (New-Color 80 165 255) 0.30)
        $titleBody = $albumBlueBottom
        $artistBody = Get-ReadableWordArtColor (Blend-Color $Accent2 (New-Color 235 248 255) 0.26)
    }
    $backgroundEffectColors = @($Accent, $Accent2, $Pink, $Cyan)
    $titleWasClashing = ((Get-MinColorDistance -Color $titleBody -Colors $backgroundEffectColors) -lt 104)
    $artistWasClashing = ((Get-MinColorDistance -Color $artistBody -Colors $backgroundEffectColors) -lt 104)
    $titleAlternates = @($Accent, $Accent2, $Cyan, $Pink, $Palette.TitleBottom, (New-Color 245 250 255), (New-Color 255 218 92))
    $artistAlternates = @($Accent2, $Accent, $Pink, $Cyan, $Palette.ArtistBottom, (New-Color 245 250 255), (New-Color 255 218 92))
    if ($blueDominant) {
        $titleAlternates = @($albumBlueBottom, $albumBlueTop, $Accent, $Cyan, (New-Color 245 250 255), (New-Color 255 218 92))
    }
    $titleBody = Get-ContrastSafeWordArtColor -Color $titleBody -AvoidColors $backgroundEffectColors -PreferredAlternates $titleAlternates
    $artistBody = Get-ContrastSafeWordArtColor -Color $artistBody -AvoidColors $backgroundEffectColors -PreferredAlternates $artistAlternates
    if ((Get-ColorDistance $titleBody $artistBody) -lt 82) {
        $artistBody = Get-ReadableWordArtColor (Blend-Color (New-Color $titleBody.B $titleBody.R $titleBody.G) $Palette.ArtistBottom 0.22)
    }
    if ((Get-ColorDistance $titleBody $artistBody) -lt 70) {
        $artistBody = Get-ReadableWordArtColor (Blend-Color $artistBody (New-Color 255 255 255) 0.34)
    }
    $titleGlow = Get-ReadableWordArtColor (Blend-Color $titleBody $Accent 0.46)
    $artistGlow = Get-ReadableWordArtColor (Blend-Color $artistBody $Accent2 0.34)
    if ($blueDominant) {
        $titleGlow = $albumBlueGlow
        $artistGlow = Blend-Color $artistBody (New-Color 130 210 255) 0.30
    } elseif ($titleWasClashing) {
        $titleGlow = Blend-Color $titleBody (New-Color 245 250 255) 0.24
    }
    if ($artistWasClashing) {
        $artistGlow = Blend-Color $artistBody (New-Color 245 250 255) 0.18
    }

    $titleTop = Blend-Color (New-Color 255 255 255) $titleBody 0.06
    if ($blueDominant -and $albumBlueTop -ne $null -and (Get-ColorDistance $titleBody $albumBlueBottom) -lt 130) { $titleTop = $albumBlueTop }

    return @{
        TitleTop = $titleTop
        TitleBottom = $titleBody
        TitleStroke = Blend-Color $DarkStroke $Palette.TitleStroke 0.08
        TitleGlow = $titleGlow
        ArtistTop = Blend-Color (New-Color 255 255 255) $artistBody 0.06
        ArtistBottom = $artistBody
        ArtistStroke = Blend-Color $DarkStroke $Palette.ArtistStroke 0.08
        ArtistGlow = $artistGlow
        TitleFont = $Palette.TitleFont
        ArtistFont = $Palette.ArtistFont
        Stroke = $Palette.Stroke
    }
}

function Draw-TextContainmentFrame {
    param(
        [Drawing.Graphics]$Graphics,
        [Drawing.Rectangle]$Rect,
        [Drawing.Color]$Accent,
        [Drawing.Color]$Accent2,
        [double]$T
    )

    $pulse = 0.5 + 0.5 * [Math]::Sin($T * [Math]::PI * 2.0)
    $fill = New-Object Drawing.SolidBrush (New-Color 0 0 18 40)
    try { $Graphics.FillRectangle($fill, $Rect) } finally { $fill.Dispose() }
    Draw-NeonTubeRect $Graphics $Rect $Accent 2.4 ([int](58 + 34 * $pulse))
    $inner = New-Object Drawing.Rectangle ($Rect.X + 12), ($Rect.Y + 12), ($Rect.Width - 24), ($Rect.Height - 24)
    Draw-NeonTubeRect $Graphics $inner $Accent2 1.3 54
}

function Draw-VisualizerTile {
    param(
        [Drawing.Graphics]$Graphics,
        [Drawing.Rectangle]$Rect,
        [string]$StyleName,
        [double]$T,
        [Drawing.Color]$Accent,
        [Drawing.Color]$Accent2,
        [Drawing.Color]$Pink,
        [Drawing.Color]$Cyan,
        [int]$Alpha
    )

    if ($Alpha -le 0) { return }
    $padX = 10
    $padTop = 6
    $padBottom = 6
    $clipState = $Graphics.Save()
    try {
        $Graphics.SetClip($Rect)
        Fill-SoftEllipse $Graphics ($Rect.X - 20) ($Rect.Y - 18) ($Rect.Width + 40) ($Rect.Height + 36) $Accent ([Math]::Min(54, [int]($Alpha * 0.12)))

        switch ($StyleName) {
            'EqualizerMirror' {
                $barCount = 15
                $barW = [Math]::Max(5, [int](($Rect.Width - ($padX * 2)) / $barCount))
                $centerY = $Rect.Y + [int]($Rect.Height / 2)
                for ($n = 0; $n -lt $barCount; $n++) {
                    $amp = 0.5 + 0.5 * [Math]::Sin(($T * [Math]::PI * 2.0 * 4.0) + ($n * 0.77))
                    $halfH = [int](14 + ((($Rect.Height / 2) - 8) * $amp))
                    $x = $Rect.X + $padX + ($n * $barW)
                    $c = if ($n % 3 -eq 0) { $Accent } elseif ($n % 3 -eq 1) { $Cyan } else { $Pink }
                    $brush = New-Object Drawing.Drawing2D.LinearGradientBrush (New-Object Drawing.Rectangle $x, ($centerY - $halfH), ([Math]::Max(4, $barW - 4)), ($halfH * 2)), (New-Color 255 255 255 ([Math]::Min(235, $Alpha))), (New-Color $c.R $c.G $c.B ([Math]::Min(245, $Alpha))), ([Drawing.Drawing2D.LinearGradientMode]::Vertical)
                    try { $Graphics.FillRectangle($brush, $x, ($centerY - $halfH), ([Math]::Max(4, $barW - 4)), ($halfH * 2)) } finally { $brush.Dispose() }
                    Fill-SoftEllipse $Graphics ($x - 2) ($centerY - 2) ([Math]::Max(8, $barW)) 4 $c ([Math]::Min(130, [int]($Alpha * 0.44)))
                }
            }
            'EqualizerStack' {
                $rows = 11
                $cols = 14
                $cellW = [Math]::Max(7, [int](($Rect.Width - ($padX * 2)) / $cols))
                $cellH = [Math]::Max(7, [int](($Rect.Height - ($padTop + $padBottom)) / $rows))
                for ($col = 0; $col -lt $cols; $col++) {
                    $amp = 0.5 + 0.5 * [Math]::Sin(($T * [Math]::PI * 2.0 * 4.0) + ($col * 0.91))
                    $litRows = [Math]::Max(2, [int]($amp * $rows))
                    for ($row = 0; $row -lt $litRows; $row++) {
                        $x = $Rect.X + $padX + ($col * $cellW)
                        $y = $Rect.Y + $Rect.Height - $padBottom - (($row + 1) * $cellH)
                        $c = if ($row -gt ($rows * 0.72)) { $Pink } elseif ($row -gt ($rows * 0.48)) { $Accent } else { $Cyan }
                        $brush = New-Object Drawing.SolidBrush (New-Color $c.R $c.G $c.B ([Math]::Min(230, [int]($Alpha * (0.50 + 0.045 * $row)))))
                        try { $Graphics.FillRectangle($brush, $x, $y, ([Math]::Max(4, $cellW - 3)), ([Math]::Max(4, $cellH - 3))) } finally { $brush.Dispose() }
                    }
                }
            }
            'EqualizerThin' {
                $barCount = 28
                $barW = [Math]::Max(3, [int](($Rect.Width - ($padX * 2)) / $barCount))
                for ($n = 0; $n -lt $barCount; $n++) {
                    $amp = 0.42 + 0.58 * (0.5 + 0.5 * [Math]::Sin(($T * [Math]::PI * 2.0 * 4.0) + ($n * 0.48) + ([Math]::Sin($n) * 0.65)))
                    $barH = [int](18 + (($Rect.Height - 24) * $amp))
                    $x = $Rect.X + $padX + ($n * $barW)
                    $y = $Rect.Y + $Rect.Height - $padBottom - $barH
                    $c = if ($n % 4 -eq 0) { $Pink } elseif ($n % 4 -eq 1) { $Cyan } else { $Accent }
                    $pen = New-Object Drawing.Pen (New-Color $c.R $c.G $c.B ([Math]::Min(235, $Alpha))), ([Math]::Max(2, $barW - 2))
                    try { $Graphics.DrawLine($pen, $x, ($Rect.Y + $Rect.Height - $padBottom), $x, $y) } finally { $pen.Dispose() }
                    Fill-SoftEllipse $Graphics ($x - 3) ($y - 5) 6 6 $c ([Math]::Min(150, [int]($Alpha * 0.50)))
                }
            }
            'EqualizerSweep' {
                $barCount = 18
                $barW = [Math]::Max(5, [int](($Rect.Width - ($padX * 2)) / $barCount))
                $sweep = 0.5 + 0.5 * [Math]::Sin($T * [Math]::PI * 2.0 * 3.0)
                for ($n = 0; $n -lt $barCount; $n++) {
                    $phase = ($n / [double]($barCount - 1))
                    $amp = 0.35 + 0.65 * (1.0 - [Math]::Min(1.0, [Math]::Abs($phase - $sweep) * 2.8))
                    $amp = [Math]::Max($amp, 0.35 + 0.25 * [Math]::Sin(($T * [Math]::PI * 2.0 * 4.0) + ($n * 0.72)))
                    $barH = [int](18 + (($Rect.Height - 24) * $amp))
                    $x = $Rect.X + $padX + ($n * $barW)
                    $y = $Rect.Y + $Rect.Height - $padBottom - $barH
                    $c = if ($n % 3 -eq 0) { $Cyan } elseif ($n % 3 -eq 1) { $Pink } else { $Accent }
                    $brush = New-Object Drawing.Drawing2D.LinearGradientBrush (New-Object Drawing.Rectangle $x, $y, ([Math]::Max(4, $barW - 4)), $barH), (New-Color 255 255 255 ([Math]::Min(250, $Alpha))), (New-Color $c.R $c.G $c.B ([Math]::Min(250, $Alpha))), ([Drawing.Drawing2D.LinearGradientMode]::Vertical)
                    try { $Graphics.FillRectangle($brush, $x, $y, ([Math]::Max(4, $barW - 4)), $barH) } finally { $brush.Dispose() }
                }
            }
            'EqualizerSidePulse' {
                $rows = 13
                $centerX = $Rect.X + [int]($Rect.Width / 2)
                $cellH = [Math]::Max(7, [int](($Rect.Height - ($padTop + $padBottom)) / $rows))
                for ($row = 0; $row -lt $rows; $row++) {
                    $amp = 0.35 + 0.65 * (0.5 + 0.5 * [Math]::Sin(($T * [Math]::PI * 2.0 * 4.0) + ($row * 0.86)))
                    $halfW = [int](18 + (($Rect.Width / 2 - 16) * $amp))
                    $y = $Rect.Y + $padTop + ($row * $cellH)
                    $c = if ($row % 3 -eq 0) { $Pink } elseif ($row % 3 -eq 1) { $Accent } else { $Cyan }
                    $brush = New-Object Drawing.Drawing2D.LinearGradientBrush (New-Object Drawing.Rectangle ($centerX - $halfW), $y, ($halfW * 2), ([Math]::Max(4, $cellH - 3))), (New-Color $c.R $c.G $c.B ([Math]::Min(235, $Alpha))), (New-Color 255 255 255 ([Math]::Min(235, $Alpha))), ([Drawing.Drawing2D.LinearGradientMode]::Horizontal)
                    try { $Graphics.FillRectangle($brush, ($centerX - $halfW), $y, ($halfW * 2), ([Math]::Max(4, $cellH - 3))) } finally { $brush.Dispose() }
                }
            }
            'EqualizerComet' {
                $barCount = 22
                $barW = [Math]::Max(4, [int](($Rect.Width - ($padX * 2)) / $barCount))
                $head = ($T * $barCount * 2.0) % $barCount
                for ($n = 0; $n -lt $barCount; $n++) {
                    $dist = [Math]::Abs($n - $head)
                    $dist = [Math]::Min($dist, $barCount - $dist)
                    $amp = [Math]::Max(0.22, 1.0 - ($dist / 5.2))
                    $barH = [int](14 + (($Rect.Height - 20) * $amp))
                    $x = $Rect.X + $padX + ($n * $barW)
                    $y = $Rect.Y + $Rect.Height - $padBottom - $barH
                    $c = if ($dist -lt 1.5) { $Pink } elseif ($n % 2 -eq 0) { $Cyan } else { $Accent }
                    $brush = New-Object Drawing.SolidBrush (New-Color $c.R $c.G $c.B ([Math]::Min(245, [int]($Alpha * (0.42 + (0.58 * $amp))))))
                    try { $Graphics.FillRectangle($brush, $x, $y, ([Math]::Max(3, $barW - 3)), $barH) } finally { $brush.Dispose() }
                }
            }
            default {
                $barCount = 13
                $barW = [Math]::Max(6, [int](($Rect.Width - ($padX * 2)) / $barCount))
                for ($n = 0; $n -lt $barCount; $n++) {
                    $amp = 0.5 + 0.5 * [Math]::Sin(($T * [Math]::PI * 2.0 * 4.0) + ($n * 0.92))
                    $barH = [int](18 + (($Rect.Height - 24) * $amp))
                    $x = $Rect.X + $padX + ($n * $barW)
                    $y = $Rect.Y + $Rect.Height - $padBottom - $barH
                    $c = if ($n % 3 -eq 0) { $Accent } elseif ($n % 3 -eq 1) { $Cyan } else { $Pink }
                    $brush = New-Object Drawing.Drawing2D.LinearGradientBrush (New-Object Drawing.Rectangle $x, $y, ([Math]::Max(4, $barW - 4)), $barH), (New-Color 255 255 255 ([Math]::Min(255, $Alpha))), (New-Color $c.R $c.G $c.B ([Math]::Min(255, $Alpha))), ([Drawing.Drawing2D.LinearGradientMode]::Vertical)
                    try { $Graphics.FillRectangle($brush, $x, $y, ([Math]::Max(4, $barW - 4)), $barH) } finally { $brush.Dispose() }
                }
            }
        }
    }
    finally {
        $Graphics.Restore($clipState)
    }
}

function Get-TextMotion {
    param([string]$MotionName, [double]$T)

    $titleIn = Ease-OutBack (($T - 0.26) / 0.22)
    $titleOut = Ease-OutCubic (($T - 0.84) / 0.12)
    $artistIn = Ease-OutBack (($T - 0.45) / 0.20) 1.9
    $artistOut = Ease-OutCubic (($T - 0.83) / 0.12)
    $fastTitleIn = Ease-OutBack (($T - 0.20) / 0.18) 1.75
    $fastArtistIn = Ease-OutBack (($T - 0.34) / 0.18) 1.75
    $lateTitleIn = Ease-OutBack (($T - 0.34) / 0.20) 1.65
    $lateArtistIn = Ease-OutBack (($T - 0.23) / 0.20) 1.65

    $titleAlpha = [int](255 * (Clamp01 (($T - 0.24) / 0.16)) * (1.0 - (Clamp01 $titleOut)))
    $artistAlpha = [int](255 * (Clamp01 (($T - 0.42) / 0.13)) * (1.0 - (Clamp01 $artistOut)))
    $fastTitleAlpha = [int](255 * (Clamp01 (($T - 0.18) / 0.12)) * (1.0 - (Clamp01 $titleOut)))
    $fastArtistAlpha = [int](255 * (Clamp01 (($T - 0.32) / 0.12)) * (1.0 - (Clamp01 $artistOut)))
    $lateTitleAlpha = [int](255 * (Clamp01 (($T - 0.31) / 0.13)) * (1.0 - (Clamp01 $titleOut)))
    $lateArtistAlpha = [int](255 * (Clamp01 (($T - 0.20) / 0.13)) * (1.0 - (Clamp01 $artistOut)))

    switch ($MotionName) {
        { $_ -eq 'LoopAlive' -or $_ -eq 'LoopAliveClassic' } {
            return @{
                TitleX = 980
                TitleY = 137
                TitleScale = 1.0
                TitleAlpha = 255
                ArtistX = 1000
                ArtistY = 235
                ArtistScale = 1.0
                ArtistAlpha = 255
            }
        }
        'SlideBounce' {
            $titleX = Lerp -A 1880 -B 980 -T $titleIn
            $titleX = Lerp -A $titleX -B 1880 -T $titleOut
            $artistX = Lerp -A 250 -B 1000 -T $artistIn
            $artistX = Lerp -A $artistX -B 250 -T $artistOut
            return @{ TitleX = $titleX; TitleY = 142; TitleScale = 0.88 + 0.13 * $titleIn; TitleAlpha = $titleAlpha; ArtistX = $artistX; ArtistY = 237; ArtistScale = 0.74 + 0.26 * $artistIn; ArtistAlpha = $artistAlpha }
        }
        'DropIn' {
            $titleY = Lerp -A -90 -B 142 -T $titleIn
            $titleY = Lerp -A $titleY -B 440 -T $titleOut
            $artistY = Lerp -A -50 -B 237 -T $artistIn
            $artistY = Lerp -A $artistY -B 430 -T $artistOut
            return @{ TitleX = 980; TitleY = $titleY; TitleScale = 0.84 + 0.16 * $titleIn; TitleAlpha = $titleAlpha; ArtistX = 1000; ArtistY = $artistY; ArtistScale = 0.74 + 0.26 * $artistIn; ArtistAlpha = $artistAlpha }
        }
        'ZoomReveal' {
            return @{ TitleX = 980; TitleY = 142; TitleScale = 0.30 + 0.72 * $titleIn + 0.012 * [Math]::Sin($T * [Math]::PI * 4.0); TitleAlpha = $titleAlpha; ArtistX = 1000; ArtistY = 237; ArtistScale = 0.32 + 0.70 * $artistIn; ArtistAlpha = $artistAlpha }
        }
        'TitleLeftArtistRight' {
            $titleX = Lerp -A -360 -B 980 -T $titleIn
            $titleX = Lerp -A $titleX -B -520 -T $titleOut
            $artistX = Lerp -A 2260 -B 1000 -T $artistIn
            $artistX = Lerp -A $artistX -B 2280 -T $artistOut
            return @{ TitleX = $titleX; TitleY = 142; TitleScale = 0.88 + 0.13 * $titleIn; TitleAlpha = $titleAlpha; ArtistX = $artistX; ArtistY = 237; ArtistScale = 0.76 + 0.24 * $artistIn; ArtistAlpha = $artistAlpha }
        }
        'TitleRightArtistLeft' {
            $titleX = Lerp -A 2280 -B 980 -T $titleIn
            $titleX = Lerp -A $titleX -B 2280 -T $titleOut
            $artistX = Lerp -A -320 -B 1000 -T $artistIn
            $artistX = Lerp -A $artistX -B -420 -T $artistOut
            return @{ TitleX = $titleX; TitleY = 142; TitleScale = 0.88 + 0.13 * $titleIn; TitleAlpha = $titleAlpha; ArtistX = $artistX; ArtistY = 237; ArtistScale = 0.76 + 0.24 * $artistIn; ArtistAlpha = $artistAlpha }
        }
        'TitleUpArtistDown' {
            $titleY = Lerp -A 430 -B 142 -T $titleIn
            $titleY = Lerp -A $titleY -B -130 -T $titleOut
            $artistY = Lerp -A -70 -B 237 -T $artistIn
            $artistY = Lerp -A $artistY -B 430 -T $artistOut
            return @{ TitleX = 980; TitleY = $titleY; TitleScale = 0.86 + 0.15 * $titleIn; TitleAlpha = $titleAlpha; ArtistX = 1000; ArtistY = $artistY; ArtistScale = 0.76 + 0.24 * $artistIn; ArtistAlpha = $artistAlpha }
        }
        'TitleDownArtistUp' {
            $titleY = Lerp -A -120 -B 142 -T $titleIn
            $titleY = Lerp -A $titleY -B 440 -T $titleOut
            $artistY = Lerp -A 430 -B 237 -T $artistIn
            $artistY = Lerp -A $artistY -B -80 -T $artistOut
            return @{ TitleX = 980; TitleY = $titleY; TitleScale = 0.86 + 0.15 * $titleIn; TitleAlpha = $titleAlpha; ArtistX = 1000; ArtistY = $artistY; ArtistScale = 0.76 + 0.24 * $artistIn; ArtistAlpha = $artistAlpha }
        }
        'CrossSlide' {
            $cross = [Math]::Sin((Clamp01 (($T - 0.30) / 0.40)) * [Math]::PI)
            $titleX = Lerp -A 2200 -B 980 -T $fastTitleIn
            $artistX = Lerp -A -300 -B 1000 -T $fastArtistIn
            $titleY = 142 + (22 * $cross)
            $artistY = 237 - (18 * $cross)
            $titleX = Lerp -A $titleX -B -460 -T $titleOut
            $artistX = Lerp -A $artistX -B 2220 -T $artistOut
            return @{ TitleX = $titleX; TitleY = $titleY; TitleScale = 0.86 + 0.16 * $fastTitleIn; TitleAlpha = $fastTitleAlpha; ArtistX = $artistX; ArtistY = $artistY; ArtistScale = 0.76 + 0.25 * $fastArtistIn; ArtistAlpha = $fastArtistAlpha }
        }
        'DiagonalSplit' {
            $titleX = Lerp -A -420 -B 980 -T $titleIn
            $titleY = Lerp -A 410 -B 142 -T $titleIn
            $artistX = Lerp -A 2260 -B 1000 -T $artistIn
            $artistY = Lerp -A -70 -B 237 -T $artistIn
            $titleX = Lerp -A $titleX -B -520 -T $titleOut
            $titleY = Lerp -A $titleY -B -120 -T $titleOut
            $artistX = Lerp -A $artistX -B 2260 -T $artistOut
            $artistY = Lerp -A $artistY -B 430 -T $artistOut
            return @{ TitleX = $titleX; TitleY = $titleY; TitleScale = 0.86 + 0.15 * $titleIn; TitleAlpha = $titleAlpha; ArtistX = $artistX; ArtistY = $artistY; ArtistScale = 0.76 + 0.24 * $artistIn; ArtistAlpha = $artistAlpha }
        }
        'StaggeredRise' {
            $titleY = Lerp -A 420 -B 142 -T $lateTitleIn
            $artistY = Lerp -A 430 -B 237 -T $lateArtistIn
            $titleY = Lerp -A $titleY -B -120 -T $titleOut
            $artistY = Lerp -A $artistY -B 430 -T $artistOut
            return @{ TitleX = 980; TitleY = $titleY; TitleScale = 0.82 + 0.20 * $lateTitleIn; TitleAlpha = $lateTitleAlpha; ArtistX = 1000; ArtistY = $artistY; ArtistScale = 0.72 + 0.30 * $lateArtistIn; ArtistAlpha = $lateArtistAlpha }
        }
        'StaggeredDrop' {
            $titleY = Lerp -A -100 -B 142 -T $lateTitleIn
            $artistY = Lerp -A -70 -B 237 -T $lateArtistIn
            $titleY = Lerp -A $titleY -B 440 -T $titleOut
            $artistY = Lerp -A $artistY -B -80 -T $artistOut
            return @{ TitleX = 980; TitleY = $titleY; TitleScale = 0.82 + 0.20 * $lateTitleIn; TitleAlpha = $lateTitleAlpha; ArtistX = 1000; ArtistY = $artistY; ArtistScale = 0.72 + 0.30 * $lateArtistIn; ArtistAlpha = $lateArtistAlpha }
        }
        'PunchPop' {
            $titlePulse = [Math]::Sin((Clamp01 (($T - 0.28) / 0.24)) * [Math]::PI)
            $artistPulse = [Math]::Sin((Clamp01 (($T - 0.43) / 0.22)) * [Math]::PI)
            return @{ TitleX = 980; TitleY = 142; TitleScale = 0.18 + 0.84 * $titleIn + (0.09 * $titlePulse); TitleAlpha = $titleAlpha; ArtistX = 1000; ArtistY = 237; ArtistScale = 0.28 + 0.74 * $artistIn + (0.06 * $artistPulse); ArtistAlpha = $artistAlpha }
        }
        'WideCompress' {
            $titleX = Lerp -A 980 -B 980 -T $titleIn
            $artistX = Lerp -A 1000 -B 1000 -T $artistIn
            $titleY = Lerp -A 142 -B 142 -T $titleIn
            $artistY = Lerp -A 237 -B 237 -T $artistIn
            $titleScale = 1.28 - (0.28 * $titleIn) + (0.015 * [Math]::Sin($T * [Math]::PI * 6.0))
            $artistScale = 1.20 - (0.22 * $artistIn)
            return @{ TitleX = $titleX; TitleY = $titleY; TitleScale = $titleScale; TitleAlpha = $titleAlpha; ArtistX = $artistX; ArtistY = $artistY; ArtistScale = $artistScale; ArtistAlpha = $artistAlpha }
        }
        'CornerSweep' {
            $titleX = Lerp -A -360 -B 980 -T $titleIn
            $titleY = Lerp -A -90 -B 142 -T $titleIn
            $artistX = Lerp -A 2260 -B 1000 -T $artistIn
            $artistY = Lerp -A 430 -B 237 -T $artistIn
            $titleX = Lerp -A $titleX -B 2260 -T $titleOut
            $titleY = Lerp -A $titleY -B 430 -T $titleOut
            $artistX = Lerp -A $artistX -B -360 -T $artistOut
            $artistY = Lerp -A $artistY -B -80 -T $artistOut
            return @{ TitleX = $titleX; TitleY = $titleY; TitleScale = 0.86 + 0.14 * $titleIn; TitleAlpha = $titleAlpha; ArtistX = $artistX; ArtistY = $artistY; ArtistScale = 0.76 + 0.24 * $artistIn; ArtistAlpha = $artistAlpha }
        }
        'ArtistLead' {
            $artistX = Lerp -A -320 -B 1000 -T $lateArtistIn
            $artistX = Lerp -A $artistX -B 2260 -T $artistOut
            $titleX = Lerp -A 2260 -B 980 -T $lateTitleIn
            $titleX = Lerp -A $titleX -B -420 -T $titleOut
            return @{ TitleX = $titleX; TitleY = 142; TitleScale = 0.86 + 0.15 * $lateTitleIn; TitleAlpha = $lateTitleAlpha; ArtistX = $artistX; ArtistY = 237; ArtistScale = 0.74 + 0.28 * $lateArtistIn; ArtistAlpha = $lateArtistAlpha }
        }
        default {
            $titleY = Lerp -A 440 -B 142 -T $titleIn
            $titleY = Lerp -A $titleY -B -120 -T $titleOut
            $artistY = Lerp -A 290 -B 237 -T $artistIn
            $artistY = Lerp -A $artistY -B 420 -T $artistOut
            return @{ TitleX = 980; TitleY = $titleY; TitleScale = 0.86 + 0.14 * $titleIn + 0.012 * [Math]::Sin($T * [Math]::PI * 4.0); TitleAlpha = $titleAlpha; ArtistX = 1000; ArtistY = $artistY; ArtistScale = 0.72 + 0.28 * $artistIn; ArtistAlpha = $artistAlpha }
        }
    }
}

function Draw-WordArtPlain {
    param(
        [Drawing.Graphics]$Graphics,
        [string]$Text,
        [Drawing.Font]$Font,
        [Drawing.RectangleF]$Rect,
        [Drawing.Color]$FillTop,
        [Drawing.Color]$FillBottom,
        [Drawing.Color]$StrokeColor,
        [Drawing.Color]$GlowColor,
        [float]$StrokeWidth,
        [int]$Alpha,
        [double]$GlowBoost = 1.0
    )

    if ($Alpha -le 0) { return }

    $fmt = New-Object Drawing.StringFormat
    $fmt.Alignment = [Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [Drawing.StringAlignment]::Center
    $fmt.FormatFlags = [Drawing.StringFormatFlags]::NoWrap
    try {
        foreach ($spec in @(
            @{ Radius = [Math]::Max(2, [int]($StrokeWidth * 1.8)); Alpha = [Math]::Min(145, $Alpha * 0.34 * $GlowBoost) },
            @{ Radius = [Math]::Max(1, [int]($StrokeWidth * 0.9)); Alpha = [Math]::Min(190, $Alpha * 0.48 * $GlowBoost) }
        )) {
            $glowBrush = New-Object Drawing.SolidBrush (New-Color $GlowColor.R $GlowColor.G $GlowColor.B ([int]$spec.Alpha))
            try {
                foreach ($offset in @(
                    @(-$spec.Radius, 0), @($spec.Radius, 0), @(0, -$spec.Radius), @(0, $spec.Radius),
                    @(-$spec.Radius, -$spec.Radius), @($spec.Radius, -$spec.Radius), @(-$spec.Radius, $spec.Radius), @($spec.Radius, $spec.Radius)
                )) {
                    $glowRect = New-Object Drawing.RectangleF ([float]($Rect.X + $offset[0])), ([float]($Rect.Y + $offset[1])), $Rect.Width, $Rect.Height
                    $Graphics.DrawString($Text, $Font, $glowBrush, $glowRect, $fmt)
                }
            }
            finally { $glowBrush.Dispose() }
        }

        $shadowBrush = New-Object Drawing.SolidBrush (New-Color 0 0 20 ([Math]::Min(175, $Alpha * 0.68)))
        try {
            $shadowRect = New-Object Drawing.RectangleF ([float]($Rect.X + 7)), ([float]($Rect.Y + 7)), $Rect.Width, $Rect.Height
            $Graphics.DrawString($Text, $Font, $shadowBrush, $shadowRect, $fmt)
        }
        finally { $shadowBrush.Dispose() }

        $strokeBrush = New-Object Drawing.SolidBrush (New-Color $StrokeColor.R $StrokeColor.G $StrokeColor.B $Alpha)
        try {
            $radius = [Math]::Max(1, [int]([Math]::Ceiling($StrokeWidth / 2.0)))
            foreach ($offset in @(@(-$radius, 0), @($radius, 0), @(0, -$radius), @(0, $radius), @(-$radius, -$radius), @($radius, -$radius), @(-$radius, $radius), @($radius, $radius))) {
                $strokeRect = New-Object Drawing.RectangleF ([float]($Rect.X + $offset[0])), ([float]($Rect.Y + $offset[1])), $Rect.Width, $Rect.Height
                $Graphics.DrawString($Text, $Font, $strokeBrush, $strokeRect, $fmt)
            }
        }
        finally { $strokeBrush.Dispose() }

        $fillBrush = New-Object Drawing.Drawing2D.LinearGradientBrush $Rect, (New-Color $FillTop.R $FillTop.G $FillTop.B $Alpha), (New-Color $FillBottom.R $FillBottom.G $FillBottom.B $Alpha), ([Drawing.Drawing2D.LinearGradientMode]::Vertical)
        try {
            $Graphics.DrawString($Text, $Font, $fillBrush, $Rect, $fmt)
        }
        finally { $fillBrush.Dispose() }
    }
    finally {
        $fmt.Dispose()
    }
}

function Draw-WordArt {
    param(
        [Drawing.Graphics]$Graphics,
        [string]$Text,
        [Drawing.Font]$Font,
        [Drawing.RectangleF]$Rect,
        [Drawing.Color]$FillTop,
        [Drawing.Color]$FillBottom,
        [Drawing.Color]$StrokeColor,
        [Drawing.Color]$GlowColor,
        [float]$StrokeWidth,
        [int]$Alpha,
        [double]$GlowBoost = 1.0,
        [int]$MaxLines = 1,
        [double]$AccentStrength = 0.0,
        [double]$ShineProgress = 0.5,
        [switch]$ForceWrap
    )

    if ($Alpha -le 0) { return }

    if ($MaxLines -gt 1) {
        $effectPad = [Math]::Max(10.0, [double]($Font.Size * 0.12 + ($StrokeWidth * 1.2)))
        $wrapMaxWidth = [Math]::Max(12.0, $Rect.Width - (28.0 + ($effectPad * 2.0)))
        $oneLineWidth = [double]($Graphics.MeasureString($Text, $Font).Width)
        $wordCount = @($Text -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
        $wrapByCharacters = ($Text.Length -ge 28 -and $wordCount -ge 3)
        $preferWrap = ($ForceWrap -or $wrapByCharacters -or ($Text.Length -ge 34 -and $oneLineWidth -gt ($wrapMaxWidth * 1.08)))
        $drawMaxLines = if ($preferWrap) { $MaxLines } else { 1 }
        $lines = Split-MarqueeTextLinesForWidth -Graphics $Graphics -Text $Text -Font $Font -MaxWidth $wrapMaxWidth -MaxLines $drawMaxLines -PreferWrap:$preferWrap
        if ($lines.Count -gt 1) {
            $lineHeight = [Math]::Max(1.0, $Font.GetHeight($Graphics) * 1.04)
            $totalHeight = $lineHeight * $lines.Count
            $startY = [float]($Rect.Y + (($Rect.Height - $totalHeight) / 2.0))
            $wrappedStrokeWidth = [float]([Math]::Max(2.0, $StrokeWidth * 0.52))
            $wrappedGlowBoost = [double]($GlowBoost * 0.48)
            for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
                $lineRect = New-Object Drawing.RectangleF $Rect.X, ([float]($startY + ($lineIndex * $lineHeight))), $Rect.Width, ([float]$lineHeight)
                Draw-WordArt -Graphics $Graphics -Text ([string]$lines[$lineIndex]) -Font $Font -Rect $lineRect -FillTop $FillTop -FillBottom $FillBottom -StrokeColor $StrokeColor -GlowColor $GlowColor -StrokeWidth $wrappedStrokeWidth -Alpha $Alpha -GlowBoost $wrappedGlowBoost -MaxLines 1 -AccentStrength $AccentStrength -ShineProgress $ShineProgress
            }
            return
        }
    }

    $fmt = New-Object Drawing.StringFormat
    $fmt.Alignment = [Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [Drawing.StringAlignment]::Center
    $fmt.FormatFlags = [Drawing.StringFormatFlags]::NoWrap
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    try {
        $emSize = $Graphics.DpiY * $Font.SizeInPoints / 72.0
        $layoutRect = New-Object Drawing.RectangleF 0, 0, 10000, 1000
        $path.AddString($Text, $Font.FontFamily, [int]$Font.Style, $emSize, $layoutRect, $fmt)
        $bounds = $path.GetBounds()
        $measured = $Graphics.MeasureString($Text, $Font)
        if ($Text.Length -gt 1 -and $bounds.Width -lt ($measured.Width * 0.35)) {
            Draw-WordArtPlain -Graphics $Graphics -Text $Text -Font $Font -Rect $Rect -FillTop $FillTop -FillBottom $FillBottom -StrokeColor $StrokeColor -GlowColor $GlowColor -StrokeWidth $StrokeWidth -Alpha $Alpha -GlowBoost $GlowBoost
            return
        }
        $centerMatrix = New-Object Drawing.Drawing2D.Matrix
        try {
            $centerMatrix.Translate(
                [float]($Rect.X + ($Rect.Width / 2.0) - ($bounds.X + ($bounds.Width / 2.0))),
                [float]($Rect.Y + ($Rect.Height / 2.0) - ($bounds.Y + ($bounds.Height / 2.0)))
            )
            $path.Transform($centerMatrix)
        }
        finally {
            $centerMatrix.Dispose()
        }

        $accentGlow = 1.0 + (0.95 * (Clamp01 $AccentStrength))
        foreach ($spec in @(
            @{ W = $StrokeWidth * (5.5 + (3.0 * (Clamp01 $AccentStrength))); A = [Math]::Min(230, $Alpha * 0.42 * $GlowBoost * $accentGlow) },
            @{ W = $StrokeWidth * (3.0 + (1.8 * (Clamp01 $AccentStrength))); A = [Math]::Min(255, $Alpha * 0.66 * $GlowBoost * $accentGlow) }
        )) {
            $glowPen = New-Object Drawing.Pen (New-Color $GlowColor.R $GlowColor.G $GlowColor.B ([int]$spec.A)), ([float]$spec.W)
            try {
                $glowPen.LineJoin = [Drawing.Drawing2D.LineJoin]::Round
                $Graphics.DrawPath($glowPen, $path)
            }
            finally { $glowPen.Dispose() }
        }

        $shadowMatrix = New-Object Drawing.Drawing2D.Matrix
        $shadowMatrix.Translate(7, 7)
        $shadowPath = $path.Clone()
        try {
            $shadowPath.Transform($shadowMatrix)
            $shadowPen = New-Object Drawing.Pen (New-Color 0 0 20 ([Math]::Min(190, $Alpha * 0.75))), ($StrokeWidth * 2.6)
            try {
                $shadowPen.LineJoin = [Drawing.Drawing2D.LineJoin]::Round
                $Graphics.DrawPath($shadowPen, $shadowPath)
            }
            finally { $shadowPen.Dispose() }
        }
        finally {
            $shadowPath.Dispose()
            $shadowMatrix.Dispose()
        }

        $strokePen = New-Object Drawing.Pen (New-Color $StrokeColor.R $StrokeColor.G $StrokeColor.B $Alpha), $StrokeWidth
        try {
            $strokePen.LineJoin = [Drawing.Drawing2D.LineJoin]::Round
            $Graphics.DrawPath($strokePen, $path)
        }
        finally { $strokePen.Dispose() }

        $brush = New-Object Drawing.Drawing2D.LinearGradientBrush $Rect, (New-Color $FillTop.R $FillTop.G $FillTop.B $Alpha), (New-Color $FillBottom.R $FillBottom.G $FillBottom.B $Alpha), ([Drawing.Drawing2D.LinearGradientMode]::Vertical)
        try { $Graphics.FillPath($brush, $path) }
        finally { $brush.Dispose() }

        $shineAmount = Clamp01 $AccentStrength
        if ($shineAmount -gt 0.01) {
            $clipState = $Graphics.Save()
            try {
                $Graphics.SetClip($path)
                $shineX = [float]($Rect.X - ($Rect.Width * 0.28) + ((Clamp01 $ShineProgress) * $Rect.Width * 1.56))
                $shineAlpha = [int]([Math]::Min(205, $Alpha * 0.82 * $shineAmount))
                $shinePen = New-Object Drawing.Pen (New-Color 255 255 255 $shineAlpha), ([float]([Math]::Max(12.0, $Font.Size * 0.28)))
                try {
                    $shinePen.StartCap = [Drawing.Drawing2D.LineCap]::Round
                    $shinePen.EndCap = [Drawing.Drawing2D.LineCap]::Round
                    $Graphics.DrawLine($shinePen, $shineX, ([float]($Rect.Bottom + 14)), ([float]($shineX + ($Rect.Height * 0.72))), ([float]($Rect.Y - 14)))
                }
                finally { $shinePen.Dispose() }
            }
            finally {
                $Graphics.Restore($clipState)
            }
        }
    }
    finally {
        $path.Dispose()
        $fmt.Dispose()
    }
}

function Try-ExtractFrame {
    param([string]$InputPath, [string]$OutputPath)

    foreach ($timestamp in @('00:00:05', '00:00:10', '00:00:20', '00:00:30', '00:01:00')) {
        if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue }
        Invoke-Ffmpeg @('-y', '-hide_banner', '-loglevel', 'error', '-ss', $timestamp, '-i', $InputPath, '-frames:v', '1', $OutputPath)
        if ((Test-Path -LiteralPath $OutputPath) -and ((Get-Item -LiteralPath $OutputPath).Length -gt 0)) { return $true }
    }
    return $false
}

function Draw-ImageCover {
    param(
        [Drawing.Graphics]$Graphics,
        [Drawing.Image]$Image,
        [Drawing.Rectangle]$Rect,
        [int]$Alpha
    )

    if ($Alpha -le 0) { return }
    $attrs = New-Object Drawing.Imaging.ImageAttributes
    try {
        $cm = New-Object Drawing.Imaging.ColorMatrix
        $cm.Matrix33 = [single]($Alpha / 255.0)
        $attrs.SetColorMatrix($cm)
        $Graphics.DrawImage($Image, $Rect, 0, 0, $Image.Width, $Image.Height, [Drawing.GraphicsUnit]::Pixel, $attrs)
    }
    finally { $attrs.Dispose() }
}

function Get-ContainRect {
    param(
        [Drawing.Image]$Image,
        [Drawing.RectangleF]$Bounds
    )

    if ($Image -eq $null -or $Image.Width -le 0 -or $Image.Height -le 0) { return $Bounds }
    $scale = [Math]::Min($Bounds.Width / [double]$Image.Width, $Bounds.Height / [double]$Image.Height)
    $w = [float]($Image.Width * $scale)
    $h = [float]($Image.Height * $scale)
    return (New-Object Drawing.RectangleF ([float]($Bounds.X + (($Bounds.Width - $w) / 2.0))), ([float]($Bounds.Y + (($Bounds.Height - $h) / 2.0))), $w, $h)
}

function Draw-ImageContain {
    param(
        [Drawing.Graphics]$Graphics,
        [Drawing.Image]$Image,
        [Drawing.RectangleF]$Bounds,
        [int]$Alpha
    )

    if ($Alpha -le 0 -or $Image -eq $null) { return }
    $dest = Get-ContainRect -Image $Image -Bounds $Bounds
    $attrs = New-Object Drawing.Imaging.ImageAttributes
    try {
        $cm = New-Object Drawing.Imaging.ColorMatrix
        $cm.Matrix33 = [single]($Alpha / 255.0)
        $attrs.SetColorMatrix($cm)
        $destRect = New-Object Drawing.Rectangle ([int][Math]::Round($dest.X)), ([int][Math]::Round($dest.Y)), ([int][Math]::Round($dest.Width)), ([int][Math]::Round($dest.Height))
        $Graphics.DrawImage($Image, $destRect, 0, 0, $Image.Width, $Image.Height, [Drawing.GraphicsUnit]::Pixel, $attrs)
    }
    finally { $attrs.Dispose() }
}

function Test-SquareFriendlyImageFile {
    param(
        [string]$Path,
        [double]$MinRatio = 0.70,
        [double]$MaxRatio = 1.45
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $img = [Drawing.Image]::FromFile($Path)
        try {
            if ($img.Width -le 0 -or $img.Height -le 0) { return $false }
            $ratio = $img.Width / [double]$img.Height
            return ($ratio -ge $MinRatio -and $ratio -le $MaxRatio)
        }
        finally { $img.Dispose() }
    }
    catch {
        return $false
    }
}

function Draw-ArtistLogoLayer {
    param(
        [Drawing.Graphics]$Graphics,
        [Drawing.Image]$Image,
        [Drawing.RectangleF]$Bounds,
        [Drawing.Color]$GlowColor,
        [Drawing.Color]$GlowColor2,
        [double]$T,
        [int]$Alpha
    )

    if ($Alpha -le 0 -or $Image -eq $null) { return }
    $pulse = 0.5 + (0.5 * [Math]::Sin($T * [Math]::PI * 2.0))
    $scale = 0.965 + (0.035 * $pulse)
    $scaledBounds = New-Object Drawing.RectangleF ([float]($Bounds.X + ($Bounds.Width * (1.0 - $scale) / 2.0))), ([float]($Bounds.Y + ($Bounds.Height * (1.0 - $scale) / 2.0))), ([float]($Bounds.Width * $scale)), ([float]($Bounds.Height * $scale))
    $glowAlpha = [int]([Math]::Min(116, 48 + (52 * $pulse)))
    Fill-SoftEllipse -Graphics $Graphics -X ([int]($scaledBounds.X - 18)) -Y ([int]($scaledBounds.Y - 20)) -W ([int]($scaledBounds.Width + 36)) -H ([int]($scaledBounds.Height + 40)) -Color $GlowColor -Alpha $glowAlpha
    Fill-SoftEllipse -Graphics $Graphics -X ([int]($scaledBounds.X + 90)) -Y ([int]($scaledBounds.Y + 8)) -W ([int]($scaledBounds.Width - 180)) -H ([int]($scaledBounds.Height + 10)) -Color $GlowColor2 -Alpha ([int]($glowAlpha * 0.65))
    Draw-ImageContain -Graphics $Graphics -Image $Image -Bounds $scaledBounds -Alpha $Alpha
}

function Draw-RotatingLogoTile {
    param(
        [Drawing.Graphics]$Graphics,
        [Drawing.Image]$Image,
        [Drawing.Rectangle]$Rect,
        [int]$Alpha,
        [double]$T
    )

    if ($Alpha -le 0) { return }
    $phase = [Math]::Cos($T * [Math]::PI * 2.0)
    $fullView = [Math]::Abs($phase)
    $scaleX = 0.16 + (0.84 * $fullView)
    $destW = [Math]::Max(10, [int]($Rect.Width * $scaleX))
    $dest = New-Object Drawing.Rectangle ([int]($Rect.X + (($Rect.Width - $destW) / 2))), $Rect.Y, $destW, $Rect.Height
    $attrs = New-Object Drawing.Imaging.ImageAttributes
    try {
        $cm = New-Object Drawing.Imaging.ColorMatrix
        $cm.Matrix00 = [single]1.0
        $cm.Matrix11 = [single]1.0
        $cm.Matrix22 = [single]1.0
        $cm.Matrix33 = [single]($Alpha / 255.0)
        $attrs.SetColorMatrix($cm)
        $Graphics.DrawImage($Image, $dest, 0, 0, $Image.Width, $Image.Height, [Drawing.GraphicsUnit]::Pixel, $attrs)
    }
    finally { $attrs.Dispose() }
}

try {
    Try-ExtractFrame -InputPath $VideoPath -OutputPath $sourceFramePath | Out-Null
    if (-not (Test-Path -LiteralPath $sourceFramePath) -and (Test-Path -LiteralPath $FallbackLogoPath)) {
        Copy-Item -LiteralPath $FallbackLogoPath -Destination $sourceFramePath -Force
    }

    $parts = Get-TextParts -Name $baseName
    $embeddedReleaseTitle = Get-VideoReleaseTitle -Path $VideoPath
    if (-not [string]::IsNullOrWhiteSpace($embeddedReleaseTitle)) {
        $parts['ReleaseTitle'] = $embeddedReleaseTitle
        Write-Host ("Embedded release metadata: {0}" -f $embeddedReleaseTitle)
    }
    $parts = Get-MusicBrainzTextParts -Parts $parts
    if (-not [string]::IsNullOrWhiteSpace([string]$parts['ReleaseTitle'])) {
        Write-Host ("MusicBrainz metadata: artist={0}, title={1}, release={2}" -f $parts['Artist'], $parts['Title'], $parts['ReleaseTitle'])
    } else {
        Write-Host ("MusicBrainz metadata: artist={0}, title={1}, release=(none)" -f $parts['Artist'], $parts['Title'])
    }
    $albumCoverPath = if (Test-AlbumCoverLookupAllowed -Parts $parts) { Get-AlbumCoverPath -Parts $parts } else { '' }
    $artistLogoPath = Get-ArtistLogoPath -Parts $parts
    $artistArtPath = if ([string]::IsNullOrWhiteSpace($albumCoverPath) -or [string]::IsNullOrWhiteSpace($artistLogoPath)) { Get-ArtistArtPath -Parts $parts } else { '' }
    $leftArtworkKind = 'album'
    $artworkPath = ''
    if (-not [string]::IsNullOrWhiteSpace($albumCoverPath) -and (Test-Path -LiteralPath $albumCoverPath)) {
        $artworkPath = $albumCoverPath
        $leftArtworkKind = 'album'
    } elseif (-not [string]::IsNullOrWhiteSpace($artistArtPath) -and (Test-Path -LiteralPath $artistArtPath)) {
        $artworkPath = $artistArtPath
        $leftArtworkKind = 'artist'
    } elseif (Test-Path -LiteralPath $OneSauceLogoPath) {
        $artworkPath = $OneSauceLogoPath
        $leftArtworkKind = 'logo'
    } else {
        $artworkPath = $sourceFramePath
        $leftArtworkKind = 'frame'
    }
    $rightArtworkPath = ''
    $rightArtworkKind = 'logo'
    if (Test-SquareFriendlyImageFile -Path $artistLogoPath -MinRatio 0.45 -MaxRatio 2.20) {
        $rightArtworkPath = $artistLogoPath
        $rightArtworkKind = 'artist_logo'
    } elseif (Test-SquareFriendlyImageFile -Path $artistArtPath -MinRatio 0.72 -MaxRatio 1.38) {
        $rightArtworkPath = $artistArtPath
        $rightArtworkKind = 'artist'
    } elseif (Test-Path -LiteralPath $OneSauceLogoPath) {
        $rightArtworkPath = $OneSauceLogoPath
        $rightArtworkKind = 'logo'
    } elseif (Test-Path -LiteralPath $FallbackLogoPath) {
        $rightArtworkPath = $FallbackLogoPath
        $rightArtworkKind = 'logo'
    }
    if (-not [string]::IsNullOrWhiteSpace($rightArtworkPath) -and -not [string]::IsNullOrWhiteSpace($artworkPath) -and $rightArtworkPath -ieq $artworkPath) {
        if (Test-Path -LiteralPath $OneSauceLogoPath) {
            $rightArtworkPath = $OneSauceLogoPath
            $rightArtworkKind = 'logo'
        } elseif (Test-Path -LiteralPath $FallbackLogoPath) {
            $rightArtworkPath = $FallbackLogoPath
            $rightArtworkKind = 'logo'
        } else {
            $rightArtworkPath = ''
            $rightArtworkKind = 'logo'
        }
    }
    $accent = Get-ReadableAccent (Get-AverageColor $artworkPath) (New-Color 255 68 210)
    $accent2 = Get-AlbumSecondaryAccent $accent
    $pink = New-Color 255 55 210
    $cyan = New-Color 64 230 255
    $darkStroke = New-Color 23 0 58
    $accent2 = Blend-Color $accent2 $cyan 0.12

    $templates = @(
        'AlbumArtAura',
        'NeonEqualizer',
        'CrtWall',
        'JukeboxLightbox',
        'ConcertStage',
        'VinylSpin',
        'ArcadeMarquee',
        'SmokeNeon',
        'LaserGrid',
        'PrismBands',
        'Starburst',
        'CassetteDeck',
        'CityLights',
        'RetroSunset',
        'SoundwaveTunnel',
        'AuroraCurtain',
        'VinylShelf',
        'SpeakerStack',
        'MicStage',
        'NoteStream',
        'RecordWall',
        'DrumRoom',
        'GuitarWall',
        'HeadphoneGlow',
        'KeyboardWave'
    )
    $wordStyles = @(
        'SynthwaveNeon',
        'ChromeArcade',
        'GoldMarquee',
        'ElectricBlue',
        'RockGlow',
        'PosterPop',
        'DiscoChrome',
        'RetroScript',
        'BlockParty',
        'NeonSign',
        'ClassicSerif',
        'ActionOps',
        'LuckyPop',
        'TitanBurst',
        'RowdyGlow',
        'CarterRetro',
        'UltraPoster',
        'BevanChrome',
        'CooperPop',
        'BroadwayLights',
        'StencilRock',
        'BauhausGlow',
        'ShowcardBlast',
        'MagnetoNeon',
        'BookmanClassic',
        'RavieParty'
    )
    $visualizerStyles = @('EqualizerBars', 'EqualizerMirror', 'EqualizerStack', 'EqualizerThin', 'EqualizerSweep', 'EqualizerSidePulse', 'EqualizerComet')
    $motions = @(
        'LoopAlive',
        'LoopAliveClassic',
        'FlyPop',
        'SlideBounce',
        'DropIn',
        'ZoomReveal',
        'TitleLeftArtistRight',
        'TitleRightArtistLeft',
        'TitleUpArtistDown',
        'TitleDownArtistUp',
        'CrossSlide',
        'DiagonalSplit',
        'StaggeredRise',
        'StaggeredDrop',
        'PunchPop',
        'WideCompress',
        'CornerSweep',
        'ArtistLead'
    )
    $templateVariantCount = 8
    $seedSource = if ([string]::IsNullOrWhiteSpace($RandomSeed)) { '{0}|{1}' -f $baseName, ((Get-Item -LiteralPath $VideoPath).Length) } else { $RandomSeed }
    $rng = New-Object Random (Get-DeterministicSeed $seedSource)
    $templateName = if ($templates -contains $TemplateName) { $TemplateName } else { $templates[$rng.Next($templates.Count)] }
    $templateVariantValue = if ($TemplateVariant -ge 0) { $TemplateVariant % $templateVariantCount } else { $rng.Next($templateVariantCount) }
    $wordStyleName = if ($wordStyles -contains $WordArtStyle) { $WordArtStyle } else { $wordStyles[$rng.Next($wordStyles.Count)] }
    $motionName = if ($motions -contains $MotionStyle) { $MotionStyle } else { 'LoopAlive' }
    $visualizerStyleName = if ($visualizerStyles -contains $VisualizerStyle) { $VisualizerStyle } else { $visualizerStyles[$rng.Next($visualizerStyles.Count)] }
    $palette = Get-WordArtPalette -StyleName $wordStyleName -Accent $accent -Accent2 $accent2 -Pink $pink -Cyan $cyan -DarkStroke $darkStroke
    $palette = Get-AlbumAdaptiveWordArtPalette -Palette $palette -Accent $accent -Accent2 $accent2 -DarkStroke $darkStroke -Pink $pink -Cyan $cyan
    Write-Host ("Video marquee recipe: background={0}.v{1}, word_art={2}, motion={3}, visualizer={4}, left_art={5}, artist_logo={6}" -f $templateName, $templateVariantValue, $wordStyleName, $motionName, $visualizerStyleName, $leftArtworkKind, $false)

    $albumImage = $null
    if (Test-Path -LiteralPath $artworkPath) { $albumImage = [Drawing.Image]::FromFile($artworkPath) }
    $artistLogoImage = $null
    $rightImage = $null
    if (-not [string]::IsNullOrWhiteSpace($rightArtworkPath) -and (Test-Path -LiteralPath $rightArtworkPath)) {
        $rightImage = [Drawing.Image]::FromFile($rightArtworkPath)
    }

    try {
        $firstFrame = 0
        $lastFrame = $FrameCount - 1
        if (-not $GenerateAnimated -and $GenerateFullColorStill) {
            $firstFrame = $FullColorStillFrame
            $lastFrame = $FullColorStillFrame
        }

        for ($i = $firstFrame; $i -le $lastFrame; $i++) {
            $t = [double]$i / [double]$FrameCount
            $bitmap = New-Object Drawing.Bitmap $Width, $Height, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [Drawing.Graphics]::FromImage($bitmap)
            try {
                $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $g.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
                $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit

                Draw-TemplateBackground -Graphics $g -TemplateName $templateName -T $t -Accent $accent -Accent2 $accent2 -Pink $pink -Cyan $cyan -DarkStroke $darkStroke -Width $Width -Height $Height -TemplateVariant $templateVariantValue

                if ($albumImage -ne $null) {
                    if ($motionName -eq 'LoopAlive') {
                        $albumAlpha = 255
                        $albumSize = $PanelArtSize
                        $albumX = $PanelEdgeMargin
                        $albumLoopT = $t
                        $albumScrollRange = $Height + $albumSize
                        $albumY = [int](-$albumSize + ($albumScrollRange * $albumLoopT))
                        $albumShadowAlpha = 0
                    } elseif ($motionName -eq 'LoopAliveClassic') {
                        $albumAlpha = 255
                        $albumSize = $PanelArtSize
                        $albumX = $PanelEdgeMargin
                        $albumBouncePhase = [Math]::Sin($t * [Math]::PI * 2.0 * 3.0)
                        $albumBounceY = [int](8 * $albumBouncePhase)
                        $albumShadowAlpha = [int](28 + (62 * (Clamp01 (($albumBouncePhase + 1.0) / 2.0))))
                        $albumY = [int](($Height - $albumSize) / 2) + $albumBounceY
                    } else {
                        $inT = Ease-OutBack (($t - 0.04) / 0.28)
                        $outT = Ease-OutCubic (($t - 0.82) / 0.13)
                        $albumAlpha = [int](255 * (Clamp01 (($t - 0.02) / 0.18)) * (1.0 - (Clamp01 $outT)))
                        $albumSize = [int](310 + (8 * [Math]::Sin($t * [Math]::PI * 2.0)))
                        $albumX = [int](Lerp -A (-$PanelArtSize) -B $PanelEdgeMargin -T $inT)
                        $albumX = [int](Lerp -A $albumX -B (-$PanelArtSize) -T $outT)
                        $albumBounceY = 0
                        $albumShadowAlpha = 0
                        $albumY = [int](($Height - $albumSize) / 2) + $albumBounceY
                    }
                    if ($albumShadowAlpha -gt 0) {
                        $shadowW = [int]($albumSize * 0.82)
                        $shadowH = 18
                        $shadowX = [int]($albumX + (($albumSize - $shadowW) / 2))
                        $shadowY = [int]($albumY + $albumSize - 2)
                        Fill-SoftEllipse -Graphics $g -X $shadowX -Y $shadowY -W $shadowW -H $shadowH -Color (New-Color 0 0 0) -Alpha $albumShadowAlpha
                    }
                    if ($motionName -eq 'LoopAlive') {
                        foreach ($drawY in @($albumY, ($albumY - ($Height + $albumSize)))) {
                            if ($drawY -gt $Height -or ($drawY + $albumSize) -lt 0) { continue }
                            if ($leftArtworkKind -eq 'logo') {
                                Draw-RotatingLogoTile -Graphics $g -Image $albumImage -Rect (New-Object Drawing.Rectangle $albumX, $drawY, $albumSize, $albumSize) -Alpha $albumAlpha -T $t
                            } else {
                                Draw-ImageCover -Graphics $g -Image $albumImage -Rect (New-Object Drawing.Rectangle $albumX, $drawY, $albumSize, $albumSize) -Alpha $albumAlpha
                            }
                        }
                    } elseif ($leftArtworkKind -eq 'logo') {
                        Draw-RotatingLogoTile -Graphics $g -Image $albumImage -Rect (New-Object Drawing.Rectangle $albumX, $albumY, $albumSize, $albumSize) -Alpha $albumAlpha -T $t
                    } else {
                        Draw-ImageCover -Graphics $g -Image $albumImage -Rect (New-Object Drawing.Rectangle $albumX, $albumY, $albumSize, $albumSize) -Alpha $albumAlpha
                    }
                }

                $rightAlpha = 255
                $rightSize = $PanelArtSize
                $rightMargin = $PanelEdgeMargin
                $rightX = $Width - $rightMargin - $rightSize
                $rightY = [int](($Height - $rightSize) / 2)
                $rightRect = New-Object Drawing.Rectangle $rightX, $rightY, $rightSize, $rightSize
                Draw-VisualizerTile -Graphics $g -Rect $rightRect -StyleName $visualizerStyleName -T $t -Accent $accent -Accent2 $accent2 -Pink $pink -Cyan $cyan -Alpha $rightAlpha

                $textFrameScale = if ($motionName -eq 'LoopAlive' -or $motionName -eq 'LoopAliveClassic') { 1.0 } else { 0.985 + (0.015 * [Math]::Sin($t * [Math]::PI * 2.0)) }
                $textFrameW = [int](1040 * $textFrameScale)
                $textFrameH = [int](238 * $textFrameScale)
                $textFrame = New-Object Drawing.Rectangle ([int](($Width - $textFrameW) / 2)), ([int](($Height - $textFrameH) / 2)), $textFrameW, $textFrameH

                $titleFont = $null
                $artistFont = $null
                try {
                    $motion = Get-TextMotion -MotionName $motionName -T $t
                    $titleFillTop = $palette.TitleTop
                    $titleFillBottom = $palette.TitleBottom
                    $titleGlow = $palette.TitleGlow
                    $artistFillTop = $palette.ArtistTop
                    $artistFillBottom = $palette.ArtistBottom
                    $artistGlow = $palette.ArtistGlow
                    $titlePulse = if ($motionName -eq 'LoopAlive' -or $motionName -eq 'LoopAliveClassic') { 0.5 + (0.5 * [Math]::Sin($t * [Math]::PI * 2.0)) } else { 0.5 }
                    $artistPulse = if ($motionName -eq 'LoopAlive' -or $motionName -eq 'LoopAliveClassic') { 1.0 - $titlePulse } else { 0.5 }
                    $titleGlowBoost = if ($motionName -eq 'LoopAlive' -or $motionName -eq 'LoopAliveClassic') { 0.72 + (0.50 * $titlePulse) } else { 1.0 }
                    $artistGlowBoost = if ($motionName -eq 'LoopAlive' -or $motionName -eq 'LoopAliveClassic') { 0.72 + (0.50 * $artistPulse) } else { 1.0 }
                    if ($motionName -eq 'LoopAlive') {
                        $titleText = [string]($parts['Title'])
                        $artistText = [string]($parts['Artist'])
                        $titleArea = New-Object Drawing.RectangleF 300, -4, 1320, 194
                        $artistArea = New-Object Drawing.RectangleF 320, 170, 1280, 194
                        $swapT = 0.5 - (0.5 * [Math]::Cos($t * [Math]::PI * 2.0))
                        $titleStartY = 0.0
                        $titleEndY = 170.0
                        $artistStartY = 170.0
                        $artistEndY = 0.0
                        $titleY = [double](Lerp -A $titleStartY -B $titleEndY -T $swapT)
                        $artistY = [double](Lerp -A $artistStartY -B $artistEndY -T $swapT)
                        $titleRect = New-Object Drawing.RectangleF $titleArea.X, ([float]$titleY), $titleArea.Width, $titleArea.Height
                        $artistRect = New-Object Drawing.RectangleF $artistArea.X, ([float]$artistY), $artistArea.Width, $artistArea.Height
                        $titleWordCount = @($titleText -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
                        $artistWordCount = @($artistText -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
                        $titlePreferWrap = ($titleText.Length -ge 26 -and $titleWordCount -ge 3)
                        $artistPreferWrap = ($artistText.Length -ge 28 -and $artistWordCount -ge 3)
                        $titleStartSize = if ($titlePreferWrap) { 154 } else { Get-OneLineTextStartSize -Text $titleText -BaseSize 190 -ShortSize 218 -VeryShortSize 236 }
                        $artistStartSize = if ($artistPreferWrap) { 140 } else { Get-OneLineTextStartSize -Text $artistText -BaseSize 172 -ShortSize 202 -VeryShortSize 222 }
                        $titleFont = Get-FitFontForRect -Graphics $g -Text $titleText -FamilyName $palette.TitleFont -Style ([Drawing.FontStyle]::Regular) -StartSize $titleStartSize -Rect $titleArea -MaxLines 2 -PreferWrap:$titlePreferWrap
                        $artistFont = Get-FitFontForRect -Graphics $g -Text $artistText -FamilyName $palette.ArtistFont -Style ([Drawing.FontStyle]::Bold) -StartSize $artistStartSize -Rect $artistArea -MaxLines 2 -PreferWrap:$artistPreferWrap
                        $titleWrapMaxWidth = [Math]::Max(12.0, $titleArea.Width - (28.0 + ([Math]::Max(10.0, [double]($titleFont.Size * 0.12 + ([float]$palette.Stroke * 1.2))) * 2.0)))
                        $artistWrapMaxWidth = [Math]::Max(12.0, $artistArea.Width - (28.0 + ([Math]::Max(10.0, [double]($artistFont.Size * 0.12 + (5.0 * 1.2))) * 2.0)))
                        $titleMeasuredWidth = [double]($g.MeasureString($titleText, $titleFont).Width)
                        $artistMeasuredWidth = [double]($g.MeasureString($artistText, $artistFont).Width)
                        $titleForceWrap = ($titlePreferWrap -or (($titleFont.Size -lt 80 -and $titleWordCount -ge 3) -and $titleMeasuredWidth -gt ($titleWrapMaxWidth * 0.90)))
                        $artistForceWrap = ($artistPreferWrap -or (($artistFont.Size -lt 76 -and $artistWordCount -ge 3) -and $artistMeasuredWidth -gt ($artistWrapMaxWidth * 0.90)))
                        $wheelDepth = [Math]::Sin($t * [Math]::PI * 2.0)
                        $titleWheelScale = 0.50 + (0.50 * $wheelDepth)
                        $artistWheelScale = 0.50 - (0.50 * $wheelDepth)
                        $titleIsFront = ($t -lt 0.5)
                        $artistIsFront = (-not $titleIsFront)
                        $titleAccentWindow = Clamp01 (1.0 - ([Math]::Abs($t - 0.25) / 0.085))
                        $artistAccentWindow = Clamp01 (1.0 - ([Math]::Abs($t - 0.75) / 0.085))
                        $titleAccent = [Math]::Sin($titleAccentWindow * [Math]::PI * 0.5)
                        $artistAccent = [Math]::Sin($artistAccentWindow * [Math]::PI * 0.5)
                        $titleAccentMultiplier = 0.94
                        if ($titleText.Length -gt 18) { $titleAccentMultiplier = 0.82 }
                        $artistAccentMultiplier = 1.06
                        if ($artistText.Length -lt 12) { $artistAccentMultiplier = 1.18 }
                        $titleAccent = $titleAccent * $titleAccentMultiplier
                        $artistAccent = [Math]::Min(1.18, $artistAccent * $artistAccentMultiplier)
                        $titleShineProgress = Clamp01 (($t - 0.175) / 0.15)
                        $artistShineProgress = Clamp01 (($t - 0.675) / 0.15)
                        $titleAlphaWheel = [int]([Math]::Min(255, [Math]::Max(0, $motion.TitleAlpha * $titleWheelScale)))
                        $artistAlphaWheel = [int]([Math]::Min(255, [Math]::Max(0, 255 * $artistWheelScale)))
                        $titleGlowBoost = $titleGlowBoost * (0.25 + (0.75 * $titleWheelScale)) * (1.0 + (0.55 * $titleAccent))
                        $artistGlowBoost = $artistGlowBoost * (0.25 + (0.75 * $artistWheelScale)) * (1.0 + (0.55 * $artistAccent))
                        $titleDrawFont = New-Object Drawing.Font -ArgumentList $titleFont.FontFamily, ([float]([Math]::Max(1.0, $titleFont.Size * $titleWheelScale))), $titleFont.Style, ([Drawing.GraphicsUnit]::Pixel)
                        $artistDrawFont = New-Object Drawing.Font -ArgumentList $artistFont.FontFamily, ([float]([Math]::Max(1.0, $artistFont.Size * $artistWheelScale))), $artistFont.Style, ([Drawing.GraphicsUnit]::Pixel)
                        try {
                            $clipState = $g.Save()
                            try {
                                $g.SetClip((New-Object Drawing.Rectangle 320, 0, 1280, $Height))
                                if ($t -lt 0.5) {
                                    Draw-WordArt -Graphics $g -Text $artistText -Font $artistDrawFont -Rect $artistRect -FillTop $artistFillTop -FillBottom $artistFillBottom -StrokeColor $palette.ArtistStroke -GlowColor $artistGlow -StrokeWidth 5 -Alpha $artistAlphaWheel -GlowBoost $artistGlowBoost -MaxLines 2 -AccentStrength $artistAccent -ShineProgress $artistShineProgress -ForceWrap:$artistForceWrap
                                    Draw-WordArt -Graphics $g -Text $titleText -Font $titleDrawFont -Rect $titleRect -FillTop $titleFillTop -FillBottom $titleFillBottom -StrokeColor $palette.TitleStroke -GlowColor $titleGlow -StrokeWidth ([float]$palette.Stroke) -Alpha $titleAlphaWheel -GlowBoost $titleGlowBoost -MaxLines 2 -AccentStrength $titleAccent -ShineProgress $titleShineProgress -ForceWrap:$titleForceWrap
                                } else {
                                    Draw-WordArt -Graphics $g -Text $titleText -Font $titleDrawFont -Rect $titleRect -FillTop $titleFillTop -FillBottom $titleFillBottom -StrokeColor $palette.TitleStroke -GlowColor $titleGlow -StrokeWidth ([float]$palette.Stroke) -Alpha $titleAlphaWheel -GlowBoost $titleGlowBoost -MaxLines 2 -AccentStrength $titleAccent -ShineProgress $titleShineProgress -ForceWrap:$titleForceWrap
                                    Draw-WordArt -Graphics $g -Text $artistText -Font $artistDrawFont -Rect $artistRect -FillTop $artistFillTop -FillBottom $artistFillBottom -StrokeColor $palette.ArtistStroke -GlowColor $artistGlow -StrokeWidth 5 -Alpha $artistAlphaWheel -GlowBoost $artistGlowBoost -MaxLines 2 -AccentStrength $artistAccent -ShineProgress $artistShineProgress -ForceWrap:$artistForceWrap
                                }
                            }
                            finally {
                                $g.Restore($clipState)
                            }
                        }
                        finally {
                            if ($titleDrawFont) { $titleDrawFont.Dispose(); $titleDrawFont = $null }
                            if ($artistDrawFont) { $artistDrawFont.Dispose(); $artistDrawFont = $null }
                            if ($titleFont) { $titleFont.Dispose(); $titleFont = $null }
                            if ($artistFont) { $artistFont.Dispose(); $artistFont = $null }
                        }
                    } elseif ($motionName -eq 'LoopAliveClassic') {
                        $titleText = [string]($parts['Title'])
                        $artistText = [string]($parts['Artist'])
                        $titleLines = @(if ($titleText.Length -gt 38) { Split-MarqueeTextLines -Text $titleText -MaxLines 2 } else { $titleText })
                        $artistLines = @(if ($artistText.Length -gt 44) { Split-MarqueeTextLines -Text $artistText -MaxLines 2 } else { $artistText })

                        $titleArea = New-Object Drawing.RectangleF 360, 28, 1200, 164
                        $artistArea = New-Object Drawing.RectangleF 405, 194, 1110, 116
                        $titleLineHeight = [float]($titleArea.Height / [Math]::Max(1, $titleLines.Count))
                        $artistLineHeight = [float]($artistArea.Height / [Math]::Max(1, $artistLines.Count))
                        $titleMaxStart = if ($titleLines.Count -gt 1) { 82 } else { 112 }
                        $artistMaxStart = if ($artistLines.Count -gt 1) { 56 } else { 88 }

                        for ($lineIndex = 0; $lineIndex -lt $titleLines.Count; $lineIndex++) {
                            $lineText = [string]($titleLines[$lineIndex])
                            $lineRect = New-Object Drawing.RectangleF $titleArea.X, ([float]($titleArea.Y + ($lineIndex * $titleLineHeight))), $titleArea.Width, $titleLineHeight
                            $maxTitleFont = Get-FitFontForRect -Graphics $g -Text $lineText -FamilyName $palette.TitleFont -Style ([Drawing.FontStyle]::Regular) -StartSize $titleMaxStart -Rect $lineRect
                            try {
                                $titleStartSize = [Math]::Max(12, [int][Math]::Round($maxTitleFont.Size * (0.84 + (0.16 * $titlePulse))))
                            }
                            finally {
                                $maxTitleFont.Dispose()
                            }
                            $titleFont = Get-FitFontForRect -Graphics $g -Text $lineText -FamilyName $palette.TitleFont -Style ([Drawing.FontStyle]::Regular) -StartSize $titleStartSize -Rect $lineRect
                            try {
                                Draw-WordArt -Graphics $g -Text $lineText -Font $titleFont -Rect $lineRect -FillTop $titleFillTop -FillBottom $titleFillBottom -StrokeColor $palette.TitleStroke -GlowColor $titleGlow -StrokeWidth ([float]$palette.Stroke) -Alpha $motion.TitleAlpha -GlowBoost $titleGlowBoost
                            }
                            finally {
                                $titleFont.Dispose()
                                $titleFont = $null
                            }
                        }

                        for ($lineIndex = 0; $lineIndex -lt $artistLines.Count; $lineIndex++) {
                            $lineText = [string]($artistLines[$lineIndex])
                            $lineRect = New-Object Drawing.RectangleF $artistArea.X, ([float]($artistArea.Y + ($lineIndex * $artistLineHeight))), $artistArea.Width, $artistLineHeight
                            $maxArtistFont = Get-FitFontForRect -Graphics $g -Text $lineText -FamilyName $palette.ArtistFont -Style ([Drawing.FontStyle]::Bold) -StartSize $artistMaxStart -Rect $lineRect
                            try {
                                $artistStartSize = [Math]::Max(12, [int][Math]::Round($maxArtistFont.Size * (0.84 + (0.16 * $artistPulse))))
                            }
                            finally {
                                $maxArtistFont.Dispose()
                            }
                            $artistFont = Get-FitFontForRect -Graphics $g -Text $lineText -FamilyName $palette.ArtistFont -Style ([Drawing.FontStyle]::Bold) -StartSize $artistStartSize -Rect $lineRect
                            try {
                                Draw-WordArt -Graphics $g -Text $lineText -Font $artistFont -Rect $lineRect -FillTop $artistFillTop -FillBottom $artistFillBottom -StrokeColor $palette.ArtistStroke -GlowColor $artistGlow -StrokeWidth 5 -Alpha $motion.ArtistAlpha -GlowBoost $artistGlowBoost
                            }
                            finally {
                                $artistFont.Dispose()
                                $artistFont = $null
                            }
                        }
                    } else {
                        $titleScale = $motion.TitleScale
                        $titleRectW = [float](($textFrame.Width - 68) * $titleScale)
                        $titleRectH = [float](142 * $titleScale)
                        $titleRect = New-Object Drawing.RectangleF ([float]($motion.TitleX - ($titleRectW / 2.0))), ([float]($motion.TitleY - ($titleRectH / 2.0))), $titleRectW, $titleRectH
                        $titleFont = Get-FitFont -Graphics $g -Text $parts['Title'] -FamilyName $palette.TitleFont -Style ([Drawing.FontStyle]::Regular) -StartSize 142 -MaxWidth ([int]($textFrame.Width - 66))
                        Draw-WordArt -Graphics $g -Text $parts['Title'] -Font $titleFont -Rect $titleRect -FillTop $titleFillTop -FillBottom $titleFillBottom -StrokeColor $palette.TitleStroke -GlowColor $titleGlow -StrokeWidth ([float]$palette.Stroke) -Alpha $motion.TitleAlpha -GlowBoost $titleGlowBoost

                        $artistScale = $motion.ArtistScale
                        $artistRectW = [float](($textFrame.Width - 230) * $artistScale)
                        $artistRectH = [float](82 * $artistScale)
                        $artistRect = New-Object Drawing.RectangleF ([float]($motion.ArtistX - ($artistRectW / 2.0))), ([float]($motion.ArtistY - ($artistRectH / 2.0))), $artistRectW, $artistRectH
                        $artistFont = Get-FitFont -Graphics $g -Text $parts['Artist'] -FamilyName $palette.ArtistFont -Style ([Drawing.FontStyle]::Bold) -StartSize 68 -MaxWidth ([int]($textFrame.Width - 160))
                        Draw-WordArt -Graphics $g -Text $parts['Artist'] -Font $artistFont -Rect $artistRect -FillTop $artistFillTop -FillBottom $artistFillBottom -StrokeColor $palette.ArtistStroke -GlowColor $artistGlow -StrokeWidth 5 -Alpha $motion.ArtistAlpha -GlowBoost $artistGlowBoost
                    }
                }
                finally {
                    if ($titleFont) { $titleFont.Dispose() }
                    if ($artistFont) { $artistFont.Dispose() }
                }

                $framePath = Join-Path $frameDir ('frame_{0:0000}.png' -f $i)
                if ($GenerateAnimated) {
                    $bitmap.Save($framePath, [Drawing.Imaging.ImageFormat]::Png)
                }
                if ($GenerateFullColorStill -and $i -eq $FullColorStillFrame) {
                    $stillBitmap = New-Object Drawing.Bitmap $Width, $Height, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
                    $stillG = [Drawing.Graphics]::FromImage($stillBitmap)
                    try {
                        $stillG.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
                        $stillG.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                        $stillG.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                        $stillG.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
                        $stillG.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit

                        Draw-TemplateBackground -Graphics $stillG -TemplateName $templateName -T $t -Accent $accent -Accent2 $accent2 -Pink $pink -Cyan $cyan -DarkStroke $darkStroke -Width $Width -Height $Height -TemplateVariant $templateVariantValue

                        $stillAlbumSize = $PanelArtSize
                        $stillAlbumX = $PanelEdgeMargin
                        $stillAlbumY = [int](($Height - $stillAlbumSize) / 2)
                        $stillRightX = $Width - $stillAlbumX - $stillAlbumSize
                        $stillLeftRect = New-Object Drawing.Rectangle $stillAlbumX, $stillAlbumY, $stillAlbumSize, $stillAlbumSize
                        $stillRightRect = New-Object Drawing.Rectangle $stillRightX, $stillAlbumY, $stillAlbumSize, $stillAlbumSize

                        if ($albumImage -ne $null) {
                            if ($leftArtworkKind -eq 'logo') {
                                Draw-RotatingLogoTile -Graphics $stillG -Image $albumImage -Rect $stillLeftRect -Alpha 255 -T $t
                            } else {
                                Draw-ImageCover -Graphics $stillG -Image $albumImage -Rect $stillLeftRect -Alpha 255
                            }
                        }
                        if ($rightImage -ne $null) {
                            $stillRightBounds = New-Object Drawing.RectangleF ([float]$stillRightRect.X), ([float]$stillRightRect.Y), ([float]$stillRightRect.Width), ([float]$stillRightRect.Height)
                            Draw-ImageContain -Graphics $stillG -Image $rightImage -Bounds $stillRightBounds -Alpha 255
                        }

                        $stillTitleText = [string]($parts['Title'])
                        $stillArtistText = [string]($parts['Artist'])
                        $stillTitleRect = New-Object Drawing.RectangleF 340, -4, 1260, 194
                        $stillArtistRect = New-Object Drawing.RectangleF 360, 170, 1220, 194
                        $stillTitleFont = $null
                        $stillArtistFont = $null
                        try {
                            $stillTitleWordCount = @($stillTitleText -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
                            $stillArtistWordCount = @($stillArtistText -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
                            $stillTitlePreferWrap = ($stillTitleText.Length -ge 26 -and $stillTitleWordCount -ge 3)
                            $stillArtistPreferWrap = ($stillArtistText.Length -ge 28 -and $stillArtistWordCount -ge 3)
                            $stillTitleStartSize = if ($stillTitlePreferWrap) { 164 } else { Get-OneLineTextStartSize -Text $stillTitleText -BaseSize 200 -ShortSize 228 -VeryShortSize 246 }
                            $stillArtistStartSize = if ($stillArtistPreferWrap) { 148 } else { Get-OneLineTextStartSize -Text $stillArtistText -BaseSize 180 -ShortSize 212 -VeryShortSize 232 }
                            $stillTitleFont = Get-FitFontForRect -Graphics $stillG -Text $stillTitleText -FamilyName $palette.TitleFont -Style ([Drawing.FontStyle]::Regular) -StartSize $stillTitleStartSize -Rect $stillTitleRect -MaxLines 2 -PreferWrap:$stillTitlePreferWrap
                            $stillArtistFont = Get-FitFontForRect -Graphics $stillG -Text $stillArtistText -FamilyName $palette.ArtistFont -Style ([Drawing.FontStyle]::Bold) -StartSize $stillArtistStartSize -Rect $stillArtistRect -MaxLines 2 -PreferWrap:$stillArtistPreferWrap
                            $clipState = $stillG.Save()
                            try {
                                $stillG.SetClip((New-Object Drawing.Rectangle 330, 0, 1280, $Height))
                                Draw-WordArt -Graphics $stillG -Text $stillTitleText -Font $stillTitleFont -Rect $stillTitleRect -FillTop $titleFillTop -FillBottom $titleFillBottom -StrokeColor $palette.TitleStroke -GlowColor $titleGlow -StrokeWidth ([float]$palette.Stroke) -Alpha 255 -GlowBoost 1.04 -MaxLines 2 -ForceWrap:$stillTitlePreferWrap
                                Draw-WordArt -Graphics $stillG -Text $stillArtistText -Font $stillArtistFont -Rect $stillArtistRect -FillTop $artistFillTop -FillBottom $artistFillBottom -StrokeColor $palette.ArtistStroke -GlowColor $artistGlow -StrokeWidth 5 -Alpha 245 -GlowBoost 1.0 -MaxLines 2 -ForceWrap:$stillArtistPreferWrap
                            }
                            finally {
                                $stillG.Restore($clipState)
                            }
                        }
                        finally {
                            if ($stillTitleFont) { $stillTitleFont.Dispose() }
                            if ($stillArtistFont) { $stillArtistFont.Dispose() }
                        }

                        Save-JpegUnderLimit $stillBitmap $fullColorStillPath 200000
                    }
                    finally {
                        $stillG.Dispose()
                        $stillBitmap.Dispose()
                    }
                }
            }
            finally {
                $g.Dispose()
                $bitmap.Dispose()
            }
        }
    }
    finally {
        if ($albumImage -ne $null) { $albumImage.Dispose() }
        if ($artistLogoImage -ne $null) { $artistLogoImage.Dispose() }
        if ($rightImage -ne $null) { $rightImage.Dispose() }
    }

    if ($GenerateAnimated) {
        if (Test-Path -LiteralPath $outputPath) { Remove-Item -LiteralPath $outputPath -Force }
        $framePattern = Join-Path $frameDir 'frame_%04d.png'
        Invoke-Ffmpeg @(
            '-y',
            '-hide_banner',
            '-loglevel', 'error',
            '-framerate', $Fps,
            '-i', $framePattern,
            '-c:v', 'libx264',
            '-profile:v', 'high',
            '-level:v', '3.1',
            '-pix_fmt', 'yuv420p',
            '-b:v', '5M',
            '-maxrate', '5M',
            '-bufsize', '10M',
            '-r', $Fps,
            '-an',
            '-movflags', '+faststart',
            $outputPath
        )
        if ($LASTEXITCODE -ne 0) { throw "FFmpeg encode failed for $baseName" }
        Write-Host "Generated Animated marquee: $outputPath"
    }
    if ($GenerateFullColorStill) {
        Write-Host "Generated Full Color marquee: $fullColorStillPath"
    }
}
finally {
    if ($PrivateFonts) { $PrivateFonts.Dispose() }
    if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
}
