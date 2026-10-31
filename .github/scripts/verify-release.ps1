$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$workRoot = Join-Path $repoRoot 'work'
$testRoot = Join-Path $workRoot ('ci-tests-' + [Guid]::NewGuid().ToString('N'))
$logRoot = Join-Path $testRoot 'logs'
$engine = Join-Path $workRoot 'payload/runtime/Godot.exe'
$editor = Join-Path $repoRoot 'editor'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

# Isolate preferences and generated projects. No authentication or inference runs.
$env:APPDATA = Join-Path $testRoot 'appdata'
$env:LOCALAPPDATA = Join-Path $testRoot 'localappdata'
$env:TEMP = Join-Path $testRoot 'temp'
$env:TMP = $env:TEMP
$env:CODEX_HOME = Join-Path $testRoot 'codex-home'
$env:LUCKY_TEST_APPDATA = $env:APPDATA
$env:LUCKY_TEST_ROOT = Join-Path $testRoot 'projects'
foreach ($folder in @($env:APPDATA,$env:LOCALAPPDATA,$env:TEMP,$env:CODEX_HOME,$env:LUCKY_TEST_ROOT)) {
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
}

function Invoke-HeadlessCheck([string]$Name,[string[]]$Arguments,[string]$Expected) {
    $stdout = Join-Path $logRoot ($Name + '.out.log')
    $stderr = Join-Path $logRoot ($Name + '.err.log')
    $quoted = @($Arguments | ForEach-Object { '"' + $_.Replace('"','\"') + '"' }) -join ' '
    $process = Start-Process -FilePath $engine -ArgumentList $quoted -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $output = [IO.File]::ReadAllText($stdout) + [IO.File]::ReadAllText($stderr)
    Write-Output $output
    if ($process.ExitCode -ne 0 -or $output -match '(?m)^(SCRIPT ERROR|ERROR:|FAIL:)') {
        throw ($Name + ' failed. No release will be published.')
    }
    if ($Expected -and $output -notmatch $Expected) { throw ($Name + ' did not report its expected passing result.') }
}

Invoke-HeadlessCheck 'import-source' @('--headless','--path',$editor,'--editor','--import','--quit') ''
Invoke-HeadlessCheck 'project-store' @('--headless','--path',$editor,'--script','tests/project_store_test.gd') 'PROJECT_STORE_TESTS checks=34 failures=0'
Invoke-HeadlessCheck 'editor-integration' @('--headless','--path',$editor,'--script','tests/integration_test.gd') 'INTEGRATION_TESTS checks=25 failures=0'

$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'The .NET Framework C# compiler is unavailable.' }
$fixture = Join-Path $testRoot 'FakeServer.exe'
$fixtureSource = Join-Path $editor 'tests/fixtures/fake_app_server.cs'
& $compiler '/nologo' '/target:exe' '/codepage:65001' '/reference:System.Web.Extensions.dll' ('/out:' + $fixture) $fixtureSource
if ($LASTEXITCODE -ne 0) { throw 'The offline AI fixture did not compile.' }
Invoke-HeadlessCheck 'offline-ai' @('--headless','--path',$editor,'--script','tests/ai_bridge_test.gd','--',$fixture) 'LUCKY_AI_TRANSPORT_TEST_PASS'

# Exercise the installer's actual embedded archive without its wizard or registration.
$installer = Join-Path $repoRoot 'dist/Lucky-Setup-0.1.0-beta-windows-x64.exe'
$verifyRoot = Join-Path $testRoot 'core-payload'
$process = Start-Process -FilePath $installer -ArgumentList @('--verify-payload',('"' + $verifyRoot + '"'),'--core') -Wait -PassThru -WindowStyle Hidden
if ($process.ExitCode -ne 0) { throw 'Core installer payload extraction failed.' }
$reportPath = Join-Path $verifyRoot 'Lucky-payload-verification.json'
$report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
if (-not $report.success -or $report.mode -ne 'core' -or $report.fileCount -lt 20) { throw 'Unexpected installer payload report.' }
foreach ($required in @('Lucky.exe','Uninstall.exe','runtime/Godot.exe','editor/project.godot')) {
    if (-not (Test-Path -LiteralPath (Join-Path $verifyRoot $required))) { throw ('Missing core payload file: ' + $required) }
}
if (Test-Path -LiteralPath (Join-Path $verifyRoot 'tools/codex')) { throw 'Core-only extraction included the optional connector.' }
Invoke-HeadlessCheck 'packaged-editor' @('--headless','--path',(Join-Path $verifyRoot 'editor'),'--','--self-test-ui') 'LUCKY_UI_TEST_PASS'
Write-Output 'Release verification passed: 59 project/editor checks, offline AI transport and installer payload.'
