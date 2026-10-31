extends SceneTree

const Store = preload("res://project_store.gd")
const Main = preload("res://main.tscn")
var app: Control
var checks: int = 0
var failures: int = 0
var test_root: String

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func settle(frames: int = 4) -> void:
	for _frame in range(frames):
		await process_frame

func _run() -> void:
	var isolated_data = OS.get_environment("LUCKY_TEST_APPDATA").replace("\\", "/")
	var actual_data = OS.get_user_data_dir().replace("\\", "/")
	print("INTEGRATION_USER_DATA=", actual_data)
	if isolated_data.is_empty() or not actual_data.to_lower().begins_with(isolated_data.to_lower()):
		printerr("Integration tests require an isolated user data directory; preferences were not touched.")
		quit(2)
		return
	test_root = OS.get_environment("LUCKY_TEST_ROOT").path_join("lucky-integration-" + str(Time.get_ticks_usec()))
	if not test_root.is_absolute_path():
		printerr("Set LUCKY_TEST_ROOT to an absolute writable test folder.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(test_root)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1600, 1000)
	app = Main.instantiate()
	root.add_child(app)
	await settle()
	check(app.project.is_empty() and _visible_button(app, "＋  Create a project"), "Launcher starts with project creation available")
	var first = Store.create_project(test_root.path_join("first-3d"), "First project", "3D", "Blank")
	check(not first.has("error"), "Create a real 3D project")
	app._activate(first)
	await settle()
	check(is_instance_valid(app.viewport) and app.viewport.is_visible_in_tree(), "Opening a 3D project creates visible scene workspace")
	await _check_layout(Vector2i(1600, 1000))
	app._add_object("Box")
	app._property("name", "Saved Cube")
	app._property("position", [3.0, 2.0, -1.0])
	app._property("color", "#888888")
	app._save()
	var loaded = Store.load_project(first["path"])
	check(not loaded.has("error") and loaded["objects"].size() == 1 and loaded["objects"][0]["position"] == [3.0, 2.0, -1.0], "Saving editor changes persists scene transform")
	check(loaded["objects"][0]["name"] == "Saved Cube" and loaded["objects"][0]["color"] == "#888888", "Name and material survive disk roundtrip")
	app._duplicate()
	app._undo()
	check(app.project["objects"].size() == 1, "Undo removes the duplicate")
	app._redo()
	check(app.project["objects"].size() == 2 and app.project["objects"][0]["id"] != app.project["objects"][1]["id"], "Redo restores an independent duplicate")
	app._delete()
	app._save()
	DirAccess.make_dir_recursive_absolute(str(first["path"]).path_join("scripts"))
	var script_file = FileAccess.open(str(first["path"]).path_join("scripts/check.gd"), FileAccess.WRITE)
	script_file.store_string("extends Node\n\nfunc _ready() -> void:\n\tprint(\"INTEGRATION_SCRIPT_RUNNING\")\n")
	script_file.close()
	app.selected = 0
	app._property("script", "scripts/check.gd")
	app._save()
	app._open_script(str(first["path"]).path_join("scripts/check.gd"))
	app.script_editor.text += "\n# Edited inside Lucky\n"
	app.script_dirty = true
	app._save_script()
	check(FileAccess.get_file_as_string(str(first["path"]).path_join("scripts/check.gd")).contains("Edited inside Lucky"), "Script editor writes the selected project script")
	check(FileAccess.get_file_as_string(str(first["path"]).path_join("main.tscn")).contains("scripts/check.gd"), "Editor script attachment is written to generated scene")
	check(_run_saved(first, "INTEGRATION_SCRIPT_RUNNING"), "Saved editor project actually runs its attached script")
	app._return_home()
	await settle()
	check(app.project.is_empty() and _visible_button(app, "Open  →"), "Returning to launcher lists the saved project")
	app._load_project(str(first["path"]))
	await settle()
	check(app.project["objects"][0].get("script") == "scripts/check.gd" and Store.validate(app.project).is_empty(), "Reopening project preserves valid script attachment")
	await _check_layout(Vector2i(1440, 900))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1600, 1000)
	root.size = Vector2i(1100, 700)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await settle(6)
	var virtual_dimensions = Vector2i(root.get_visible_rect().size)
	print("SCALED_LAYOUT physical=", root.size, " virtual=", virtual_dimensions)
	_measure_layout(virtual_dimensions)
	app.light = true
	app._apply_theme()
	app.viewport.set_light_mode(true)
	check(app.theme.get_color("font_color", "Label") == Color.BLACK, "Light theme uses pure black text")
	app.light = false
	app._apply_theme()
	app.viewport.set_light_mode(false)
	check(app.theme.get_color("font_color", "Label") == Color.WHITE, "Dark theme uses pure white text")
	var second = Store.create_project(test_root.path_join("second-2d"), "Second project", "2D", "Blank")
	app._open_script(str(first["path"]).path_join("scripts/check.gd"))
	app._activate(second)
	await settle()
	check(app.script_path.is_empty() and not app.script_dirty, "Switching projects clears the previous script destination")
	app._add_object("Rectangle")
	app._property("rotation", [0.0, 0.0, 45.0])
	app._property("position", [400.0, 250.0, 0.0])
	app._save()
	var second_loaded = Store.load_project(str(second["path"]))
	check(second_loaded["objects"][0]["rotation"][2] == 45.0 and second_loaded["objects"][0]["position"][0] == 400.0, "2D rotation and movement persist")
	check(_run_saved(second), "Saved 2D editor scene starts without script errors")
	app._undo()
	app._redo()
	check(app.project["objects"][0]["position"][0] == 400.0, "2D undo/redo preserves final movement")
	app._save()
	app._return_home()
	await settle()
	check(app.project.is_empty(), "Switching projects and returning home completes cleanly")
	app.queue_free()
	await settle(2)
	_remove_test_directory(test_root)
	print("INTEGRATION_TESTS checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

func _check_layout(dimensions: Vector2i) -> void:
	root.size = dimensions
	app.size = Vector2(dimensions)
	await settle(6)
	_measure_layout(dimensions)

func _measure_layout(dimensions: Vector2i) -> void:
	var viewport_rect: Rect2 = app.viewport.get_global_rect()
	var ai_rect: Rect2 = app.ai_panel.get_global_rect()
	var editor_rect: Rect2 = app.workspace.get_global_rect()
	print("LAYOUT size=", dimensions, " editor=", editor_rect, " scene=", viewport_rect, " ai=", ai_rect)
	check(editor_rect.end.x <= dimensions.x + 1 and editor_rect.end.y <= dimensions.y + 1, "Editor fits " + str(dimensions))
	check(viewport_rect.size.x >= 300 and viewport_rect.size.y >= 220 and viewport_rect.end.x <= dimensions.x + 1 and ai_rect.end.x <= dimensions.x + 1, "Scene and AI panels fit " + str(dimensions))

func _visible_button(parent: Node, caption: String) -> bool:
	for child in parent.get_children():
		if child is Button and child.text == caption and child.is_visible_in_tree():
			return true
		if _visible_button(child, caption):
			return true
	return false

func _run_saved(project: Dictionary, expected: String = "") -> bool:
	var output: Array = []
	var result = OS.execute(OS.get_executable_path(), ["--headless", "--path", str(project["path"]), "--log-file", str(project["path"]).path_join("integration-run.log"), "--quit-after", "4"], output, true, false)
	var log = "\n".join(output)
	return result == 0 and not log.contains("SCRIPT ERROR") and not log.contains("Parse Error") and (expected.is_empty() or log.contains(expected))

func _remove_test_directory(folder: String) -> void:
	if test_root.is_empty() or not folder.begins_with(test_root):
		return
	var directory = DirAccess.open(folder)
	if directory == null:
		return
	for filename in directory.get_files():
		DirAccess.remove_absolute(folder.path_join(filename))
	for child in directory.get_directories():
		if not directory.is_link(child):
			_remove_test_directory(folder.path_join(child))
	DirAccess.remove_absolute(folder)
