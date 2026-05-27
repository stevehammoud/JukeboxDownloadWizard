param(
    [string]$SearchText = '',
    [Parameter(Mandatory=$true)][int]$Limit,
    [Parameter(Mandatory=$true)][string]$OutputFile,
    [int]$TimeoutSeconds = 900
)

if ($env:JUKEBOX_SEARCH_TEXT) {
    $SearchText = $env:JUKEBOX_SEARCH_TEXT
}
if ([string]::IsNullOrWhiteSpace($SearchText)) {
    throw 'Enter search text first.'
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

function Stop-ProcessTree {
    param([int]$ProcessId)
    try {
        & taskkill.exe /PID $ProcessId /T /F | Out-Null
    } catch {
        try { Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
}

function Quote-Arg {
    param([string]$Value)
    return '"' + ($Value -replace '"', '\"') + '"'
}

if ($SearchText -notmatch '"') {
    $SearchText = '"' + $SearchText + '"'
}
$target = 'ytsearch' + $Limit + ':' + $SearchText
$arguments = @()
$arguments += Get-YtDlpEjsArgs
$arguments += @('--flat-playlist', '--ignore-errors', '--print', '%(webpage_url)s', $target)
$argumentText = ($arguments | ForEach-Object { Quote-Arg $_ }) -join ' '
$stdoutFile = Join-Path $env:TEMP ("jukebox_search_stdout_{0}.tmp" -f ([guid]::NewGuid().ToString('N')))
$stderrFile = Join-Path $env:TEMP ("jukebox_search_stderr_{0}.tmp" -f ([guid]::NewGuid().ToString('N')))

try {
    $p = Start-Process -FilePath 'yt-dlp' -ArgumentList $argumentText -NoNewWindow -PassThru -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
    if (-not $p) { throw 'Could not start yt-dlp search.' }

    $start = Get-Date
    $lastProgressBucket = 0
    while (-not $p.HasExited) {
        Start-Sleep -Milliseconds 250
        if (Test-Path -LiteralPath $stdoutFile) {
            $liveCount = @((Get-Content -LiteralPath $stdoutFile -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })).Count
            $bucket = [Math]::Floor($liveCount / 25)
            if ($bucket -gt $lastProgressBucket) {
                $lastProgressBucket = $bucket
                Write-Host ("PROGRESS|Searching YouTube|{0}|{1}|Found {0} candidate URL(s)" -f $liveCount, $Limit)
            }
        }
        if (((Get-Date) - $start).TotalSeconds -gt $TimeoutSeconds) {
            Stop-ProcessTree -ProcessId $p.Id
            break
        }
    }

    $count = 0
    if (Test-Path -LiteralPath $stdoutFile) {
        Get-Content -LiteralPath $stdoutFile | ForEach-Object {
            $line = $_.Trim()
            if ($line) {
                Add-Content -LiteralPath $OutputFile -Value $line -Encoding ASCII
                $count++
            }
        }
    }

    Write-Host "Found $count candidate URL(s)."
    if ($p.ExitCode -ne 0 -and (Test-Path -LiteralPath $stderrFile)) {
        $err = @(Get-Content -LiteralPath $stderrFile | Select-Object -Last 5)
        if ($err.Count -gt 0) { Write-Host ($err -join [Environment]::NewLine) }
    }
    exit $p.ExitCode
} finally {
    if ($p -and -not $p.HasExited) {
        Stop-ProcessTree -ProcessId $p.Id
    }
    if (Test-Path -LiteralPath $stdoutFile) { Remove-Item -LiteralPath $stdoutFile -Force }
    if (Test-Path -LiteralPath $stderrFile) { Remove-Item -LiteralPath $stderrFile -Force }
}
