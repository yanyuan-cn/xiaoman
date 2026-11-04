# One-command release for xiaoman.
# Pure ASCII on purpose: Windows PowerShell 5.1 reads .ps1 as ANSI, non-ASCII breaks parsing.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\release.ps1 -Notes "what changed"
#   powershell -ExecutionPolicy Bypass -File scripts\release.ps1 -SkipBuild -DryRun
#
# What it does:
#   1. reads the version from pubspec.yaml, checks lib/core/version.dart agrees
#   2. builds the release APK (optional), verifies the APK's versionCode/versionName
#   3. commits + pushes the version bump
#   4. creates the GitHub Release vX.Y.Z and uploads app-release.apk
#   5. rewrites version.json with the new version + sha256, commits and pushes
#
# Requires: git, curl.exe, Flutter, Android SDK (aapt). GitHub token is read from
# the Windows credential store via `git credential fill`.

[CmdletBinding()]
param(
    [string]$Notes = '',
    [switch]$SkipBuild,
    [switch]$DryRun,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$RepoSlug    = 'yanyuan-cn/xiaoman'
$ApkPath     = Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk'
$VersionJson = Join-Path $root 'version.json'

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }
function Step($msg) { Write-Host ''; Write-Host "== $msg" -ForegroundColor Cyan }

# Native commands write warnings/errors to stderr; with ErrorActionPreference=Stop
# PowerShell turns those into terminating errors before we can inspect $LASTEXITCODE.
function Invoke-Native {
    param(
        [string]$Exe,
        [string[]]$NativeArgs,
        [switch]$AllowFail
    )
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $Exe @NativeArgs 2>&1 | Out-String
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $old
    }
    if (-not $AllowFail -and $code -ne 0) {
        Fail "$Exe $($NativeArgs -join ' ') failed (exit $code):`n$out"
    }
    return [pscustomobject]@{ Output = $out; Code = $code }
}

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
    return (Invoke-Native -Exe 'git' -NativeArgs $GitArgs).Output
}

# API calls: try direct first, fall back to the configured proxy. The proxy on
# this machine is frequently down, and a dead proxy makes curl fail instantly.
function Invoke-Curl {
    param([string[]]$CurlArgs)
    $direct = Invoke-Native -Exe 'curl.exe' -AllowFail -NativeArgs $CurlArgs
    if ($direct.Code -eq 0) { return $direct }
    if ($ProxyArgs.Count -gt 0) {
        Write-Host '   direct request failed, retrying through the proxy...'
        return (Invoke-Native -Exe 'curl.exe' -AllowFail -NativeArgs ($ProxyArgs + $CurlArgs))
    }
    return $direct
}

# Network here is flaky: the local proxy comes and goes and direct access drops
# mid-handshake. Try direct first, then through the configured proxy, a few times.
function Push-Main {
    for ($i = 1; $i -le 3; $i++) {
        $r = Invoke-Native -Exe 'git' -AllowFail -NativeArgs @(
            '-c', 'http.proxy=', '-c', 'https.proxy=', 'push', 'origin', 'main')
        if ($r.Code -eq 0) { return }
        Write-Host "   push attempt $i (direct) failed, retrying..."
        Start-Sleep -Seconds 5
    }
    $r = Invoke-Native -Exe 'git' -AllowFail -NativeArgs @('push', 'origin', 'main')
    if ($r.Code -ne 0) { Fail "git push failed:`n$($r.Output)" }
}

$ProxyArgs = @()
$proxyCfg = (& git config --get http.proxy 2>$null)
if ($proxyCfg) { $ProxyArgs = @('-x', $proxyCfg.Trim()) }

function Get-GitHubToken {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $cred = ("protocol=https`nhost=github.com`n`n" | & git -c credential.helper=wincred credential fill 2>$null)
    } finally {
        $ErrorActionPreference = $old
    }
    $t = ($cred | Where-Object { $_ -like 'password=*' }) -replace '^password=', ''
    if (-not $t) { Fail 'no GitHub credential in the Windows credential store' }
    return $t
}

# ---------- 1. version ----------
Step 'Version'

