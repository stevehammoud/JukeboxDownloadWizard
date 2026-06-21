param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('AddVideo', 'VideoPreview', 'ImportSource', 'SourceCount', 'SourcePreview', 'Search', 'SearchPreview', 'Review', 'Clear', 'Validate', 'Download', 'GenerateMarquees', 'ConvertMp4ToMp3', 'MoveToSsd', 'RollbackCancel')]
    [string]$Action,
    [string]$Value = '',
    [int]$Limit = 25,
    [int]$MinMinutes = 0,
    [int]$MaxMinutes = 60,
    [int]$MinSeconds = -1,
    [int]$MaxSeconds = -1,
    [ValidateSet(480, 720, 1080)]
    [int]$Resolution = 720,
    [ValidateSet('Video', 'Audio')]
    [string]$DownloadMediaType = 'Video',
    [string]$NormalizeAudio = 'false',
    [string]$GenerateStandardMarquee = 'false',
    [string]$GenerateFullColorMarquee = 'false'
)

$Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$PackageRoot = Split-Path -Parent $Root
$AppRoot = Split-Path -Parent $PackageRoot
$VisibleRoot = if ((Split-Path -Leaf $PackageRoot) -ieq '.jukebox_download_wizard') { $AppRoot } else { $PackageRoot }
$LibDir = Join-Path $Root 'lib'
$ResourceDir = Join-Path $VisibleRoot 'resources'
$HiddenResourceDir = Join-Path $Root 'resources'
$ResourceCacheDir = Join-Path $HiddenResourceDir 'cache'
$ResourceTempDir = Join-Path $HiddenResourceDir 'temp'
$DownloadDir = Join-Path $VisibleRoot 'downloads'
$LogDir = Join-Path $VisibleRoot 'logs'
$ArchiveLogDir = Join-Path $LogDir 'ARCHIVE_LOGS'
$ToolsDir = Join-Path $Root 'tools'
$YtDlpPortablePath = Join-Path $ToolsDir 'yt-dlp.exe'
$DenoPortablePath = Join-Path $ToolsDir 'deno.exe'
$DenoPortableFolder = Join-Path $ToolsDir 'deno'
$DenoPortableFolderPath = Join-Path $DenoPortableFolder 'deno.exe'
$FfmpegPortableBinDir = Join-Path $ToolsDir 'ffmpeg\bin'
$FfmpegPortablePath = Join-Path $FfmpegPortableBinDir 'ffmpeg.exe'
$WizardLogDir = $LogDir
$UrlLogDir = $LogDir
$UrlFile = Join-Path $ResourceDir 'jukebox_urls.txt'
$CancelSnapshotFile = Join-Path $ResourceTempDir 'jukebox_urls.cancel_snapshot.txt'
$DownloadSnapshotFile = Join-Path $ResourceTempDir 'download_files.cancel_snapshot.txt'
$CookieFile = Join-Path $ResourceDir 'ytcookies.txt'
$MetadataCacheFile = Join-Path $ResourceCacheDir 'jukebox_url_metadata_cache.json'
$MaxSearchLimit = 250
$MaxSourceLimit = 500
$MinDurationSeconds = if ($MinSeconds -ge 0) { [Math]::Max(0, $MinSeconds) } else { [Math]::Max(0, $MinMinutes * 60) }
$MaxDurationSeconds = if ($MaxSeconds -ge 0) { [Math]::Max(30, $MaxSeconds) } else { [Math]::Max(60, $MaxMinutes * 60) }
if ($MinDurationSeconds -gt $MaxDurationSeconds) { $MinDurationSeconds = $MaxDurationSeconds }
$FileNameTotalLimit = 75
$Processes = 4
$Height = $Resolution
$DownloadAudioOnly = $DownloadMediaType -eq 'Audio'
$NormalizeAudioEnabled = $NormalizeAudio -match '^(1|true|yes|on)$'
$GenerateStandardMarqueeEnabled = $GenerateStandardMarquee -match '^(1|true|yes|on)$'
$GenerateFullColorMarqueeEnabled = $GenerateFullColorMarquee -match '^(1|true|yes|on)$'
$VideoCodec = 'avc1'
$AudioExt = 'm4a'
$VideoExt = 'mp4'
$MaxLogFiles = 5
$SsdFolderName = 'ha8800_screensaver'
$DownloadDriveReserveBytes = 5GB

New-Item -ItemType Directory -Path $ResourceDir, $ResourceCacheDir, $ResourceTempDir, $DownloadDir, $WizardLogDir, $UrlLogDir, $ToolsDir, $FfmpegPortableBinDir -Force | Out-Null

function Add-ToolPath {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return }
    $parts = @($env:PATH -split ';' | Where-Object { $_ })
    if ($parts -notcontains $Path) {
        $env:PATH = $Path + ';' + $env:PATH
    }
}

Add-ToolPath $ToolsDir
Add-ToolPath $DenoPortableFolder
Add-ToolPath $FfmpegPortableBinDir

if (-not $env:JUKEBOX_GUI_SESSION_STAMP) {
    $env:JUKEBOX_GUI_SESSION_STAMP = Get-Date -Format yyyyMMddHHmmss
}

$UrlLog = Join-Path $UrlLogDir "jukebox_gui_urls_$($env:JUKEBOX_GUI_SESSION_STAMP).log"
$DownloadLog = Join-Path $WizardLogDir "jukebox_gui_download_$($env:JUKEBOX_GUI_SESSION_STAMP).log"
function Format-ByteSize {
    param([Int64]$Bytes)

    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    return "$Bytes bytes"
}

