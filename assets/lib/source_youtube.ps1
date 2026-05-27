param(
    [string]$SourceUrl = $env:JUKEBOX_SOURCE_URL,
    [Parameter(Mandatory=$true)][int]$Limit,
    [Parameter(Mandatory=$true)][string]$OutputFile
)

if ([string]::IsNullOrWhiteSpace($SourceUrl)) {
    throw 'No source URL was provided.'
}

if (Test-Path -LiteralPath $OutputFile) {
    Remove-Item -LiteralPath $OutputFile -Force
}

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

if ($SourceUrl -match '[?&]list=([^&]+)') {
    $SourceUrl = 'https://www.youtube.com/playlist?list=' + $matches[1]
}

$urls = New-Object System.Collections.Generic.List[string]
$seen = @{}
$chunkSize = 100
$maxItems = if ($Limit -gt 0) { $Limit } else { 5000 }
$start = 1
$lastExitCode = 0

while ($start -le $maxItems) {
    $end = [Math]::Min($start + $chunkSize - 1, $maxItems)
    $args = @()
    $args += Get-YtDlpEjsArgs
    $args += @('--flat-playlist', '--ignore-errors', '--playlist-start', $start.ToString(), '--playlist-end', $end.ToString(), '--print', '%(webpage_url)s', $SourceUrl)

    $batch = @(& yt-dlp @args)
    $lastExitCode = $LASTEXITCODE
    if ($lastExitCode -ne 0) { break }

    $addedThisBatch = 0
    foreach ($url in $batch) {
        $clean = "$url".Trim()
        if (-not $clean) { continue }
        if ($seen.ContainsKey($clean)) { continue }
        $seen[$clean] = $true
        $urls.Add($clean)
        $addedThisBatch++
    }

    if ($batch.Count -lt $chunkSize -or $addedThisBatch -eq 0) { break }
    $start += $chunkSize
}

$urls | Set-Content -LiteralPath $OutputFile -Encoding ASCII
exit $lastExitCode
