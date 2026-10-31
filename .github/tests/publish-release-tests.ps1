# Offline contract test. Every gh invocation is intercepted; no network is used.
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$testRoot = Join-Path $repoRoot ('work/publish-fixture-' + [Guid]::NewGuid().ToString('N'))
$expected = @('AI.md','BUILD.md','CHANGELOG.md','FEATURES.md','LICENSE.txt','Lucky-Setup-0.1.0-beta-windows-x64.exe','Lucky-Source-0.1.0-beta.zip','README.md','SHA256SUMS.txt','SOURCE-MANIFEST.json','TEST-RESULTS.md','THIRD-PARTY.md')
$previousEnvironment = @{}
foreach ($name in @('RELEASE_TAG','GITHUB_REF','GH_TOKEN','GH_REPO','GITHUB_SHA','GITHUB_STEP_SUMMARY')) {
    $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$previousGh = Get-Command gh -CommandType Function -ErrorAction SilentlyContinue
$previousExit = $global:LASTEXITCODE
$checks = 0

function Assert-True([bool]$Condition,[string]$Message) {
    $script:checks++
    if (-not $Condition) { throw $Message }
}

function global:gh {
    $arguments = @($args)
    $state = $global:LuckyPublishFixtureState
    $global:LASTEXITCODE = 0
    if ($arguments[0] -eq 'release' -and $arguments[1] -eq 'view') {
        if (-not $state.Exists) { $global:LASTEXITCODE = 1; return 'release not found' }
        if ($arguments[-1] -eq 'isDraft,targetCommitish') {
            return (@{isDraft=$state.Draft;targetCommitish=$env:GITHUB_SHA} | ConvertTo-Json -Compress)
        }
        return (@{isDraft=$state.Draft;isPrerelease=$true;url='https://github.com/fixture/lucky/releases/tag/v0.1.0-beta'} | ConvertTo-Json -Compress)
    }
    if ($arguments[0] -eq 'release' -and $arguments[1] -eq 'create') {
        if ($arguments -notcontains '--draft') { throw 'Fixture expected draft creation.' }
        $state.Creates++
        $state.Exists = $true
        $state.Draft = $true
        return 'draft created'
    }
    if ($arguments[0] -eq 'release' -and $arguments[1] -eq 'upload') {
        if (-not $state.Draft) { throw 'Fixture refuses public asset mutation.' }
        $state.Uploads++
        $state.Assets = @($state.Files | ForEach-Object {
            @{name=$_.Name;size=$_.Length;digest=('sha256:' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())}
        })
        if ($state.Mode -eq 'corrupt') { $state.Assets[0].size++ }
        return 'assets uploaded'
    }
    if ($arguments[0] -eq 'release' -and $arguments[1] -eq 'edit') {
        if ($arguments -notcontains '--draft=false') { throw 'Fixture expected publication.' }
        $state.Publishes++
        $state.Draft = $false
        return 'published'
    }
    if ($arguments[0] -eq 'api') {
        $route = $arguments[1]
        $state.Routes += $route
        if ($route -like '*/commits/*') { $global:LASTEXITCODE = 1; return 'not found' }
        if ($route -like '*/releases?per_page=100') {
            return (ConvertTo-Json -InputObject @(@{id=99;tag_name='v0.0.0';draft=$false},@{id=123;tag_name=$env:RELEASE_TAG;draft=$state.Draft}) -Compress)
        }
        if ($route -like '*/releases/123') {
            return (@{id=123;draft=$state.Draft;assets=$state.Assets} | ConvertTo-Json -Depth 6 -Compress)
        }
        throw ('Unexpected fixture API route: ' + $route)
    }
    throw ('Unexpected fixture command: ' + ($arguments -join ' '))
}

try {
    $env:RELEASE_TAG = 'v0.1.0-beta'
    $env:GITHUB_REF = 'refs/heads/main'
    $env:GH_TOKEN = 'offline-fixture-token'
    $env:GH_REPO = 'fixture/lucky'
    $env:GITHUB_SHA = '0123456789abcdef0123456789abcdef01234567'
    $env:GITHUB_STEP_SUMMARY = ''
    foreach ($mode in @('new','retry','corrupt','published')) {
        $caseRoot = Join-Path $testRoot $mode
        $scriptRoot = Join-Path $caseRoot '.github/scripts'
        $distRoot = Join-Path $caseRoot 'dist'
        New-Item -ItemType Directory -Force -Path $scriptRoot,$distRoot | Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot '.github/scripts/publish-release.ps1') -Destination $scriptRoot
        'Offline fixture notes' | Set-Content -LiteralPath (Join-Path $caseRoot '.github/RELEASE-NOTES.md')
        foreach ($name in $expected) { ('Offline fixture for ' + $name) | Set-Content -LiteralPath (Join-Path $distRoot $name) -Encoding ASCII }
        $global:LuckyPublishFixtureState = @{
            Mode=$mode;Exists=($mode -eq 'retry' -or $mode -eq 'published');Draft=($mode -ne 'published')
            Creates=0;Uploads=0;Publishes=0;Assets=@();Routes=@();Files=@(Get-ChildItem -LiteralPath $distRoot -File | Sort-Object Name)
        }
        $failure = $null
        try { & (Join-Path $scriptRoot 'publish-release.ps1') | Out-Null }
        catch { $failure = $_.Exception.Message }
        $state = $global:LuckyPublishFixtureState
        if ($mode -in @('new','retry')) {
            Assert-True ($null -eq $failure) ($mode + ' unexpectedly failed: ' + $failure)
            Assert-True ($state.Uploads -eq 1 -and $state.Publishes -eq 1 -and -not $state.Draft) ($mode + ' did not upload and publish exactly once.')
            Assert-True ($state.Creates -eq [int]($mode -eq 'new')) ($mode + ' created the wrong number of drafts.')
            Assert-True ($state.Assets.Count -eq 12) ($mode + ' did not include all assets.')
            Assert-True (@($state.Routes | Where-Object { $_ -like '*/releases/123' }).Count -eq 1) ($mode + ' did not verify the draft by numeric ID.')
            Assert-True (@($state.Routes | Where-Object { $_ -like '*/releases/tags/*' }).Count -eq 0) ($mode + ' used the draft-unsafe by-tag endpoint.')
        }
        elseif ($mode -eq 'corrupt') {
            Assert-True ($failure -like '*Uploaded size mismatch*') ('Corrupt upload was not rejected: ' + $failure)
            Assert-True ($state.Publishes -eq 0 -and $state.Draft) 'Corrupt assets must leave the release unpublished.'
        }
        else {
            Assert-True ($failure -like '*already published*') ('Published-release protection did not trigger: ' + $failure)
            Assert-True ($state.Uploads -eq 0 -and $state.Publishes -eq 0) 'Existing public release was changed.'
        }
        Write-Output ('PASS: ' + $mode)
    }
    Write-Output ('PUBLISH_RELEASE_TESTS checks=' + $checks + ' failures=0')
}
finally {
    foreach ($name in $previousEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name,$previousEnvironment[$name],'Process') }
    if ($previousGh) { Set-Item -LiteralPath Function:\global:gh -Value $previousGh.ScriptBlock }
    else { Remove-Item -LiteralPath Function:\gh -Force }
    Remove-Variable LuckyPublishFixtureState -Scope Global -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = $previousExit
}
