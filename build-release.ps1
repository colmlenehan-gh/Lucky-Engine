param([switch]$SkipConnector)

# Run from the extracted Lucky source bundle. All paths are relative to this file.
# This build performs headless imports only; it never opens Lucky or its installer.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$sourceRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$workRoot = Join-Path $sourceRoot 'work'
$cacheRoot = Join-Path $workRoot 'cache'
$payloadRoot = Join-Path $workRoot 'payload'
$distRoot = Join-Path $sourceRoot 'dist'
$buildRoot = Join-Path $workRoot ('build-' + [Guid]::NewGuid().ToString('N'))
foreach ($folder in @($workRoot,$cacheRoot,$distRoot,$buildRoot)) { New-Item -ItemType Directory -Force -Path $folder | Out-Null }

function Assert-WorkspacePath([string]$Path) {
    $prefix = [IO.Path]::GetFullPath($workRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to modify a path outside the build workspace.' }
    return $full
}

function Assert-NoDirectoryLinks([string]$Folder) {
    if (-not [IO.Directory]::Exists($Folder)) { return }
    if (([IO.File]::GetAttributes($Folder) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('Linked build directory is not allowed: ' + $Folder) }
    foreach ($child in [IO.Directory]::GetDirectories($Folder)) { Assert-NoDirectoryLinks $child }
}

function Reset-BuildDirectory([string]$Folder) {
    $checked = Assert-WorkspacePath $Folder
    if (Test-Path -LiteralPath $checked) {
        Assert-NoDirectoryLinks $checked
        Remove-Item -LiteralPath $checked -Recurse -Force
    }
    New-Item -ItemType Directory -Path $checked -Force | Out-Null
}

function Get-PinnedDownload([string]$Url,[string]$FileName,[string]$Algorithm,[string]$ExpectedHash) {
    Write-Host ('Preparing verified dependency: ' + $FileName)
    $cached = Join-Path $cacheRoot $FileName
    if (Test-Path -LiteralPath $cached) {
        $actual = (Get-FileHash -LiteralPath $cached -Algorithm $Algorithm).Hash
        if ($actual -eq $ExpectedHash) { return $cached }
    }
    $partial = $cached + '.download'
    Invoke-WebRequest -Uri $Url -OutFile $partial -UseBasicParsing
    $actual = (Get-FileHash -LiteralPath $partial -Algorithm $Algorithm).Hash
    if ($actual -ne $ExpectedHash) { throw ('Checksum verification failed for ' + $FileName + '. No downloaded executable was run.') }
    Move-Item -LiteralPath $partial -Destination $cached -Force
    return $cached
}

function Get-Notice([string]$Url,[string]$FileName) {
    $path = Join-Path $cacheRoot $FileName
    Invoke-WebRequest -Uri $Url -OutFile $path -UseBasicParsing
    Copy-Item -LiteralPath $path -Destination (Join-Path $payloadRoot ('licenses/' + $FileName))
}

function Invoke-HeadlessGodot([string[]]$Arguments) {
    $lines = @(& $script:godotConsole @Arguments 2>&1)
    $result = $LASTEXITCODE
    $text = $lines | Out-String
    Write-Output $text
    if ($result -ne 0 -or $text -match '(?m)^(SCRIPT ERROR|ERROR:)') { throw 'Godot headless build validation failed.' }
}

$godotZip = Get-PinnedDownload 'https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip' 'Godot-4.7.2-win64.zip' 'SHA512' '83decd58fdf67b9d657958a1ae6bf1929c20785315a81effe245874cdc57acb709bf868e00778a96984338c1b29dafdb453c6847747694621c6ecf5da2259993'
$godotExtract = Join-Path $buildRoot 'godot'
Write-Output 'Extracting the verified Godot runtime.'
Expand-Archive -LiteralPath $godotZip -DestinationPath $godotExtract
$godot = Join-Path $godotExtract 'Godot_v4.7.2-stable_win64.exe'
$script:godotConsole = Join-Path $godotExtract 'Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $godot)) { throw 'The verified Godot archive is missing its runtime.' }

Reset-BuildDirectory $payloadRoot
foreach ($folder in @('runtime','editor','examples','docs','licenses')) { New-Item -ItemType Directory -Path (Join-Path $payloadRoot $folder) -Force | Out-Null }
Copy-Item -LiteralPath $godot -Destination (Join-Path $payloadRoot 'runtime/Godot.exe')
$editorRoot = Join-Path $payloadRoot 'editor'
$editorSource = Join-Path $sourceRoot 'editor'
foreach ($file in @('project.godot','main.tscn','main.gd','project_store.gd','viewport.gd','ai_bridge.gd','icon.svg')) {
    Copy-Item -LiteralPath (Join-Path $editorSource $file) -Destination (Join-Path $editorRoot $file)
    $uid = Join-Path $editorSource ($file + '.uid')
    if (Test-Path -LiteralPath $uid) { Copy-Item -LiteralPath $uid -Destination (Join-Path $editorRoot ($file + '.uid')) }
}
if (Test-Path -LiteralPath (Join-Path $sourceRoot 'docs')) {
    Copy-Item -Path (Join-Path $sourceRoot 'docs/*') -Destination (Join-Path $payloadRoot 'docs') -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $sourceRoot 'LICENSE.txt') -Destination (Join-Path $payloadRoot 'licenses/LUCKY-LICENSE.txt')
Copy-Item -LiteralPath (Join-Path $sourceRoot 'THIRD-PARTY.md') -Destination (Join-Path $payloadRoot 'licenses/THIRD-PARTY.md')
Get-Notice 'https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/LICENSE.txt' 'GODOT-LICENSE.txt'
Get-Notice 'https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/COPYRIGHT.txt' 'GODOT-COPYRIGHT.txt'
Get-Notice 'https://raw.githubusercontent.com/openai/codex/rust-v0.166.0/LICENSE' 'CODEX-LICENSE.txt'
Get-Notice 'https://raw.githubusercontent.com/openai/codex/rust-v0.166.0/NOTICE' 'CODEX-NOTICE.txt'

if (-not $SkipConnector) {
    Write-Output 'Preparing the optional account connector.'
    $connectorArchive = Get-PinnedDownload 'https://github.com/openai/codex/releases/download/rust-v0.166.0/codex-app-server-package-x86_64-pc-windows-msvc.tar.gz' 'codex-app-server-0.166.0-win64.tar.gz' 'SHA256' '2476ec968c64e9ae47f449446320e47a54d16f5436ce6eb95eec758584f12eb6'
    $tarCommand = Get-Command tar.exe -ErrorAction SilentlyContinue
    if (-not $tarCommand) { throw 'Windows tar.exe is required to unpack the optional account connector. Install it or build with -SkipConnector.' }
    $connectorRoot = Join-Path $payloadRoot 'tools/codex'
    New-Item -ItemType Directory -Path $connectorRoot -Force | Out-Null
    $entries = @(& $tarCommand.Source -tzf $connectorArchive)
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the verified connector archive.' }
    foreach ($entry in $entries) {
        if ($entry -match '(^[/\\]|^[A-Za-z]:|(^|[/\\])\.\.([/\\]|$))') { throw 'Connector archive contains an unsafe path.' }
    }
    & $tarCommand.Source -xzf $connectorArchive -C $connectorRoot
    if ($LASTEXITCODE -ne 0) { throw 'Connector extraction failed.' }
    if (-not (Test-Path -LiteralPath (Join-Path $connectorRoot 'bin/codex-app-server.exe'))) { throw 'The connector executable is missing.' }
}

$profile = Join-Path $buildRoot 'profile'
New-Item -ItemType Directory -Path $profile -Force | Out-Null
$previousAppData = $env:APPDATA
$previousLocalAppData = $env:LOCALAPPDATA
$previousExamples = $env:LUCKY_EXAMPLES_DIR
try {
    $env:APPDATA = $profile
    $env:LOCALAPPDATA = $profile
    $env:LUCKY_EXAMPLES_DIR = Join-Path $payloadRoot 'examples'
    Write-Output 'Importing editor resources headlessly.'
    Invoke-HeadlessGodot -Arguments @('--headless','--path',$editorRoot,'--editor','--import','--quit')
    $exampleScript = Join-Path $buildRoot 'create_examples.gd'
    @'
extends SceneTree
const Store = preload("res://project_store.gd")
func _initialize() -> void:
    var folder: String = OS.get_environment("LUCKY_EXAMPLES_DIR")
    var samples: Array = [["2D Platformer", "2D", "Platformer"], ["3D Showcase", "3D", "Showcase"]]
    for sample in samples:
        var result: Dictionary = Store.create_project(folder.path_join(sample[0]), sample[0], sample[1], sample[2])
        if result.has("error"):
            push_error(str(result["error"]))
            quit(1)
            return
    quit(0)
'@ | Set-Content -LiteralPath $exampleScript -Encoding UTF8
    Invoke-HeadlessGodot -Arguments @('--headless','--path',$editorRoot,'--script',$exampleScript)
    Write-Output 'Example projects generated.'
}
finally {
    $env:APPDATA = $previousAppData
    $env:LOCALAPPDATA = $previousLocalAppData
    $env:LUCKY_EXAMPLES_DIR = $previousExamples
}

# Retain texture imports, and remove editor metadata containing build-machine paths.
$importCache = Join-Path $editorRoot '.godot'
if (Test-Path -LiteralPath $importCache) {
    Get-ChildItem -LiteralPath $importCache -Force | Where-Object { $_.Name -ne 'imported' } | ForEach-Object {
        $checked = Assert-WorkspacePath $_.FullName
        if ($_.PSIsContainer) { Assert-NoDirectoryLinks $checked; Remove-Item -LiteralPath $checked -Recurse -Force }
        else { Remove-Item -LiteralPath $checked -Force }
    }
}
foreach ($folder in @('docs','export_templates','feature_profiles','script_templates','text_editor_themes')) {
    $generated = Join-Path $editorRoot $folder
    if (Test-Path -LiteralPath $generated) {
        $checked = Assert-WorkspacePath $generated
        Assert-NoDirectoryLinks $checked
        Remove-Item -LiteralPath $checked -Recurse -Force
    }
}

$packaging = Join-Path $sourceRoot 'packaging/build.ps1'
Write-Output 'Compiling the Windows launcher and uninstaller.'
& $packaging -PayloadDirectory $payloadRoot -OutputDirectory $distRoot -StageOnly
if ($LASTEXITCODE -ne 0) { throw 'Native launcher build failed.' }
$payloadZip = Join-Path $workRoot 'LuckyPayload.zip'
if (Test-Path -LiteralPath $payloadZip) { Remove-Item -LiteralPath (Assert-WorkspacePath $payloadZip) -Force }
[IO.Compression.ZipFile]::CreateFromDirectory($payloadRoot,$payloadZip,[IO.Compression.CompressionLevel]::Optimal,$false)
Write-Output 'Payload compressed; compiling the self-contained installer.'
& $packaging -PayloadZip $payloadZip -OutputDirectory $distRoot
if ($LASTEXITCODE -ne 0) { throw 'Native installer build failed.' }
$installer = Join-Path $distRoot 'Lucky-Setup-0.1.0-beta-windows-x64.exe'
$hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
($hash + '  ' + [IO.Path]::GetFileName($installer)) | Set-Content -LiteralPath (Join-Path $distRoot 'SHA256SUMS.txt') -Encoding ASCII
Write-Output ('Built ' + $installer)