function Get-AvailableBytesForPath {
    param([string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($fullPath)
    $drive = New-Object System.IO.DriveInfo($root)
    if (-not $drive.IsReady) { throw "Drive is not ready: $root" }
    return [Int64]$drive.AvailableFreeSpace
}

function Assert-MinFreeSpace {
    param(
        [string]$Path,
        [Int64]$RequiredReserveBytes,
        [string]$Purpose
    )

    $available = Get-AvailableBytesForPath -Path $Path
    if ($available -lt $RequiredReserveBytes) {
        throw "Not enough free disk space for $Purpose. Available: $(Format-ByteSize $available). Required reserve: $(Format-ByteSize $RequiredReserveBytes). Free space before trying again."
    }
    Write-Host "Disk space check passed for $Purpose. Available: $(Format-ByteSize $available). Reserve: $(Format-ByteSize $RequiredReserveBytes)."
}

function Remove-OldLogs {
    param(
        [string]$Path,
        [string]$Prefix,
        [int]$Keep
    )

    if (-not (Test-Path -LiteralPath $Path)) { return }
    Get-ChildItem -LiteralPath $Path -File -Force |
        Where-Object { $_.Name -like "$Prefix*.log" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $Keep |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Write-Log {
    param([string]$LogFile, [string]$Level, [string]$Message)
    "[{0}] [{1}] {2}" -f (Get-Date), $Level, $Message | Add-Content -LiteralPath $LogFile -Encoding ASCII
}

function Ensure-Tool {
    param([string]$Name)
    if (Get-Command $Name -ErrorAction SilentlyContinue) { return }
    if ($Name -eq 'yt-dlp') {
        throw "yt-dlp was not found. Add the portable copy here: $YtDlpPortablePath"
    }
    if ($Name -eq 'ffmpeg') {
        throw "ffmpeg was not found. Add the portable copy here: $FfmpegPortablePath"
    }
    throw "$Name was not found."
}

function Get-ToolSource {
    param([string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) { return '' }
    return $command.Source
}

function Get-DenoSource {
    if (Test-Path -LiteralPath $DenoPortablePath) { return $DenoPortablePath }
    if (Test-Path -LiteralPath $DenoPortableFolderPath) { return $DenoPortableFolderPath }
    return Get-ToolSource 'deno'
}

function Get-YtDlpEjsArgs {
    $deno = Get-DenoSource
    if (-not $deno) { return @() }
    $env:JUKEBOX_YTDLP_DENO = $deno
    return @('--js-runtimes', "deno:$deno", '--remote-components', 'ejs:npm')
}

function Set-DenoEnvironment {
    $deno = Get-DenoSource
    if ($deno) { $env:JUKEBOX_YTDLP_DENO = $deno }
}

function Get-ToolLocationLabel {
    param([string]$Path)
    if ($Path -like "$ToolsDir*") { return "portable app tools ($Path)" }
    return "system PATH ($Path)"
}

function Test-YouTubeUrl {
    param([string]$Url)
    return ($Url -match '^https?://' -and ($Url -match 'youtube\.com' -or $Url -match 'youtu\.be'))
}

function Invoke-ReviewUrls {
    param([string]$ExistingUrlFile = '')

    Ensure-Tool 'yt-dlp'
    Set-DenoEnvironment
    $reviewArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $LibDir 'review_urls.ps1'), '-UrlFile', $UrlFile, '-CacheFile', $MetadataCacheFile)
    $reviewArgs += @('-MinDurationSeconds', $MinDurationSeconds.ToString(), '-MaxDurationSeconds', $MaxDurationSeconds.ToString())
    if ($ExistingUrlFile) {
        $reviewArgs += @('-ExistingUrlFile', $ExistingUrlFile)
    }
    $summary = ''
    & powershell @reviewArgs 2>> $UrlLog | ForEach-Object {
        $line = "$_"
        if ($line -match '^\d+\|\d+\|\d+\|\d+$') {
            $summary = $line
        } else {
            Write-Host $line
        }
    }
    if ($LASTEXITCODE -ne 0) { throw 'Video review failed. Check video builder logs.' }
    if (-not $summary) { $summary = '0|0|0|0' }
    $parts = "$summary".Split('|')
    $kept = if ($parts.Count -gt 0) { $parts[0] } else { '0' }
    $skipped = if ($parts.Count -gt 1) { $parts[1] } else { '0' }
    $cacheHits = if ($parts.Count -gt 2) { $parts[2] } else { '0' }
    $checked = if ($parts.Count -gt 3) { $parts[3] } else { '0' }
    Write-Host "Approved videos: $kept"
    Write-Host "Removed or skipped: $skipped"
    Write-Host "Used cached review info: $cacheHits"
    Write-Host "New videos reviewed online: $checked"
}

function New-UrlSnapshot {
    if (-not (Test-Path -LiteralPath $UrlFile)) {
        New-Item -ItemType File -Path $UrlFile -Force | Out-Null
    }
    $snapshot = Join-Path $env:TEMP ("jukebox_gui_existing_urls_{0}.tmp" -f ([guid]::NewGuid().ToString('N')))
    Copy-Item -LiteralPath $UrlFile -Destination $snapshot -Force
    return $snapshot
}

function Add-Video {
    param([string]$Url)
    if (-not (Test-YouTubeUrl $Url)) { throw 'Expected a YouTube video.' }
    $snapshot = New-UrlSnapshot
    try {
        Add-Content -LiteralPath $UrlFile -Value $Url -Encoding ASCII
        Write-Host 'Added video. Reviewing list...'
        Invoke-ReviewUrls -ExistingUrlFile $snapshot
    } finally {
        if (Test-Path -LiteralPath $snapshot) { Remove-Item -LiteralPath $snapshot -Force }
    }
}

function Video-Preview {
    param([string]$Url)
    if (-not (Test-YouTubeUrl $Url)) { throw 'Expected a YouTube video.' }
    Ensure-Tool 'yt-dlp'
    Set-DenoEnvironment

    $tmp = Join-Path $ResourceTempDir 'jukebox_video_preview_candidates.txt'
    $previewFile = Join-Path $ResourceTempDir 'jukebox_video_preview.tsv'
    Set-Content -LiteralPath $tmp -Value $Url -Encoding ASCII
    if (Test-Path -LiteralPath $previewFile) { Remove-Item -LiteralPath $previewFile -Force }

    try {
        Write-Host 'Reviewing video...'
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LibDir 'review_urls.ps1') -UrlFile $tmp -ExistingUrlFile $UrlFile -MinDurationSeconds $MinDurationSeconds -MaxDurationSeconds $MaxDurationSeconds -OutputDetailsFile $previewFile -CacheFile $MetadataCacheFile -EnrichMusicBrainzMetadata 2>&1 | Tee-Object -FilePath $UrlLog -Append
        if ($LASTEXITCODE -ne 0) { throw 'Video review failed.' }
        Write-Host "PREVIEW_FILE|$previewFile"
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    }
}

function Import-Source {
    param([string]$Url, [int]$Limit)
    if (-not (Test-YouTubeUrl $Url)) { throw 'Expected a YouTube playlist, channel, or video.' }
    Ensure-Tool 'yt-dlp'
    Set-DenoEnvironment
    $tmp = Join-Path $env:TEMP ("jukebox_gui_source_{0}.tmp" -f ([guid]::NewGuid().ToString('N')))
    $snapshot = New-UrlSnapshot
    try {
        $env:JUKEBOX_SOURCE_URL = $Url
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LibDir 'source_youtube.ps1') -Limit $Limit -OutputFile $tmp 2>> $UrlLog
        if ($LASTEXITCODE -ne 0) { throw 'Source import failed. Check video builder logs.' }
        if (Test-Path -LiteralPath $tmp) {
            Get-Content -LiteralPath $tmp | Add-Content -LiteralPath $UrlFile -Encoding ASCII
        }
        Write-Host 'Imported source videos. Reviewing list...'
        Invoke-ReviewUrls -ExistingUrlFile $snapshot
    } finally {
        $env:JUKEBOX_SOURCE_URL = $null
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
        if (Test-Path -LiteralPath $snapshot) { Remove-Item -LiteralPath $snapshot -Force }
    }
}

function Search-Videos {
    param([string]$Text, [int]$Limit)
    if ([string]::IsNullOrWhiteSpace($Text)) { throw 'Enter search text first.' }
    if ($Limit -lt 1) { $Limit = 25 }
    if ($Limit -gt $MaxSearchLimit) { $Limit = $MaxSearchLimit }
    Ensure-Tool 'yt-dlp'
    Set-DenoEnvironment
    $tmp = Join-Path $env:TEMP ("jukebox_gui_search_{0}.tmp" -f ([guid]::NewGuid().ToString('N')))
    $snapshot = New-UrlSnapshot
    Copy-Item -LiteralPath $snapshot -Destination $CancelSnapshotFile -Force
    try {
        $env:JUKEBOX_SEARCH_TEXT = $Text
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LibDir 'search_youtube.ps1') -Limit $Limit -OutputFile $tmp 2>> $UrlLog
        if ($LASTEXITCODE -ne 0) { throw 'YouTube search failed. Check video builder logs.' }
        if (Test-Path -LiteralPath $tmp) {
            Get-Content -LiteralPath $tmp | Add-Content -LiteralPath $UrlFile -Encoding ASCII
        }
        Write-Host 'Added search candidates. Reviewing list...'
        Invoke-ReviewUrls -ExistingUrlFile $snapshot
        if (Test-Path -LiteralPath $CancelSnapshotFile) { Remove-Item -LiteralPath $CancelSnapshotFile -Force }
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
        if (Test-Path -LiteralPath $snapshot) { Remove-Item -LiteralPath $snapshot -Force }
        $env:JUKEBOX_SEARCH_TEXT = $null
    }
}

