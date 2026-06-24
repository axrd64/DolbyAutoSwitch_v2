# DolbyAutoSwitch.ps1
# Watches for audio device changes. Disables Dolby effects when any external
# device is active; re-enables when back to internal speakers only.
# Runs as a hidden background process launched by Task Scheduler at login.
# No device names to configure — fully automatic.

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ── Paths ─────────────────────────────────────────────────────────────────────
$SCRIPT_DIR  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ICO_PATH    = Join-Path $SCRIPT_DIR 'dolby_auto_switch.ico'
$LOG_FILE    = Join-Path $SCRIPT_DIR 'DolbyAutoSwitch.log'
$MAX_LOG     = 2MB

# ── Dolby service & registry ──────────────────────────────────────────────────
$DOLBY_SERVICE   = 'DolbyDAXAPI'
$DOLBY_REG_ROOTS = @(
    'HKCU:\SOFTWARE\Dolby\Dolby Access',
    'HKCU:\SOFTWARE\Dolby\DAX3',
    'HKLM:\SOFTWARE\Dolby\DAX3'
)
$DOLBY_VALUE_NAMES = @('ProcessingEnabled','EffectsEnabled','EnableEffects','DolbyEnabled')

# Keywords that identify built-in laptop audio (case-insensitive)
$INTERNAL_KEYWORDS = @(
    'speakers','realtek','built-in','internal','laptop',
    'thinkpad','qualcomm','high definition audio'
)

# ── Logging ───────────────────────────────────────────────────────────────────
function Write-Log {
    param([string]$Msg, [string]$Level = 'INFO')
    $line = "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] [$Level] $Msg"
    if ((Test-Path $LOG_FILE) -and (Get-Item $LOG_FILE).Length -gt $MAX_LOG) {
        Rename-Item $LOG_FILE "$LOG_FILE.bak" -Force -EA SilentlyContinue
    }
    Add-Content $LOG_FILE $line -EA SilentlyContinue
}

# ── Device helpers ────────────────────────────────────────────────────────────
function Test-IsInternal([string]$Name) {
    $l = $Name.ToLower()
    foreach ($kw in $INTERNAL_KEYWORDS) { if ($l -match [regex]::Escape($kw)) { return $true } }
    return $false
}

function Get-ExternalAudioDevices {
    $result = @()
    try {
        Get-CimInstance Win32_SoundDevice | Where-Object { $_.StatusInfo -eq 3 } | ForEach-Object {
            if (-not (Test-IsInternal $_.Name)) { $result += $_.Name }
        }
    } catch {}
    return $result
}

# ── Dolby control ─────────────────────────────────────────────────────────────
function Set-DolbyEnabled([bool]$Enable) {
    $changed = $false
    foreach ($root in $DOLBY_REG_ROOTS) {
        if (-not (Test-Path $root)) { continue }
        foreach ($vn in $DOLBY_VALUE_NAMES) {
            $prop = Get-ItemProperty $root -Name $vn -EA SilentlyContinue
            if ($prop) {
                Set-ItemProperty $root -Name $vn -Value ([int]$Enable) -Type DWord -EA SilentlyContinue
                $changed = $true
            }
        }
    }
    # COM bridge attempt
    try {
        $com = New-Object -ComObject 'DolbyLaboratories.Control.DolbyAudioProcessing' -EA Stop
        $com.Enable = $Enable
        $changed = $true
    } catch {}
    return $changed
}

function Restart-DolbyService {
    $svc = Get-Service $DOLBY_SERVICE -EA SilentlyContinue
    if ($svc) { Restart-Service $DOLBY_SERVICE -Force -EA SilentlyContinue }
}

