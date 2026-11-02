# Generate android/ (if missing), set app label and install permission.
# Pure ASCII: Windows PowerShell 5.1 reads .ps1 as ANSI, non-ASCII breaks parsing.
# Usage: powershell -ExecutionPolicy Bypass -File scripts\init_android.ps1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (Test-Path .\android) {
    Write-Host 'android/ already exists, skip generating.' -ForegroundColor Yellow
} else {
    if (Test-Path .\_tmp) { Remove-Item -Recurse -Force .\_tmp }
    Write-Host 'Generating android/ ...' -ForegroundColor Cyan
    flutter create --platforms=android --org com.xiaoman --project-name xiaoman _tmp
    Copy-Item -Recurse _tmp\android .\android
    Remove-Item -Recurse -Force _tmp
}

$manifest = Join-Path $root 'android\app\src\main\AndroidManifest.xml'
if (-not (Test-Path $manifest)) {
    Write-Host "manifest not found: $manifest" -ForegroundColor Red
    exit 1
}

$text = [System.IO.File]::ReadAllText($manifest)

# 0x5C0F = Xiao, 0x6EE1 = Man
$label = 'android:label="' + [char]0x5C0F + [char]0x6EE1 + '"'
if ($text -match 'android:label="xiaoman"') {
    $text = $text.Replace('android:label="xiaoman"', $label)
    Write-Host 'App label updated.' -ForegroundColor Green
}

if ($text -notmatch 'REQUEST_INSTALL_PACKAGES') {
    $text = [regex]::Replace(
        $text,
        '(<manifest[^>]*>\r?\n)',
        "`$1    <uses-permission android:name=`"android.permission.REQUEST_INSTALL_PACKAGES`" />`r`n",
        1)
    Write-Host 'Install permission added.' -ForegroundColor Green
}

if ($text -notmatch '<queries>') {
    $text = $text.Replace(
        '</manifest>',
        "    <queries>`r`n        <intent>`r`n            <action android:name=`"android.intent.action.VIEW`" />`r`n            <data android:mimeType=`"application/vnd.android.package-archive`" />`r`n        </intent>`r`n    </queries>`r`n</manifest>")
    Write-Host 'Package queries added.' -ForegroundColor Green
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($manifest, $text, $utf8NoBom)

Write-Host ''
Write-Host 'Next:' -ForegroundColor Cyan
Write-Host '  flutter pub get'
Write-Host '  flutter run'