function Search-VideosPreview {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { throw 'Enter search text first.' }
    Ensure-Tool 'yt-dlp'
    Set-DenoEnvironment

    $tmp = Join-Path $ResourceTempDir 'jukebox_search_preview_candidates.txt'
    $previewFile = Join-Path $ResourceTempDir 'jukebox_search_preview.tsv'
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    if (Test-Path -LiteralPath $previewFile) { Remove-Item -LiteralPath $previewFile -Force }

    try {
        $env:JUKEBOX_SEARCH_TEXT = $Text
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LibDir 'search_youtube.ps1') -Limit $MaxSearchLimit -OutputFile $tmp -TimeoutSeconds 60 2>&1 | Tee-Object -FilePath $UrlLog -Append
        if (-not (Test-Path -LiteralPath $tmp)) {
            New-Item -ItemType File -Path $tmp -Force | Out-Null
        }

        Write-Host 'Reviewing search candidates...'
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LibDir 'review_urls.ps1') -UrlFile $tmp -ExistingUrlFile $UrlFile -MinDurationSeconds $MinDurationSeconds -MaxDurationSeconds $MaxDurationSeconds -OutputDetailsFile $previewFile -CacheFile $MetadataCacheFile -EnrichMusicBrainzMetadata 2>&1 | Tee-Object -FilePath $UrlLog -Append
        if ($LASTEXITCODE -ne 0) { throw 'Search candidate review failed.' }
        Write-Host "PREVIEW_FILE|$previewFile"
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
        $env:JUKEBOX_SEARCH_TEXT = $null
    }
}