# ── Tray icon ─────────────────────────────────────────────────────────────────
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function New-TrayIcon {
    $ni = New-Object System.Windows.Forms.NotifyIcon

    if (Test-Path $ICO_PATH) {
        $ni.Icon = New-Object System.Drawing.Icon($ICO_PATH)
    } else {
        $ni.Icon = [System.Drawing.SystemIcons]::Information
    }

    $ni.Text    = 'DolbyAutoSwitch'
    $ni.Visible = $true

    $menu = New-Object System.Windows.Forms.ContextMenuStrip

    $itemStatus = New-Object System.Windows.Forms.ToolStripMenuItem
    $itemStatus.Text    = 'Status: Starting...'
    $itemStatus.Enabled = $false
    $menu.Items.Add($itemStatus) | Out-Null

    $menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

    $itemUninstall = New-Object System.Windows.Forms.ToolStripMenuItem
    $itemUninstall.Text = 'Uninstall DolbyAutoSwitch'
    $itemUninstall.Add_Click({
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "This will uninstall DolbyAutoSwitch, remove the scheduled task, and restore Dolby effects to ON.`n`nContinue?",
            'Uninstall DolbyAutoSwitch',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
            $uninstaller = Join-Path $SCRIPT_DIR 'Uninstall-DolbyAutoSwitch.ps1'
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$uninstaller`"" -Verb RunAs
        }
    })
    $menu.Items.Add($itemUninstall) | Out-Null

    $itemExit = New-Object System.Windows.Forms.ToolStripMenuItem
    $itemExit.Text = 'Exit (keeps running at next login)'
    $itemExit.Add_Click({ [System.Windows.Forms.Application]::Exit() })
    $menu.Items.Add($itemExit) | Out-Null

    $ni.ContextMenuStrip = $menu
    return $ni, $itemStatus
}

# ── State machine ─────────────────────────────────────────────────────────────
$script:LastState = $null

function Update-DolbyState($trayIcon, $statusItem) {
    $ext = Get-ExternalAudioDevices

    if ($ext.Count -gt 0) {
        if ($script:LastState -ne 'external') {
            Write-Log "External device(s): $($ext -join ', ') — Dolby OFF"
            if (Set-DolbyEnabled $false) { Restart-DolbyService }
            $script:LastState = 'external'
        }
        if ($trayIcon)   { $trayIcon.Text   = "DolbyAutoSwitch — Dolby OFF ($($ext[0]))" }
        if ($statusItem) { $statusItem.Text  = "Dolby OFF — external: $($ext[0])" }
    } else {
        if ($script:LastState -ne 'internal') {
            Write-Log 'Internal speakers only — Dolby ON'
            if (Set-DolbyEnabled $true) { Restart-DolbyService }
            $script:LastState = 'internal'
        }
        if ($trayIcon)   { $trayIcon.Text   = 'DolbyAutoSwitch — Dolby ON (internal speakers)' }
        if ($statusItem) { $statusItem.Text  = 'Dolby ON — internal speakers' }
    }
}

# ── Main ──────────────────────────────────────────────────────────────────────
Write-Log '=== DolbyAutoSwitch started ==='

$tray, $statusItem = New-TrayIcon

# Timer for polling + event processing
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({ Update-DolbyState $tray $statusItem })
$timer.Start()

# Initial state
Update-DolbyState $tray $statusItem

# WMI watcher (best-effort — timer is the reliable fallback)
try {
    $q = "SELECT * FROM __InstanceOperationEvent WITHIN 2 WHERE TargetInstance ISA 'Win32_SoundDevice'"
    Register-WmiEvent -Query $q -SourceIdentifier 'AudioDeviceChange' -Action {
        Start-Sleep -Milliseconds 1500
        # Signal the timer to run immediately on next tick (already polling every 3s anyway)
    } -EA Stop
    Write-Log 'WMI watcher registered'
} catch {
    Write-Log "WMI watcher unavailable — timer polling only: $_" 'WARN'
}

[System.Windows.Forms.Application]::Run()

$tray.Visible = $false
$tray.Dispose()
Write-Log 'DolbyAutoSwitch exited'
