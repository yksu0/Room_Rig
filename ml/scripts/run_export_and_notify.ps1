# Run WSL ONNX→TFLite export. Open Chrome + YouTube ONLY on success.
$ErrorActionPreference = "Continue"
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$log = Join-Path $repo "ml\out\wsl_export_last.log"
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null

$tflite = Join-Path $repo "assets\models\yolo_roomrig.tflite"
$beforeSize = if (Test-Path $tflite) { (Get-Item $tflite).Length } else { 0 }
$beforeTime = if (Test-Path $tflite) { (Get-Item $tflite).LastWriteTimeUtc } else { [datetime]::MinValue }

"=== export started $(Get-Date -Format o) ===" | Tee-Object -FilePath $log

wsl -d Ubuntu -- bash -c "sed -i 's/\r$//' /mnt/c/Users/tempadmin/.gemini/antigravity/scratch/room_rig/ml/scripts/wsl_onnx_to_tflite.sh /mnt/c/Users/tempadmin/.gemini/antigravity/scratch/room_rig/ml/scripts/wsl_fix_dns.sh; bash /mnt/c/Users/tempadmin/.gemini/antigravity/scratch/room_rig/ml/scripts/wsl_fix_dns.sh; bash /mnt/c/Users/tempadmin/.gemini/antigravity/scratch/room_rig/ml/scripts/wsl_onnx_to_tflite.sh" 2>&1 |
  Tee-Object -FilePath $log -Append

$exit = $LASTEXITCODE
$afterSize = if (Test-Path $tflite) { (Get-Item $tflite).Length } else { 0 }
$afterTime = if (Test-Path $tflite) { (Get-Item $tflite).LastWriteTimeUtc } else { [datetime]::MinValue }
"=== export finished $(Get-Date -Format o) exit=$exit tflite_bytes=$afterSize ===" | Tee-Object -FilePath $log -Append

# Success = clean exit AND a new/changed Room Rig tflite (not the old ~3.3MB smoke stand-in alone).
$oldSmokeBytes = 3333264
$ok = ($exit -eq 0) -and (Test-Path $tflite) -and (
  ($afterTime -gt $beforeTime) -or ($afterSize -ne $beforeSize)
) -and ($afterSize -ne $oldSmokeBytes -or $afterTime -gt $beforeTime)

if (-not $ok) {
  "=== notify skipped (export failed or tflite unchanged) ===" | Tee-Object -FilePath $log -Append
  exit 1
}

$url = "https://www.youtube.com/watch?v=ZbZSe6N_BXs&autoplay=1"
$chrome = @(
  "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($chrome) { Start-Process -FilePath $chrome -ArgumentList $url }
else { Start-Process $url }
"=== notify: YouTube opened (export success) ===" | Tee-Object -FilePath $log -Append