function Source-VideosPreview {
    param([string]$Url)
    if (-not (Test-YouTubeUrl $Url)) { throw 'Expected a YouTube playlist, channel, or video.' }
    Ensure-Tool 'yt-dlp'
    Set-DenoEnvironment

    $tmp = Join-Path $ResourceTempDir 'jukebox_source_preview_candidates.txt'
    $previewFile = Join-Path $ResourceTempDir 'jukebox_source_preview.tsv'
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    if (Test-Path -LiteralPath $previewFile) { Remove-Item -LiteralPath $previewFile -Force }

    try {
        $env:JUKEBOX_SOURCE_URL = $Url
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LibDir 'source_youtube.ps1') -Limit $MaxSourceLimit -OutputFile $tmp 2>&1 | Tee-Object -FilePath $UrlLog -Append
        if (-not (Test-Path -LiteralPath $tmp)) {
            New-Item -ItemType File -Path $tmp -Force | Out-Null
        }

        Write-Host 'Reviewing source candidates...'
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LibDir 'review_urls.ps1') -UrlFile $tmp -ExistingUrlFile $UrlFile -MinDurationSeconds $MinDurationSeconds -MaxDurationSeconds $MaxDurationSeconds -OutputDetailsFile $previewFile -CacheFile $MetadataCacheFile -EnrichMusicBrainzMetadata 2>&1 | Tee-Object -FilePath $UrlLog -Append
        if ($LASTEXITCODE -ne 0) { throw 'Source candidate review failed.' }
        Write-Host "PREVIEW_FILE|$previewFile"
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
        $env:JUKEBOX_SOURCE_URL = $null
    }
}

function Source-VideosCount {
    param([string]$Url)
    if (-not (Test-YouTubeUrl $Url)) { throw 'Expected a YouTube playlist, channel, or video.' }
    Ensure-Tool 'yt-dlp'
    Set-DenoEnvironment

    $tmp = Join-Path $env:TEMP ("jukebox_gui_source_count_{0}.tmp" -f ([guid]::NewGuid().ToString('N')))
    try {
        $env:JUKEBOX_SOURCE_URL = $Url
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LibDir 'source_youtube.ps1') -Limit $MaxSourceLimit -OutputFile $tmp 2>&1 | Tee-Object -FilePath $UrlLog -Append
        if ($LASTEXITCODE -ne 0) { throw 'Source count failed. Check video builder logs.' }
        $count = 0
        if (Test-Path -LiteralPath $tmp) {
            $count = @(Get-Content -LiteralPath $tmp | Where-Object { $_.Trim() }).Count
        }
        Write-Host "SOURCE_COUNT|$count"
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
        $env:JUKEBOX_SOURCE_URL = $null
    }
}

function Restore-CancelSnapshot {
    if (Test-Path -LiteralPath $CancelSnapshotFile) {
        Copy-Item -LiteralPath $CancelSnapshotFile -Destination $UrlFile -Force
        Remove-Item -LiteralPath $CancelSnapshotFile -Force
        $count = @(Get-Content -LiteralPath $UrlFile -ErrorAction SilentlyContinue | Where-Object { $_.Trim() }).Count
        Write-Host "Cancelled search. Video list was restored to its original state ($count video(s))."
    }
}

function Clear-Urls {
    Set-Content -LiteralPath $UrlFile -Value @() -Encoding ASCII
    Write-Host 'Cleared the saved video list.'
    Write-Host 'Saved video review cache was kept for future searches.'
}

function Validate-CookieFile {
    if (-not (Test-Path -LiteralPath $CookieFile)) { throw "Cookie file not found: $CookieFile" }
    if ((Get-Item -LiteralPath $CookieFile).Length -le 0) { throw "Cookie file is empty: $CookieFile" }
    $first = Get-Content -LiteralPath $CookieFile -TotalCount 1
    if ($first -ne '# Netscape HTTP Cookie File') { throw "Cookie file is not in Netscape format: $CookieFile" }
    Write-Host 'Cookie file is ready.'
}

