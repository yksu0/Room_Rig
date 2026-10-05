# Wireless Scan debug — streams Flutter/YOLO logs over Wi‑Fi (adb).
# Does NOT add extra inference on the phone; only logcat over the network.
#
# One-time (USB plugged once):
#   1. Phone: Developer options → Wireless debugging ON (Android 11+)
#      OR: adb tcpip 5555
#   2. Note phone IP (same Wi‑Fi as PC)
#   3. .\scripts\wireless_scan_logs.ps1 -PhoneIp 192.168.x.x
#
# Then unplug and scan the room while this window shows detect timings/errors.

param(
    [Parameter(Mandatory = $true)]
    [string]$PhoneIp,
    [int]$Port = 5555,
    [string]$Filter = "TfliteObjectDetector|HybridObjectDetector|flutter|ScanModel|AndroidRuntime"
)

$ErrorActionPreference = "Stop"

function Resolve-Adb {
    $candidates = @(
        (Get-Command adb -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
        "$env:ANDROID_HOME\platform-tools\adb.exe",
        "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe",
        "C:\Users\tempadmin\Documents\codes\Code_Shit\Tools\android-sdk\platform-tools\adb.exe"
    ) | Where-Object { $_ -and (Test-Path $_) }
    if (-not $candidates) {
        Write-Error "adb not found. Install Android platform-tools or set ANDROID_HOME."
    }
    return $candidates[0]
}

$adb = Resolve-Adb
Write-Host "Using adb: $adb"
Write-Host "Connecting adb to ${PhoneIp}:${Port} ..."
& $adb connect "${PhoneIp}:${Port}" | Write-Host

$devices = & $adb devices
Write-Host ($devices -join "`n")
if (($devices -join "`n") -notmatch [regex]::Escape($PhoneIp)) {
    Write-Error "Phone not listed. Enable wireless debugging / run 'adb tcpip 5555' over USB first."
}

Write-Host ""
Write-Host "MONITOR ON — streaming logs (Ctrl+C = MONITOR OFF). Filter: $Filter"
Write-Host "Look for: TfliteObjectDetector: infer Xms / disabled / init failed"
Write-Host ""

& $adb logcat -c | Out-Null
& $adb logcat -v time *:S flutter:V AndroidRuntime:E | Select-String -Pattern $Filter
