# Lucky 0.1.0 beta validation

The release was built on Windows x64 using the verified official Godot 4.7.2 runtime and Codex app-server 0.166.0 package. No graphical application, installer wizard, authentication browser, or game window was opened. Lucky was not installed on the development computer.

| Check | Result |
| --- | --- |
| Build from the included release wrapper | Passed; native launcher, uninstaller and self-contained setup compiled |
| Godot project storage tests | 34 checks passed, zero failures |
| Editor integration tests | 25 checks passed, zero failures |
| Generated 2D and 3D projects | Started headlessly; attached scripts executed |
| Snapshots with attached scripts | Restored against the correct project folder and executed |
| Editor layout geometry | Fits 1600×1000 and 1440×900 virtual canvases; 1100×700 physical window scales correctly |
| Dark/light theme behavior | Headless UI checks passed |
| Offline AI protocol fixture | Actual process pipes, auth fixture, catalogs, reasoning, Fast on/off, text attachment, MCP config/reload, UTF-8 streaming, completion and disconnect passed |
| Real optional connector | Initialization and nine model catalog records verified in an empty isolated configuration, without authentication or inference |
| Advertised Fast field | Accepted by real protocol schema; invalid/nonexistent-thread probes made no inference request |
| Full installer extraction | Passed, 43 files; optional examples, documentation and connector present |
| Core-only installer extraction | Passed, 23 files; optional components omitted |
| Extracted payload integrity | All 43 full-install files match staged SHA-256 hashes |
| Packaged editor | Headless launcher startup and UI exercise passed using extracted runtime |
| Installer path handling | Representative archive traversal rejected; nonempty destination preserved |
| Machine-specific paths | No developer user-directory paths found in delivered editor, packaging source or docs |

Preferences and test projects were isolated in temporary build folders. No real account login, authenticated model response, provider configuration change, or external MCP operation was performed during validation.

## Remaining validation

The graphical appearance has not been visually inspected in a running window, and the wizard/shortcuts/registry/uninstallation flow has not been exercised on a clean Windows machine. Full provider sign-in, live account inference, real MCP servers and hardware/driver compatibility need user testing. The installer is unsigned. No comparative performance claims are made.

This beta is a custom editor built on an unmodified Godot runtime. Its supported editor features and remaining work are listed in FEATURES.md.