function Get-ApprovedUrls {
    if (-not (Test-Path -LiteralPath $UrlFile)) { throw "Video list file not found: $UrlFile" }
    $urls = @(Get-Content -LiteralPath $UrlFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    if ($urls.Count -eq 0) { throw 'Video list contains no valid video entries.' }
    foreach ($url in $urls) {
        if ($url -notmatch '^https?://') { throw "Invalid video entry: $url" }
    }
    return $urls
}

function Validate-Setup {
    Ensure-Tool 'yt-dlp'
    Ensure-Tool 'ffmpeg'
    Write-Host "yt-dlp: $(Get-ToolLocationLabel (Get-ToolSource 'yt-dlp'))"
    Write-Host "ffmpeg: $(Get-ToolLocationLabel (Get-ToolSource 'ffmpeg'))"
    $deno = Get-DenoSource
    if ($deno) {
        Write-Host "Deno JavaScript runtime: $(Get-ToolLocationLabel $deno)"
    } else {
        Write-Host "Deno JavaScript runtime: not found. Add deno.exe to assets\tools or assets\tools\deno if YouTube reports signature solving warnings."
    }
    Validate-CookieFile
    $urls = Get-ApprovedUrls
    Write-Host "Video list contains $($urls.Count) video(s)."
    Write-Host 'Validation completed successfully. No downloads were attempted.'
}

function Invoke-YtDlpDownload {
    param([string[]]$Arguments)

    $currentPart = ''
    $completedParts = @{}
    & yt-dlp @Arguments 2>&1 | ForEach-Object {
        $line = "$_"
        Add-Content -LiteralPath $DownloadLog -Value $line -Encoding ASCII

        if ($line -match '^\[download\]\s+Destination:\s+(.+)$') {
            $destination = $matches[1]
            $ext = [System.IO.Path]::GetExtension($destination).ToLowerInvariant()
            if ($ext -eq '.mp4') {
                $currentPart = 'mp4'
                $completedParts[$currentPart] = $false
                Write-Host 'Part 1 of 2 (.mp4) download started.'
            } elseif ($ext -eq '.m4a') {
                $currentPart = 'm4a'
                $completedParts[$currentPart] = $false
                Write-Host 'Part 2 of 2 (.m4a) download started.'
            } else {
                $currentPart = ''
                Write-Host $line
            }
        } elseif ($line -match '^\[download\]\s+100(?:\.0)?%') {
            if ($currentPart -and -not ($completedParts.ContainsKey($currentPart) -and $completedParts[$currentPart])) {
                $completedParts[$currentPart] = $true
                if ($currentPart -eq 'mp4') {
                    Write-Host 'Part 1 of 2 (.mp4) download completed.'
                } elseif ($currentPart -eq 'm4a') {
                    Write-Host 'Part 2 of 2 (.m4a) download completed.'
                }
            }
        } elseif ($line -notmatch '^\[download\]') {
            Write-Host $line
        }
    }

    return $LASTEXITCODE
}

function New-DownloadSnapshot {
    Get-ChildItem -LiteralPath $DownloadDir -File -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object { $_.FullName } |
        Set-Content -LiteralPath $DownloadSnapshotFile -Encoding ASCII
}

function Restore-DownloadSnapshot {
    if (-not (Test-Path -LiteralPath $DownloadSnapshotFile)) { return }

    $before = @{}
    Get-Content -LiteralPath $DownloadSnapshotFile -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_) { $before[$_] = $true }
    }

    $discardDir = Join-Path $DownloadDir 'discard'
    New-Item -ItemType Directory -Path $discardDir -Force | Out-Null
    $moved = 0
    Get-ChildItem -LiteralPath $DownloadDir -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notlike "$discardDir*" -and -not $before.ContainsKey($_.FullName) } |
        ForEach-Object {
            $destination = Get-UniqueDestinationPath -Folder $discardDir -FileName $_.Name
            Move-Item -LiteralPath $_.FullName -Destination $destination -Force
            $moved++
        }

    Remove-Item -LiteralPath $DownloadSnapshotFile -Force
    if ($moved -gt 0) {
        Write-Host "Cancelled download. New/partial files were moved to downloads\discard: $moved"
    }
}

function Get-DownloadFileSnapshot {
    $snapshot = @{}
    Get-ChildItem -LiteralPath $DownloadDir -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notlike "$(Join-Path $DownloadDir 'discard')*" } |
        ForEach-Object { $snapshot[$_.FullName] = $true }
    return $snapshot
}

function Get-NewDownloadFiles {
    param([hashtable]$Before)

    return @(Get-ChildItem -LiteralPath $DownloadDir -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notlike "$(Join-Path $DownloadDir 'discard')*" -and
            -not $Before.ContainsKey($_.FullName)
        })
}

function Invoke-AudioNormalization {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "Audio normalization skipped. File not found: $Path"
        return $false
    }

    $folder = Split-Path -Parent $Path
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $ext = [System.IO.Path]::GetExtension($Path)
    $temp = Join-Path $folder ("{0}.normalized{1}" -f $base, $ext)
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }

    $fileName = [System.IO.Path]::GetFileName($Path)
    Write-Host ("PROGRESS|Audio normalization|0|1|{0}" -f $fileName)
    Write-Host ("Normalizing audio: {0}" -f $fileName)
    Add-Content -LiteralPath $DownloadLog -Value "Normalizing audio: $Path" -Encoding ASCII
    $normalizeStart = Get-Date
    & ffmpeg -hide_banner -y -i $Path -c:v copy -af 'loudnorm=I=-16:TP=-1.5:LRA=11' -c:a aac -b:a 192k $temp 2>&1 |
        Tee-Object -FilePath $DownloadLog -Append | Out-Null
    $exit = $LASTEXITCODE
    $elapsed = New-TimeSpan -Start $normalizeStart -End (Get-Date)
    $elapsedText = '{0}:{1:00}' -f [int]$elapsed.TotalMinutes, $elapsed.Seconds
    if ($exit -eq 0 -and (Test-Path -LiteralPath $temp)) {
        Move-Item -LiteralPath $temp -Destination $Path -Force
        Write-Host "Audio normalization completed in $elapsedText."
        Write-Host ("PROGRESS|Audio normalization|1|1|Completed {0}" -f $fileName)
        return $true
    }

    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
    Write-Host "[ERROR] Audio normalization failed after $elapsedText. Original file was kept."
    Write-Host ("PROGRESS|Audio normalization|1|1|Failed {0}" -f $fileName)
    return $false
}

