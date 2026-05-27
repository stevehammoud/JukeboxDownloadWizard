param(
    [Parameter(Mandatory=$true)][string]$UrlFile,
    [string]$ExistingUrlFile = '',
    [int]$MinDurationSeconds = 0,
    [int]$MaxDurationSeconds = 3600,
    [string]$OutputDetailsFile = '',
    [string]$CacheFile = '',
    [switch]$EnrichMusicBrainzMetadata,
    [switch]$RequireMusicBrainzMetadata
)

if (-not (Test-Path -LiteralPath $UrlFile)) {
    New-Item -ItemType File -Path $UrlFile -Force | Out-Null
}

$ResourceDir = Split-Path -Parent $UrlFile
$AssetsDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$MusicBrainzMetadataScript = Join-Path $AssetsDir 'lib\musicbrainz_metadata_lookup.ps1'
$MusicBrainzCacheDir = Join-Path $AssetsDir 'resources\cache\musicbrainz_metadata'
if ([string]::IsNullOrWhiteSpace($CacheFile)) {
    $CacheFile = Join-Path $ResourceDir 'jukebox_url_metadata_cache.json'
}
$CacheVersion = 2
$MaxCacheRecords = 5000
if ($MaxDurationSeconds -lt 1) { $MaxDurationSeconds = 3600 }
if ($MinDurationSeconds -lt 0) { $MinDurationSeconds = 0 }
if ($MinDurationSeconds -gt $MaxDurationSeconds) { $MinDurationSeconds = $MaxDurationSeconds }
$seen = [ordered]@{}
$seenTitles = @{}
$trustedExistingIds = @{}
$trustedExistingUrls = @{}
$accepted = New-Object System.Collections.Generic.List[string]
$acceptedIds = New-Object System.Collections.Generic.List[string]
$acceptedDetails = New-Object System.Collections.Generic.List[string]
$acceptedCurrent = 0
$rejected = 0
$metadataChecks = 0
$cacheHits = 0
$inputLines = @(Get-Content -LiteralPath $UrlFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
$inputTotal = $inputLines.Count
$inputIndex = 0

function Get-YtDlpEjsArgs {
    if ($env:JUKEBOX_YTDLP_DENO -and (Test-Path -LiteralPath $env:JUKEBOX_YTDLP_DENO)) {
        return @('--js-runtimes', "deno:$($env:JUKEBOX_YTDLP_DENO)", '--remote-components', 'ejs:npm')
    }
    $deno = Get-Command deno -ErrorAction SilentlyContinue
    if ($deno) {
        return @('--js-runtimes', "deno:$($deno.Source)", '--remote-components', 'ejs:npm')
    }
    return @()
}

function Get-TitleKey {
    param([string]$Title)
    if ([string]::IsNullOrWhiteSpace($Title)) { return '' }

    $key = $Title.ToLowerInvariant()
    $key = $key -replace '[\(\[\{][^\)\]\}]*[\)\]\}]', ' '
    $key = $key -replace '["''`]', ' '
    $key = $key -replace '\b(19|20)\d{2}\b', ' '
    $key = $key -replace '\b(official|music|video|trailer|teaser|clip|lyrics?|lyric|hd|uhd|4k|8k|remaster(ed)?|extended|full|version)\b', ' '
    $key = $key -replace '\b(1080p|720p|480p|2160p)\b', ' '
    $key = $key -replace '[^a-z0-9]+', ' '
    $key = $key -replace '\s+', ' '
    return $key.Trim()
}

function Get-VideoId {
    param([string]$Line)

    $result = [ordered]@{ Id = ''; IsShort = $false }
    if ($Line -match '/shorts/([A-Za-z0-9_-]{11})') {
        $result.Id = $matches[1]
        $result.IsShort = $true
    } elseif ($Line -match 'youtu\.be/([A-Za-z0-9_-]{11})') {
        $result.Id = $matches[1]
    } elseif ($Line -match '[?&]v=([A-Za-z0-9_-]{11})') {
        $result.Id = $matches[1]
    } elseif ($Line -match '/embed/([A-Za-z0-9_-]{11})') {
        $result.Id = $matches[1]
    }
    return $result
}

function Split-VideoTitle {
    param([string]$Title)

    $artist = ''
    $name = $Title
    if ($Title -match '^(.*?)\s+-\s+(.*)$') {
        $artist = $matches[1].Trim()
        $name = $matches[2].Trim()
    }
    $artist = $artist -replace "`t", ' '
    $name = $name -replace "`t", ' '
    return [pscustomobject]@{ Artist = $artist; Title = $name }
}

function Get-MusicBrainzMatch {
    param([string]$VideoTitle)
    $parts = Split-VideoTitle $VideoTitle
    if ([string]::IsNullOrWhiteSpace($parts.Title) -or -not (Test-Path -LiteralPath $MusicBrainzMetadataScript)) { return $null }
    try {
        New-Item -ItemType Directory -Path $MusicBrainzCacheDir -Force | Out-Null
        $json = & powershell -NoProfile -ExecutionPolicy Bypass -File $MusicBrainzMetadataScript -Artist $parts.Artist -Title $parts.Title -CacheDir $MusicBrainzCacheDir 2>$null | Select-Object -First 1
        if ([string]::IsNullOrWhiteSpace($json)) { return $null }
        $metadata = $json | ConvertFrom-Json
        if ([string]::IsNullOrWhiteSpace([string]$metadata.Artist) -or [string]::IsNullOrWhiteSpace([string]$metadata.Title)) { return $null }
        return $metadata
    }
    catch {
        return $null
    }
}

function Format-Duration {
    param([int]$Seconds)

    if ($Seconds -lt 0) { $Seconds = 0 }
    $span = [TimeSpan]::FromSeconds($Seconds)
    if ($span.TotalHours -ge 1) {
        return '{0}:{1:00}:{2:00}' -f [int][Math]::Floor($span.TotalHours), $span.Minutes, $span.Seconds
    }
    return '{0}:{1:00}' -f [int]$span.TotalMinutes, $span.Seconds
}

function Encode-PreviewField {
    param([string]$Value)

    if ($null -eq $Value) { $Value = '' }
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
}

function Load-MetadataCache {
    if (-not (Test-Path -LiteralPath $CacheFile)) { return @{} }
    try {
        $raw = Get-Content -LiteralPath $CacheFile -Raw | ConvertFrom-Json
        if (-not $raw -or -not $raw.videos) { return @{} }
        $loaded = @{}
        foreach ($prop in $raw.videos.PSObject.Properties) {
            $loaded[$prop.Name] = $prop.Value
        }
        return $loaded
    } catch {
        return @{}
    }
}

function Save-MetadataCache {
    param([hashtable]$Cache)

    $videos = [ordered]@{}
    foreach ($id in ($Cache.Keys | Sort-Object)) {
        $videos[$id] = $Cache[$id]
    }
    $payload = [ordered]@{
        version = $CacheVersion
        updated = (Get-Date).ToString('s')
        videos = $videos
    }
    $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $CacheFile -Encoding ASCII
}

function Get-CacheField {
    param($Record, [string]$Name, $Default = '')

    if ($Record -is [System.Collections.IDictionary] -and $Record.Contains($Name)) {
        return $Record[$Name]
    }
    if ($Record -and $Record.PSObject.Properties[$Name]) {
        return $Record.PSObject.Properties[$Name].Value
    }
    return $Default
}

function Set-CacheField {
    param($Record, [string]$Name, $Value)

    if ($Record -is [System.Collections.IDictionary]) {
        $Record[$Name] = $Value
        return
    }
    if ($Record.PSObject.Properties[$Name]) {
        $Record.PSObject.Properties[$Name].Value = $Value
    } else {
        $Record | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Touch-CacheRecord {
    param($Record)

    $now = (Get-Date).ToString('s')
    if (-not (Get-CacheField $Record 'firstSeen' '')) {
        Set-CacheField $Record 'firstSeen' $now
    }
    Set-CacheField $Record 'lastSeen' $now
    Set-CacheField $Record 'lastReviewed' $now
}

function Prune-MetadataCache {
    param([hashtable]$Cache)

    if ($Cache.Count -le $MaxCacheRecords) { return }
    $removeCount = $Cache.Count - $MaxCacheRecords
    $oldest = @(
        foreach ($id in $Cache.Keys) {
            $record = $Cache[$id]
            $stamp = Get-CacheField $record 'lastSeen' (Get-CacheField $record 'lastReviewed' (Get-CacheField $record 'firstSeen' ''))
            [pscustomobject]@{ Id = $id; Stamp = [string]$stamp }
        }
    ) | Sort-Object Stamp | Select-Object -First $removeCount

    foreach ($item in $oldest) {
        $Cache.Remove($item.Id)
    }
}

function Get-MetadataRecord {
    param([string]$Id, [string]$Url, [hashtable]$Cache)

    if ($Cache.ContainsKey($Id)) {
        $cachedDuration = Get-CacheField $Cache[$Id] 'durationSeconds' $null
        $cachedLiveStatus = Get-CacheField $Cache[$Id] 'liveStatus' $null
        $cachedMbArtist = Get-CacheField $Cache[$Id] 'mbArtist' ''
        $cachedMbTitle = Get-CacheField $Cache[$Id] 'mbTitle' ''
        if ($cachedDuration -ne $null -and $cachedDuration -ne '' -and $cachedLiveStatus -ne $null) {
            if ((-not $RequireMusicBrainzMetadata) -or ((-not [string]::IsNullOrWhiteSpace([string]$cachedMbArtist)) -and (-not [string]::IsNullOrWhiteSpace([string]$cachedMbTitle)))) {
                $script:cacheHits++
                Touch-CacheRecord $Cache[$Id]
                return $Cache[$Id]
            }
        }
        $Cache.Remove($Id)
    }

    $script:metadataChecks++
    $ejsArgs = Get-YtDlpEjsArgs
    $json = & yt-dlp @ejsArgs --dump-single-json --no-playlist --skip-download $Url 2>$null
    if (-not $json) {
        $now = (Get-Date).ToString('s')
        $record = [ordered]@{ approved = $false; reason = 'metadata unavailable'; title = ''; titleKey = ''; durationSeconds = 0; liveStatus = ''; isLive = $false; wasLive = $false; width = 0; height = 0; firstSeen = $now; lastSeen = $now; lastReviewed = $now }
        $Cache[$Id] = $record
        return $record
    }

    $meta = $json | ConvertFrom-Json
    $titleKey = Get-TitleKey $meta.title
    $duration = [double]$meta.duration
    $liveStatus = [string]$meta.live_status
    $isLive = ($meta.is_live -eq $true)
    $wasLive = ($meta.was_live -eq $true)
    $w = [double]$meta.width
    $h = [double]$meta.height
    if (-not $w -or -not $h) {
        $fmt = @($meta.formats | Where-Object { $_.width -and $_.height -and $_.vcodec -ne 'none' } |
            Sort-Object @{Expression={ [int]$_.width * [int]$_.height }} -Descending |
            Select-Object -First 1)
        if ($fmt) {
            $w = [double]$fmt.width
            $h = [double]$fmt.height
        }
    }

    $approved = $false
    $reason = ''
    if ($isLive -or $wasLive -or ($liveStatus -and $liveStatus -ne 'not_live')) {
        $reason = 'live or DVR stream'
    } elseif (-not $duration -or $duration -le 0) {
        $reason = 'missing duration'
    } elseif ($duration -lt $MinDurationSeconds) {
        $reason = "shorter than $MinDurationSeconds seconds"
    } elseif ($duration -gt $MaxDurationSeconds) {
        $reason = "longer than $MaxDurationSeconds seconds"
    } elseif (-not $w -or -not $h) {
        $reason = 'missing dimensions'
    } else {
        $ratio = $w / $h
        $is43 = [Math]::Abs($ratio - (4/3)) -le 0.04
        $is169 = [Math]::Abs($ratio - (16/9)) -le 0.04
        if ($is43 -or $is169) {
            $approved = $true
        } else {
            $reason = 'not 4:3 or 16:9'
        }
    }

    $mbArtist = ''
    $mbTitle = ''
    $mbReleaseDate = ''
    if ($approved -and ($RequireMusicBrainzMetadata -or $EnrichMusicBrainzMetadata)) {
        $mb = Get-MusicBrainzMatch -VideoTitle ([string]$meta.title)
        if ($mb) {
            $mbArtist = [string]$mb.Artist
            $mbTitle = [string]$mb.Title
            $mbReleaseDate = [string]$mb.ReleaseDate
        } elseif ($RequireMusicBrainzMetadata) {
            $approved = $false
            $reason = 'artist/title not found'
        }
    }

    $now = (Get-Date).ToString('s')
    $record = [ordered]@{
        approved = $approved
        reason = $reason
        title = [string]$meta.title
        titleKey = $titleKey
        durationSeconds = [int]$duration
        liveStatus = $liveStatus
        isLive = [bool]$isLive
        wasLive = [bool]$wasLive
        width = [int]$w
        height = [int]$h
        mbArtist = $mbArtist
        mbTitle = $mbTitle
        mbReleaseDate = $mbReleaseDate
        firstSeen = $now
        lastSeen = $now
        lastReviewed = $now
    }
    $Cache[$Id] = $record
    return $record
}

function Test-MetadataRecordApproved {
    param($Record)

    $duration = [double](Get-CacheField $Record 'durationSeconds' 0)
    $liveStatus = [string](Get-CacheField $Record 'liveStatus' '')
    $isLive = [bool](Get-CacheField $Record 'isLive' $false)
    $wasLive = [bool](Get-CacheField $Record 'wasLive' $false)
    $w = [double](Get-CacheField $Record 'width' 0)
    $h = [double](Get-CacheField $Record 'height' 0)

    if ($isLive -or $wasLive -or ($liveStatus -and $liveStatus -ne 'not_live')) { return $false }
    if (-not $duration -or $duration -le 0) { return $false }
    if ($duration -lt $MinDurationSeconds) { return $false }
    if ($duration -gt $MaxDurationSeconds) { return $false }
    if (-not $w -or -not $h) { return $false }
    if ($RequireMusicBrainzMetadata) {
        if ([string]::IsNullOrWhiteSpace([string](Get-CacheField $Record 'mbArtist' ''))) { return $false }
        if ([string]::IsNullOrWhiteSpace([string](Get-CacheField $Record 'mbTitle' ''))) { return $false }
    }

    $ratio = $w / $h
    $is43 = [Math]::Abs($ratio - (4/3)) -le 0.04
    $is169 = [Math]::Abs($ratio - (16/9)) -le 0.04
    return ($is43 -or $is169)
}

if ($ExistingUrlFile -and (Test-Path -LiteralPath $ExistingUrlFile)) {
    Get-Content -LiteralPath $ExistingUrlFile | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#')) { return }
        $parsed = Get-VideoId $line
        if ($parsed.Id -and -not $parsed.IsShort) {
            $trustedExistingIds[$parsed.Id] = $true
            $trustedExistingUrls[$parsed.Id] = "https://youtu.be/$($parsed.Id)"
        }
    }
}

$cache = Load-MetadataCache

foreach ($existingId in $trustedExistingIds.Keys) {
    if (-not $seen.Contains($existingId)) {
        try {
            $existingRecord = Get-MetadataRecord -Id $existingId -Url $trustedExistingUrls[$existingId] -Cache $cache
            if (-not (Test-MetadataRecordApproved $existingRecord)) {
                $script:rejected++
                return
            }

            $seen[$existingId] = $true
            $accepted.Add($trustedExistingUrls[$existingId])
            $acceptedIds.Add($existingId)
            $existingTitleKey = [string](Get-CacheField $existingRecord 'titleKey' '')
            if ($existingTitleKey) { $seenTitles[$existingTitleKey] = $true }
        } catch {
            $script:rejected++
        }
    }
}

$inputLines | ForEach-Object {
    $line = $_
    $script:inputIndex++
    if ($script:inputTotal -gt 0) {
        Write-Host ("PROGRESS|Reviewing URLs|{0}|{1}|{2}" -f $script:inputIndex, $script:inputTotal, $line)
    }

    $parsed = Get-VideoId $line
    $id = $parsed.Id
    $isShort = $parsed.IsShort

    if (-not $id -or $isShort -or $seen.Contains($id)) {
        $script:rejected++
        return
    }

    $seen[$id] = $true
    $url = "https://youtu.be/$id"

    try {
        $record = $null
        if ($cache.ContainsKey($id)) {
            $record = Get-MetadataRecord -Id $id -Url $url -Cache $cache
            if (-not (Test-MetadataRecordApproved $record)) { $script:rejected++; return }
        } else {
            $record = Get-MetadataRecord -Id $id -Url $url -Cache $cache
            if (-not (Test-MetadataRecordApproved $record)) { $script:rejected++; return }
        }

        $titleKey = [string]$record.titleKey
        if ($titleKey -and $seenTitles.ContainsKey($titleKey)) {
            $script:rejected++
            return
        }

        if ($titleKey) { $seenTitles[$titleKey] = $true }
        $accepted.Add($url)
        $acceptedIds.Add($id)
        $script:acceptedCurrent++
        if ($OutputDetailsFile) {
            $mbArtist = [string](Get-CacheField $record 'mbArtist' '')
            $mbTitle = [string](Get-CacheField $record 'mbTitle' '')
            if (-not [string]::IsNullOrWhiteSpace($mbArtist) -and -not [string]::IsNullOrWhiteSpace($mbTitle)) {
                $parts = [pscustomobject]@{ Artist = $mbArtist; Title = $mbTitle }
            } else {
                $parts = Split-VideoTitle ([string](Get-CacheField $record 'title' ''))
            }
            $durationText = Format-Duration ([int](Get-CacheField $record 'durationSeconds' 0))
            $detailFormat = '{0}' + "`t" + '{1}' + "`t" + '{2}' + "`t" + '{3}'
            $acceptedDetails.Add(($detailFormat -f $url, $parts.Artist, $parts.Title, $durationText))
            Write-Host ("CANDIDATE|{0}|{1}|{2}|{3}" -f (Encode-PreviewField $url), (Encode-PreviewField $parts.Artist), (Encode-PreviewField $parts.Title), (Encode-PreviewField $durationText))
        }
    } catch {
        $script:rejected++
    }
}

Set-Content -LiteralPath $UrlFile -Value $accepted -Encoding ASCII
if ($OutputDetailsFile) {
    $header = 'Url' + "`t" + 'Artist' + "`t" + 'Title' + "`t" + 'Length'
    Set-Content -LiteralPath $OutputDetailsFile -Value @($header) -Encoding UTF8
    if ($acceptedDetails.Count -gt 0) {
        Add-Content -LiteralPath $OutputDetailsFile -Value $acceptedDetails -Encoding UTF8
    }
}
Prune-MetadataCache -Cache $cache
Save-MetadataCache -Cache $cache
'{0}|{1}|{2}|{3}' -f $acceptedCurrent, $rejected, $cacheHits, $metadataChecks
