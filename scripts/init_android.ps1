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

if ($text -notmatch 'android.permission.INTERNET') {
    $text = [regex]::Replace(
        $text,
        '(<manifest[^>]*>\r?\n)',
        "`$1    <uses-permission android:name=`"android.permission.INTERNET`" />`r`n",
        1)
    Write-Host 'Internet permission added.' -ForegroundColor Green
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

# --- Launcher icon switch: two activity-alias entries (D1 dark / D3 light) ---
# Keep this block ASCII only: PS 5.1 reads .ps1 as ANSI, so the Chinese label is
# built from char codes instead of being written literally.
if ($text -notmatch 'activity-alias') {
    $text = [regex]::Replace(
        $text,
        '(?s)\s*<intent-filter>\s*<action android:name="android.intent.action.MAIN"\s*/>\s*<category android:name="android.intent.category.LAUNCHER"\s*/>\s*</intent-filter>',
        '')

    $aliasLabel = 'android:label="' + [char]0x5C0F + [char]0x6EE1 + '"'
    $aliases = @"
        <activity-alias
            android:name=".LauncherD1"
            android:enabled="true"
            android:exported="true"
            android:icon="@mipmap/ic_launcher"
            android:roundIcon="@mipmap/ic_launcher_round"
            $aliasLabel
            android:targetActivity=".MainActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity-alias>
        <activity-alias
            android:name=".LauncherD3"
            android:enabled="false"
            android:exported="true"
            android:icon="@mipmap/ic_launcher_d3"
            android:roundIcon="@mipmap/ic_launcher_d3_round"
            $aliasLabel
            android:targetActivity=".MainActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity-alias>

"@
    $text = $text.Replace('</application>', $aliases + '    </application>')
    Write-Host 'Launcher icon switch installed.' -ForegroundColor Green
}

# --- Auto bookkeeping: SMS permission + notification listener + SMS receiver ---
if ($text -notmatch 'android.permission.RECEIVE_SMS') {
    $text = [regex]::Replace(
        $text,
        '(<manifest[^>]*>\r?\n)',
        "`$1    <uses-permission android:name=`"android.permission.RECEIVE_SMS`" />`r`n",
        1)
    Write-Host 'SMS permission added.' -ForegroundColor Green
}

if ($text -notmatch 'AutoBookService') {
    $auto = @"
        <service
            android:name=".AutoBookService"
            android:exported="true"
            android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE">
            <intent-filter>
                <action android:name="android.service.notification.NotificationListenerService" />
            </intent-filter>
        </service>
        <receiver
            android:name=".SmsReceiver"
            android:exported="true"
            android:permission="android.permission.BROADCAST_SMS">
            <intent-filter android:priority="999">
                <action android:name="android.provider.Telephony.SMS_RECEIVED" />
            </intent-filter>
        </receiver>

"@
    $text = $text.Replace('</application>', $auto + '    </application>')
    Write-Host 'Auto bookkeeping components installed.' -ForegroundColor Green
}

# --- Auto bookkeeping: accessibility (screen reading) + floating window ---
if ($text -notmatch 'android.permission.SYSTEM_ALERT_WINDOW') {
    $text = [regex]::Replace(
        $text,
        '(<manifest[^>]*>\r?\n)',
        "`$1    <uses-permission android:name=`"android.permission.SYSTEM_ALERT_WINDOW`" />`r`n",
        1)
    Write-Host 'Overlay permission added.' -ForegroundColor Green
}

if ($text -notmatch 'AutoAccessService') {
    $access = @"
        <service
            android:name=".AutoAccessService"
            android:exported="true"
            android:label="@string/auto_access_label"
            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">
            <intent-filter>
                <action android:name="android.accessibilityservice.AccessibilityService" />
            </intent-filter>
            <meta-data
                android:name="android.accessibilityservice"
                android:resource="@xml/auto_access_config" />
        </service>

"@
    $text = $text.Replace('</application>', $access + '    </application>')
    Write-Host 'Accessibility service installed.' -ForegroundColor Green
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($manifest, $text, $utf8NoBom)

# Icon switch + auto bookkeeping need custom Kotlin; android/ is generated, so
# keep the sources under scripts/android/ and copy them in every time.
$kotlinSrc = Join-Path $root 'scripts\android'
$kotlinDst = Join-Path $root 'android\app\src\main\kotlin\com\xiaoman\xiaoman'
if (Test-Path $kotlinSrc) {
    New-Item -ItemType Directory -Force -Path $kotlinDst | Out-Null
    Copy-Item (Join-Path $kotlinSrc '*.kt') $kotlinDst -Force
    Write-Host ("Kotlin sources installed: " + (Get-ChildItem $kotlinDst -Filter *.kt).Count) -ForegroundColor Green
}

# Accessibility config + string resources live with the Kotlin sources.
$androidResSrc = Join-Path $root 'scripts\android\res'
$androidResDst = Join-Path $root 'android\app\src\main\res'
if (Test-Path $androidResSrc) {
    Get-ChildItem $androidResSrc -Directory | ForEach-Object {
        $target = Join-Path $androidResDst $_.Name
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        Copy-Item (Join-Path $_.FullName '*') $target -Force -Recurse
    }
    Write-Host 'Auto bookkeeping resources installed.' -ForegroundColor Green
}

# Replace launcher icons (assets/icon/res -> android/app/src/main/res)
$resSrc = Join-Path $root 'assets\icon\res'
$resDst = Join-Path $root 'android\app\src\main\res'
if (Test-Path $resSrc) {
    Get-ChildItem $resSrc -Directory | ForEach-Object {
        $target = Join-Path $resDst $_.Name
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        Copy-Item (Join-Path $_.FullName '*') $target -Force -Recurse
    }
    Write-Host 'App icon updated.' -ForegroundColor Green
}

Write-Host ''
Write-Host 'Next:' -ForegroundColor Cyan
Write-Host '  flutter pub get'
Write-Host '  flutter run'
