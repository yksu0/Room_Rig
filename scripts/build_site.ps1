# Inject Supabase public keys into the marketing site (Windows).
# Usage: .\scripts\build_site.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$url = $env:SUPABASE_URL
$key = $env:SUPABASE_ANON_KEY
if (-not $url -or -not $key) {
  $localCfg = Join-Path $root 'supabase.local.json'
  if (Test-Path $localCfg) {
    $cfg = Get-Content $localCfg -Raw | ConvertFrom-Json
    $url = $cfg.SUPABASE_URL
    $key = $cfg.SUPABASE_ANON_KEY
  }
}
if (-not $url -or -not $key) {
  throw 'Set SUPABASE_URL and SUPABASE_ANON_KEY (or supabase.local.json).'
}

$out = Join-Path $root 'build\site'
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Path $out | Out-Null
Copy-Item -Path (Join-Path $root 'site\*') -Destination $out -Recurse -Force

function Escape-Js([string]$s) {
  return ($s | ConvertTo-Json -Compress).Trim('"')
}

$config = @"
window.ROOM_RIG_SITE = {
  supabaseUrl: "$(Escape-Js $url)",
  supabaseAnonKey: "$(Escape-Js $key)",
  githubReleasesUrl: "https://github.com/yksu0/Room_Rig/releases",
  appDeepLink: "com.roomrig.room_rig://login-callback/",
};
"@
Set-Content -Path (Join-Path $out 'config.js') -Value $config -Encoding utf8
Copy-Item (Join-Path $root 'site\vercel.json') (Join-Path $out 'vercel.json') -Force
Write-Host "Output: $out"
