# Build + install debug APK with Supabase / Google dart-defines from supabase.local.json.
# Usage: .\scripts\install_android.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$defines = @()
$localCfg = Join-Path $root 'supabase.local.json'
if (Test-Path $localCfg) {
  $cfg = Get-Content $localCfg -Raw | ConvertFrom-Json
  if ($cfg.SUPABASE_URL) {
    $defines += "--dart-define=SUPABASE_URL=$($cfg.SUPABASE_URL)"
  }
  if ($cfg.SUPABASE_ANON_KEY) {
    $defines += "--dart-define=SUPABASE_ANON_KEY=$($cfg.SUPABASE_ANON_KEY)"
  }
  if ($cfg.GOOGLE_WEB_CLIENT_ID) {
    $defines += "--dart-define=GOOGLE_WEB_CLIENT_ID=$($cfg.GOOGLE_WEB_CLIENT_ID)"
  }
  Write-Host 'Loaded defines from supabase.local.json'
} else {
  Write-Host 'WARN: No supabase.local.json - auth will be guest-only.'
}

Write-Host 'Building debug APK...'
flutter build apk --debug @defines
$apk = Join-Path $root 'build\app\outputs\flutter-apk\app-debug.apk'
if (-not (Test-Path $apk)) {
  throw "APK not found at $apk"
}

function Resolve-Adb {
  $candidates = @(
    "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    "$env:ANDROID_HOME\platform-tools\adb.exe",
    "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe",
    'C:\Users\tempadmin\Documents\codes\Code_Shit\Tools\android-sdk\platform-tools\adb.exe'
  )
  foreach ($c in $candidates) {
    if ($c -and (Test-Path $c)) { return $c }
  }
  $fromPath = Get-Command adb -ErrorAction SilentlyContinue
  if ($fromPath) { return $fromPath.Source }
  return $null
}

$adb = Resolve-Adb
if (-not $adb) {
  throw 'adb not found. Install Android platform-tools or set ANDROID_HOME.'
}
Write-Host "Installing $apk ..."
& $adb install -r $apk
Write-Host 'Done. Open Room Rig and try Continue with Google (native account picker, not Chrome).'