$pubspec = Get-Content (Join-Path $root 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') {
    Fail 'cannot parse "version: x.y.z+n" from pubspec.yaml'
}
$ver = $Matches[1]
$code = [int]$Matches[2]

$dart = Get-Content (Join-Path $root 'lib\core\version.dart') -Raw
if ($dart -notmatch "kAppVersion\s*=\s*'([^']+)'") { Fail 'cannot parse kAppVersion in lib/core/version.dart' }
$dartVer = $Matches[1]
if ($dart -notmatch 'kAppBuild\s*=\s*(\d+)') { Fail 'cannot parse kAppBuild in lib/core/version.dart' }
$dartCode = [int]$Matches[1]

if ($dartVer -ne $ver -or $dartCode -ne $code) {
    Fail "version mismatch: pubspec $ver+$code vs version.dart $dartVer+$dartCode"
}
$tag = "v$ver"
Write-Host "   $ver+$code  tag=$tag"

# ---------- 2. build ----------
if (-not $SkipBuild) {
    Step 'Build'
    if (-not (Test-Path (Join-Path $root 'android'))) {
        Write-Host '   android/ missing, running init_android.ps1'
        Invoke-Native -Exe 'powershell' -NativeArgs @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $root 'scripts\init_android.ps1')
        ) | Out-Null
    }
    Invoke-Native -Exe 'flutter' -NativeArgs @('pub', 'get', '--enforce-lockfile') | Out-Null
    Invoke-Native -Exe 'flutter' -NativeArgs @('build', 'apk', '--release') | Out-Null
}

if (-not (Test-Path $ApkPath)) { Fail "APK not found: $ApkPath" }

# ---------- 3. verify APK version ----------
Step 'Verify APK'
$aapt = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Android\Sdk\build-tools') -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName 'aapt.exe' } |
        Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $aapt) { Fail 'aapt.exe not found under %LOCALAPPDATA%\Android\Sdk\build-tools' }

$badging = (& $aapt dump badging $ApkPath 2>$null | Select-Object -First 1)
if ($badging -notmatch "versionCode='(\d+)'") { Fail "cannot read versionCode from APK: $badging" }
$apkCode = [int]$Matches[1]
if ($badging -notmatch "versionName='([^']+)'") { Fail "cannot read versionName from APK: $badging" }
$apkVer = $Matches[1]
if ($apkCode -ne $code -or $apkVer -ne $ver) {
    Fail "APK is $apkVer+$apkCode but source says $ver+$code"
}
Write-Host "   APK says $apkVer+$apkCode"

$size = (Get-Item $ApkPath).Length
$sha = (Get-FileHash $ApkPath -Algorithm SHA256).Hash
Write-Host ('   size {0:N0} bytes' -f $size)
Write-Host "   sha256 $sha"

# ---------- 4. preconditions ----------
Step 'Remote precondition'
$token = Get-GitHubToken
$probe = (Invoke-Curl -CurlArgs @('-sS', '--max-time', '40',
                   '-H', "Authorization: Bearer $token",
                   '-H', 'Accept: application/vnd.github+json',
                   '-w', "`n%{http_code}",
                   "https://api.github.com/repos/$RepoSlug/releases/tags/$tag")).Output
$probeText = $probe.TrimEnd()
$probeLines = $probeText -split "`n"
$httpCode = $probeLines[-1].Trim()
$probeBody = ($probeLines[0..($probeLines.Count - 2)]) -join "`n"
if ($httpCode -eq '200') { Fail "release $tag already exists on GitHub" }
if ($httpCode -ne '404') { Fail "cannot check remote tag (HTTP $httpCode): $probeBody" }
Write-Host "   $tag is free"

$dirty = (Invoke-Git status --porcelain) -split "`n" | Where-Object { $_ }
$unexpected = $dirty | Where-Object { $_ -notmatch '(pubspec\.yaml|lib/core/version\.dart|version\.json)\s*$' }
if ($unexpected) {
    Write-Host ($unexpected -join "`n")
    Fail 'working tree has unrelated changes; commit them first'
}

