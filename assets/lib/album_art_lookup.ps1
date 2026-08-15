param(
    [string]$Artist = '',
    [string]$Title = '',
    [string]$CacheDir = '',
    [string]$ReleaseMbid = '',
    [string]$ReleaseTitle = '',
    [ValidateSet('standard', 'curated')]
    [string]$LookupMode = 'standard'
)

$ErrorActionPreference = 'Stop'

function Get-SafeCacheName {
    param([string]$Value)
    $safe = $Value.ToLowerInvariant()
    $safe = $safe -replace '[^a-z0-9]+', '_'
    $safe = $safe.Trim('_')
    if ($safe.Length -gt 120) { $safe = $safe.Substring(0, 120).Trim('_') }
    if ($safe.Length -eq 0) { $safe = [Guid]::NewGuid().ToString('N') }
    return $safe
}

function Invoke-MusicBrainzJson {
    param([string]$Url)
    $headers = @{ 'User-Agent' = 'JukeboxDownloadWizard/0.3.0.0 ( https://musicbrainz.org/ )' }
    return Invoke-RestMethod -Uri $Url -Headers $headers -TimeoutSec 12
}

function Test-ImageFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        $img = [Drawing.Image]::FromFile($Path)
        try { return ($img.Width -gt 0 -and $img.Height -gt 0) }
        finally { $img.Dispose() }
    }
    catch {
        return $false
    }
}

function Test-KnownArtist {
    param([string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value.Trim() -ine 'UNKNOWN ARTIST')
}

function Get-AlbumQueryParts {
    param([string]$ArtistValue, [string]$TitleValue)

    $resolvedArtist = if ($null -eq $ArtistValue) { '' } else { $ArtistValue.Trim() }
    $resolvedTitle = if ($null -eq $TitleValue) { '' } else { $TitleValue.Trim() }

    if ((-not (Test-KnownArtist $resolvedArtist)) -and $resolvedTitle -match '^\s*(?<artist>[^-|:]+?)\s+[-|:]\s+(?<title>.+?)\s*$') {
        $resolvedArtist = $Matches['artist'].Trim()
        $resolvedTitle = $Matches['title'].Trim()
    }
    if ($resolvedArtist -match '^\s*(?<name>.+?)\s*,\s*(?<article>The|A|An)\s*$') {
        $resolvedArtist = ('{0} {1}' -f $Matches['article'], $Matches['name'])
    }
    if ($resolvedArtist -match '(?i)^\s*AC[\s_\-\/]*DC\s*$') { $resolvedArtist = 'AC/DC' }
    if ($resolvedArtist -match '(?i)^\s*DESTINYS\s+CHILD\s*$') { $resolvedArtist = "Destiny's Child" }
    if ($resolvedArtist -match '(?i)^\s*GUNS\s+N\s+ROSES\s*$') { $resolvedArtist = "Guns N' Roses" }
    if ($resolvedArtist -match '(?i)^\s*CELINE\s+DION\s*$') { $resolvedArtist = ([string]([char]0x0043) + [char]0x00e9 + 'line Dion') }
    if ($resolvedArtist -match '(?i)^\s*BEYONCE\s*$') { $resolvedArtist = ([string]([char]0x0042) + 'eyonc' + [char]0x00e9) }
    if ($resolvedArtist -match '^\s*(?<thousands>\d{1,2})\s+(?<hundreds>\d{3})(?<rest>\s+\S.*)$') {
        $resolvedArtist = ('{0},{1}{2}' -f $Matches['thousands'], $Matches['hundreds'], $Matches['rest'])
    }

    return @{ Artist = $resolvedArtist; Title = $resolvedTitle }
}

function Try-DownloadCover {
    param([string]$ReleaseId, [string]$OutputPath)
    if ([string]::IsNullOrWhiteSpace($ReleaseId)) { return $false }
    $url = 'https://coverartarchive.org/release/' + $ReleaseId + '/front-500'
    try {
        Invoke-WebRequest -Uri $url -OutFile $OutputPath -TimeoutSec 20 -MaximumRedirection 5 -UseBasicParsing | Out-Null
        if ((Test-Path -LiteralPath $OutputPath) -and ((Get-Item -LiteralPath $OutputPath).Length -gt 0) -and (Test-ImageFile -Path $OutputPath)) { return $true }
    }
    catch {
    }
    if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue }
    return $false
}

