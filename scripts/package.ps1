param(
    [string]$Version = '',
    [ValidateSet('', 'major', 'minor', 'patch', 'build')][string]$Bump = '',
    [switch]$NoBuild,
    [switch]$NoInstaller,
    [string]$InnoCompiler = ''
)

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$VersionFile = Join-Path $Root 'version.txt'
$ReadmeFile = Join-Path $Root 'README.md'
$AssemblyInfoFile = Join-Path $Root 'src\AssemblyInfo.cs'
$MainWindowFile = Join-Path $Root 'src\MainWindow.cs'
$InstallerFile = Join-Path $Root 'installer\JukeboxDownloadWizard.iss'
$InnoReadmeFile = Join-Path $Root 'installer\README_INNO_SETUP.txt'
$DistDir = Join-Path $Root 'dist'
$StageDir = Join-Path $Root '_release_stage'
$Utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false

function Write-Utf8File {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
}

function Get-CurrentVersion {
    $text = Get-Content -LiteralPath $VersionFile -Raw
    if ($text -notmatch 'Version:\s*(?<version>\d+\.\d+\.\d+\.\d+)') {
        throw "Could not find Version: x.x.x.x in $VersionFile"
    }
    return $Matches['version']
}

function Get-BumpedVersion {
    param([string]$Current, [string]$Part)
    [int[]]$pieces = $Current.Split('.') | ForEach-Object { [int]$_ }
    if ($pieces.Count -ne 4) { throw "Version must have four parts: $Current" }
    switch ($Part) {
        'major' { $pieces[0]++; $pieces[1] = 0; $pieces[2] = 0; $pieces[3] = 0 }
        'minor' { $pieces[1]++; $pieces[2] = 0; $pieces[3] = 0 }
        'patch' { $pieces[2]++; $pieces[3] = 0 }
        'build' { $pieces[3]++ }
        default { throw "Unknown bump part: $Part" }
    }
    return ($pieces -join '.')
}

function Assert-Version {
    param([string]$Value)
    if ($Value -notmatch '^\d+\.\d+\.\d+\.\d+$') {
        throw "Version must be in x.x.x.x format. Received: $Value"
    }
}

function Set-TextFileVersion {
    param([string]$Path, [string]$Old, [string]$New)
    $text = Get-Content -LiteralPath $Path -Raw
    $text = $text -replace [regex]::Escape($Old), $New
    $text = [regex]::Replace($text, 'JukeboxDownloadWizard/\d+\.\d+\.\d+\.\d+', "JukeboxDownloadWizard/$New")
    $text = [regex]::Replace($text, '(?m)^Version:\s*\d+\.\d+\.\d+\.\d+', "Version: $New")
    Write-Utf8File -Path $Path -Text ($text.TrimEnd() + [Environment]::NewLine)
}

function Update-VersionFiles {
    param([string]$OldVersion, [string]$NewVersion)

    $today = Get-Date -Format 'yyyy-MM-dd'
    $versionText = @(
        'Jukebox Download Wizard',
        "Version: $NewVersion",
        "Date: $today",
        'Author: Steve Hammoud'
    ) -join [Environment]::NewLine
    Write-Utf8File -Path $VersionFile -Text ($versionText + [Environment]::NewLine)

    foreach ($path in @($AssemblyInfoFile, $MainWindowFile, $InstallerFile, $InnoReadmeFile, $ReadmeFile)) {
        if (Test-Path -LiteralPath $path) { Set-TextFileVersion -Path $path -Old $OldVersion -New $NewVersion }
    }

    $metadataScripts = @(
        (Join-Path $Root 'assets\lib\album_art_lookup.ps1'),
        (Join-Path $Root 'assets\lib\generate_marquees.ps1'),
        (Join-Path $Root 'assets\lib\musicbrainz_metadata_lookup.ps1')
    )
    foreach ($path in $metadataScripts) {
        if (Test-Path -LiteralPath $path) { Set-TextFileVersion -Path $path -Old $OldVersion -New $NewVersion }
    }
}

function Assert-RequiredFile {
    param([string]$Path, [string]$Message)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw $Message }
}

function Assert-RequiredTools {
    $required = @(
        'assets\tools\yt-dlp.exe',
        'assets\tools\deno\deno.exe',
        'assets\tools\ffmpeg\bin\ffmpeg.exe',
        'assets\tools\ffmpeg\bin\ffprobe.exe'
    )
    foreach ($relative in $required) {
        Assert-RequiredFile -Path (Join-Path $Root $relative) -Message "Missing required local packaging tool: $relative"
    }
}

