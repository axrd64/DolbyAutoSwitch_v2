# Uninstall-DolbyAutoSwitch.ps1
# Removes DolbyAutoSwitch completely:
#   - Stops and removes the scheduled task
#   - Removes the Settings > Apps registry entry
#   - Restores Dolby effects to ON
#   - Deletes installed files
# Can be triggered from Settings > Apps, the tray icon, or run directly.

#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$APP_NAME    = 'DolbyAutoSwitch'
$INSTALL_DIR = "$env:ProgramData\$APP_NAME"
$TASK_NAME   = $APP_NAME
$REG_BASE    = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$APP_NAME"

$DOLBY_SERVICE    = 'DolbyDAXAPI'
$DOLBY_REG_ROOTS  = @(
    'HKCU:\SOFTWARE\Dolby\Dolby Access',
    'HKCU:\SOFTWARE\Dolby\DAX3',
    'HKLM:\SOFTWARE\Dolby\DAX3'
)
$DOLBY_VALUE_NAMES = @('ProcessingEnabled','EffectsEnabled','EnableEffects','DolbyEnabled')

Write-Host ""
Write-Host "  DolbyAutoSwitch Uninstaller" -ForegroundColor Cyan
Write-Host "  ───────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# ── Stop & remove scheduled task ──────────────────────────────────────────────
$task = Get-ScheduledTask -TaskName $TASK_NAME -EA SilentlyContinue
if ($task) {
    Stop-ScheduledTask  -TaskName $TASK_NAME -EA SilentlyContinue
    Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false -EA SilentlyContinue
    Write-Host "  [OK] Scheduled task removed" -ForegroundColor Green
} else {
    Write-Host "  [--] Scheduled task not found (already removed)" -ForegroundColor Gray
}

# Kill any remaining PowerShell process running the script
Get-Process powershell -EA SilentlyContinue | Where-Object {
    ($_.MainWindowTitle -eq '' -or $_.MainWindowTitle -eq $null) -and
    (Get-WmiObject Win32_Process -Filter "ProcessId=$($_.Id)" -EA SilentlyContinue).CommandLine -match 'DolbyAutoSwitch'
} | Stop-Process -Force -EA SilentlyContinue

# ── Restore Dolby effects to ON ───────────────────────────────────────────────
$restored = $false
foreach ($root in $DOLBY_REG_ROOTS) {
    if (-not (Test-Path $root)) { continue }
    foreach ($vn in $DOLBY_VALUE_NAMES) {
        $prop = Get-ItemProperty $root -Name $vn -EA SilentlyContinue
        if ($prop) {
            Set-ItemProperty $root -Name $vn -Value 1 -Type DWord -EA SilentlyContinue
            $restored = $true
        }
    }
}
# COM bridge attempt
try {
    $com = New-Object -ComObject 'DolbyLaboratories.Control.DolbyAudioProcessing' -EA Stop
    $com.Enable = $true
    $restored = $true
} catch {}

if ($restored) {
    # Restart Dolby service so the change takes effect immediately
    Restart-Service $DOLBY_SERVICE -Force -EA SilentlyContinue
    Write-Host "  [OK] Dolby effects restored to ON" -ForegroundColor Green
} else {
    Write-Host "  [--] Dolby registry keys not found — nothing to restore" -ForegroundColor Gray
}

# ── Remove Settings > Apps entry ──────────────────────────────────────────────
if (Test-Path $REG_BASE) {
    Remove-Item $REG_BASE -Recurse -Force -EA SilentlyContinue
    Write-Host "  [OK] Removed from Settings > Apps" -ForegroundColor Green
} else {
    Write-Host "  [--] Apps registry entry not found" -ForegroundColor Gray
}

# ── Delete installed files ────────────────────────────────────────────────────
if (Test-Path $INSTALL_DIR) {
    Remove-Item $INSTALL_DIR -Recurse -Force -EA SilentlyContinue
    if (-not (Test-Path $INSTALL_DIR)) {
        Write-Host "  [OK] Installed files removed ($INSTALL_DIR)" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Could not fully remove $INSTALL_DIR — you can delete it manually." -ForegroundColor Yellow
    }
} else {
    Write-Host "  [--] Install directory not found" -ForegroundColor Gray
}

Write-Host ""
Write-Host "  DolbyAutoSwitch has been uninstalled." -ForegroundColor Cyan
Write-Host "  Dolby effects are now ON. You can close this window." -ForegroundColor Gray
Write-Host ""
Read-Host "  Press Enter to close"
