using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: System.Reflection.AssemblyTitle("Lucky Engine")]
[assembly: System.Reflection.AssemblyProduct("Lucky Engine")]
[assembly: System.Reflection.AssemblyDescription("Lucky Engine desktop launcher and uninstaller")]
[assembly: System.Reflection.AssemblyCompany("Lucky contributors")]
[assembly: System.Reflection.AssemblyVersion("0.1.0.0")]
[assembly: System.Reflection.AssemblyFileVersion("0.1.0.0")]

namespace LuckyDesktop
{
    internal static class Program
    {
        const string ProductId = "Lucky.Engine.0.1";
        const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\LuckyEngine";

        [STAThread]
        static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
#if UNINSTALL
            Uninstall();
#else
            try
            {
                string root = Application.StartupPath;
                string engine = Path.Combine(root, "runtime", "Godot.exe");
                string editor = Path.Combine(root, "editor");
                if (!File.Exists(engine) || !File.Exists(Path.Combine(editor, "project.godot")))
                    throw new FileNotFoundException("Lucky's runtime files are missing. Reinstall Lucky to restore them.");
                ProcessStartInfo start = new ProcessStartInfo(engine);
                start.Arguments = "--path " + Quote(editor) + " --rendering-method gl_compatibility --no-header";
                start.WorkingDirectory = editor;
                start.UseShellExecute = false;
                start.CreateNoWindow = true;
                Process.Start(start);
            }
            catch (Exception error)
            {
                MessageBox.Show(error.Message, "Lucky could not start", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
#endif
        }

        static string Quote(string path)
        {
            return "\"" + path.TrimEnd(Path.DirectorySeparatorChar) + "\"";
        }

        static string InstalledFile(string root, string relative)
        {
            if (String.IsNullOrWhiteSpace(relative) || Path.IsPathRooted(relative) || relative.Contains(":"))
                throw new InvalidDataException("The installation manifest contains an invalid path.");
            string prefix = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            string full = Path.GetFullPath(Path.Combine(prefix, relative.Replace('/', Path.DirectorySeparatorChar)));
            if (!full.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("The installation manifest points outside Lucky's folder.");
            string ancestor = Path.GetDirectoryName(full);
            while (!String.IsNullOrEmpty(ancestor) && ancestor.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                if (Directory.Exists(ancestor) && (File.GetAttributes(ancestor) & FileAttributes.ReparsePoint) != 0)
                    throw new InvalidDataException("Lucky cannot uninstall through a linked directory.");
                ancestor = Path.GetDirectoryName(ancestor);
            }
            return full;
        }

        static void Uninstall()
        {
            try
            {
                string root = Path.GetFullPath(Application.StartupPath);
                if ((File.GetAttributes(root) & FileAttributes.ReparsePoint) != 0)
                    throw new InvalidDataException("Run Uninstall from Lucky's original installation folder.");
                string marker = Path.Combine(root, "Lucky.install.json");
                if (!File.Exists(marker))
                    throw new InvalidDataException("Lucky's installation manifest is missing. No files were removed.");
                JavaScriptSerializer json = new JavaScriptSerializer();
                InstallManifest manifest = json.Deserialize<InstallManifest>(File.ReadAllText(marker));
                if (manifest == null || manifest.ProductId != ProductId || manifest.Files == null || !manifest.Files.Contains("Lucky.exe"))
                    throw new InvalidDataException("This folder does not contain a valid Lucky installation. No files were removed.");
                List<string> verified = new List<string>();
                foreach (string relative in manifest.Files)
                    verified.Add(InstalledFile(root, relative));
                if (MessageBox.Show("Remove Lucky Engine from this computer?\n\nOnly files installed by Lucky will be removed. Your projects and other added files will be preserved.", "Uninstall Lucky", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                    return;
                List<string> failed = new List<string>();
                string self = Application.ExecutablePath;
                foreach (string full in verified)
                {
                    if (String.Equals(full, self, StringComparison.OrdinalIgnoreCase) || String.Equals(full, marker, StringComparison.OrdinalIgnoreCase))
                        continue;
                    try { if (File.Exists(full)) File.Delete(full); }
                    catch { failed.Add(full); }
                }
                if (failed.Count == 0)
                {
                    RemoveShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Lucky", "Lucky.lnk"), root);
                    RemoveShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Lucky", "Uninstall Lucky.lnk"), root);
                    RemoveShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "Lucky.lnk"), root);
                    using (RegistryKey key = Registry.CurrentUser.OpenSubKey(UninstallKey))
                    {
                        if (key != null && String.Equals(Convert.ToString(key.GetValue("InstallLocation")), root, StringComparison.OrdinalIgnoreCase))
                            Registry.CurrentUser.DeleteSubKeyTree(UninstallKey, false);
                    }
                    File.Delete(marker);
                    DeleteEmptyChildren(root);
                    // The running uninstaller cannot delete itself. Windows removes it at restart.
                    bool scheduled = MoveFileEx(self, null, 4);
                    if (scheduled) MoveFileEx(root, null, 4);
                    MessageBox.Show("Lucky has been removed. Your projects were preserved.\n\nThe small uninstaller file may remain until you restart Windows; you can also delete it after closing this message.", "Lucky removed", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
                else
                {
                    MessageBox.Show("Some Lucky files are still in use. Close Lucky and run Uninstall again.\n\nYour projects have been preserved.", "Uninstall incomplete", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
            }
            catch (Exception error)
            {
                MessageBox.Show(error.Message, "Could not uninstall Lucky", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        static void RemoveShortcut(string path, string root)
        {
            if (!File.Exists(path)) return;
            object shell = null;
            object shortcut = null;
            try
            {
                shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
                shortcut = shell.GetType().InvokeMember("CreateShortcut", System.Reflection.BindingFlags.InvokeMethod, null, shell, new object[] { path });
                string target = Convert.ToString(shortcut.GetType().InvokeMember("TargetPath", System.Reflection.BindingFlags.GetProperty, null, shortcut, null));
                if (target.StartsWith(root.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                    File.Delete(path);
            }
            catch { }
            finally
            {
                if (shortcut != null && Marshal.IsComObject(shortcut)) Marshal.ReleaseComObject(shortcut);
                if (shell != null && Marshal.IsComObject(shell)) Marshal.ReleaseComObject(shell);
            }
        }

        static void DeleteEmptyChildren(string root)
        {
            foreach (string directory in Directory.GetDirectories(root))
            {
                if ((File.GetAttributes(directory) & FileAttributes.ReparsePoint) != 0) continue;
                DeleteEmptyChildren(directory);
                try { if (Directory.GetFileSystemEntries(directory).Length == 0) Directory.Delete(directory); } catch { }
            }
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern bool MoveFileEx(string existing, string destination, int flags);
    }

    public sealed class InstallManifest
    {
        public string ProductId { get; set; }
        public string Version { get; set; }
        public List<string> Files { get; set; }
    }
}