function Get-MediaDurationMilliseconds {
    param([string]$Path)

    try {
        $duration = (& ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 $Path 2>> $DownloadLog | Select-Object -First 1)
        if ($duration) {
            return [Math]::Max(1, [int]([double]$duration * 1000))
        }
    } catch {
    }
    return 100
}

function Download-Videos {
    Ensure-Tool 'yt-dlp'
    Ensure-Tool 'ffmpeg'
    Validate-CookieFile
    $urls = Get-ApprovedUrls
    Assert-MinFreeSpace -Path $DownloadDir -RequiredReserveBytes $DownloadDriveReserveBytes -Purpose 'PC downloads'
    New-DownloadSnapshot
    $success = 0
    $failed = 0
    $total = 0
    $format = if ($DownloadAudioOnly) { 'bestaudio/best' } else { "bestvideo[vcodec*=$VideoCodec][height<=$Height]+bestaudio[ext=$AudioExt]/best[ext=$VideoExt][height<=$Height]" }
    $outputControl = '%(title).70s.%(ext)s'
    $mediaLabel = if ($DownloadAudioOnly) { 'audio' } else { 'videos' }
    $newFileExtension = if ($DownloadAudioOnly) { '.mp3' } else { '.mp4' }
    Write-Host "Download log: $DownloadLog"

    foreach ($url in $urls) {
        $total++
        Assert-MinFreeSpace -Path $DownloadDir -RequiredReserveBytes $DownloadDriveReserveBytes -Purpose 'PC downloads'
        Write-Host ("PROGRESS|Downloading $mediaLabel|{0}|{1}|Starting download" -f $total, $urls.Count)
        $beforeThisDownload = Get-DownloadFileSnapshot
        $ejsArgs = Get-YtDlpEjsArgs
        $title = (& yt-dlp @ejsArgs --no-warnings --get-title --cookies $CookieFile $url 2>> $DownloadLog | Select-Object -First 1)
        if (-not $title) { $title = $url }
        Write-Host "[$total/$($urls.Count)] Processing: $title"
        $args = @()
        $args += $ejsArgs
        $args += @(
            '-N', $Processes,
            '--force-ipv4',
            '--socket-timeout', '60',
            '--retries', '10',
            '--fragment-retries', '10',
            '-f', $format
        )
        if ($DownloadAudioOnly) {
            $args += @('-x', '--audio-format', 'mp3', '--audio-quality', '0')
        } else {
            $args += @('--merge-output-format', $VideoExt)
        }
        $args += @(
            '--cookies', $CookieFile,
            '-P', $DownloadDir,
            '-o', $outputControl,
            '--windows-filenames',
            '--force-overwrites',
            '--no-cache-dir',
            '--newline',
            $url
        )
        $downloadExitCode = Invoke-YtDlpDownload -Arguments $args
        if ($downloadExitCode -eq 0) {
            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LibDir 'cleanup_filenames.ps1') -DownloadDir $DownloadDir -TotalLimit $FileNameTotalLimit 2>&1 | Tee-Object -FilePath $DownloadLog -Append
            $cleanupExitCode = $LASTEXITCODE
            if ($cleanupExitCode -eq 0) {
                $newFiles = @(Get-NewDownloadFiles -Before $beforeThisDownload | Where-Object { $_.Extension -ieq $newFileExtension })
                if ($NormalizeAudioEnabled -and -not $DownloadAudioOnly) {
                    foreach ($file in $newFiles) {
                        Invoke-AudioNormalization -Path $file.FullName | Out-Null
                    }
                }
                if ($GenerateStandardMarqueeEnabled -or $GenerateFullColorMarqueeEnabled) {
                    $marqueeIndex = 0
                    foreach ($file in $newFiles) {
                        $marqueeIndex++
                        Write-Host ("PROGRESS|Generating marquees|{0}|{1}|{2}" -f $marqueeIndex, $newFiles.Count, $file.BaseName)
                        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LibDir 'generate_marquees.ps1') -VideoPath $file.FullName -DownloadDir $DownloadDir -Standard $GenerateStandardMarqueeEnabled.ToString() -FullColor $GenerateFullColorMarqueeEnabled.ToString() 2>&1 | Tee-Object -FilePath $DownloadLog -Append
                        if ($LASTEXITCODE -ne 0) { throw "Marquee generation failed for $($file.Name)." }
                    }
                }
                $success++
                Write-Host '[SUCCESS]'
            } else {
                $failed++
                Write-Host '[ERROR] Filename cleanup failed.'
            }
        } else {
            $failed++
            Write-Host '[ERROR] Download failed. Check download log.'
        }
    }

    Write-Host "Finished. Total=$total Success=$success Failed=$failed"
    if (Test-Path -LiteralPath $DownloadSnapshotFile) { Remove-Item -LiteralPath $DownloadSnapshotFile -Force }
    if ($failed -gt 0) { exit 1 }
}

