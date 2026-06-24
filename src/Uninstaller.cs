// Uninstaller.cs — DolbyAutoSwitch Uninstaller
// Compiles to Uninstall-DolbyAutoSwitch.exe
// Requires: .NET Framework 4.5+
// Build: see build.bat

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Windows.Forms;

[assembly: AssemblyTitle("DolbyAutoSwitch Uninstaller")]
[assembly: AssemblyProduct("DolbyAutoSwitch")]
[assembly: AssemblyVersion("1.0.0.0")]

namespace DolbyAutoSwitch
{
    static class Uninstaller
    {
        [STAThread]
        static int Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            if (!IsAdministrator())
            {
                RelaunchAsAdmin();
                return 0;
            }

            var confirm = MessageBox.Show(
                "This will completely remove DolbyAutoSwitch.\n\n" +
                "• Scheduled task will be stopped and deleted\n" +
                "• Dolby effects will be restored to ON\n" +
                "• All installed files will be deleted\n" +
                "• Entry removed from Settings → Apps\n\n" +
                "Continue?",
                "DolbyAutoSwitch — Uninstall",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Question
            );

            if (confirm != DialogResult.Yes) return 0;

            string installDir    = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                "DolbyAutoSwitch"
            );
            string helperScript  = Path.Combine(Path.GetTempPath(), "_das_uninstall.ps1");

            File.WriteAllText(helperScript, BuildUninstallScript(installDir));

            try
            {
                int exit = RunPowerShell(helperScript, wait: true);
                if (File.Exists(helperScript)) File.Delete(helperScript);

                MessageBox.Show(
                    "DolbyAutoSwitch has been removed.\n\n" +
                    "Dolby effects are now restored to ON.\n" +
                    "You can delete this EXE if you no longer need it.",
                    "DolbyAutoSwitch — Uninstalled",
                    MessageBoxButtons.OK,
                    exit == 0 ? MessageBoxIcon.Information : MessageBoxIcon.Warning
                );
            }
            catch (Exception ex)
            {
                if (File.Exists(helperScript)) File.Delete(helperScript);
                MessageBox.Show(
                    $"Uninstall error:\n\n{ex.Message}",
                    "DolbyAutoSwitch — Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error
                );
                return 1;
            }

            return 0;
        }

        static string BuildUninstallScript(string installDir)
        {
            string dst = installDir.Replace("'", "''");
            return $@"
Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'
$installDir = '{dst}'
$taskName   = 'DolbyAutoSwitch'
$regBase    = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\DolbyAutoSwitch'

# Stop & remove task
Stop-ScheduledTask  -TaskName $taskName -EA SilentlyContinue
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -EA SilentlyContinue

# Kill any orphaned watcher process
Get-Process powershell -EA SilentlyContinue | Where-Object {{
    (Get-WmiObject Win32_Process -Filter ""ProcessId=$($_.Id)"" -EA SilentlyContinue).CommandLine -match 'DolbyAutoSwitch'
}} | Stop-Process -Force -EA SilentlyContinue

# Restore Dolby to ON
$roots  = @('HKCU:\SOFTWARE\Dolby\Dolby Access','HKCU:\SOFTWARE\Dolby\DAX3','HKLM:\SOFTWARE\Dolby\DAX3')
$values = @('ProcessingEnabled','EffectsEnabled','EnableEffects','DolbyEnabled')
foreach ($r in $roots) {{
    if (-not (Test-Path $r)) {{ continue }}
    foreach ($v in $values) {{
        if (Get-ItemProperty $r -Name $v -EA SilentlyContinue) {{
            Set-ItemProperty $r -Name $v -Value 1 -Type DWord -EA SilentlyContinue
        }}
    }}
}}
try {{ $com = New-Object -ComObject 'DolbyLaboratories.Control.DolbyAudioProcessing' -EA Stop; $com.Enable = $true }} catch {{}}
Restart-Service 'DolbyDAXAPI' -Force -EA SilentlyContinue

# Remove Apps entry
if (Test-Path $regBase) {{ Remove-Item $regBase -Recurse -Force -EA SilentlyContinue }}

# Delete files (with delay so this script itself can finish)
Start-Sleep -Seconds 1
if (Test-Path $installDir) {{ Remove-Item $installDir -Recurse -Force -EA SilentlyContinue }}
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
            catch { }
        }
    }
}
