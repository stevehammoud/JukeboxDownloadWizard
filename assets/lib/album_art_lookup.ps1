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

function Repair-SearchText {
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
    return $Value.Trim()
}

function Get-AlbumQueryParts {
    param([string]$ArtistValue, [string]$TitleValue)

    $resolvedArtist = if ($null -eq $ArtistValue) { '' } else { Repair-SearchText $ArtistValue }
    $resolvedTitle = if ($null -eq $TitleValue) { '' } else { Repair-SearchText $TitleValue }

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
    if ($resolvedArtist -match '(?i)^\s*(A\s*\$?\s*AP|ASAP)\s+ROCKY\s*$') { $resolvedArtist = 'A$AP Rocky' }
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
    $text = (Repair-SearchText $Value).Normalize('FormD') -replace '\p{Mn}', ''
    $text = $text.ToLowerInvariant()
    $text = $text -replace '\bac\s*/?\s*dc\b', 'acdc'
    $text = $text -replace '\b(ft|feat|featuring|with|and|y|con|x)\b', ' '
    $text = $text -replace '[^\p{L}\p{Nd}]+', ' '
    $text = $text -replace '\ba\s+ap\b', 'asap'
    $text = $text -replace '\s+', ' '
    return $text.Trim()
}

function Test-NormalizedContains {
    param([string]$Value, [string]$Needle)
    if ([string]::IsNullOrWhiteSpace($Value) -or [string]::IsNullOrWhiteSpace($Needle)) { return $false }
    return ($Value -match ('(^| )' + [regex]::Escape($Needle) + '( |$)'))
}

function Get-ArtistCreditText {
    param($Recording)
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($credit in @($Recording.'artist-credit')) {
        if ($credit.name) { $names.Add([string]$credit.name) }
        elseif ($credit.artist.name) { $names.Add([string]$credit.artist.name) }
    }
    return (($names | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' & ')
}

function Test-RecordingCompatible {
    param($Recording, [string]$ArtistValue, [string]$TitleValue)
    if (-not $Recording -or [string]::IsNullOrWhiteSpace([string]$Recording.title)) { return $false }

    $targetTitle = Get-NormalizedText $TitleValue
    $recordingTitle = Get-NormalizedText ([string]$Recording.title)
    if ([string]::IsNullOrWhiteSpace($targetTitle) -or [string]::IsNullOrWhiteSpace($recordingTitle)) { return $false }
    $titleOk = ($recordingTitle -eq $targetTitle -or (Test-NormalizedContains $recordingTitle $targetTitle) -or (Test-NormalizedContains $targetTitle $recordingTitle))
    if (-not $titleOk) { return $false }

    if (-not (Test-KnownArtist $ArtistValue)) { return $true }
    $targetArtist = Get-NormalizedText $ArtistValue
    $artistCredit = Get-NormalizedText (Get-ArtistCreditText -Recording $Recording)
    if ([string]::IsNullOrWhiteSpace($targetArtist) -or [string]::IsNullOrWhiteSpace($artistCredit)) { return $false }
    return ($artistCredit -eq $targetArtist -or (Test-NormalizedContains $artistCredit $targetArtist) -or (Test-NormalizedContains $targetArtist $artistCredit))
}

function Test-PlaylistLikeTitle {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value -match '(?i)\b(playlist|hits|collection|collector|best\s+of|greatest\s+hits|number\s+ones|essential|ultimate|anthology|singles|various\s+artists|now\s+that''?s\s+what\s+i\s+call|karaoke|tribute|cover|workout|party|chill|mix|mega-?mix|live|anniversary|deluxe|expanded|edition)\b')
}

function Get-ReleaseFallbackScore {
    param($Recording, $Release, [string]$TitleValue, [string]$ReleaseTitleValue)
    if (-not $Release -or [string]::IsNullOrWhiteSpace([string]$Release.id)) { return -9999 }
    if (Test-PlaylistLikeTitle ([string]$Release.title)) { return -9999 }
    if ($Release.'release-group' -and (Test-PlaylistLikeTitle ([string]$Release.'release-group'.title))) { return -9999 }

    $score = 0
    $releaseName = Get-NormalizedText ([string]$Release.title)
    $groupName = if ($Release.'release-group') { Get-NormalizedText ([string]$Release.'release-group'.title) } else { '' }
    $titleName = Get-NormalizedText $TitleValue
    $preferredName = if (-not [string]::IsNullOrWhiteSpace($ReleaseTitleValue)) { Get-NormalizedText $ReleaseTitleValue } else { $titleName }

    foreach ($candidateName in @($releaseName, $groupName)) {
        if ([string]::IsNullOrWhiteSpace($candidateName)) { continue }
        if ($preferredName -and $candidateName -eq $preferredName) { $score += 260 }
        elseif ($preferredName -and (Test-NormalizedContains $candidateName $preferredName)) { $score += 150 }
        elseif ($titleName -and $candidateName -eq $titleName) { $score += 180 }
        elseif ($titleName -and (Test-NormalizedContains $candidateName $titleName)) { $score += 90 }
    }
    if ([string]$Release.status -ieq 'Official') { $score += 40 }
    switch ([string]$Release.country) {
        'US' { $score += 35; break }
        'XW' { $score += 25; break }
        'GB' { $score += 18; break }
    }
    if ([string]$Release.date -match '^\d{4}(-\d{2})?(-\d{2})?$') { $score += 15 }
    return $score
}

