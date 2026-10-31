using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("Lucky Engine Setup")]
[assembly: AssemblyProduct("Lucky Engine")]
[assembly: AssemblyDescription("Lucky Engine 0.1.0-beta offline Windows installer")]
[assembly: AssemblyCompany("Lucky contributors")]
[assembly: AssemblyVersion("0.1.0.0")]
[assembly: AssemblyFileVersion("0.1.0.0")]

namespace LuckySetup
{
    internal static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            // Test mode extracts the real embedded archive without creating a window,
            // registration, shortcuts, account state, or a launched application.
            if (args.Length >= 2 && args[0] == "--verify-payload")
            {
                string target = null;
                try
                {
                    target = SetupWizard.ValidateDestination(args[1]);
                    Directory.CreateDirectory(target);
                    bool all = args.Length < 3 || args[2] != "--core";
                    List<string> files = SetupWizard.ExtractPayload(target, all, all, all, delegate { });
                    object report = new { success = true, mode = all ? "all" : "core", fileCount = files.Count, files = files };
                    File.WriteAllText(Path.Combine(target, "Lucky-payload-verification.json"), new JavaScriptSerializer().Serialize(report), new UTF8Encoding(false));
                    return 0;
                }
                catch (Exception error)
                {
                    if (target != null && Directory.Exists(target))
                        File.WriteAllText(Path.Combine(target, "Lucky-payload-verification.json"), new JavaScriptSerializer().Serialize(new { success = false, error = error.ToString() }), new UTF8Encoding(false));
                    return 2;
                }
            }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            if (!Environment.Is64BitOperatingSystem)
            {
                MessageBox.Show("Lucky requires 64-bit Windows 10 or Windows 11.", "Lucky Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
            Application.Run(new SetupWizard());
            return 0;
        }
    }

    sealed class SetupWizard : Form
    {
        const string ProductId = "Lucky.Engine.0.1";
        const string Version = "0.1.0-beta";
        const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\LuckyEngine";
        readonly string[] names = { "Welcome", "License", "Components", "Destination", "Ready", "Installing", "Complete" };
        readonly Panel content = new Panel();
        readonly Label[] steps = new Label[7];
        readonly Button back = new Button();
        readonly Button next = new Button();
        readonly Button cancel = new Button();
        readonly Label title = new Label();
        readonly Label subtitle = new Label();
        TextBox destination;
        CheckBox accepted;
        CheckBox examples;
        CheckBox docs;
        CheckBox desktop;
        CheckBox connector;
        CheckBox launch;
        MonoProgress progress;
        Label status;
        int page;
        bool busy;
        bool installed;
        bool selectedExamples = true;
        bool selectedDocs = true;
        bool selectedDesktop;
        bool selectedConnector = true;
        bool bundledConnector;
        string installPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Lucky");
        string installWarning = "";

