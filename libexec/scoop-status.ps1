# Usage: scoop status
# Summary: Show status and check for new app versions
# Help: Options:
#   -l, --local         Checks the status for only the locally installed apps,
#                       and disables remote fetching/checking for Scoop and buckets

. "$PSScriptRoot\..\lib\manifest.ps1" # 'manifest' 'parse_json' "install_info"
. "$PSScriptRoot\..\lib\versions.ps1" # 'Select-CurrentVersion'
. "$PSScriptRoot\..\lib\buckets.ps1" # 'Get-LocalBucket'

# check if scoop needs updating
$currentdir = versiondir 'scoop' 'current'
$needs_update = $false
$bucket_needs_update = $false
$script:network_failure = $false
$no_remotes = $args[0] -eq '-l' -or $args[0] -eq '--local'
if (!(Get-Command git -ErrorAction SilentlyContinue)) { $no_remotes = $true }
$list = @()
if (!(Get-FormatData ScoopStatus)) {
    Update-FormatData "$PSScriptRoot\..\supporting\formats\ScoopTypes.Format.ps1xml"
}

function Test-UpdateStatus($repopath) {
    if (Test-Path "$repopath\.git") {
        Invoke-Git -Path $repopath -ArgumentList @('fetch', '-q', 'origin')
        $script:network_failure = 128 -eq $LASTEXITCODE
        $branch = Invoke-Git -Path $repopath -ArgumentList @('branch', '--show-current')
        $commits = Invoke-Git -Path $repopath -ArgumentList @('log', "HEAD..origin/$branch", '--oneline')
        if ($commits) { return $true }
        else { return $false }
    } else {
        return $true
    }
}

if (!$no_remotes) {
    $needs_update = Test-UpdateStatus $currentdir
    foreach ($bucket in Get-LocalBucket) {
        if (Test-UpdateStatus (Find-BucketDirectory $bucket -Root)) {
            $bucket_needs_update = $true
            break
        }
    }
}

if ($needs_update) {
    warn "Scoop out of date. Run 'scoop update' to get the latest changes."
} elseif ($bucket_needs_update) {
    warn "Scoop bucket(s) out of date. Run 'scoop update' to get the latest changes."
} elseif (!$script:network_failure -and !$no_remotes) {
    success 'Scoop is up to date.'
}

$true, $false | ForEach-Object { # local and global apps
    $global = $_
    $dir = appsdir $global
    if (!(Test-Path $dir)) { return }

    $appNames = @(Get-ChildItem $dir -Directory -Name -Exclude 'scoop' | Where-Object Length -GT 0)

    if ($appNames.Length -eq 0) { return }

    foreach ($app in $appNames) {
        $status = app_status $app $global
        if (-not ($status.outdated -or $status.failed -or $status.removed -or $status.missing_deps)) { continue }

        $item = [ordered]@{}
        $item.Name = $app
        $item.'Installed Version' = $status.version
        $item.'Latest Version' = if ($status.outdated) { $status.latest_version } else { '' }
        $item.'Missing Dependencies' = $status.missing_deps -Split ' ' -Join ' | '
        $info = @()
        if ($status.failed) { $info += 'Install failed' }
        if ($status.hold) { $info += 'Held package' }
        if ($status.removed) { $info += 'Manifest removed' }
        $item.Info = $info -join ', '
        $list += [PSCustomObject]$item
    }
}

if ($list.Length -eq 0 -and !$needs_update -and !$bucket_needs_update -and !$script:network_failure) {
    success 'Everything is ok!'
}

$list | Add-Member -TypeName ScoopStatus -PassThru

exit 0
