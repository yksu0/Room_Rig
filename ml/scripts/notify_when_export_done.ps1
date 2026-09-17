# Legacy watcher — only opens YouTube if TFLite was actually updated.
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$tflite = Join-Path $repo "assets\models\yolo_roomrig.tflite"
$log = Join-Path $repo "ml\out\wsl_export_last.log"

Write-Host "Use ml\scripts\run_export_and_notify.ps1 instead (YouTube only on success)."
if (Test-Path $log) {
  $tail = Get-Content $log -Tail 5
  $tail | ForEach-Object { Write-Host $_ }
  if ($tail -match 'notify skipped|exit=1') {
    Write-Host "Export failed — not opening YouTube."
    exit 1
  }
}
if (-not (Test-Path $tflite)) { exit 1 }
$size = (Get-Item $tflite).Length
if ($size -eq 3333264) {
  Write-Host "Still smoke TFLite ($size) — not opening YouTube."
  exit 1
}
$url = "https://www.youtube.com/watch?v=ZbZSe6N_BXs&autoplay=1"
$chrome = @(
  "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($chrome) { Start-Process -FilePath $chrome -ArgumentList $url } else { Start-Process $url }
