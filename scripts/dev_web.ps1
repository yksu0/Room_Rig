# Single-tab Flutter web session on a fixed port.
# Does NOT launch Chrome — refresh http://localhost:7357 in the tab you already use.
#
# Usage:
#   .\scripts\dev_web.ps1
# Optional: gitignored supabase.local.json with SUPABASE_URL + SUPABASE_ANON_KEY

param(
  [int]$Port = 7357,
  [switch]$Restart
)

$ErrorActionPreference = 'Stop'
$url = "http://localhost:$Port"
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
  Write-Host "Loaded Supabase defines from supabase.local.json"
} else {
  Write-Host "No supabase.local.json - guest-only mode (see supabase.local.json.example)"
}

$listeners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($listeners) {
  $pids = $listeners.OwningProcess | Sort-Object -Unique
  foreach ($procId in $pids) {
    try {
      Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
    } catch {}
  }
  Start-Sleep -Seconds 1
}

Write-Host "Serving on $url (no new Chrome tab). Refresh that URL in your existing tab."
if ($defines.Count -gt 0) {
  flutter run -d web-server --web-port $Port @defines
} else {
  flutter run -d web-server --web-port $Port
}