function Get-FileReviewKey {
    param([string]$FileName)

    $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $ext = [System.IO.Path]::GetExtension($FileName).ToLowerInvariant()
    if ($base -match '^\s*(.+?)\s+-\s+(.+?)\s*$') {
        $artist = $matches[1]
        $title = $matches[2].Trim()
        if ($title -match '^(.*?)\s*\(([^)]*)\)') {
            $title = ($matches[1] + ' ' + $matches[2]).Trim()
        } else {
            $title = $title -replace '[\(\[\{].*$', ' '
        }
        $title = $title -replace '\b(feat|ft|featuring)\.?\s+.*$', ' '
        $artistKey = $artist.Normalize('FormD') -replace '\p{Mn}', ''
        $titleKey = $title.Normalize('FormD') -replace '\p{Mn}', ''
        $key = "$artistKey $titleKey"
        $key = $key.ToLowerInvariant()
        $key = $key -replace '_+', ' '
        $key = $key -replace '["''`]', ' '
        $key = $key -replace '[^a-z0-9]+', ' '
        $key = $key -replace '\s+', ' '
        $key = $key.Trim()
        if (-not [string]::IsNullOrWhiteSpace($key)) { return "$ext|$key" }
    }

    $key = $base.Normalize('FormD') -replace '\p{Mn}', ''
    $key = $key.ToLowerInvariant()
    $key = $key -replace '_+', ' '
    $key = $key -replace '[\(\[\{][^\)\]\}]*[\)\]\}]', ' '
    $key = $key -replace '["''`]', ' '
    $key = $key -replace '\b(19|20)\d{2}\b', ' '
    $key = $key -replace '\b(official|music|video|trailer|teaser|clip|lyrics?|lyric|hd|uhd|4k|8k|remaster(ed)?|extended|full|version)\b', ' '
    $key = $key -replace '\b(1080p|720p|480p|2160p)\b', ' '
    $key = $key -replace '[^a-z0-9]+', ' '
    $key = $key -replace '\s+', ' '
    $key = $key.Trim()
    if ([string]::IsNullOrWhiteSpace($key)) { $key = $base.ToLowerInvariant().Trim() }
    return "$ext|$key"
}

function Get-UniqueDestinationPath {
    param([string]$Folder, [string]$FileName)

    $destination = Join-Path $Folder $FileName
    if (-not (Test-Path -LiteralPath $destination)) { return $destination }

    $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $ext = [System.IO.Path]::GetExtension($FileName)
    $n = 1
    do {
        $destination = Join-Path $Folder ("{0} ({1}){2}" -f $base, $n, $ext)
        $n++
    } while (Test-Path -LiteralPath $destination)
    return $destination
}

function Test-EligibleMoveTarget {
    param([string]$TargetPath)

    if ([string]::IsNullOrWhiteSpace($TargetPath)) {
        throw "Choose $SsdFolderName or a folder inside it before moving downloads."
    }

    $resolved = [System.IO.Path]::GetFullPath($TargetPath.Trim())
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw "Selected destination folder does not exist: $resolved"
    }

    $root = [System.IO.Path]::GetPathRoot($resolved)
    $drive = New-Object System.IO.DriveInfo($root)
    if (-not $drive.IsReady) {
        throw "Selected drive is not ready: $root"
    }

    $requiredRoot = Join-Path $root $SsdFolderName
    if (-not (Test-Path -LiteralPath $requiredRoot -PathType Container)) {
        throw "One saUCE build not detected. All downloads remain in $DownloadDir"
    }

    $resolvedTrimmed = $resolved.TrimEnd('\')
    $requiredTrimmed = ([System.IO.Path]::GetFullPath($requiredRoot)).TrimEnd('\')
    if (($resolvedTrimmed -ine $requiredTrimmed) -and (-not $resolvedTrimmed.StartsWith($requiredTrimmed + '\', [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "Selected destination must be $SsdFolderName or a folder inside it: $resolved"
    }

    return $resolved.TrimEnd('\')
}

function Generate-MarqueesForList {
    param([string]$ListFile)

    Ensure-Tool 'ffmpeg'
    if (-not ($GenerateStandardMarqueeEnabled -or $GenerateFullColorMarqueeEnabled)) {
        $script:GenerateStandardMarqueeEnabled = $true
    }
    if (-not (Test-Path -LiteralPath $ListFile)) { throw "Selected video list was not found: $ListFile" }
    $files = @(Get-Content -LiteralPath $ListFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and (Test-Path -LiteralPath $_) -and ([IO.Path]::GetExtension($_) -ieq '.mp4') })
    if ($files.Count -eq 0) { throw 'No MP4 files were selected for marquee generation.' }

    $index = 0
    foreach ($file in $files) {
        $index++
        $name = [IO.Path]::GetFileNameWithoutExtension($file)
        Write-Host ("PROGRESS|Generating marquees|{0}|{1}|{2}" -f $index, $files.Count, $name)
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LibDir 'generate_marquees.ps1') -VideoPath $file -DownloadDir $DownloadDir -Standard $GenerateStandardMarqueeEnabled.ToString() -FullColor $GenerateFullColorMarqueeEnabled.ToString() 2>&1 | Tee-Object -FilePath $DownloadLog -Append
        if ($LASTEXITCODE -ne 0) { throw "Marquee generation failed for $([IO.Path]::GetFileName($file))." }
    }
    Write-Host "Finished generating marquee artwork for $($files.Count) file(s). Output: $(Join-Path $DownloadDir 'marquee')"
}
function Get-UniqueSiblingPath {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $Path }
    $folder = Split-Path -Parent $Path
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $ext = [System.IO.Path]::GetExtension($Path)
    $n = 1
    do {
        $candidate = Join-Path $folder ("{0} ({1}){2}" -f $base, $n, $ext)
        $n++
    } while (Test-Path -LiteralPath $candidate)
    return $candidate
}

function Convert-Mp4ToMp3ForList {
    param([string]$ListFile)

    Ensure-Tool 'ffmpeg'
    if (-not (Test-Path -LiteralPath $ListFile)) { throw "Selected MP4 list was not found: $ListFile" }
    $files = @(Get-Content -LiteralPath $ListFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and (Test-Path -LiteralPath $_) -and ([IO.Path]::GetExtension($_) -ieq '.mp4') })
    if ($files.Count -eq 0) { throw 'No MP4 files were selected for MP3 conversion.' }

    $index = 0
    $converted = 0
    foreach ($file in $files) {
        $index++
        $name = [IO.Path]::GetFileNameWithoutExtension($file)
        $folder = Split-Path -Parent $file
        $target = Get-UniqueSiblingPath -Path (Join-Path $folder ($name + '.mp3'))
        Write-Host ("PROGRESS|Converting MP4s to MP3|{0}|{1}|{2}" -f $index, $files.Count, $name)
        Write-Host "Converting to MP3: $([IO.Path]::GetFileName($file))"
        & ffmpeg -hide_banner -y -i $file -vn -codec:a libmp3lame -q:a 0 $target 2>&1 | Tee-Object -FilePath $DownloadLog -Append | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $target)) { throw "MP3 conversion failed for $([IO.Path]::GetFileName($file))." }
        $converted++
        Write-Host "Created MP3: $target"
    }
    Write-Host "Finished converting $converted MP4 file(s) to MP3."
}