        public SetupWizard()
        {
            using (Stream payload = Assembly.GetExecutingAssembly().GetManifestResourceStream("LuckyPayload.zip"))
            {
                if (payload != null)
                    using (ZipArchive archive = new ZipArchive(payload, ZipArchiveMode.Read))
                        bundledConnector = archive.Entries.Any(entry => entry.FullName.Replace('\\', '/').Equals("tools/codex/bin/codex-app-server.exe", StringComparison.OrdinalIgnoreCase));
            }
            selectedConnector = bundledConnector;
            Text = "Lucky Engine Setup";
            Width = 880;
            Height = 600;
            MinimumSize = Size;
            MaximumSize = Size;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.Black;
            ForeColor = Color.White;
            Font = new Font("Segoe UI", 10);
            AutoScaleMode = AutoScaleMode.Dpi;
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
            FormClosing += OnClosing;

            Panel sidebar = new Panel { Dock = DockStyle.Left, Width = 205, BackColor = Color.Black };
            sidebar.Paint += delegate(object sender, PaintEventArgs e) { e.Graphics.DrawLine(Pens.DimGray, sidebar.Width - 1, 0, sidebar.Width - 1, sidebar.Height); };
            sidebar.Controls.Add(new Label { Text = "LUCKY", Location = new Point(28, 32), AutoSize = true, Font = new Font("Segoe UI", 26, FontStyle.Bold) });
            sidebar.Controls.Add(new Label { Text = "ENGINE  /  " + Version, Location = new Point(30, 83), AutoSize = true, ForeColor = Color.Silver, Font = new Font("Segoe UI", 9) });
            for (int i = 0; i < steps.Length; i++)
            {
                steps[i] = new Label { Text = (i + 1).ToString("00") + "   " + names[i], Location = new Point(30, 150 + i * 40), AutoSize = true, ForeColor = Color.Gray };
                sidebar.Controls.Add(steps[i]);
            }
            sidebar.Controls.Add(new Label { Text = "MAKE SOMETHING\nWORTH PLAYING.", Location = new Point(30, 470), AutoSize = true, Font = new Font("Segoe UI", 10, FontStyle.Bold) });
            Controls.Add(sidebar);

            Panel main = new Panel { Dock = DockStyle.Fill, Padding = new Padding(36, 28, 36, 22) };
            Controls.Add(main);
            main.BringToFront();
            title.Location = new Point(30, 30);
            title.Size = new Size(580, 48);
            title.Font = new Font("Segoe UI", 25, FontStyle.Bold);
            subtitle.Location = new Point(33, 82);
            subtitle.Size = new Size(570, 44);
            subtitle.ForeColor = Color.Silver;
            main.Controls.Add(title);
            main.Controls.Add(subtitle);
            content.Location = new Point(33, 140);
            content.Size = new Size(570, 325);
            main.Controls.Add(content);
            StyleButton(back, "Back", new Point(272, 488), false);
            StyleButton(next, "Continue", new Point(382, 488), true);
            StyleButton(cancel, "Cancel", new Point(33, 488), false);
            back.Click += delegate { if (page > 0) { CaptureSettings(); page--; ShowPage(); } };
            next.Click += OnNext;
            cancel.Click += delegate { Close(); };
            main.Controls.Add(back);
            main.Controls.Add(next);
            main.Controls.Add(cancel);
            ShowPage();
        }

        static void StyleButton(Button button, string text, Point location, bool primary)
        {
            button.Text = text;
            button.Location = location;
            button.Size = new Size(105, 40);
            button.FlatStyle = FlatStyle.Flat;
            button.FlatAppearance.BorderColor = Color.White;
            button.FlatAppearance.BorderSize = 1;
            button.BackColor = primary ? Color.White : Color.Black;
            button.ForeColor = primary ? Color.Black : Color.White;
            button.Font = new Font("Segoe UI", 10, FontStyle.Bold);
            button.Cursor = Cursors.Hand;
        }

        Label Body(string text, int y, int height)
        {
            Label label = new Label { Text = text, Location = new Point(0, y), Size = new Size(560, height), ForeColor = Color.Silver };
            content.Controls.Add(label);
            return label;
        }

        CheckBox Check(string text, int y, bool value)
        {
            CheckBox box = new CheckBox { Text = text, Location = new Point(0, y), Size = new Size(560, 32), Checked = value, ForeColor = Color.White, BackColor = Color.Black };
            content.Controls.Add(box);
            return box;
        }

        void CaptureSettings()
        {
            if (page == 2)
            {
                selectedExamples = examples.Checked;
                selectedDocs = docs.Checked;
                selectedDesktop = desktop.Checked;
                selectedConnector = connector.Checked;
            }
            if (page == 3 && destination != null) installPath = destination.Text.Trim();
        }

