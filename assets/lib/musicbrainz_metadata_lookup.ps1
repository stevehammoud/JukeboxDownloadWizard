param(
    [string]$Artist = '',
    [string]$Title = '',
    [string]$ReleaseTitle = '',
    [string]$ReleaseYear = '',
    [string]$CacheDir = '',
    [ValidateSet('standard', 'curated')]
    [string]$LookupMode = 'standard'
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

function Get-FoldedText {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $text = (Repair-TextEncoding $Value).Normalize('FormD') -replace '\p{Mn}', ''
    $text = $text.ToLowerInvariant()
    $text = $text -replace '\bac\s*/?\s*dc\b', 'acdc'
    $text = $text -replace '\b(ft|feat|featuring|with|and|y|con|x)\b', ' '
    $text = $text -replace '[^\p{L}\p{Nd}]+', ' '
    $text = $text -replace '\ba\s+ap\b', 'asap'
    return (($text -replace '\s+', ' ').Trim())
}

function Test-TextEquivalent {
    param([string]$Left, [string]$Right)
    $a = Get-FoldedText $Left
    $b = Get-FoldedText $Right
    return (-not [string]::IsNullOrWhiteSpace($a) -and $a -eq $b)
}

function Remove-TitleNoise {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $noiseWords = 'official\s+music\s+video|official\s+video|official\s+audio|official\s+lyric\s+video|official|lyric\s+video|lyrics?|visuali[sz]er|music\s+video|audio|hd|hq|sd|4k|[0-9]{3,4}p|remaster(?:ed)?|karaoke|unreleased\s+video|new\s+unreleased\s+video|new\s+video'
    $versionWords = 'short(?:ened)?\s+version|complete\s+version|album\s+version|single\s+version|video\s+version|radio\s+edit|extended\s+version|colori[sz]ed\s+version|one\s+take\s+version|dance\s+version|prism\s+album'
    $contextNoiseWords = $noiseWords + '|live\s+(?:at|from|in|on)\b.*|sub(?:titula[dd][ao]?|itula[dd][ao]?|titulos?)|espanol|ingles|legendado|traducao|translated|translation'
    $contextNoiseWords = $contextNoiseWords + '|' + $versionWords
    $clean = Repair-TextEncoding $Value
    $clean = $clean -replace '(?i)\s+\b(with|w/)\s+lyrics?\b.*$', ''
    $clean = $clean -replace ('(?i)\s*[\[\(\{][^\]\)\}]*\b(' + $versionWords + ')\b[^\]\)\}]*[\]\)\}]'), ''
    $clean = $clean -replace ('(?i)\s+[-|:]\s*(' + $versionWords + ')\b.*$'), ''
    $clean = $clean -replace '(?i)\s*[\[\(\{]\s*(tv|mv|hd|hq|sd|4k|[0-9]{3,4}p|live)\s*[\]\)\}]', ''
    $clean = $clean -replace ('(?i)\s*[\[\(\{][^\]\)\}]*\b(' + $contextNoiseWords + ')\b[^\]\)\}]*[\]\)\}]'), ''
    $clean = $clean -replace ('(?i)\s*[\[\(\{][^\]\)\}]*\b(ft\.?|feat\.?|featuring)\b[^\]\)\}]*[\]\)\}]'), ''
    $clean = $clean -replace ('(?i)\s*[\[\(\{][^\]\)\}]*\b(' + $contextNoiseWords + '|ft\.?|feat\.?|featuring)\b[^\]\)\}]*$'), ''
    $clean = $clean -replace '(?i)\s+\b(ft\.?|feat\.?|featuring)\b\.?\s+.*$', ''
    $clean = $clean -replace ('(?i)\s+[-|:]\s*(' + $contextNoiseWords + ')\b.*$'), ''
    $clean = $clean -replace ('(?i)\s+\b(live\s+(?:at|from|in|on)\b.*)$'), ''
    $clean = $clean -replace ('(?i)\s+\b(' + $contextNoiseWords + ')\b.*$'), ''
    $clean = $clean -replace ('(?i)\b(' + $noiseWords + ')\b'), ''
    $clean = $clean -replace '\s+', ' '
    return $clean.Trim(' ', '-', '|', ':', '_')
}

function Get-QueryParts {
    param([string]$ArtistValue, [string]$TitleValue)

    $resolvedArtist = if ($null -eq $ArtistValue) { '' } else { (Repair-TextEncoding $ArtistValue).Trim() }
    $resolvedTitle = if ($null -eq $TitleValue) { '' } else { Remove-TitleNoise $TitleValue.Trim() }

    if ((-not (Test-KnownArtist $resolvedArtist)) -and $resolvedTitle -match '^\s*(?<artist>[^-|:]+?)\s+[-|:]\s+(?<title>.+?)\s*$') {
        $resolvedArtist = $Matches['artist'].Trim()
        $resolvedTitle = Remove-TitleNoise $Matches['title'].Trim()
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

function Get-ArtistCreditName {
    param($Recording)
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($credit in @($Recording.'artist-credit')) {
        if ($credit.name) { $names.Add([string]$credit.name) }
        elseif ($credit.artist.name) { $names.Add([string]$credit.artist.name) }
    }
    return (Repair-TextEncoding (($names | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' & '))
}

function Test-ArtistCompatible {
    param($Recording, [string]$ArtistValue)
    if (-not (Test-KnownArtist $ArtistValue)) { return $true }

    $artistCredit = Get-ArtistCreditName -Recording $Recording
    $primaryArtist = Get-PrimaryArtistName -Value $ArtistValue
    $foldedCredit = Get-FoldedText $artistCredit
    $foldedArtist = Get-FoldedText $ArtistValue
    $foldedPrimary = Get-FoldedText $primaryArtist

    if ([string]::IsNullOrWhiteSpace($foldedCredit)) { return $false }
    if (-not [string]::IsNullOrWhiteSpace($foldedArtist)) {
        if ($foldedCredit -eq $foldedArtist) { return $true }
        if ($foldedCredit -match ('(^| )' + [regex]::Escape($foldedArtist) + '( |$)')) { return $true }
        if ($foldedArtist -match ('(^| )' + [regex]::Escape($foldedCredit) + '( |$)')) { return $true }
    }
    if (-not [string]::IsNullOrWhiteSpace($foldedPrimary)) {
        if ($foldedCredit -eq $foldedPrimary) { return $true }
        if ($foldedCredit -match ('(^| )' + [regex]::Escape($foldedPrimary) + '( |$)')) { return $true }
    }
    return $false
}
function Get-PrimaryArtistName {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $primary = $Value
    $primary = $primary -replace '(?i)\s+(\(|\[)?\s*(ft\.?|feat\.?|featuring|with)\s+.*$', ''
    $primary = $primary -replace '\s*,\s+.*$', ''
    $primary = $primary -replace '(?i)\s+&\s+.*$', ''
    $primary = $primary -replace '(?i)\s+x\s+.*$', ''
    $primary = $primary -replace '(?i)\s+(y|con)\s+.*$', ''
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
                elseif (Test-TextEquivalent ([string]$_.name) $Name) { $score += 80 }
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
    return ($Value -match '(?i)\b(playlist|hits|collection|collector|best\s+of|greatest\s+hits|number\s+ones|essential|ultimate|anthology|singles|various\s+artists|now\s+that''?s\s+what\s+i\s+call|karaoke|tribute|cover|workout|party|chill|mix|mega-?mix|live|anniversary|deluxe|expanded|edition)\b')
}
function Test-VersionVariantTitle {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value -match '(?i)\b(remix|mix|live|acoustic|instrumental|karaoke|tribute|cover|version|edit|sped\s+up|slowed|nightcore)\b')
}

function Get-YearFromDate {
    param([string]$Value)
    if ($Value -match '^(?<year>(19|20)\d{2})') { return [int]$Matches['year'] }
    return $null
}

function Get-RecordingFirstYear {
    param($Recording)
    $year = Get-YearFromDate ([string]$Recording.'first-release-date')
    if ($null -ne $year) { return $year }
    $years = @($Recording.releases | ForEach-Object { Get-YearFromDate ([string]$_.date) } | Where-Object { $null -ne $_ } | Sort-Object)
    if ($years.Count -gt 0) { return [int]$years[0] }
    return $null
}

function Test-CompilationLikeRelease {
    param($Release)
    if (-not $Release) { return $false }
    $group = $Release.'release-group'
    if (Test-PlaylistLikeTitle ([string]$Release.title)) { return $true }
    if (Test-PlaylistLikeTitle ([string]$group.title)) { return $true }
    if (Test-PlaylistLikeTitle ([string]$Release.disambiguation)) { return $true }
    foreach ($secondaryType in @($group.'secondary-types')) {
        if ([string]$secondaryType -match '(?i)Compilation|Soundtrack|Live|DJ-mix|Mixtape/Street|Remix') { return $true }
    }
    return $false
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
    $releaseYear = Get-YearFromDate ([string]$Release.date)
    $recordingFirstYear = Get-RecordingFirstYear -Recording $Recording

    if ($status -ieq 'Official') { $score += 300 }
    elseif (-not [string]::IsNullOrWhiteSpace($status)) { $score += 20 }

    switch -Regex ($primaryType) {
        '^(Album)$' { $score += 390; break }
        '^(Single)$' { $score += 170; break }
        '^(EP)$' { $score += 200; break }
        default { $score += 20; break }
    }

    foreach ($secondaryType in $secondaryTypes) {
        if ([string]$secondaryType -match '(?i)Compilation|Soundtrack|Live|DJ-mix|Mixtape/Street|Remix') { $score -= 700 }
    }

    if (Test-PlaylistLikeTitle $title) { $score -= 450 }
    if (Test-PlaylistLikeTitle ([string]$group.title)) { $score -= 450 }
    if (Test-PlaylistLikeTitle $disambiguation) { $score -= 250 }
    if ((Test-VersionVariantTitle $title) -and -not (Test-VersionVariantTitle $recordingTitle)) { $score -= 340 }
    if ((Test-VersionVariantTitle ([string]$group.title)) -and -not (Test-VersionVariantTitle $recordingTitle)) { $score -= 340 }
    $releaseTitleMatchesRecording = $false
    if ($title -ieq $recordingTitle) { $score += 90; $releaseTitleMatchesRecording = $true }
    elseif ($title -match ('(?i)^' + [regex]::Escape($recordingTitle) + '\s*[\(\[]')) { $score += 70; $releaseTitleMatchesRecording = $true }
    elseif ($primaryType -ieq 'Single' -and $title -match ('(?i)' + [regex]::Escape($recordingTitle))) { $score += 45; $releaseTitleMatchesRecording = $true }
    if ($primaryType -ieq 'Single' -and -not $releaseTitleMatchesRecording) { $score -= 320 }
    if ([string]$Release.date -match '^\d{4}(-\d{2})?(-\d{2})?$') { $score += 60 }
    else { $score -= 25 }
    if (-not [string]::IsNullOrWhiteSpace($ReleaseYear) -and $null -ne $releaseYear) {
        $delta = [Math]::Abs($releaseYear - ([int]$ReleaseYear))
        if ($delta -eq 0) { $score += 520 }
        elseif ($delta -le 1) { $score += 140 }
        elseif ($delta -gt 8) { $score -= 520 }
        elseif ($delta -gt 3) { $score -= 260 }
    } elseif ($null -ne $releaseYear -and $null -ne $recordingFirstYear) {
        $deltaFromOriginal = $releaseYear - $recordingFirstYear
        if ($deltaFromOriginal -eq 0) { $score += 220 }
        elseif ($deltaFromOriginal -eq 1) { $score += 90 }
        elseif ($deltaFromOriginal -gt 2 -and $deltaFromOriginal -le 8) { $score -= 220 }
        elseif ($deltaFromOriginal -gt 8) { $score -= 520 }
        elseif ($deltaFromOriginal -lt -1) { $score -= 120 }
    }
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
    return (Test-CompilationLikeRelease -Release $Release)
}

function Test-LaterEraCoverRelease {
    param($Release, $Recording)
    if (-not $Release -or -not $Recording) { return $false }
    if (-not [string]::IsNullOrWhiteSpace($ReleaseYear)) { return $false }
    $releaseYear = Get-YearFromDate ([string]$Release.date)
    $recordingFirstYear = Get-RecordingFirstYear -Recording $Recording
    if ($null -eq $releaseYear -or $null -eq $recordingFirstYear) { return $false }
    return (($releaseYear - $recordingFirstYear) -gt 2)
}

function Test-YearMismatchCoverRelease {
    param($Release)
    if (-not $Release) { return $false }
    if ([string]::IsNullOrWhiteSpace($ReleaseYear)) { return $false }
    $releaseYear = Get-YearFromDate ([string]$Release.date)
    if ($null -eq $releaseYear) { return $true }
    return ([Math]::Abs($releaseYear - ([int]$ReleaseYear)) -gt 1)
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
                        elseif (Test-TextEquivalent $groupArtist $ArtistValue) { $score += 165 }
                        elseif ($groupArtist -match ('(?i)' + [regex]::Escape($ArtistValue))) { $score += 45 }
                        else { $score -= 500 }
                    }
                    if ([string]$_.title -ieq $TitleValue) { $score += 260 }
                    elseif ([string]$_.title -match ('(?i)^' + [regex]::Escape($TitleValue) + '\s*[\(\[]')) { $score += 180 }
                    elseif ([string]$_.title -match ('(?i)' + [regex]::Escape($TitleValue))) { $score += 70 }
                    if ((Test-VersionVariantTitle ([string]$_.title) -or Test-VersionVariantTitle ([string]$_.disambiguation)) -and -not (Test-VersionVariantTitle $TitleValue)) { $score -= 280 }
                    switch -Regex ([string]$_.'primary-type') {
                        '^(Album)$' { $score += 390; break }
                        '^(EP)$' { $score += 200; break }
                        '^(Single)$' { $score += 170; break }
                    }
                    foreach ($secondaryType in @($_.'secondary-types')) {
                        if ([string]$secondaryType -match '(?i)Compilation|Soundtrack|Live|DJ-mix|Mixtape/Street|Remix') { $score -= 350 }
                    }
                    if ([string]$_.'first-release-date' -match '^\d{4}(-\d{2})?(-\d{2})?$') { $score += 35 }
                    if (-not [string]::IsNullOrWhiteSpace($ReleaseYear) -and [string]$_.'first-release-date' -match '^(?<year>(19|20)\d{2})') {
                        $delta = [Math]::Abs(([int]$Matches['year']) - ([int]$ReleaseYear))
                        if ($delta -eq 0) { $score += 240 }
                        elseif ($delta -le 1) { $score += 70 }
                        elseif ($delta -gt 8) { $score -= 100 }
                    }
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
    param($Recording, [hashtable]$Headers, [string]$ArtistValue, [string]$TitleValue, $PreferredRelease = $null, [string]$PreferredReleaseSource = '')

    $release = Select-BestRelease -Recording $Recording
    $directRelease = $null
    $directReleaseSource = ''
    if ($PreferredRelease) {
        $directRelease = $PreferredRelease
        $directReleaseSource = $PreferredReleaseSource
    } elseif ((Test-WeakCoverRelease -Release $release) -or (Test-LaterEraCoverRelease -Release $release -Recording $Recording) -or (Test-YearMismatchCoverRelease -Release $release)) {
        $directRelease = Find-DirectCoverRelease -ArtistValue $ArtistValue -TitleValue $TitleValue -Headers $Headers
        $directReleaseSource = 'title'
    }
    $result = [ordered]@{
        Artist = Get-ArtistCreditName -Recording $Recording
        Title = Repair-TextEncoding ([string]$Recording.title)
        ReleaseTitle = ''
        ReleaseDate = ''
        ReleaseMbid = ''
        ReleaseMatchSource = ''
        ArtistMbid = Get-PreferredArtistMbid -Recording $Recording -Headers $Headers
        RecordingMbid = [string]$Recording.id
    }
    if ($release) {
        $result.ReleaseTitle = Repair-TextEncoding ([string]$release.title)
        $result.ReleaseDate = [string]$release.date
        $result.ReleaseMbid = [string]$release.id
        $result.ReleaseMatchSource = 'recording'
    }
    if ($directRelease) {
        $result.ReleaseTitle = [string]$directRelease.title
        $result.ReleaseDate = [string]$directRelease.date
        $result.ReleaseMbid = [string]$directRelease.id
        $result.ReleaseMatchSource = $directReleaseSource
    }
    $result | ConvertTo-Json -Depth 5 -Compress
}

function Write-DirectReleaseMetadataResult {
    param([string]$ArtistValue, [string]$TitleValue, $Release, [string]$ReleaseSource = '')

    $result = [ordered]@{
        Artist = Repair-TextEncoding $ArtistValue
        Title = Repair-TextEncoding $TitleValue
        ReleaseTitle = Repair-TextEncoding ([string]$Release.title)
        ReleaseDate = [string]$Release.date
        ReleaseMbid = [string]$Release.id
        ReleaseMatchSource = $ReleaseSource
        ArtistMbid = ''
        RecordingMbid = ''
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

    $variantWords = 'instrumental|acoustic|karaoke|tribute|cover|remix|live|sub(?:titula[dd][ao]?|itula[dd][ao]?|titulos?)|espanol|ingles|legendado|traducao|translated|translation|sped\s+up|slowed|nightcore|making\s+of|behind\s+the\s+scenes|interview|commentary'
    if (($recordingTitle -match ('(?i)\b(' + $variantWords + ')\b')) -and ($TitleValue -notmatch ('(?i)\b(' + $variantWords + ')\b'))) {
        $score -= 500
    }

    $artistCredit = Get-ArtistCreditName -Recording $Recording
    $primaryArtist = Get-PrimaryArtistName -Value $ArtistValue
    if (Test-KnownArtist $ArtistValue) {
        if ($artistCredit -ieq $ArtistValue) { $score += 160 }
        elseif (Test-TextEquivalent $artistCredit $ArtistValue) { $score += 145 }
        elseif ($artistCredit -match ('(?i)' + [regex]::Escape($ArtistValue))) { $score += 40 }
        else { $score -= 300 }
    }
    if (Test-KnownArtist $primaryArtist) {
        if ($artistCredit -ieq $primaryArtist) { $score += 140 }
        elseif (Test-TextEquivalent $artistCredit $primaryArtist) { $score += 125 }
        elseif ($artistCredit -match ('(?i)' + [regex]::Escape($primaryArtist))) { $score += 35 }
        else { $score -= 500 }
    }
    $requestedHasCollab = ($ArtistValue -match '(?i)\b(ft\.?|feat\.?|featuring|with)\b|&|\sx\s|,')
    if (-not $requestedHasCollab -and $artistCredit -match '\s&\s') { $score -= 90 }
    $releaseCount = @($Recording.releases).Count
    if ($releaseCount -gt 0) {
        $score += 10
        $score += [Math]::Min(520, [int](80 * [Math]::Log($releaseCount + 1, 2)))
        $bestReleaseScore = @($Recording.releases | ForEach-Object { Get-ReleaseScore -Release $_ -Recording $Recording } | Sort-Object -Descending | Select-Object -First 1)
        if ($bestReleaseScore.Count -gt 0) { $score += [int]([double]$bestReleaseScore[0] / 3.0) }
    }
    if ([string]$Recording.'first-release-date' -match '^\d{4}(-\d{2})?(-\d{2})?$') { $score += 35 }
    if (@($Recording.releases | Where-Object { [string]$_.date -match '^\d{4}(-\d{2})?(-\d{2})?$' }).Count -gt 0) { $score += 25 }
    else { $score -= 30 }
    if (-not [string]::IsNullOrWhiteSpace($ReleaseYear)) {
        $yearMatches = @($Recording.releases | Where-Object { [string]$_.date -match ('^' + [regex]::Escape($ReleaseYear)) })
        if ($yearMatches.Count -gt 0) { $score += 560 }
        elseif ([string]$Recording.'first-release-date' -match '^(?<year>(19|20)\d{2})') {
            $delta = [Math]::Abs(([int]$Matches['year']) - ([int]$ReleaseYear))
            if ($delta -eq 0) { $score += 260 }
            elseif ($delta -le 1) { $score += 100 }
            elseif ($delta -gt 8) { $score -= 700 }
            elseif ($delta -gt 3) { $score -= 420 }
            else { $score -= 220 }
        }
        else { $score -= 260 }
    }
    if ([string]$Recording.disambiguation -match '(?i)\b(live|karaoke|tribute|cover|remix|acoustic|instrumental)\b') { $score -= 260 }
    if (@($Recording.releases | Where-Object { -not (Test-PlaylistLikeTitle ([string]$_.title)) -and -not (Test-PlaylistLikeTitle ([string]$_.'release-group'.title)) }).Count -gt 0) { $score += 30 }

    return $score
}

function Find-Recording {
    param([string]$ArtistValue, [string]$TitleValue, [hashtable]$Headers)

    $titleSearches = New-Object System.Collections.Generic.List[string]
    $titleSearches.Add($TitleValue)
    if ($TitleValue -match "(?i)^don't\s+stop\s+'?til\s+you\s+get\s+enough$") {
        $titleSearches.Add('Dont Stop Till You Get Enough')
        $titleSearches.Add('Dont Stop Til You Get Enough')
        $titleSearches.Add("Don't Stop Til You Get Enough")
    }
    $foldedTitle = Get-FoldedText $TitleValue
    if (-not [string]::IsNullOrWhiteSpace($foldedTitle)) { $titleSearches.Add($foldedTitle) }
    $titleSearches = @($titleSearches | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $queries = New-Object System.Collections.Generic.List[string]
    foreach ($titleSearch in $titleSearches) {
        $safeTitle = $titleSearch.Replace('"','')
        if (Test-KnownArtist $ArtistValue) {
            $queries.Add('artist:"' + $ArtistValue.Replace('"','') + '" AND recording:"' + $safeTitle + '"')
            $primaryArtist = Get-PrimaryArtistName -Value $ArtistValue
            if ((Test-KnownArtist $primaryArtist) -and ($primaryArtist -ine $ArtistValue)) {
                $queries.Add('artist:"' + $primaryArtist.Replace('"','') + '" AND recording:"' + $safeTitle + '"')
            }
        }
        if (-not $queries.Contains('recording:"' + $safeTitle + '"')) {
            $queries.Add('recording:"' + $safeTitle + '"')
        }
    }
    $queries = @($queries | Select-Object -Unique)

    foreach ($query in $queries) {
        try {
            $url = 'https://musicbrainz.org/ws/2/recording/?query=' + [uri]::EscapeDataString($query) + '&fmt=json&limit=25&inc=artist-credits+releases+release-groups+media'
            $result = Invoke-RestMethod -Uri $url -Headers $Headers -TimeoutSec 12
            $match = @($result.recordings) |
                Where-Object { $_.title -and (Test-ArtistCompatible -Recording $_ -ArtistValue $ArtistValue) } |
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
$ReleaseTitle = Remove-TitleNoise $ReleaseTitle
if ($ReleaseYear -notmatch '^(19|20)\d{2}$') { $ReleaseYear = '' }

New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
$cachePrefix = if (Test-KnownArtist $Artist) { $Artist } else { 'unknown_artist' }
$cacheRelease = if ([string]::IsNullOrWhiteSpace($ReleaseTitle)) { 'no_release' } else { $ReleaseTitle }
$cacheYear = if ([string]::IsNullOrWhiteSpace($ReleaseYear)) { 'no_year' } else { $ReleaseYear }
$cacheKey = Get-SafeCacheName ('v30 - ' + $LookupMode + ' - ' + $cachePrefix + ' - ' + $Title + ' - ' + $cacheRelease + ' - ' + $cacheYear)
$cachePath = Join-Path $CacheDir ($cacheKey + '.metadata.json')
$missPath = Join-Path $CacheDir ($cacheKey + '.metadata.miss')

if (Test-Path -LiteralPath $cachePath) {
    Get-Content -LiteralPath $cachePath -Raw
    return
}
if (Test-Path -LiteralPath $missPath) { return }

$headers = @{ 'User-Agent' = 'JukeboxDownloadWizard/0.3.0.0 ( https://musicbrainz.org/ )' }
$preferredRelease = $null
$preferredReleaseSource = ''
if (-not [string]::IsNullOrWhiteSpace($ReleaseTitle)) {
    $preferredRelease = Find-DirectCoverRelease -ArtistValue $Artist -TitleValue $ReleaseTitle -Headers $headers
    if ($preferredRelease) { $preferredReleaseSource = 'release_tag' }
}
if ((-not $preferredRelease) -and -not [string]::IsNullOrWhiteSpace($ReleaseYear)) {
    $preferredRelease = Find-DirectCoverRelease -ArtistValue $Artist -TitleValue $Title -Headers $headers
    if ($preferredRelease) { $preferredReleaseSource = 'title_year' }
}

try {
    $recording = Find-Recording -ArtistValue $Artist -TitleValue $Title -Headers $headers
    if ($recording) {
        $json = Write-MetadataResult -Recording $recording -Headers $headers -ArtistValue $Artist -TitleValue $Title -PreferredRelease $preferredRelease -PreferredReleaseSource $preferredReleaseSource
        Set-Content -LiteralPath $cachePath -Value $json -Encoding UTF8
        Write-Output $json
        return
    }
}
catch {
}

if ($preferredRelease) {
    $json = Write-DirectReleaseMetadataResult -ArtistValue $Artist -TitleValue $Title -Release $preferredRelease -ReleaseSource $preferredReleaseSource
    Set-Content -LiteralPath $cachePath -Value $json -Encoding UTF8
    Write-Output $json
    return
}

Set-Content -LiteralPath $missPath -Value ((Get-Date).ToString('s')) -Encoding ASCII