function Move-DownloadsToSsd {
    param([string]$TargetPath = '')

    $files = @(Get-ChildItem -LiteralPath $DownloadDir -File -Force -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) { throw 'Downloads folder is empty. Nothing to move.' }

    $target = Test-EligibleMoveTarget -TargetPath $TargetPath
    $moved = 0
    $discarded = 0
    $discardDir = Join-Path $DownloadDir 'discard'
    New-Item -ItemType Directory -Path $discardDir -Force | Out-Null

    $targetKeys = @{}
    Get-ChildItem -LiteralPath $target -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $targetKeys[(Get-FileReviewKey $_.Name)] = $_.Name
    }

    Write-Host "Moving downloads to: $target"
    $total = $files.Count
    $current = 0
    foreach ($file in $files) {
        $current++
        Write-Host ("PROGRESS|Moving to SSD|{0}|{1}|{2}" -f $current, $total, $file.Name)
        $reviewKey = Get-FileReviewKey $file.Name
        $destination = Join-Path $target $file.Name
        if ((Test-Path -LiteralPath $destination) -or $targetKeys.ContainsKey($reviewKey)) {
            $discardPath = Get-UniqueDestinationPath -Folder $discardDir -FileName $file.Name
            Move-Item -LiteralPath $file.FullName -Destination $discardPath
            $discarded++
            if ($targetKeys.ContainsKey($reviewKey)) {
                Write-Host "Duplicate moved to discard: $($file.Name) (matches $($targetKeys[$reviewKey]))"
            } else {
                Write-Host "Duplicate moved to discard: $($file.Name)"
            }
            continue
        }
        Move-Item -LiteralPath $file.FullName -Destination $destination
        $targetKeys[$reviewKey] = [System.IO.Path]::GetFileName($destination)
        $moved++
        Write-Host "Moved: $($file.Name)"
    }
    Write-Host "Finished moving $moved file(s). Duplicates moved to discard: $discarded"
}

try {
    Write-Log $UrlLog 'INFO' "GUI action started: $Action"
    switch ($Action) {
        'AddVideo' { Add-Video -Url $Value }
        'VideoPreview' { Video-Preview -Url $Value }
        'ImportSource' { Import-Source -Url $Value -Limit $Limit }
        'SourceCount' { Source-VideosCount -Url $Value }
        'SourcePreview' { Source-VideosPreview -Url $Value }
        'Search' { Search-Videos -Text $Value -Limit $Limit }
        'SearchPreview' { Search-VideosPreview -Text $Value }
        'Review' { Invoke-ReviewUrls }
        'Clear' { Clear-Urls }
        'Validate' { Validate-Setup }
        'Download' { Download-Videos }
        'GenerateMarquees' { Generate-MarqueesForList -ListFile $Value }
        'ConvertMp4ToMp3' { Convert-Mp4ToMp3ForList -ListFile $Value }
        'MoveToSsd' { Move-DownloadsToSsd -TargetPath $Value }
        'RollbackCancel' {
            Restore-CancelSnapshot
            Restore-DownloadSnapshot
        }
    }
} catch {
    Restore-CancelSnapshot
    if ($Action -eq 'Download') { Restore-DownloadSnapshot }
    $errorMessage = $_.Exception.Message
    Write-Log $UrlLog 'ERROR' $errorMessage
    if ($Action -eq 'Download') { Write-Log $DownloadLog 'ERROR' $errorMessage }
    Write-Host $errorMessage
    exit 1
} finally {
    if ($Action -ne 'Search' -and (Test-Path -LiteralPath $CancelSnapshotFile)) {
        Remove-Item -LiteralPath $CancelSnapshotFile -Force
    }
    if ($Action -ne 'Download' -and (Test-Path -LiteralPath $DownloadSnapshotFile)) {
        Remove-Item -LiteralPath $DownloadSnapshotFile -Force
    }
}

