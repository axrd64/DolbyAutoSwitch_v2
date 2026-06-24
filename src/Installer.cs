// Installer.cs — DolbyAutoSwitch Installer
// Compiles to Install-DolbyAutoSwitch.exe
// Requires: .NET Framework 4.5+ (built into Windows 8+)
// Build: see build.bat

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Windows.Forms;

[assembly: AssemblyTitle("DolbyAutoSwitch Installer")]
[assembly: AssemblyProduct("DolbyAutoSwitch")]
[assembly: AssemblyVersion("1.0.0.0")]

namespace DolbyAutoSwitch
{
    static class Installer
    {
        // Required files that must be in the same directory as this EXE
        static readonly string[] RequiredFiles = {
            "DolbyAutoSwitch.ps1",
            "Uninstall-DolbyAutoSwitch.ps1",
            "dolby_auto_switch.ico"
        };

        [STAThread]
        static int Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            // Self-elevate if not admin
            if (!IsAdministrator())
            {
                RelaunchAsAdmin();
                return 0;
            }

            string exeDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);

            // Verify required files are present
            foreach (string f in RequiredFiles)
            {
                if (!File.Exists(Path.Combine(exeDir, f)))
                {
                    MessageBox.Show(
                        $"Missing required file: {f}\n\nMake sure all DolbyAutoSwitch files are in the same folder as this installer.",
                        "DolbyAutoSwitch — Missing Files",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error
                    );
                    return 1;
                }
            }

            // Confirm install
            var confirm = MessageBox.Show(
                "DolbyAutoSwitch will be installed.\n\n" +
                "• Runs silently at every login\n" +
                "• Disables Dolby when external audio is connected\n" +
                "• Re-enables Dolby when back to internal speakers\n" +
                "• Appears in Settings → Apps for easy removal\n\n" +
                "Install now?",
                "DolbyAutoSwitch — Install",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Question
            );

            if (confirm != DialogResult.Yes) return 0;

            // Build the PowerShell install command (same logic as the old PS1 installer,
            // but invoked from C# so the user sees a proper EXE, not a PS window)
            string installDir  = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                "DolbyAutoSwitch"
            );
            string installScript = Path.Combine(exeDir, "_install_helper.ps1");

            // Write a temporary helper PS1 that does the actual work
            File.WriteAllText(installScript, BuildInstallScript(exeDir, installDir));

            try
            {
                int exit = RunPowerShell(installScript, wait: true);
                File.Delete(installScript);

                if (exit == 0)
                {
                    MessageBox.Show(
                        "Installation complete!\n\n" +
                        "DolbyAutoSwitch is now running in the background.\n" +
                        "Look for the tray icon near the clock.\n\n" +
                        "To uninstall: Settings → Apps → DolbyAutoSwitch\n" +
                        "or right-click the tray icon.",
                        "DolbyAutoSwitch — Installed",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Information
                    );
                }
                else
                {
                    MessageBox.Show(
                        $"Installation encountered an issue (exit code {exit}).\n\n" +
                        "Check that Dolby Access is installed and try again.\n" +
                        $"Log: {installDir}\\DolbyAutoSwitch.log",
                        "DolbyAutoSwitch — Warning",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Warning
                    );
                }
            }
            catch (Exception ex)
            {
                if (File.Exists(installScript)) File.Delete(installScript);
                MessageBox.Show(
                    $"Installation failed:\n\n{ex.Message}",
                    "DolbyAutoSwitch — Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error
                );
                return 1;
            }

            return 0;
        }

        static string BuildInstallScript(string sourceDir, string installDir)
        {
            // Escape paths for PowerShell single-quote strings
            string src = sourceDir.Replace("'", "''");
            string dst = installDir.Replace("'", "''");
            string user = $@"{Environment.UserDomainName}\{Environment.UserName}".Replace("'", "''");

            return $@"
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sourceDir  = '{src}'
$installDir = '{dst}'
$taskName   = 'DolbyAutoSwitch'
$appName    = 'DolbyAutoSwitch'
$files      = @('DolbyAutoSwitch.ps1','Uninstall-DolbyAutoSwitch.ps1','dolby_auto_switch.ico')

if (-not (Test-Path $installDir)) {{ New-Item $installDir -ItemType Directory -Force | Out-Null }}
foreach ($f in $files) {{ Copy-Item (Join-Path $sourceDir $f) $installDir -Force }}

# Task Scheduler
$scriptPath = Join-Path $installDir 'DolbyAutoSwitch.ps1'
$icoPath    = Join-Path $installDir 'dolby_auto_switch.ico'
if (Get-ScheduledTask -TaskName $taskName -EA SilentlyContinue) {{
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}}
$action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
               -Argument ""-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File \`""$scriptPath\`""""
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User '{user}'
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) `
               -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 2) `
               -MultipleInstances IgnoreNew -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId '{user}' -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Description 'Auto-enables/disables Dolby Atmos based on audio device.' `
    -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

# Settings > Apps registry entry
$uninstallExe = Join-Path $installDir 'Uninstall-DolbyAutoSwitch.exe'
$uninstallPs  = Join-Path $installDir 'Uninstall-DolbyAutoSwitch.ps1'
$uninstallCmd = if (Test-Path $uninstallExe) {{ $uninstallExe }} else {{
    ""powershell.exe -NoProfile -ExecutionPolicy Bypass -File \`""$uninstallPs\`""""
}}
$regBase = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\DolbyAutoSwitch'
New-Item $regBase -Force | Out-Null
Set-ItemProperty $regBase 'DisplayName'     'DolbyAutoSwitch'
Set-ItemProperty $regBase 'DisplayVersion'  '1.0.0'
Set-ItemProperty $regBase 'Publisher'       'DolbyAutoSwitch'
Set-ItemProperty $regBase 'InstallLocation' $installDir
Set-ItemProperty $regBase 'UninstallString' $uninstallCmd
Set-ItemProperty $regBase 'DisplayIcon'     $icoPath
Set-ItemProperty $regBase 'NoModify'        1 -Type DWord
Set-ItemProperty $regBase 'NoRepair'        1 -Type DWord
Set-ItemProperty $regBase 'EstimatedSize'   50 -Type DWord

Start-ScheduledTask -TaskName $taskName
exit 0
";
        }

        static int RunPowerShell(string scriptPath, bool wait = true)
        {
            var psi = new ProcessStartInfo
            {
                FileName        = "powershell.exe",
                Arguments       = $"-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"{scriptPath}\"",
                UseShellExecute = false,
                CreateNoWindow  = true
            };
            var p = Process.Start(psi);
            if (wait) { p.WaitForExit(); return p.ExitCode; }
            return 0;
        }

        static bool IsAdministrator()
        {
            var identity  = WindowsIdentity.GetCurrent();
            var principal = new WindowsPrincipal(identity);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }

        static void RelaunchAsAdmin()
        {
            var psi = new ProcessStartInfo
            {
                FileName        = Assembly.GetExecutingAssembly().Location,
                UseShellExecute = true,
                Verb            = "runas"
            };
            try { Process.Start(psi); }
            catch { /* user cancelled UAC */ }
        }
    }
}
