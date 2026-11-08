# Light OS: Windows Host USB Auto-Reboot Watcher (PowerShell)
# Watches for a USB volume labeled PORTEUS, PORTEUX, or EFIBOOT and
# automatically restarts Windows so the PC boots into Light OS.
#
# Usage (Run as Administrator):
#   powershell -ExecutionPolicy Bypass -File tools\host-usb-autoboot.ps1

param(
    [switch]$DryRun
)

$TargetLabels = @("PORTEUS", "PORTEUX", "EFIBOOT")
Write-Host "[Light OS] Watching for Light OS USB ($($TargetLabels -join ', '))..."

while ($true) {
    $vol = Get-Volume | Where-Object { $TargetLabels -contains $_.FileSystemLabel } | Select-Object -First 1
    if ($null -ne $vol) {
        Write-Host "[Light OS] Detected Light OS USB on drive $($vol.DriveLetter): ($($vol.FileSystemLabel))"
        if ($DryRun) {
            Write-Host "[Light OS] -DryRun enabled: skipping reboot."
            break
        }
        Restart-Computer -Force
        break
    }
    Start-Sleep -Seconds 1
}