function Get-AppleArtworkUrl {
    param([string]$ArtistValue, [string]$ReleaseTitleValue, [string]$TitleValue)

    $searchTitle = if (-not [string]::IsNullOrWhiteSpace($ReleaseTitleValue)) { Repair-SearchText $ReleaseTitleValue } else { Repair-SearchText $TitleValue }
    if ([string]::IsNullOrWhiteSpace($searchTitle)) { return '' }

    $artistTerm = Repair-SearchText $ArtistValue
    $term = if (Test-KnownArtist $artistTerm) { ($artistTerm + ' ' + $searchTitle) } else { $searchTitle }
    $url = 'https://itunes.apple.com/search?term=' + [uri]::EscapeDataString($term) + '&entity=album&limit=8'
    try {
        $result = Invoke-RestMethod -Uri $url -TimeoutSec 12
        $targetArtist = Get-NormalizedText $ArtistValue
        $targetRelease = Get-NormalizedText $searchTitle
        $targetTitle = Get-NormalizedText $TitleValue
        $best = @($result.results) |
            Where-Object { $_.artworkUrl100 -and $_.collectionName } |
            ForEach-Object {
                $artistName = Get-NormalizedText ([string]$_.artistName)
                $collectionName = Get-NormalizedText ([string]$_.collectionName)
                $artistOk = (-not $targetArtist) -or ($artistName -eq $targetArtist) -or (Test-NormalizedContains $artistName $targetArtist) -or (Test-NormalizedContains $targetArtist $artistName)
                $releaseOk = $false
                if ($targetRelease -and ($collectionName -eq $targetRelease -or (Test-NormalizedContains $collectionName $targetRelease) -or (Test-NormalizedContains $targetRelease $collectionName))) { $releaseOk = $true }
                if ($targetTitle -and ($collectionName -eq $targetTitle -or (Test-NormalizedContains $collectionName $targetTitle) -or (Test-NormalizedContains $targetTitle $collectionName))) { $releaseOk = $true }
                if ($artistOk -and $releaseOk) { $_ }
            } |
            Sort-Object @{ Expression = {
                $score = 0
                $artistName = Get-NormalizedText ([string]$_.artistName)
                $collectionName = Get-NormalizedText ([string]$_.collectionName)
                if ($targetArtist -and $artistName -eq $targetArtist) { $score += 300 }
                elseif ($targetArtist -and (Test-NormalizedContains $artistName $targetArtist)) { $score += 120 }
                elseif ($targetArtist) { $score -= 300 }
                if ($targetRelease -and $collectionName -eq $targetRelease) { $score += 300 }
                elseif ($targetRelease -and (Test-NormalizedContains $collectionName $targetRelease)) { $score += 140 }
                elseif ($targetTitle -and (Test-NormalizedContains $collectionName $targetTitle)) { $score += 80 }
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
$cacheKeySource = if (-not [string]::IsNullOrWhiteSpace($ReleaseMbid)) { $LookupMode + ' - release-v8 - ' + $ReleaseMbid } else { $LookupMode + ' - title-v6 - ' + $cachePrefix + ' - ' + $Title + ' - ' + $ReleaseTitle }
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
    $releaseIds = @($result.recordings |
        Where-Object { Test-RecordingCompatible -Recording $_ -ArtistValue $Artist -TitleValue $Title } |
        ForEach-Object {
            $recording = $_
            foreach ($release in @($recording.releases)) {
                $score = Get-ReleaseFallbackScore -Recording $recording -Release $release -TitleValue $Title -ReleaseTitleValue $ReleaseTitle
                if ($release.id -and $score -ge 80) {
                    [pscustomobject]@{ Id = [string]$release.id; Score = $score }
                }
            }
        } |
        Sort-Object @{ Expression = { $_.Score }; Descending = $true } |
        Select-Object -ExpandProperty Id -Unique)

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

