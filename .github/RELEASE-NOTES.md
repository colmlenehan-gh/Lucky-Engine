# Lucky Engine 0.1.0 beta

The first Lucky beta introduces a custom Windows launcher and scene editor built on the Godot 4.7.2 runtime.

- Pure black and white interface, with an inverted light theme.
- 2D and 3D projects, Showcase examples and a playable Platformer template.
- Scene editing, transforms, materials, asset import, script editing and attachment, undo/redo, project cloning and snapshots.
- Run projects and create portable Windows runtime-folder exports.
- An AI chat panel inside the editor, with an optional bundled ChatGPT account connector, discovered model and reasoning options, advertised Fast tiers and MCP connections.
- A Windows setup wizard with optional examples, documentation and account connector, plus an uninstaller.

Lucky's custom code is MIT licensed. The unmodified Godot runtime, optional Codex connector and their dependencies retain their upstream licenses and notices.

## Downloads

- `Lucky-Setup-0.1.0-beta-windows-x64.exe` — self-contained Windows x64 installer.
- `Lucky-Source-0.1.0-beta.zip` — editor, packaging source, tests and build instructions.
- `SHA256SUMS.txt` — checksums for the release files.

The release also includes `README.md`, `FEATURES.md`, `AI.md`, `BUILD.md`, `CHANGELOG.md`, `LICENSE.txt`, `THIRD-PARTY.md`, `SOURCE-MANIFEST.json` and `TEST-RESULTS.md`.

## Validation and beta scope

59 project/editor checks passed, alongside offline AI transport and package-extraction/integrity checks. The real optional connector was initialized and its model catalog inspected without authentication or inference.

This is an early custom editor on an unmodified Godot runtime, rather than a source-compiled fork of the full upstream editor. The installer is unsigned. Graphical appearance, clean-machine installation/uninstallation and live authenticated AI inference remain untested. Other AI providers and advanced editor systems remain unfinished. See `FEATURES.md` and `TEST-RESULTS.md` for the exact scope.

Requirements: Windows 10 or 11 x64 and OpenGL 3.3-compatible graphics. AI requires internet access and an eligible provider account; no API key or local language model is required.
