param(
    [string]$Artist = '',
    [string]$Title = '',
    [string]$CacheDir = ''
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding

function Get-SafeCacheName {
    param([string]$Value)
    $safe = $Value.ToLowerInvariant()
    $safe = $safe -replace '[^a-z0-9]+', '_'
    $safe = $safe.Trim('_')
    if ($safe.Length -gt 120) { $safe = $safe.Substring(0, 120).Trim('_') }
    if ($safe.Length -eq 0) { $safe = [Guid]::NewGuid().ToString('N') }
    return $safe
}

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
function Test-KnownArtist {
    param([string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value.Trim() -ine 'UNKNOWN ARTIST')
}

function Remove-TitleNoise {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $noiseWords = 'official\s+music\s+video|official\s+video|official\s+audio|official\s+lyric\s+video|lyric\s+video|lyrics?|visuali[sz]er|music\s+video|audio|hd|4k|remaster(?:ed)?|karaoke|unreleased\s+video|new\s+unreleased\s+video|new\s+video|video'
    $clean = Repair-TextEncoding $Value
    $clean = $clean -replace ('(?i)\s*[\[\(\{][^\]\)\}]*\b(' + $noiseWords + ')\b[^\]\)\}]*[\]\)\}]'), ''
    $clean = $clean -replace ('(?i)\s*[\[\(\{][^\]\)\}]*\b(ft\.?|feat\.?|featuring)\b[^\]\)\}]*[\]\)\}]'), ''
    $clean = $clean -replace ('(?i)\s*[\[\(\{][^\]\)\}]*\b(' + $noiseWords + '|ft\.?|feat\.?|featuring)\b[^\]\)\}]*$'), ''
    $clean = $clean -replace '(?i)\s+\b(ft\.?|feat\.?|featuring)\b\.?\s+.*$', ''
    $clean = $clean -replace ('(?i)\s+[-|:]\s*(' + $noiseWords + ')\b.*$'), ''
    $clean = $clean -replace ('(?i)\b(' + $noiseWords + ')\b'), ''
    $clean = $clean -replace '\s+', ' '
    return $clean.Trim(' ', '-', '|', ':', '.', '_')
}

function Get-QueryParts {
    param([string]$ArtistValue, [string]$TitleValue)

    $resolvedArtist = if ($null -eq $ArtistValue) { '' } else { $ArtistValue.Trim() }
    $resolvedTitle = if ($null -eq $TitleValue) { '' } else { Remove-TitleNoise $TitleValue.Trim() }

    if ((-not (Test-KnownArtist $resolvedArtist)) -and $resolvedTitle -match '^\s*(?<artist>[^-|:]+?)\s+[-|:]\s+(?<title>.+?)\s*$') {
        $resolvedArtist = $Matches['artist'].Trim()
        $resolvedTitle = Remove-TitleNoise $Matches['title'].Trim()
    }

    return @{ Artist = $resolvedArtist; Title = $resolvedTitle }
}

function Get-ArtistCreditName {
    param($Recording)
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($credit in @($Recording.'artist-credit')) {
        if ($credit.name) { $names.Add([string]$credit.name) }
        elseif ($credit.artist.name) { $names.Add([string]$credit.artist.name) }
    }
    return (Repair-TextEncoding (($names | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' & '))
}

function Get-PrimaryArtistName {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $primary = $Value
    $primary = $primary -replace '(?i)\s+(\(|\[)?\s*(ft\.?|feat\.?|featuring|with)\s+.*$', ''
    $primary = $primary -replace '(?i)\s+&\s+.*$', ''
    $primary = $primary -replace '(?i)\s+x\s+.*$', ''
    $primary = $primary.Trim(' ', '-', '|', ':', '.', '_', '(', '[', ')', ']')
    return $primary
}

function Get-FirstArtistMbid {
    param($Recording)
    foreach ($credit in @($Recording.'artist-credit')) {
        if ($credit.artist.id) { return [string]$credit.artist.id }
    }
    return ''
}

function Find-ArtistMbidByName {
    param([string]$Name, [hashtable]$Headers)
    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    try {
        $query = 'artist:"' + $Name.Replace('"','') + '"'
        $url = 'https://musicbrainz.org/ws/2/artist/?query=' + [uri]::EscapeDataString($query) + '&fmt=json&limit=8'
        $result = Invoke-RestMethod -Uri $url -Headers $Headers -TimeoutSec 12
        $artist = @($result.artists) |
            Sort-Object @{ Expression = {
                $score = [int]($_.score -as [int])
                if ([string]$_.name -ieq $Name) { $score += 100 }
                if ([string]$_.type -ieq 'Group') { $score += 20 }
                $score
            }; Descending = $true } |
            Select-Object -First 1
        if ($artist.id) { return [string]$artist.id }
    }
    catch {
    }
    return ''
}

function Get-PreferredArtistMbid {
    param($Recording, [hashtable]$Headers)
    $artistCredit = Get-ArtistCreditName -Recording $Recording
    $firstMbid = Get-FirstArtistMbid -Recording $Recording
    if ($artistCredit -match '\s&\s|\sx\s|,') {
        $groupMbid = Find-ArtistMbidByName -Name $artistCredit -Headers $Headers
        if (-not [string]::IsNullOrWhiteSpace($groupMbid)) { return $groupMbid }
    }
    return $firstMbid
}

function Get-ReleaseDateSortValue {
    param($Release)
    $date = [string]$Release.date
    if ($date -match '^\d{4}(-\d{2})?(-\d{2})?$') { return $date }
    return '9999-99-99'
}

function Test-PlaylistLikeTitle {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value -match '(?i)\b(playlist|hits|collection|collector|best\s+of|greatest\s+hits|various\s+artists|now\s+that''?s\s+what\s+i\s+call|karaoke|tribute|cover|workout|party|chill|mix|live|anniversary|deluxe|expanded|edition)\b')
}

function Get-ReleaseScore {
    param($Release, $Recording)

    $score = 0
    $status = [string]$Release.status
    $title = [string]$Release.title
    $recordingTitle = [string]$Recording.title
    $group = $Release.'release-group'
    $primaryType = [string]$group.'primary-type'
    $secondaryTypes = @($group.'secondary-types')
    $disambiguation = [string]$Release.disambiguation

    if ($status -ieq 'Official') { $score += 300 }
    elseif (-not [string]::IsNullOrWhiteSpace($status)) { $score += 20 }

    switch -Regex ($primaryType) {
        '^(Single)$' { $score += 260; break }
        '^(Album)$' { $score += 230; break }
        '^(EP)$' { $score += 200; break }
        default { $score += 20; break }
    }

    foreach ($secondaryType in $secondaryTypes) {
        if ([string]$secondaryType -match '(?i)Compilation|Soundtrack|Live|DJ-mix|Mixtape/Street') { $score -= 350 }
    }

    if (Test-PlaylistLikeTitle $title) { $score -= 450 }
    if (Test-PlaylistLikeTitle ([string]$group.title)) { $score -= 450 }
    if (Test-PlaylistLikeTitle $disambiguation) { $score -= 250 }
    if ($title -ieq $recordingTitle) { $score += 90 }
    elseif ($title -match ('(?i)^' + [regex]::Escape($recordingTitle) + '\s*[\(\[]')) { $score += 70 }
    elseif ($primaryType -ieq 'Single' -and $title -match ('(?i)' + [regex]::Escape($recordingTitle))) { $score += 45 }
    if ([string]$Release.date -match '^\d{4}(-\d{2})?(-\d{2})?$') { $score += 60 }
    else { $score -= 25 }
    if ($Release.'track-count' -and [int]$Release.'track-count' -le 6) { $score += 35 }
    if ($Release.'track-count' -and [int]$Release.'track-count' -gt 40) { $score -= 40 }

    foreach ($medium in @($Release.media)) {
        foreach ($track in @($medium.track)) {
            if ([string]$track.title -ieq $recordingTitle) { $score += 40 }
            if ([string]$track.number -match '^(1|A1)$') { $score += 10 }
        }
    }

    return $score
}

function Select-BestRelease {
    param($Recording)

    return @($Recording.releases) |
        Sort-Object `
            @{ Expression = { Get-ReleaseScore -Release $_ -Recording $Recording }; Descending = $true },
            @{ Expression = { Get-ReleaseDateSortValue -Release $_ } } |
        Select-Object -First 1
}

function Test-WeakCoverRelease {
    param($Release)
    if (-not $Release) { return $true }
    $group = $Release.'release-group'
    if (Test-PlaylistLikeTitle ([string]$Release.title)) { return $true }
    if (Test-PlaylistLikeTitle ([string]$group.title)) { return $true }
    if (Test-PlaylistLikeTitle ([string]$Release.disambiguation)) { return $true }
    foreach ($secondaryType in @($group.'secondary-types')) {
        if ([string]$secondaryType -match '(?i)Compilation|Soundtrack|Live|DJ-mix|Mixtape/Street') { return $true }
    }
    return $false
}

function Get-ReleaseFromReleaseGroup {
    param($ReleaseGroup, [hashtable]$Headers)
    if (-not $ReleaseGroup -or [string]::IsNullOrWhiteSpace([string]$ReleaseGroup.id)) { return $null }
    try {
        $url = 'https://musicbrainz.org/ws/2/release?release-group=' + [uri]::EscapeDataString([string]$ReleaseGroup.id) + '&fmt=json&limit=12'
        $result = Invoke-RestMethod -Uri $url -Headers $Headers -TimeoutSec 12
        return @($result.releases) |
            Where-Object { $_.id -and ([string]$_.status -ieq 'Official') } |
            Sort-Object `
                @{ Expression = { if ([string]$_.date -match '^\d{4}(-\d{2})?(-\d{2})?$') { 0 } else { 1 } } },
                @{ Expression = {
                    switch ([string]$_.country) {
                        'US' { 0; break }
                        'XW' { 1; break }
                        'GB' { 2; break }
                        default { 3; break }
                    }
                } },
                @{ Expression = { [string]$_.date } } |
            Select-Object -First 1
    }
    catch {
    }
    return $null
}

function Find-DirectCoverRelease {
    param([string]$ArtistValue, [string]$TitleValue, [hashtable]$Headers)
    if ([string]::IsNullOrWhiteSpace($TitleValue)) { return $null }

    $queries = New-Object System.Collections.Generic.List[string]
    if (Test-KnownArtist $ArtistValue) {
        $queries.Add('artist:"' + $ArtistValue.Replace('"','') + '" AND release:"' + $TitleValue.Replace('"','') + '"')
        $primaryArtist = Get-PrimaryArtistName -Value $ArtistValue
        if ((Test-KnownArtist $primaryArtist) -and ($primaryArtist -ine $ArtistValue)) {
            $queries.Add('artist:"' + $primaryArtist.Replace('"','') + '" AND release:"' + $TitleValue.Replace('"','') + '"')
        }
    }
    $queries.Add('release:"' + $TitleValue.Replace('"','') + '"')

    foreach ($query in $queries) {
        try {
            $url = 'https://musicbrainz.org/ws/2/release-group/?query=' + [uri]::EscapeDataString($query) + '&fmt=json&limit=12'
            $result = Invoke-RestMethod -Uri $url -Headers $Headers -TimeoutSec 12
            $group = @($result.'release-groups') |
                Where-Object { $_.id -and $_.title -and -not (Test-PlaylistLikeTitle ([string]$_.title)) } |
                Sort-Object @{ Expression = {
                    $score = [int]($_.score -as [int])
                    $groupArtist = Get-ArtistCreditName -Recording $_
                    if (Test-KnownArtist $ArtistValue) {
                        if ($groupArtist -ieq $ArtistValue) { $score += 180 }
                        elseif ($groupArtist -match ('(?i)' + [regex]::Escape($ArtistValue))) { $score += 45 }
                        else { $score -= 500 }
                    }
                    if ([string]$_.title -ieq $TitleValue) { $score += 260 }
                    elseif ([string]$_.title -match ('(?i)^' + [regex]::Escape($TitleValue) + '\s*[\(\[]')) { $score += 180 }
                    elseif ([string]$_.title -match ('(?i)' + [regex]::Escape($TitleValue))) { $score += 70 }
                    switch -Regex ([string]$_.'primary-type') {
                        '^(Single)$' { $score += 240; break }
                        '^(Album)$' { $score += 160; break }
                        '^(EP)$' { $score += 120; break }
                    }
                    foreach ($secondaryType in @($_.'secondary-types')) {
                        if ([string]$secondaryType -match '(?i)Compilation|Soundtrack|Live|DJ-mix|Mixtape/Street|Remix') { $score -= 350 }
                    }
                    if ([string]$_.'first-release-date' -match '^\d{4}(-\d{2})?(-\d{2})?$') { $score += 35 }
                    $score
                }; Descending = $true } |
                Select-Object -First 1
            $release = Get-ReleaseFromReleaseGroup -ReleaseGroup $group -Headers $Headers
            if ($release) {
                return [pscustomobject]@{
                    id = [string]$release.id
                    title = Repair-TextEncoding ([string]$release.title)
                    date = [string]$release.date
                }
            }
        }
        catch {
        }
    }

    return $null
}

function Write-MetadataResult {
    param($Recording, [hashtable]$Headers, [string]$ArtistValue, [string]$TitleValue)

    $release = Select-BestRelease -Recording $Recording
    $directRelease = $null
    if (Test-WeakCoverRelease -Release $release) {
        $directRelease = Find-DirectCoverRelease -ArtistValue $ArtistValue -TitleValue $TitleValue -Headers $Headers
    }
    $result = [ordered]@{
        Artist = Get-ArtistCreditName -Recording $Recording
        Title = Repair-TextEncoding ([string]$Recording.title)
        ReleaseTitle = ''
        ReleaseDate = ''
        ReleaseMbid = ''
        ArtistMbid = Get-PreferredArtistMbid -Recording $Recording -Headers $Headers
        RecordingMbid = [string]$Recording.id
    }
    if ($release) {
        $result.ReleaseTitle = Repair-TextEncoding ([string]$release.title)
        $result.ReleaseDate = [string]$release.date
        $result.ReleaseMbid = [string]$release.id
    }
    if ($directRelease) {
        $result.ReleaseTitle = [string]$directRelease.title
        $result.ReleaseDate = [string]$directRelease.date
        $result.ReleaseMbid = [string]$directRelease.id
    }
    $result | ConvertTo-Json -Depth 5 -Compress
}

function Get-RecordingScore {
    param($Recording, [string]$ArtistValue, [string]$TitleValue)

    $score = 0
    $recordingTitle = ([string]$Recording.title).Trim()
    if ($recordingTitle -ieq $TitleValue.Trim()) { $score += 200 }
    elseif ($recordingTitle -match ('(?i)^' + [regex]::Escape($TitleValue.Trim()) + '\s*[\(\[]')) { $score += 50 }
    elseif ($recordingTitle -match ('(?i)' + [regex]::Escape($TitleValue.Trim()))) { $score += 20 }

    $variantWords = 'instrumental|acoustic|karaoke|tribute|cover|remix|live|sped\s+up|slowed|nightcore|making\s+of|behind\s+the\s+scenes|interview|commentary'
    if (($recordingTitle -match ('(?i)\b(' + $variantWords + ')\b')) -and ($TitleValue -notmatch ('(?i)\b(' + $variantWords + ')\b'))) {
        $score -= 500
    }

    $artistCredit = Get-ArtistCreditName -Recording $Recording
    $primaryArtist = Get-PrimaryArtistName -Value $ArtistValue
    if (Test-KnownArtist $ArtistValue) {
        if ($artistCredit -ieq $ArtistValue) { $score += 160 }
        elseif ($artistCredit -match ('(?i)' + [regex]::Escape($ArtistValue))) { $score += 40 }
        else { $score -= 300 }
    }
    if (Test-KnownArtist $primaryArtist) {
        if ($artistCredit -ieq $primaryArtist) { $score += 140 }
        elseif ($artistCredit -match ('(?i)' + [regex]::Escape($primaryArtist))) { $score += 35 }
        else { $score -= 500 }
    }
    $requestedHasCollab = ($ArtistValue -match '(?i)\b(ft\.?|feat\.?|featuring|with)\b|&|\sx\s')
    if (-not $requestedHasCollab -and $artistCredit -match '\s&\s') { $score -= 90 }
    if (@($Recording.releases).Count -gt 0) { $score += 10 }
    if (@($Recording.releases).Count -gt 0) {
        $bestReleaseScore = @($Recording.releases | ForEach-Object { Get-ReleaseScore -Release $_ -Recording $Recording } | Sort-Object -Descending | Select-Object -First 1)
        if ($bestReleaseScore.Count -gt 0) { $score += [int]([double]$bestReleaseScore[0] / 3.0) }
    }
    if ([string]$Recording.'first-release-date' -match '^\d{4}(-\d{2})?(-\d{2})?$') { $score += 35 }
    if (@($Recording.releases | Where-Object { [string]$_.date -match '^\d{4}(-\d{2})?(-\d{2})?$' }).Count -gt 0) { $score += 25 }
    else { $score -= 30 }
    if ([string]$Recording.disambiguation -match '(?i)\b(live|karaoke|tribute|cover|remix|acoustic|instrumental)\b') { $score -= 260 }
    if (@($Recording.releases | Where-Object { -not (Test-PlaylistLikeTitle ([string]$_.title)) -and -not (Test-PlaylistLikeTitle ([string]$_.'release-group'.title)) }).Count -gt 0) { $score += 30 }

    return $score
}

function Find-Recording {
    param([string]$ArtistValue, [string]$TitleValue, [hashtable]$Headers)

    $safeTitle = $TitleValue.Replace('"','')
    $queries = New-Object System.Collections.Generic.List[string]
    if (Test-KnownArtist $ArtistValue) {
        $queries.Add('artist:"' + $ArtistValue.Replace('"','') + '" AND recording:"' + $safeTitle + '"')
        $primaryArtist = Get-PrimaryArtistName -Value $ArtistValue
        if ((Test-KnownArtist $primaryArtist) -and ($primaryArtist -ine $ArtistValue)) {
            $queries.Add('artist:"' + $primaryArtist.Replace('"','') + '" AND recording:"' + $safeTitle + '"')
        }
    }
    if (-not (Test-KnownArtist $ArtistValue)) {
        $queries.Add('recording:"' + $safeTitle + '"')
    }

    foreach ($query in $queries) {
        try {
            $url = 'https://musicbrainz.org/ws/2/recording/?query=' + [uri]::EscapeDataString($query) + '&fmt=json&limit=25'
            $result = Invoke-RestMethod -Uri $url -Headers $Headers -TimeoutSec 12
            $match = @($result.recordings) |
                Where-Object { $_.title } |
                ForEach-Object {
                    [pscustomobject]@{
                        Recording = $_
                        Score = Get-RecordingScore -Recording $_ -ArtistValue $ArtistValue -TitleValue $TitleValue
                    }
                } |
                Sort-Object @{ Expression = { $_.Score }; Descending = $true } |
                Select-Object -First 1
            if ($match) {
                $minimumScore = if (Test-KnownArtist $ArtistValue) { 140 } else { 90 }
                if ([int]$match.Score -ge $minimumScore) { return $match.Recording }
            }
            Start-Sleep -Milliseconds 250
        }
        catch {
        }
    }

    return $null
}

$queryParts = Get-QueryParts -ArtistValue $Artist -TitleValue $Title
$Artist = $queryParts['Artist']
$Title = $queryParts['Title']
if ([string]::IsNullOrWhiteSpace($Title) -or [string]::IsNullOrWhiteSpace($CacheDir)) { return }

New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
$cachePrefix = if (Test-KnownArtist $Artist) { $Artist } else { 'unknown_artist' }
$cacheKey = Get-SafeCacheName ('v17 - ' + $cachePrefix + ' - ' + $Title)
$cachePath = Join-Path $CacheDir ($cacheKey + '.metadata.json')
$missPath = Join-Path $CacheDir ($cacheKey + '.metadata.miss')

if (Test-Path -LiteralPath $cachePath) {
    Get-Content -LiteralPath $cachePath -Raw
    return
}
if (Test-Path -LiteralPath $missPath) { return }

$headers = @{ 'User-Agent' = 'JukeboxDownloadWizard/0.2.2.2 ( https://musicbrainz.org/ )' }

try {
    $recording = Find-Recording -ArtistValue $Artist -TitleValue $Title -Headers $headers
    if ($recording) {
        $json = Write-MetadataResult -Recording $recording -Headers $headers -ArtistValue $Artist -TitleValue $Title
        Set-Content -LiteralPath $cachePath -Value $json -Encoding UTF8
        Write-Output $json
        return
    }
}
catch {
}

Set-Content -LiteralPath $missPath -Value ((Get-Date).ToString('s')) -Encoding ASCII