function Try-DownloadReleaseGroupCover {
    param([string]$ReleaseGroupId, [string]$OutputPath)
    if ([string]::IsNullOrWhiteSpace($ReleaseGroupId)) { return $false }
    $url = 'https://coverartarchive.org/release-group/' + $ReleaseGroupId + '/front-500'
    try {
        Invoke-WebRequest -Uri $url -OutFile $OutputPath -TimeoutSec 20 -MaximumRedirection 5 -UseBasicParsing | Out-Null
        if ((Test-Path -LiteralPath $OutputPath) -and ((Get-Item -LiteralPath $OutputPath).Length -gt 0) -and (Test-ImageFile -Path $OutputPath)) { return $true }
    }
    catch {
    }
    if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue }
    return $false
}

function Get-NormalizedText {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $text = $Value.Normalize('FormD') -replace '\p{Mn}', ''
    $text = $text.ToLowerInvariant()
    $text = $text -replace '\bac\s*/?\s*dc\b', 'acdc'
    $text = $text -replace '\b(ft|feat|featuring|with|and|y|con|x)\b', ' '
    $text = $text -replace '[^\p{L}\p{Nd}]+', ' '
    $text = $text -replace '\s+', ' '
    return $text.Trim()
}

function Get-AppleArtworkUrl {
    param([string]$ArtistValue, [string]$ReleaseTitleValue, [string]$TitleValue)

    $searchTitle = if (-not [string]::IsNullOrWhiteSpace($ReleaseTitleValue)) { $ReleaseTitleValue } else { $TitleValue }
    if ([string]::IsNullOrWhiteSpace($searchTitle)) { return '' }

    $term = if (Test-KnownArtist $ArtistValue) { ($ArtistValue + ' ' + $searchTitle) } else { $searchTitle }
    $url = 'https://itunes.apple.com/search?term=' + [uri]::EscapeDataString($term) + '&entity=album&limit=8'
    try {
        $result = Invoke-RestMethod -Uri $url -TimeoutSec 12
        $targetArtist = Get-NormalizedText $ArtistValue
        $targetRelease = Get-NormalizedText $searchTitle
        $targetTitle = Get-NormalizedText $TitleValue
        $best = @($result.results) |
            Where-Object { $_.artworkUrl100 -and $_.collectionName } |
            Sort-Object @{ Expression = {
                $score = 0
                $artistName = Get-NormalizedText ([string]$_.artistName)
                $collectionName = Get-NormalizedText ([string]$_.collectionName)
                if ($targetArtist -and $artistName -eq $targetArtist) { $score += 300 }
                elseif ($targetArtist -and $artistName -match [regex]::Escape($targetArtist)) { $score += 120 }
                elseif ($targetArtist) { $score -= 300 }
                if ($targetRelease -and $collectionName -eq $targetRelease) { $score += 300 }
                elseif ($targetRelease -and $collectionName -match [regex]::Escape($targetRelease)) { $score += 140 }
                elseif ($targetTitle -and $collectionName -match [regex]::Escape($targetTitle)) { $score += 80 }
                if ($collectionName -match '\bsingle\b') { $score -= 120 }
                $score
            }; Descending = $true } |
            Select-Object -First 1
        if ($best -and $best.artworkUrl100) {
            return ([string]$best.artworkUrl100) -replace '/\d+x\d+bb\.', '/1000x1000bb.'
        }
    }
    catch {
    }
    return ''
}

function Try-DownloadAppleArtwork {
    param([string]$ArtistValue, [string]$ReleaseTitleValue, [string]$TitleValue, [string]$OutputPath)

    $artworkUrl = Get-AppleArtworkUrl -ArtistValue $ArtistValue -ReleaseTitleValue $ReleaseTitleValue -TitleValue $TitleValue
    if ([string]::IsNullOrWhiteSpace($artworkUrl)) { return $false }
    try {
        Invoke-WebRequest -Uri $artworkUrl -OutFile $OutputPath -TimeoutSec 20 -MaximumRedirection 5 -UseBasicParsing | Out-Null
        if ((Test-Path -LiteralPath $OutputPath) -and ((Get-Item -LiteralPath $OutputPath).Length -gt 0) -and (Test-ImageFile -Path $OutputPath)) { return $true }
    }
    catch {
    }
    if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue }
    return $false
}

