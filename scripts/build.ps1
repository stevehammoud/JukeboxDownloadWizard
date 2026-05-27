$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Out = Join-Path $Root "JukeboxDownloadWizard.exe"
$Icon = Join-Path $Root "assets\images\JukeboxDownloadWizard.ico"
$RefRoot64 = "C:\Windows\Microsoft.NET\assembly\GAC_64"
$RefRootMsil = "C:\Windows\Microsoft.NET\assembly\GAC_MSIL"
$Refs = @(
    "$RefRoot64\PresentationCore\v4.0_4.0.0.0__31bf3856ad364e35\PresentationCore.dll",
    "$RefRootMsil\PresentationFramework\v4.0_4.0.0.0__31bf3856ad364e35\PresentationFramework.dll",
    "$RefRootMsil\WindowsBase\v4.0_4.0.0.0__31bf3856ad364e35\WindowsBase.dll",
    "$RefRootMsil\System.Xaml\v4.0_4.0.0.0__b77a5c561934e089\System.Xaml.dll"
)
$RefArgs = $Refs | ForEach-Object { "/reference:$_" }
& "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:winexe /platform:anycpu "/out:$Out" "/win32icon:$Icon" $RefArgs /reference:System.Windows.Forms.dll /reference:System.Drawing.dll (Join-Path $Root "src\AssemblyInfo.cs") (Join-Path $Root "src\Program.cs") (Join-Path $Root "src\MainWindow.cs")