function Find-InnoCompiler {
    if (-not [string]::IsNullOrWhiteSpace($InnoCompiler)) {
        Assert-RequiredFile -Path $InnoCompiler -Message "Inno compiler not found: $InnoCompiler"
        return $InnoCompiler
    }

    $candidates = @(
        'C:\Users\steve\AppData\Local\Programs\Inno Setup 6\ISCC.exe',
        'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
        'C:\Program Files\Inno Setup 6\ISCC.exe'
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }

    $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw 'Inno Setup compiler ISCC.exe was not found. Install Inno Setup or pass -InnoCompiler.'
}

function Assert-ReleaseStubs {
    Assert-RequiredFile -Path (Join-Path $Root 'resources\ytcookies.example.txt') -Message 'Missing resources\ytcookies.example.txt'
    Assert-RequiredFile -Path (Join-Path $Root 'resources\jukebox_urls.example.txt') -Message 'Missing resources\jukebox_urls.example.txt'
    Assert-RequiredFile -Path (Join-Path $Root 'resources\fanart_personal_api_key.example.txt') -Message 'Missing resources\fanart_personal_api_key.example.txt'
}

function Clear-PackageRuntimeData {
    $runtimePaths = @(
        (Join-Path $Root 'assets\resources\cache'),
        (Join-Path $Root 'assets\resources\temp'),
        (Join-Path $Root 'downloads'),
        (Join-Path $Root 'logs'),
        (Join-Path $Root '.jukebox_download_wizard')
    )
    foreach ($path in $runtimePaths) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}

function New-CleanDirectory {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function New-ReleaseZip {
    param([string]$ZipPath, [string]$SetupExe)
    if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
    New-CleanDirectory -Path $StageDir
    Copy-Item -LiteralPath $SetupExe -Destination $StageDir
    Copy-Item -LiteralPath $ReadmeFile -Destination (Join-Path $StageDir 'README.md')
    Copy-Item -LiteralPath $VersionFile -Destination $StageDir
    Compress-Archive -Path (Join-Path $StageDir '*') -DestinationPath $ZipPath -CompressionLevel Optimal
    Remove-Item -LiteralPath $StageDir -Recurse -Force
}

function Assert-ZipContents {
    param([string]$ZipPath, [string]$ExpectedSetupName)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entries = @($zip.Entries | ForEach-Object { $_.FullName })
    }
    finally {
        $zip.Dispose()
    }

    $expected = @($ExpectedSetupName, 'README.md', 'version.txt') | Sort-Object
    $actual = @($entries | Sort-Object)
    if (($actual -join '|') -ne ($expected -join '|')) {
        throw "Unexpected ZIP contents in $ZipPath. Expected: $($expected -join ', ') Actual: $($actual -join ', ')"
    }
}

$currentVersion = Get-CurrentVersion
$newVersion = $Version.Trim()
if ([string]::IsNullOrWhiteSpace($newVersion) -and -not [string]::IsNullOrWhiteSpace($Bump)) {
    $newVersion = Get-BumpedVersion -Current $currentVersion -Part $Bump
}
if ([string]::IsNullOrWhiteSpace($newVersion)) { $newVersion = $currentVersion }
Assert-Version -Value $newVersion

if ($newVersion -ne $currentVersion) {
    Write-Host "Updating version: $currentVersion -> $newVersion"
}
else {
    Write-Host "Packaging version: $newVersion"
}
Update-VersionFiles -OldVersion $currentVersion -NewVersion $newVersion

Assert-ReleaseStubs
Assert-RequiredTools
Clear-PackageRuntimeData
New-Item -ItemType Directory -Path $DistDir -Force | Out-Null

if (-not $NoBuild) {
    Write-Host 'Building application executable...'
    & (Join-Path $PSScriptRoot 'build.ps1')
}

$setupExe = Join-Path $DistDir "JukeboxDownloadWizard_Setup_v$newVersion.exe"
if (-not $NoInstaller) {
    $iscc = Find-InnoCompiler
    Write-Host "Compiling installer with $iscc..."
    & $iscc $InstallerFile
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE" }
}
Assert-RequiredFile -Path $setupExe -Message "Expected setup executable was not created: $setupExe"

$versionZip = Join-Path $DistDir "JukeboxDownloadWizard_Setup_v$newVersion.zip"
$genericZip = Join-Path $DistDir 'JukeboxDownloadWizard.zip'
$setupName = Split-Path -Leaf $setupExe

Write-Host 'Creating release ZIP files...'
New-ReleaseZip -ZipPath $versionZip -SetupExe $setupExe
New-ReleaseZip -ZipPath $genericZip -SetupExe $setupExe
Assert-ZipContents -ZipPath $versionZip -ExpectedSetupName $setupName
Assert-ZipContents -ZipPath $genericZip -ExpectedSetupName $setupName

Write-Host ''
Write-Host 'Release package complete:'
Write-Host "  $versionZip"
Write-Host "  $genericZip"

