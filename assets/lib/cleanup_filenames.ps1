param(
    [Parameter(Mandatory=$true)][string]$DownloadDir,
    [int]$TotalLimit = 75
)

if (-not (Test-Path -LiteralPath $DownloadDir)) { return }

function Repair-UnknownArtistName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $Name }

    $candidate = $Name.Trim()
    if ($candidate -match '(?i)^\s*(unknown\s+artist|artist\s+unknown|unknown)\s*[-:|]\s*(?<rest>.+?)\s*$') {
        $rest = $Matches['rest'].Trim()
        if ($rest -match '^\s*(?<artist>[^-|:]{2,80}?)\s+[-|:]\s+(?<title>.+?)\s*$') {
            return ($Matches['artist'].Trim() + ' - ' + $Matches['title'].Trim())
        }
        return $rest
    }

    return $candidate
}
Get-ChildItem -LiteralPath $DownloadDir -File | ForEach-Object {
    $ext = $_.Extension
    $BaseLimit = [Math]::Max(1, $TotalLimit - $ext.Length)
    $name = Repair-UnknownArtistName $_.BaseName
    $name = $name -replace ([string][char]0xfffd + '\??'), ''
    $name = $name -replace [string][char]0xfffd, ''
    $name = $name.Normalize('FormD') -replace '\p{Mn}', ''
    $name = $name -replace '\[', '(' -replace '\]', ')'
    $name = $name -replace '_+', ' '
    $name = $name -replace "[^A-Za-z0-9 '`$!&@\-\._\(\)]", ' '
    $name = $name -replace '\s+', ' '
    $name = $name.Trim(' ', '.', '_', '-')
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'video' }
    if ($name.Length -gt $BaseLimit) {
        $name = $name.Substring(0, $BaseLimit).Trim('.', '_', '-')
    }
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'video' }

    $candidate = $name + $ext
    $candidatePath = Join-Path $DownloadDir $candidate
    if ((Test-Path -LiteralPath $candidatePath) -and ($candidate -ine $_.Name)) {
        Remove-Item -LiteralPath $candidatePath -Force
        Write-Host "Replaced existing file: $candidate"
    }

    if ($candidate -cne $_.Name) {
        Rename-Item -LiteralPath $_.FullName -NewName $candidate
    }
}

