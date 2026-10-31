# Build Lucky 0.1.0 beta

Lucky consists of a Godot project implementing the custom editor, an upstream runtime, and Windows launcher/setup programs. Building this package does not compile a modified Godot engine from C++ source.

## Inputs

- Windows x64 with Windows PowerShell.
- The .NET Framework C# compiler used by `packaging/build.ps1` for the launcher, setup and uninstaller.
- The official [Godot 4.7.2 Windows x64 release](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable), verified against its published checksums.
- The Lucky editor source directory containing `project.godot`, scripts and `main.tscn`.
- License notices for Godot and all redistributed components.
- Optional: the official [Codex release v0.166.0](https://github.com/openai/codex/releases/tag/rust-v0.166.0) app-server Windows x64 package, including its companion executables and notices. No account credentials belong in the payload.

Keep source, intermediate output and payload directories separate. All paths below are relative examples; choose your own locations.

## One-command release build

From the extracted source bundle, run `powershell -ExecutionPolicy Bypass -File .\build-release.ps1`. It downloads and verifies the pinned upstream archives, imports editor assets headlessly, generates example projects and creates the installer in `dist/`. Add `-SkipConnector` to omit the optional account connector. This wrapper was executed successfully for this release. It does not open or install Lucky.

## Payload layout

```text
payload/
  Lucky.exe                 generated Windows launcher
  Uninstall.exe             generated uninstaller
  editor/                   Lucky Godot project and imported resources
  runtime/                  upstream Godot Windows executable
  examples/                 optional example projects
  docs/                     optional user documentation
  licenses/                 required third-party notices
  tools/codex/              optional app-server package
    bin/codex-app-server.exe
    ... companion files ...
```

Preserve the runtime and connector filenames expected by the launcher/build source. Inspect `packaging/build.ps1` and its launcher source for the exact current names. Do not redistribute a developer's `.godot/editor` metadata, application-data settings, provider credentials or recent-project locations. Imported resources required by the editor may be included after a clean headless import.

## Prepare and check the editor

Place a verified engine executable in your build environment. The following commands run without opening a graphical window:

```powershell
& .\runtime\Godot.exe --headless --path .\editor --editor --import --quit
& .\runtime\Godot.exe --headless --path .\editor --check-only --script main.gd
& .\runtime\Godot.exe --headless --path .\editor --script tests/project_store_test.gd
& .\runtime\Godot.exe --headless --path .\editor -- --self-test-ui
```

Use an isolated temporary application-data/configuration directory when running tests. Headless UI checks instantiate controls and exercise behavior but do not establish visual layout quality. Do not run authenticated AI requests as part of a build.

For the offline AI transport check, compile the included fixture and pass its executable to the Godot test. This fixture communicates over real process pipes but never accesses the network, credentials or provider configuration:

```powershell
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$fixture = Join-Path (Get-Location) 'FakeAppServer.exe'
$fixtureSource = Join-Path (Get-Location) 'editor\tests\fixtures\fake_app_server.cs'
& $compiler /nologo /target:exe /r:System.Web.Extensions.dll "/out:$fixture" $fixtureSource
& .\runtime\Godot.exe --headless --path .\editor `
  --script tests/ai_bridge_test.gd -- $fixture
```

The transport check covers initialization, fixture subscription state, catalog/effort discovery, advertised Fast on/off, text attachment framing, MCP configuration/reload requests, UTF-8 streaming, completion and cleanup. It does not establish that a real account can perform inference or authorize a real MCP server.

## Build launcher and installer

From the directory containing `packaging`:

```powershell
powershell -ExecutionPolicy Bypass -File .\packaging\build.ps1 `
  -PayloadDirectory .\payload -OutputDirectory .\dist -StageOnly
```

This compiles `payload/Lucky.exe` and `payload/Uninstall.exe`. Populate the remaining payload folders, then make a ZIP whose root contains `Lucky.exe` rather than an extra enclosing folder:

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory(
  (Join-Path (Get-Location) 'payload'),
  (Join-Path (Get-Location) 'LuckyPayload.zip'))
powershell -ExecutionPolicy Bypass -File .\packaging\build.ps1 `
  -PayloadZip .\LuckyPayload.zip -OutputDirectory .\dist
```

The result is `dist/Lucky-Setup-0.1.0-beta-windows-x64.exe`. It embeds the payload and offers optional examples, documentation and the account connector. It performs a per-user installation with no administrator requirement and no component downloads.

Use a ZIP method that retains `.godot/imported`; dropping that directory loses imported icon resources.

## Verify without installing or opening Lucky

The installer supports a payload-only check. Supply a new or empty absolute output folder:

```powershell
& .\dist\Lucky-Setup-0.1.0-beta-windows-x64.exe `
  --verify-payload (Join-Path (Get-Location) 'verify-full')
```

Add `--core` to verify extraction with optional components omitted. This mode writes `Lucky-payload-verification.json`; it does not register an installation, create shortcuts or launch the app. A return value of 0 indicates success and 2 indicates failure. Examine the report and verify that the full and core payloads contain the expected components.

Inspect the assembled release for absolute developer paths and secrets, calculate a SHA-256 checksum for the installer, and retain the validation report. The unsigned beta still needs graphical review and installation/uninstallation testing on clean supported Windows systems before a production release.

## Modify the upstream engine

The package includes unmodified upstream engine binaries. To build an actual C++ fork, obtain the [Godot source at the pinned tag](https://github.com/godotengine/godot/tree/4.7.2-stable), retain its notices, and follow the [official Windows compilation guide](https://docs.godotengine.org/en/stable/contributing/development/compiling/compiling_for_windows.html). That separate toolchain and build are not included in this beta's packaging script.
