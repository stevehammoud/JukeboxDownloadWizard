param(
    [string]$ArtistMbid = '',
    [string]$Artist = '',
    [string]$CacheDir = '',
    [string]$ProjectKeyPath = '',
    [string]$PersonalKeyPath = '',
    [ValidateSet('Image','Logo')][string]$AssetType = 'Image'
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

function Get-TextFileValue {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return '' }
    return ((Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue) -as [string]).Trim()
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

function Save-ImageFromUrl {
    param([string]$Url, [string]$OutputPath)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -TimeoutSec 25 -MaximumRedirection 8 -UseBasicParsing | Out-Null
        if ((Test-Path -LiteralPath $OutputPath) -and ((Get-Item -LiteralPath $OutputPath).Length -gt 0) -and (Test-ImageFile -Path $OutputPath)) { return $true }
    }
    catch {
    }
    if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue }
    return $false
}

function Get-FanartUrls {
    param($FanartJson, [string]$AssetType = 'Image')

    $priority = if ($AssetType -eq 'Logo') {
        @('hdmusiclogo', 'musiclogo', 'musicbanner')
    } else {
        @('artistthumb', 'artistbackground', 'musicbanner', 'hdmusiclogo', 'musiclogo')
    }
    $urls = New-Object System.Collections.Generic.List[string]
    foreach ($propertyName in $priority) {
        $items = @($FanartJson.PSObject.Properties[$propertyName].Value)
        if ($items.Count -gt 0) {
            $bestItems = $items | Sort-Object @{ Expression = { [int]($_.likes -as [int]) }; Descending = $true } | Select-Object -First 8
            foreach ($item in $bestItems) {
                if ($item.url -and -not $urls.Contains([string]$item.url)) { $urls.Add([string]$item.url) }
            }
        }
    }
    return @($urls)
}

function Get-FanartImage {
    param([string]$Mbid, [string]$OutputPrefix, [string]$AssetType = 'Image')
    $projectKey = Get-TextFileValue -Path $ProjectKeyPath
    if ([string]::IsNullOrWhiteSpace($projectKey)) { return $false }

    $url = 'https://webservice.fanart.tv/v3/music/' + $Mbid + '?api_key=' + [uri]::EscapeDataString($projectKey)
    $personalKey = Get-TextFileValue -Path $PersonalKeyPath
    if (-not [string]::IsNullOrWhiteSpace($personalKey)) {
        $url += '&client_key=' + [uri]::EscapeDataString($personalKey)
    }

    try {
        $headers = @{ 'User-Agent' = 'JukeboxDownloadWizard/0.2.1.1' }
        $fanart = Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 20
        $imageUrls = @(Get-FanartUrls -FanartJson $fanart -AssetType $AssetType)
        $saved = 0
        for ($i = 0; $i -lt $imageUrls.Count; $i++) {
            $ext = if ($AssetType -eq 'Logo') { 'png' } else { 'jpg' }
            $outputPath = '{0}_{1}_{2:00}.{3}' -f $OutputPrefix, $AssetType.ToLowerInvariant(), ($i + 1), $ext
            if (Save-ImageFromUrl -Url $imageUrls[$i] -OutputPath $outputPath) { $saved++ }
            if ($saved -ge 8) { break }
        }
        return ($saved -gt 0)
    }
    catch {
        return $false
    }
}

function Get-WikidataIdForArtist {
    param([string]$Mbid)
    try {
        $headers = @{ 'User-Agent' = 'JukeboxDownloadWizard/0.2.1.1 ( https://musicbrainz.org/ )' }
        $url = 'https://musicbrainz.org/ws/2/artist/' + $Mbid + '?inc=url-rels&fmt=json'
        $artistData = Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 15
        foreach ($rel in @($artistData.relations)) {
            $resource = [string]$rel.url.resource
            if ($resource -match 'wikidata\.org/wiki/(Q\d+)') { return $Matches[1] }
        }
    }
    catch {
    }
    return ''
}

function Get-WikidataImageName {
    param([string]$Qid)
    if ([string]::IsNullOrWhiteSpace($Qid)) { return '' }
    try {
        $headers = @{ 'User-Agent' = 'JukeboxDownloadWizard/0.2.1.1' }
        $url = 'https://www.wikidata.org/wiki/Special:EntityData/' + $Qid + '.json'
        $data = Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 15
        $entity = $data.entities.$Qid
        $claim = @($entity.claims.P18) | Select-Object -First 1
        if ($claim -and $claim.mainsnak.datavalue.value) { return [string]$claim.mainsnak.datavalue.value }
    }
    catch {
    }
    return ''
}

function Get-WikimediaImage {
    param([string]$Mbid, [string]$OutputPath)
    $qid = Get-WikidataIdForArtist -Mbid $Mbid
    $imageName = Get-WikidataImageName -Qid $qid
    if ([string]::IsNullOrWhiteSpace($imageName)) { return $false }
    $url = 'https://commons.wikimedia.org/wiki/Special:FilePath/' + [uri]::EscapeDataString($imageName) + '?width=900'
    return Save-ImageFromUrl -Url $url -OutputPath $OutputPath
}

if ([string]::IsNullOrWhiteSpace($ArtistMbid) -or [string]::IsNullOrWhiteSpace($CacheDir)) { return }
New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null

$cacheName = Get-SafeCacheName (($ArtistMbid + ' ' + $Artist + ' ' + $AssetType).Trim())
$imagePrefix = Join-Path $CacheDir $cacheName
$imagePath = Join-Path $CacheDir ($cacheName + '_wikimedia.jpg')
$missPath = Join-Path $CacheDir ($cacheName + '.miss')

$cachedImages = @(Get-ChildItem -LiteralPath $CacheDir -File -Filter ($cacheName + '_*.*') -ErrorAction SilentlyContinue | Where-Object { Test-ImageFile -Path $_.FullName })
if ($cachedImages.Count -gt 0) {
    Write-Output (($cachedImages | Get-Random).FullName)
    return
}
if (Test-Path -LiteralPath $missPath) { return }

if (Get-FanartImage -Mbid $ArtistMbid -OutputPrefix $imagePrefix -AssetType $AssetType) {
    $cachedImages = @(Get-ChildItem -LiteralPath $CacheDir -File -Filter ($cacheName + '_*.*') -ErrorAction SilentlyContinue | Where-Object { Test-ImageFile -Path $_.FullName })
    if ($cachedImages.Count -gt 0) {
        Write-Output (($cachedImages | Get-Random).FullName)
    }
    return
}

if ($AssetType -eq 'Logo') {
    Set-Content -LiteralPath $missPath -Value ((Get-Date).ToString('s')) -Encoding ASCII
    return
}

Start-Sleep -Milliseconds 250
if (Get-WikimediaImage -Mbid $ArtistMbid -OutputPath $imagePath) {
    Write-Output $imagePath
    return
}

Set-Content -LiteralPath $missPath -Value ((Get-Date).ToString('s')) -Encoding ASCII