function Get-ReleaseGroupId {
    param([string]$ReleaseId)
    if ([string]::IsNullOrWhiteSpace($ReleaseId)) { return '' }
    try {
        $url = 'https://musicbrainz.org/ws/2/release/' + $ReleaseId + '?inc=release-groups&fmt=json'
        $release = Invoke-MusicBrainzJson -Url $url
        if ($release.'release-group'.id) { return [string]$release.'release-group'.id }
    }
    catch {
    }
    return ''
}

$queryParts = Get-AlbumQueryParts -ArtistValue $Artist -TitleValue $Title
$Artist = $queryParts['Artist']
$Title = $queryParts['Title']
if (([string]::IsNullOrWhiteSpace($Title) -and [string]::IsNullOrWhiteSpace($ReleaseMbid)) -or [string]::IsNullOrWhiteSpace($CacheDir)) { return }

New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
$cachePrefix = if (Test-KnownArtist $Artist) { $Artist } else { 'unknown_artist' }
$cacheKeySource = if (-not [string]::IsNullOrWhiteSpace($ReleaseMbid)) { $LookupMode + ' - release-v5 - ' + $ReleaseMbid } else { $LookupMode + ' - title-v3 - ' + $cachePrefix + ' - ' + $Title + ' - ' + $ReleaseTitle }
$cacheKey = Get-SafeCacheName $cacheKeySource
$coverPath = Join-Path $CacheDir ($cacheKey + '.jpg')
$missPath = Join-Path $CacheDir ($cacheKey + '.miss')

if (Test-Path -LiteralPath $coverPath) {
    if (Test-ImageFile -Path $coverPath) {
        Write-Output $coverPath
        return
    }
    Remove-Item -LiteralPath $coverPath -Force -ErrorAction SilentlyContinue
}
if (Test-Path -LiteralPath $missPath) { return }

if (-not [string]::IsNullOrWhiteSpace($ReleaseMbid)) {
    if (Try-DownloadCover -ReleaseId $ReleaseMbid -OutputPath $coverPath) {
        Write-Output $coverPath
        return
    }
    $releaseGroupId = Get-ReleaseGroupId -ReleaseId $ReleaseMbid
    if (Try-DownloadReleaseGroupCover -ReleaseGroupId $releaseGroupId -OutputPath $coverPath) {
        Write-Output $coverPath
        return
    }
    if (Try-DownloadAppleArtwork -ArtistValue $Artist -ReleaseTitleValue $ReleaseTitle -TitleValue $Title -OutputPath $coverPath) {
        Write-Output $coverPath
        return
    }
}

$safeTitle = $Title.Replace('"','')
if (Test-KnownArtist $Artist) {
    $query = 'artist:"' + $Artist.Replace('"','') + '" AND recording:"' + $safeTitle + '"'
}
else {
    $query = 'recording:"' + $safeTitle + '"'
}
$url = 'https://musicbrainz.org/ws/2/recording/?query=' + [uri]::EscapeDataString($query) + '&fmt=json&limit=8'

try {
    $result = Invoke-MusicBrainzJson -Url $url
    $releaseIds = New-Object System.Collections.Generic.List[string]
    foreach ($recording in @($result.recordings)) {
        foreach ($release in @($recording.releases)) {
            if ($release.id -and -not $releaseIds.Contains([string]$release.id)) {
                $releaseIds.Add([string]$release.id)
            }
        }
    }

    foreach ($releaseId in $releaseIds) {
        if (Try-DownloadCover -ReleaseId $releaseId -OutputPath $coverPath) {
            Write-Output $coverPath
            return
        }
        Start-Sleep -Milliseconds 250
    }
}
catch {
}

if (Try-DownloadAppleArtwork -ArtistValue $Artist -ReleaseTitleValue $ReleaseTitle -TitleValue $Title -OutputPath $coverPath) {
    Write-Output $coverPath
    return
}

Set-Content -LiteralPath $missPath -Value ((Get-Date).ToString('s')) -Encoding ASCII
