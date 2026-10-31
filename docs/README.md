# Lucky Engine 0.1.0 beta

Lucky is an experimental Windows scene editor and launcher built on Godot 4.7.2. Its custom interface uses a pure black background with white text and controls. Settings also provides the inverse white-and-black theme.

This beta uses the unmodified upstream Godot runtime with new Lucky editor code. It is not a source-compiled fork of the full Godot editor, and it does not claim feature or performance parity with established engines.

## Install and start

1. Keep the release files together and run the included Lucky Setup executable.
2. Choose a new or empty installation folder and optional examples, documentation, ChatGPT account connector and desktop shortcut. The default location is the current user's local application-data folder. Administrator access is not required.
3. Finish setup to open the Lucky launcher, or leave its launch option unchecked to start later.
4. Create a project, select 2D or 3D and a template, then choose its parent folder. Lucky creates a dedicated project folder.
5. Use **Add** to create objects, **Inspector** to edit them, **Save** to write the project, and **Run** to launch it.

The package is unsigned. It has not been installed or opened in a graphical window during preparation. Headless checks are recorded in the release validation report. A Windows security prompt may identify the installer as an unknown publisher.

## Requirements

- Windows 10 or Windows 11, 64-bit x86 processor.
- Graphics hardware and driver supporting OpenGL 3.3.
- Write access to the selected installation and project folders.
- For AI: select the optional included Codex app-server connector, or provide a compatible installed executable; internet access, an eligible ChatGPT account and any required organization permission are also needed. Installing the ChatGPT desktop application alone does not guarantee a compatible app-server is available.

The game-engine runtime is included. The optional connector adds approximately 460 MB of executables, not model weights. An API key and a local language model are not required. Setup does not download extra components.

## First project

**Blank** starts with no objects. **Showcase** creates an example scene. **Platformer** creates a playable 2D scene: use A/D or arrow keys to move and Space to jump.

In 2D, drag objects to move them, use the mouse wheel to zoom and the middle mouse button to pan. In 3D, right-drag to orbit and use the wheel to adjust the view. Select an object and press **F** to frame it. The Inspector provides numeric transforms and material color.

Import images and files with **Assets → Import**. Double-click an image in a 2D project to add a sprite. Use the Script tab to create or edit GDScript files, then select an object's **Script attachment** field in the Inspector to attach a compatible script. Project tools provide rename and clone actions. See [Features](FEATURES.md) for the exact scope and limitations.

**Export** creates a portable Windows folder containing the engine runtime, project data, assets and license notices. Choose a separate empty destination folder. Keep its files together and start it with `RUN_GAME.cmd`. This is a source-folder runtime export; platform-specific optimized export templates are not part of this beta.

## Useful shortcuts

| Shortcut | Action |
| --- | --- |
| Ctrl K | Command palette |
| Ctrl S | Save project or active script |
| Ctrl Z / Ctrl Y | Undo / redo scene changes |
| Ctrl D | Duplicate the selected object |
| Delete | Remove the selected object |
| F | Frame selection |
| F5 / F8 | Run / stop the project |

Create a project snapshot with **Snapshot**. Use the command palette to restore the latest snapshot. Snapshots preserve scene data; they are not complete copies of every asset or external file.

## AI

Open **AI**, press **Connect**, and sign in if needed. Use **Connections** to choose a compatible `codex.exe` when automatic discovery fails. The sidebar discovers model names and reasoning modes from the provider. It supports streaming chat, selected image/text attachments and discovery of configured MCP servers.

AI is read-only in this beta. Prompts, attachments and any project files the assistant reads may be sent to the connected provider. Subscription limits and provider permissions still apply. Fast is available when advertised by the selected model and can increase plan usage. Other listed AI providers are unavailable. HTTPS MCP server configuration is shared with the connected provider. See [AI integration](AI.md).

## Files and recovery

Projects use `project.lucky.json` as their editable Lucky scene source. Saving regenerates `project.godot`, `main.tscn` and `LuckyRuntime.gd`; manual edits to those generated files may be replaced by the next save. Keep custom assets and scripts in their project folders. Preferences and recent-project locations are stored in the current user's application data at runtime.

Lucky opens its own project format. General import of existing Godot projects or arbitrary `.tscn` files is future work. Keep backups when experimenting.

## Source and licenses

Lucky editor source and packaging sources are included in the release. Lucky code uses the MIT license. The included Godot runtime, optional Codex connector and their third-party components retain their respective notices in `licenses` and the relevant component folders.

- [Godot source](https://github.com/godotengine/godot/tree/4.7.2-stable)
- [Godot Windows requirements and download](https://godotengine.org/download/windows/)
- [Godot license](https://godotengine.org/license/)
- [Build instructions](BUILD.md)
- [Changes in this beta](CHANGELOG.md)