        void ShowPage()
        {
            content.Controls.Clear();
            title.Text = names[page];
            for (int i = 0; i < steps.Length; i++)
            {
                steps[i].ForeColor = i == page ? Color.White : Color.Gray;
                steps[i].Font = new Font("Segoe UI", 10, i == page ? FontStyle.Bold : FontStyle.Regular);
            }
            back.Visible = page > 0 && page < 5;
            next.Enabled = true;
            next.Visible = page != 5;
            cancel.Visible = page < 5;
            next.Text = page == 4 ? "Install" : page == 6 ? "Finish" : "Continue";
            if (page == 0)
            {
                title.Text = "Hello, Lucky.";
                subtitle.Text = "A fresh space to build your next game.";
                Label hero = Body("BLACK CANVAS.\nBRIGHT IDEAS.", 12, 106);
                hero.Font = new Font("Segoe UI", 26, FontStyle.Bold);
                hero.ForeColor = Color.White;
                Body("This wizard installs Lucky Engine, its bundled Godot runtime, and the files it needs to run. No administrator account is required.", 142, 70);
                Body("Windows 10 / 11  ·  64-bit\nProjects stay in the folders you choose.", 245, 65);
            }
            else if (page == 1)
            {
                subtitle.Text = "Open source software, with its notices included.";
                TextBox license = new TextBox { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Location = new Point(0, 0), Size = new Size(560, 265), BackColor = Color.Black, ForeColor = Color.White, BorderStyle = BorderStyle.FixedSingle, Font = new Font("Segoe UI", 9), Text = LicenseText };
                content.Controls.Add(license);
                accepted = Check("I accept the license terms.", 285, false);
                next.Enabled = false;
                accepted.CheckedChanged += delegate { next.Enabled = accepted.Checked; };
            }
            else if (page == 2)
            {
                subtitle.Text = "Choose what comes with your workspace.";
                CheckBox core = Check("Lucky Engine + bundled runtime  (required)", 0, true);
                core.Enabled = false;
                examples = Check("Example projects  ·  2D and 3D starting points", 48, selectedExamples);
                docs = Check("Documentation + source build guide", 96, selectedDocs);
                connector = Check("ChatGPT account connector  ·  no model files", 144, selectedConnector);
                if (!bundledConnector)
                {
                    connector.Text = "ChatGPT account connector  ·  not bundled in this build";
                    connector.Enabled = false;
                }
                desktop = Check("Create a desktop shortcut", 192, selectedDesktop);
                Body("Connector uses subscription sign-in; no API key or local model.\nStart menu shortcuts and an uninstaller are included.\nInstallation stays offline. Account sign-in requires internet.", 250, 72);
            }
            else if (page == 3)
            {
                subtitle.Text = "Install for your Windows account.";
                Body("Installation folder", 0, 28);
                destination = new TextBox { Text = installPath, Location = new Point(0, 40), Size = new Size(435, 30), BackColor = Color.Black, ForeColor = Color.White, BorderStyle = BorderStyle.FixedSingle };
                content.Controls.Add(destination);
                Button browse = new Button();
                StyleButton(browse, "Browse", new Point(449, 35), false);
                browse.Click += delegate
                {
                    using (FolderBrowserDialog picker = new FolderBrowserDialog())
                    {
                        picker.Description = "Choose an empty folder for Lucky Engine";
                        picker.SelectedPath = destination.Text;
                        if (picker.ShowDialog(this) == DialogResult.OK) destination.Text = picker.SelectedPath;
                    }
                };
                content.Controls.Add(browse);
                Body("Choose a new or empty folder. Existing files are never overwritten.\n\nTo replace an earlier Lucky installation, uninstall it first. Projects stored outside the installation folder are preserved.", 112, 125);
                Body("Your Windows account must have permission to write to this folder.", 262, 50);
            }
            else if (page == 4)
            {
                subtitle.Text = "Everything is ready. Make it yours.";
                Label summary = Body("LUCKY ENGINE " + Version + "\n\n" + installPath + "\n\nCore + Godot runtime\n" + (selectedExamples ? "Example projects\n" : "") + (selectedDocs ? "Documentation\n" : "") + (selectedConnector ? "ChatGPT account connector\n" : "") + "Start menu shortcuts" + (selectedDesktop ? " + desktop shortcut" : ""), 0, 270);
                summary.ForeColor = Color.White;
                Body("Installation stays offline. No account is needed to use the editor.", 280, 40);
            }
            else if (page == 5)
            {
                subtitle.Text = "Building your workspace.";
                Body("LUCKY IS GETTING READY.", 12, 65).Font = new Font("Segoe UI", 18, FontStyle.Bold);
                progress = new MonoProgress { Location = new Point(0, 110), Size = new Size(560, 24) };
                content.Controls.Add(progress);
                status = Body("Preparing files...", 155, 110);
                Body("Please keep this window open until setup finishes.", 280, 40);
            }
            else
            {
                title.Text = "You're in.";
                subtitle.Text = "Lucky Engine is installed.";
                Label message = Body("YOUR NEXT GAME\nSTARTS HERE.", 6, 110);
                message.Font = new Font("Segoe UI", 26, FontStyle.Bold);
                message.ForeColor = Color.White;
                launch = Check("Launch Lucky Engine", 155, true);
                Body(String.IsNullOrEmpty(installWarning) ? "Create a project in the launcher to begin.\nYou can change themes and connect AI providers in Settings." : installWarning, 220, 95);
            }
        }

