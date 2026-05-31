param(
    [string]$Artist = '',
    [string]$Title = '',
    [string]$CacheDir = '',
    [string]$ReleaseMbid = ''
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
    $headers = @{ 'User-Agent' = 'JukeboxDownloadWizard/0.2.2.2 ( https://musicbrainz.org/ )' }
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

$queryParts = Get-AlbumQueryParts -ArtistValue $Artist -TitleValue $Title
$Artist = $queryParts['Artist']
$Title = $queryParts['Title']
if (([string]::IsNullOrWhiteSpace($Title) -and [string]::IsNullOrWhiteSpace($ReleaseMbid)) -or [string]::IsNullOrWhiteSpace($CacheDir)) { return }

New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
$cachePrefix = if (Test-KnownArtist $Artist) { $Artist } else { 'unknown_artist' }
$cacheKeySource = if (-not [string]::IsNullOrWhiteSpace($ReleaseMbid)) { 'release - ' + $ReleaseMbid } else { $cachePrefix + ' - ' + $Title }
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

Set-Content -LiteralPath $missPath -Value ((Get-Date).ToString('s')) -Encoding ASCII
