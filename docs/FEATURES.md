# Features and beta scope

The following features are implemented in the Lucky source. Headless tests verify selected flows; a complete graphical usability and clean-machine installation test is still required.

## Launcher and appearance

- Custom Lucky launcher and editor interface.
- Pure black default surfaces with white foreground controls.
- Inverted white/black light theme in Settings.
- Recent-project list, name filtering and removal from the list.
- Project renaming and cloning.
- Optional example gallery that copies examples into a user-selected location.
- Project creation into a dedicated folder.
- Open existing Lucky project manifests.
- Blank, Showcase and playable 2D Platformer templates.
- Searchable command palette.
- Resizable editor panels and a hideable AI sidebar.
- Saved appearance, autosave and snapping preferences.

## Scene editing

- Native Godot-backed 3D scene preview.
- 2D scene canvas with image sprites, shapes and labels.
- 3D box, sphere, plane and capsule primitives.
- Scene object filtering and mouse selection.
- Object names, visibility, position, rotation and scale data.
- Material color and label-text editing.
- Duplicate, delete and reorder objects.
- Scene undo and redo history, bounded to 150 recorded changes.
- Grid display and movement snapping.
- 2D object dragging, zoom and pan.
- 3D camera orbit and zoom.
- Frame selection and reset viewport commands.

## Project workflow

- Save a portable Lucky JSON manifest.
- Generate native `project.godot`, `main.tscn` and runtime script files.
- Validate object IDs, supported types, transforms, colors and asset paths.
- Refuse to create projects over existing nonempty folders.
- Use temporary-file replacement when writing project files.
- Autosave scene changes every 60 seconds when enabled.
- Create scene-data snapshots and restore the latest snapshot.
- Import files into the project without overwriting duplicate filenames.
- Browse imported assets and add image sprites to 2D scenes.
- GDScript editing with line numbers, basic highlighting and brace completion.
- Per-object GDScript attachment from the project's scripts and imported assets.
- Unsaved-change prompts when switching projects or scripts.
- Run and stop projects with the included engine runtime.
- Read runtime output in the editor output panel.
- Playable platformer movement, jumping and rectangle collision in the template.
- Portable Windows runtime-folder export to a separate empty destination.
- Include upstream runtime license notices in portable exports.
- Editor output log and keyboard shortcuts.

## Assistant integration

- Chat panel inside the Lucky window.
- Connect to the optional included Codex app-server or a compatible installed executable.
- Use existing supported ChatGPT sign-in or start a user-initiated sign-in.
- No API-key field, credential copying or local model requirement.
- Discover the available model catalog and reasoning-effort options.
- Request Fast/priority service only for models that advertise it.
- Stream assistant text and stop an active turn.
- Attach supported image formats and text/code files.
- List configured MCP servers and their reported authorization state.
- Add HTTPS MCP server URLs to shared provider configuration and request server OAuth.
- Keep AI turns read-only and decline command/file-change approval requests.
- Discard stale conversation events when a conversation is reset.

## Not implemented in this beta

- A complete replacement for every Godot editor subsystem.
- General Godot project or arbitrary scene import.
- A full scene-node hierarchy, animation timeline, shader graph or visual scripting system.
- Comprehensive resource inspectors, terrain tools, advanced physics authoring or asset pipelines.
- Integrated debugging, code completion or a full GDScript language server.
- Automatic AI changes to project files.
- Working Claude Code, Cursor, Grok or OpenCode adapters.
- Automatic third-party plugin-package or local AI model installation.
- Cross-platform native game exports, mobile toolchains or console deployment.
- Cloud accounts, team collaboration, cloud sync or a hosted marketplace.
- A signed installer or measured performance comparisons with other engines.

The included runtime provides underlying Godot functionality, but that does not mean every upstream capability is exposed through Lucky's custom editor UI.