        async void OnNext(object sender, EventArgs args)
        {
            if (page == 6)
            {
                if (launch.Checked)
                {
                    try { Process.Start(new ProcessStartInfo(Path.Combine(installPath, "Lucky.exe")) { WorkingDirectory = installPath, UseShellExecute = false, CreateNoWindow = true }); }
                    catch (Exception error) { MessageBox.Show(error.Message, "Lucky could not start", MessageBoxButtons.OK, MessageBoxIcon.Error); }
                }
                Close();
                return;
            }
            CaptureSettings();
            if (page == 3)
            {
                try { installPath = ValidateDestination(installPath); }
                catch (Exception error) { MessageBox.Show(error.Message, "Choose a different folder", MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
            }
            if (page == 4)
            {
                page = 5;
                busy = true;
                ShowPage();
                try
                {
                    await Task.Run((Action)Install);
                    installed = true;
                    page = 6;
                }
                catch (Exception error)
                {
                    MessageBox.Show(error.Message + "\n\nLucky was not installed. You can choose another folder and retry.", "Setup could not finish", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    page = 3;
                }
                finally { busy = false; ShowPage(); }
                return;
            }
            page++;
            ShowPage();
        }

        internal static string ValidateDestination(string folder)
        {
            if (String.IsNullOrWhiteSpace(folder) || !Path.IsPathRooted(folder)) throw new IOException("Choose a complete folder path.");
            string full = Path.GetFullPath(folder).TrimEnd(Path.DirectorySeparatorChar);
            if (String.Equals(full, Path.GetPathRoot(full).TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase))
                throw new IOException("Choose a dedicated Lucky folder, rather than a drive root.");
            if (File.Exists(full)) throw new IOException("That path is a file. Choose an empty folder.");
            if (Directory.Exists(full) && Directory.GetFileSystemEntries(full).Length > 0)
                throw new IOException("That folder contains files. Choose an empty folder so none of your files are overwritten.");
            string ancestor = full;
            while (!String.IsNullOrEmpty(ancestor))
            {
                if (Directory.Exists(ancestor) && (File.GetAttributes(ancestor) & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("Choose a folder outside linked or redirected directories.");
                ancestor = Path.GetDirectoryName(ancestor);
            }
            return full;
        }

        internal static string SafeEntry(string root, string name)
        {
            if (String.IsNullOrWhiteSpace(name) || Path.IsPathRooted(name) || name.Contains(":")) throw new InvalidDataException("The setup archive contains an invalid path.");
            string[] parts = name.Split(new char[] { '/', '\\' }, StringSplitOptions.RemoveEmptyEntries);
            foreach (string part in parts)
            {
                if (part == "." || part == ".." || part.EndsWith(".") || part.EndsWith(" ") || part.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0)
                    throw new InvalidDataException("The setup archive contains an unsafe path.");
                string stem = part.Split('.')[0].ToUpperInvariant();
                if (stem == "CON" || stem == "PRN" || stem == "AUX" || stem == "NUL" || (stem.Length == 4 && (stem.StartsWith("COM") || stem.StartsWith("LPT")) && Char.IsDigit(stem[3])))
                    throw new InvalidDataException("The setup archive contains a reserved Windows filename.");
            }
            string prefix = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            string full = Path.GetFullPath(Path.Combine(prefix, String.Join(Path.DirectorySeparatorChar.ToString(), parts)));
            if (!full.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("The setup archive points outside its installation folder.");
            return full;
        }

        void Report(int percent, string text)
        {
            Invoke((Action)delegate { progress.Value = Math.Max(0, Math.Min(100, percent)); status.Text = text; });
        }

        internal static List<string> ExtractPayload(string stage, bool selectedExamples, bool selectedDocs, bool selectedConnector, Action<int, string> report)
        {
                List<string> files = new List<string>();
                using (Stream resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("LuckyPayload.zip"))
                {
                    if (resource == null) throw new InvalidDataException("The installer payload is missing.");
                    using (ZipArchive archive = new ZipArchive(resource, ZipArchiveMode.Read))
                    {
                        if (archive.Entries.Count > 100000) throw new InvalidDataException("The setup archive contains too many files.");
                        List<ZipArchiveEntry> selected = new List<ZipArchiveEntry>();
                        long total = 0;
                        foreach (ZipArchiveEntry entry in archive.Entries)
                        {
                            SafeEntry(stage, entry.FullName);
                            string relative = entry.FullName.Replace('\\', '/');
                            if ((!selectedExamples && relative.StartsWith("examples/", StringComparison.OrdinalIgnoreCase)) || (!selectedDocs && relative.StartsWith("docs/", StringComparison.OrdinalIgnoreCase))) continue;
                            if (!selectedConnector && relative.StartsWith("tools/codex/", StringComparison.OrdinalIgnoreCase)) continue;
                            if (String.IsNullOrEmpty(entry.Name)) continue;
                            total = checked(total + entry.Length);
                            if (total > 4L * 1024 * 1024 * 1024) throw new InvalidDataException("The setup archive exceeds its allowed size.");
                            selected.Add(entry);
                        }
                        long copied = 0;
                        byte[] buffer = new byte[131072];
                        foreach (ZipArchiveEntry entry in selected)
                        {
                            string path = SafeEntry(stage, entry.FullName);
                            Directory.CreateDirectory(Path.GetDirectoryName(path));
                            using (Stream input = entry.Open())
                            using (FileStream output = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                            {
                                int read;
                                while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
                                {
                                    output.Write(buffer, 0, read);
                                    copied += read;
                                    if (copied > total) throw new InvalidDataException("The setup archive contains inconsistent file sizes.");
                                }
                            }
                            files.Add(entry.FullName.Replace('\\', '/'));
                            report(total == 0 ? 80 : (int)(copied * 90 / total), "Installing " + entry.FullName.Replace('\\', '/'));
                        }
                    }
                }
                foreach (string required in new string[] { "Lucky.exe", "Uninstall.exe", "runtime/Godot.exe", "editor/project.godot" })
                    if (!File.Exists(SafeEntry(stage, required))) throw new InvalidDataException("The installer is missing " + required + ".");
                return files;
        }

        void Install()
        {
            string target = ValidateDestination(installPath);
            string parent = Path.GetDirectoryName(target);
            Directory.CreateDirectory(parent);
            string stage = Path.Combine(parent, ".Lucky-staging-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(stage);
            bool committed = false;
            try
            {
                List<string> files = ExtractPayload(stage, selectedExamples, selectedDocs, selectedConnector, Report);
                files.Add("Lucky.install.json");
                InstallManifest manifest = new InstallManifest { ProductId = ProductId, Version = Version, Files = files };
                File.WriteAllText(Path.Combine(stage, "Lucky.install.json"), new JavaScriptSerializer().Serialize(manifest), new UTF8Encoding(false));
                // The destination is checked again immediately before the atomic directory move.
                ValidateDestination(target);
                if (Directory.Exists(target)) Directory.Delete(target, false);
                Directory.Move(stage, target);
                committed = true;
                Report(95, "Adding shortcuts and uninstall information...");
                try { RegisterInstall(target, files); }
                catch (Exception error) { installWarning = "Lucky is installed. Windows could not create every shortcut: " + error.Message + "\nYou can open Lucky.exe from the installation folder."; }
                Report(100, "Lucky is ready.");
            }
            finally
            {
                if (!committed && Directory.Exists(stage))
                {
                    string safeParent = Path.GetFullPath(parent).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
                    string fullStage = Path.GetFullPath(stage);
                    if (fullStage.StartsWith(safeParent, StringComparison.OrdinalIgnoreCase) && Path.GetFileName(fullStage).StartsWith(".Lucky-staging-", StringComparison.Ordinal))
                        Directory.Delete(fullStage, true);
                }
            }
        }

        void RegisterInstall(string root, List<string> files)
        {
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(UninstallKey))
            {
                key.SetValue("DisplayName", "Lucky Engine");
                key.SetValue("DisplayVersion", Version);
                key.SetValue("Publisher", "Lucky contributors");
                key.SetValue("InstallLocation", root);
                key.SetValue("DisplayIcon", Path.Combine(root, "Lucky.exe"));
                key.SetValue("UninstallString", "\"" + Path.Combine(root, "Uninstall.exe") + "\"");
                key.SetValue("NoModify", 1, RegistryValueKind.DWord);
                key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                long bytes = 0;
                foreach (string relative in files)
                {
                    string file = SafeEntry(root, relative);
                    if (File.Exists(file)) bytes += new FileInfo(file).Length;
                }
                key.SetValue("EstimatedSize", (int)Math.Min(Int32.MaxValue, bytes / 1024), RegistryValueKind.DWord);
            }
            string programs = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Lucky");
            Directory.CreateDirectory(programs);
            MakeShortcut(Path.Combine(programs, "Lucky.lnk"), Path.Combine(root, "Lucky.exe"), root);
            MakeShortcut(Path.Combine(programs, "Uninstall Lucky.lnk"), Path.Combine(root, "Uninstall.exe"), root);
            if (selectedDesktop) MakeShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "Lucky.lnk"), Path.Combine(root, "Lucky.exe"), root);
        }

        static void MakeShortcut(string path, string target, string root)
        {
            if (File.Exists(path)) return;
            object shell = null;
            object shortcut = null;
            try
            {
                shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
                shortcut = shell.GetType().InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { path });
                shortcut.GetType().InvokeMember("TargetPath", BindingFlags.SetProperty, null, shortcut, new object[] { target });
                shortcut.GetType().InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, shortcut, new object[] { root });
                shortcut.GetType().InvokeMember("IconLocation", BindingFlags.SetProperty, null, shortcut, new object[] { target + ",0" });
                shortcut.GetType().InvokeMember("Save", BindingFlags.InvokeMethod, null, shortcut, null);
            }
            finally
            {
                if (shortcut != null && Marshal.IsComObject(shortcut)) Marshal.ReleaseComObject(shortcut);
                if (shell != null && Marshal.IsComObject(shell)) Marshal.ReleaseComObject(shell);
            }
        }

        void OnClosing(object sender, FormClosingEventArgs args)
        {
            if (busy) { args.Cancel = true; return; }
            if (!installed && page > 0 && MessageBox.Show("Cancel Lucky installation?", "Lucky Setup", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                args.Cancel = true;
        }

        const string LicenseText = "LUCKY ENGINE — MIT LICENSE\r\nCopyright (c) 2026 Lucky contributors\r\n\r\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the Software), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\r\n\r\nThe above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\r\n\r\nTHE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.\r\n\r\nGODOT RUNTIME\r\nLucky includes an unmodified Godot Engine runtime under its MIT license. Godot and third-party copyright and license notices are included in the installed licenses folder.\r\n\r\nAI connections and optional provider applications have their own account requirements and terms. Lucky does not include a provider subscription or an AI model.";
    }

    public sealed class InstallManifest
    {
        public string ProductId { get; set; }
        public string Version { get; set; }
        public List<string> Files { get; set; }
    }

    sealed class MonoProgress : Control
    {
        int value;
        public int Value
        {
            get { return value; }
            set { this.value = Math.Max(0, Math.Min(100, value)); Invalidate(); }
        }
        public MonoProgress()
        {
            DoubleBuffered = true;
            BackColor = Color.Black;
            ForeColor = Color.White;
        }
        protected override void OnPaint(PaintEventArgs args)
        {
            args.Graphics.Clear(Color.Black);
            args.Graphics.DrawRectangle(Pens.White, 0, 0, Math.Max(0, Width - 1), Math.Max(0, Height - 1));
            args.Graphics.FillRectangle(Brushes.White, 3, 3, Math.Max(0, (Width - 6) * value / 100), Math.Max(0, Height - 6));
        }
    }
}
