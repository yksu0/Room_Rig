# Single-tab Flutter web session on a fixed port.
# Does NOT launch Chrome — refresh http://localhost:7357 in the tab you already use.
#
# Usage:
#   .\scripts\dev_web.ps1          # start (or replace) web-server on 7357
#   .\scripts\dev_web.ps1 -Restart # if already running, only works when you attach stdin

param(
  [int]$Port = 7357,
  [switch]$Restart
)

$ErrorActionPreference = 'Stop'
$url = "http://localhost:$Port"

# Free the port if a previous flutter/dart is still bound to it.
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
flutter run -d web-server --web-port $Port
