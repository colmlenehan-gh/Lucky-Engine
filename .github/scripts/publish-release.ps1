$ErrorActionPreference = 'Stop'
if ($env:RELEASE_TAG -cne 'v0.1.0-beta') { throw 'Unsupported release tag.' }
if ($env:GITHUB_REF -cne 'refs/heads/main') { throw 'Release must be dispatched from main.' }
if (-not $env:GH_TOKEN -or -not $env:GH_REPO -or $env:GITHUB_SHA -notmatch '^[a-f0-9]{40}$') { throw 'GitHub release context is incomplete.' }
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$distRoot = Join-Path $repoRoot 'dist'
$notes = Join-Path $repoRoot '.github/RELEASE-NOTES.md'
$expected = @('AI.md','BUILD.md','CHANGELOG.md','FEATURES.md','LICENSE.txt','Lucky-Setup-0.1.0-beta-windows-x64.exe','Lucky-Source-0.1.0-beta.zip','README.md','SHA256SUMS.txt','SOURCE-MANIFEST.json','TEST-RESULTS.md','THIRD-PARTY.md')
$assets = @(Get-ChildItem -LiteralPath $distRoot -File | Sort-Object Name)
if ($assets.Count -ne $expected.Count -or @(Compare-Object $expected @($assets.Name)).Count -ne 0) { throw 'Release assets do not match the expected twelve files.' }

function Invoke-Gh([string[]]$Arguments,[switch]$AllowFailure) {
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& gh @Arguments 2>&1)
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    $text = ($output | Out-String).Trim()
    if ($code -ne 0 -and -not $AllowFailure) { throw ('GitHub CLI failed: ' + $text) }
    return [pscustomobject]@{ ExitCode = $code; Text = $text }
}

$existing = Invoke-Gh @('release','view',$env:RELEASE_TAG,'--repo',$env:GH_REPO,'--json','isDraft,targetCommitish') -AllowFailure
if ($existing.ExitCode -eq 0) {
    $release = $existing.Text | ConvertFrom-Json
    if (-not $release.isDraft) { throw 'This release is already published. Existing public assets will not be replaced.' }
    if ($release.targetCommitish -cne $env:GITHUB_SHA) { throw 'The existing draft targets a different commit. Review it before retrying.' }
}
else {
    $tag = Invoke-Gh @('api',('repos/' + $env:GH_REPO + '/commits/' + $env:RELEASE_TAG),'--jq','.sha') -AllowFailure
    if ($tag.ExitCode -eq 0 -and $tag.Text -cne $env:GITHUB_SHA) { throw 'The existing release tag points to another commit.' }
    $null = Invoke-Gh @('release','create',$env:RELEASE_TAG,'--repo',$env:GH_REPO,'--target',$env:GITHUB_SHA,'--title','Lucky Engine 0.1.0 beta','--notes-file',$notes,'--draft','--prerelease','--latest=false')
}

# Retries may replace assets only while this same-commit release remains a draft.
$uploadArguments = @('release','upload',$env:RELEASE_TAG,'--repo',$env:GH_REPO,'--clobber') + @($assets.FullName)
$null = Invoke-Gh $uploadArguments
$result = Invoke-Gh @('api',('repos/' + $env:GH_REPO + '/releases?per_page=100'))
$listedReleases = $result.Text | ConvertFrom-Json
$candidates = @($listedReleases | Where-Object { $_.tag_name -ceq $env:RELEASE_TAG })
if ($candidates.Count -ne 1 -or -not $candidates[0].draft -or $candidates[0].id -notmatch '^\d+$') { throw 'Could not identify the unique draft release; release remains unpublished.' }
# Draft releases may not have a Git tag yet, so the by-tag API can return 404.
$releaseId = [string]$candidates[0].id
$result = Invoke-Gh @('api',('repos/' + $env:GH_REPO + '/releases/' + $releaseId))
$uploaded = $result.Text | ConvertFrom-Json
if (-not $uploaded.draft -or @($uploaded.assets).Count -ne $expected.Count -or @(Compare-Object $expected @($uploaded.assets.name)).Count -ne 0) { throw 'Draft asset verification failed; release remains unpublished.' }
foreach ($file in $assets) {
    $remote = @($uploaded.assets | Where-Object { $_.name -ceq $file.Name })
    if ($remote.Count -ne 1 -or $remote[0].size -ne $file.Length) { throw ('Uploaded size mismatch: ' + $file.Name) }
    if ($remote[0].digest) {
        $digest = 'sha256:' + (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($remote[0].digest -cne $digest) { throw ('Uploaded checksum mismatch: ' + $file.Name) }
    }
}
$null = Invoke-Gh @('release','edit',$env:RELEASE_TAG,'--repo',$env:GH_REPO,'--title','Lucky Engine 0.1.0 beta','--notes-file',$notes,'--draft=false','--prerelease','--latest=false')
$result = Invoke-Gh @('release','view',$env:RELEASE_TAG,'--repo',$env:GH_REPO,'--json','url,isDraft,isPrerelease')
$published = $result.Text | ConvertFrom-Json
if ($published.isDraft -or -not $published.isPrerelease) { throw 'Release publication status is unexpected.' }
Write-Output ('Published ' + $published.url)
if ($env:GITHUB_STEP_SUMMARY) {
    ('Published [Lucky Engine 0.1.0 beta](' + $published.url + ') with all twelve assets after headless tests and payload verification.') | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY
}
