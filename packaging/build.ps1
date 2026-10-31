param(
    [string]$PayloadDirectory,
    [string]$PayloadZip,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [switch]$StageOnly
)

$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe'
}
if (-not (Test-Path -LiteralPath $compiler)) { throw 'The Windows .NET Framework C# compiler is required.' }
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

# Native icon is drawn from vector primitives; no external artwork or font files.
$iconPath = Join-Path $PSScriptRoot 'Lucky.ico'
if (-not (Test-Path -LiteralPath $iconPath)) {
    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object Drawing.Bitmap 256,256
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([Drawing.Color]::Black)
    $white = New-Object Drawing.SolidBrush ([Drawing.Color]::White)
    $graphics.FillRectangle($white, 58, 46, 31, 159)
    $graphics.FillRectangle($white, 58, 174, 139, 31)
    $graphics.FillEllipse($white, 163, 46, 34, 34)
    $icon = [Drawing.Icon]::FromHandle($bitmap.GetHicon())
    $stream = [IO.File]::Create($iconPath)
    try { $icon.Save($stream) } finally { $stream.Dispose(); $graphics.Dispose(); $white.Dispose(); $bitmap.Dispose() }
}

$baseArgs = @('/nologo','/target:winexe','/platform:x64','/optimize+','/codepage:65001',('/win32icon:' + $iconPath),'/reference:System.Windows.Forms.dll','/reference:System.Drawing.dll','/reference:System.Web.Extensions.dll')

if ($PayloadDirectory) {
    $payloadRoot = [IO.Path]::GetFullPath($PayloadDirectory)
    New-Item -ItemType Directory -Path $payloadRoot -Force | Out-Null
    & $compiler @baseArgs ('/out:' + (Join-Path $payloadRoot 'Lucky.exe')) (Join-Path $PSScriptRoot 'Bootstrap.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Lucky launcher compilation failed.' }
    & $compiler @baseArgs '/define:UNINSTALL' ('/out:' + (Join-Path $payloadRoot 'Uninstall.exe')) (Join-Path $PSScriptRoot 'Bootstrap.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Lucky uninstaller compilation failed.' }
    Write-Output 'Compiled Lucky.exe and Uninstall.exe into the payload.'
}

if (-not $StageOnly) {
    if (-not $PayloadZip -or -not (Test-Path -LiteralPath $PayloadZip)) { throw 'Pass -PayloadZip with the completed archive, or use -StageOnly to compile the launcher first.' }
    $archivePath = [IO.Path]::GetFullPath($PayloadZip)
    $installerPath = Join-Path $outputRoot 'Lucky-Setup-0.1.0-beta-windows-x64.exe'
    $installerArgs = $baseArgs + @('/reference:System.IO.Compression.dll','/reference:System.IO.Compression.FileSystem.dll',('/resource:' + $archivePath + ',LuckyPayload.zip'),('/out:' + $installerPath),(Join-Path $PSScriptRoot 'Installer.cs'))
    & $compiler @installerArgs
    if ($LASTEXITCODE -ne 0) { throw 'Lucky installer compilation failed.' }
    Write-Output ('Built ' + $installerPath)
}