if ($DryRun) {
    Step 'Dry run'
    Write-Host '   everything checks out; nothing was published'
    exit 0
}

if (-not $Yes) {
    Write-Host ''
    $answer = Read-Host "Publish $tag to GitHub now? type YES"
    if ($answer -ne 'YES') { Write-Host 'aborted'; exit 1 }
}

# ---------- 5. commit + push version bump ----------
Step 'Commit version bump'
$bumpDirty = ((Invoke-Git status --porcelain pubspec.yaml lib/core/version.dart) -replace '\s', '')
if ($bumpDirty) {
    Invoke-Git add pubspec.yaml lib/core/version.dart | Out-Null
    Invoke-Git commit -m "chore: version $ver+$code" | Out-Null
    Write-Host '   committed'
} else {
    Write-Host '   nothing to commit'
}
Push-Main
Write-Host '   pushed'

# ---------- 6. create release + upload ----------
Step 'Create release'
if (-not $Notes) { $Notes = "See the changelog in the app (v$ver)." }
$releaseBody = "$Notes`n`nAPK SHA-256:`n$sha"

$jsonFile = Join-Path $env:TEMP "xiaoman-release-$code.json"
$payload = [ordered]@{
    tag_name         = $tag
    target_commitish = 'main'
    name             = $tag
    body             = $releaseBody
    draft            = $false
    prerelease       = $false
}
[IO.File]::WriteAllText($jsonFile, ($payload | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))

$create = (Invoke-Curl -CurlArgs @('-sS', '--max-time', '60', '-X', 'POST',
                   '-H', "Authorization: Bearer $token",
                   '-H', 'Accept: application/vnd.github+json',
                   '-H', 'Content-Type: application/json',
                   '--data-binary', "@$jsonFile",
                   "https://api.github.com/repos/$RepoSlug/releases")).Output
if ($create -notmatch '"id"\s*:\s*(\d+)') { Fail "create release failed: $create" }
$releaseId = $Matches[1]
Write-Host "   release $releaseId created"

Step 'Upload APK'
$uploadArgs = @('-sS', '--http1.1', '--max-time', '900', '--retry', '2', '-X', 'POST',
                '-H', "Authorization: Bearer $token",
                '-H', 'Content-Type: application/vnd.android.package-archive',
                '--data-binary', "@$ApkPath",
                "https://uploads.github.com/repos/$RepoSlug/releases/$releaseId/assets?name=app-release.apk")
# 直连优先：经代理传 57MB 实测会卡死，而 uploads.github.com 直连是通的。
$upload = (Invoke-Curl -CurlArgs $uploadArgs).Output
if ($upload -notmatch '"state"\s*:\s*"uploaded"') { Fail "upload failed: $upload" }
if ($upload -notmatch ('"size"\s*:\s*' + $size)) { Fail 'uploaded size does not match local file' }
Write-Host "   uploaded $size bytes"

# ---------- 7. version.json ----------
Step 'Update version.json'
# Built by hand: ConvertTo-Json in PowerShell 5.1 indents with 4 spaces and puts two
# spaces after the colon, which does not match the repo style and makes noisy diffs.
$escapedNotes = $Notes -replace '\\', '\\' -replace '"', '\"' -replace "`r", '' -replace "`n", '\n'
$manifestText = @"
{
  "versionCode": $code,
  "versionName": "$ver",
  "apkUrl": "https://github.com/$RepoSlug/releases/download/$tag/app-release.apk",
  "sha256": "$sha",
  "url": "https://github.com/$RepoSlug/releases",
  "notes": "$escapedNotes"
}
"@
[IO.File]::WriteAllText($VersionJson, $manifestText, (New-Object System.Text.UTF8Encoding($false)))
Write-Host '   version.json rewritten'

Invoke-Git add version.json | Out-Null
Invoke-Git commit -m "release: $tag" | Out-Null
Push-Main
Write-Host '   pushed'

Step 'Done'
Write-Host "   https://github.com/$RepoSlug/releases/tag/$tag"
Write-Host '   Pages may take a minute to serve the new version.json'
Write-Host "   Then check the phone sees $ver"
