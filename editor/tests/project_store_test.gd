extends SceneTree

const Store = preload("res://project_store.gd")
var failures: int = 0
var checks: int = 0
var test_root: String

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _run() -> void:
	test_root = OS.get_environment("TEMP").path_join("lucky-store-test-" + str(Time.get_ticks_usec()))
	if not test_root.is_absolute_path():
		test_root = ProjectSettings.globalize_path("user://lucky-store-test-" + str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(test_root)
	var project = Store.create_project(test_root.path_join("showcase"), "Roundtrip \"Lucky\"", "3D", "Showcase")
	check(not project.has("error"), "Create 3D showcase")
	check(project.get("objects", []).size() == 4, "Showcase includes four objects")
	check(Store.validate(project).is_empty(), "New project validates")
	var loaded = Store.load_project(str(project.get("path", "")))
	check(not loaded.has("error") and loaded.get("name") == project.get("name"), "Project JSON roundtrip")
	var scene = Store.generate_scene(project)
	check(scene.contains("Camera3D") and scene.contains("WorldEnvironment"), "3D scene contains camera and environment")
	check(_run_generated(project), "Generated 3D project starts headlessly without scene or script errors")
	var snapshot = Store.backup(project)
	check(not snapshot.is_empty() and FileAccess.file_exists(snapshot), "Snapshot writes a real backup")
	project["name"] = "Changed"
	check(Store.save_project(project).is_empty(), "Save edits")
	var restored = Store.restore_latest(project)
	check(not restored.has("error") and restored.get("name") == "Roundtrip \"Lucky\"", "Restore snapshot")
	check(restored.get("path") == project.get("path"), "Restored project retains correct folder")
	var fixture = test_root.path_join("fixture.txt")
	var fixture_file = FileAccess.open(fixture, FileAccess.WRITE)
	fixture_file.store_string("asset roundtrip")
	fixture_file.close()
	var imports = Store.import_assets(project, [fixture, fixture])
	check(imports.size() == 2 and imports[0] != imports[1], "Asset imports preserve existing assets")
	check(Store.list_assets(project).size() == 2, "Asset listing")
	DirAccess.make_dir_recursive_absolute(str(project["path"]).path_join("scripts"))
	var script_file = FileAccess.open(str(project["path"]).path_join("scripts/attached.gd"), FileAccess.WRITE)
	script_file.store_string("extends Node\n\nfunc _ready() -> void:\n\tprint(\"LUCKY_ATTACHED_SCRIPT_EXECUTED\")\n")
	script_file.close()
	project["objects"][0]["script"] = "scripts/attached.gd"
	check(Store.list_assets(project).has("scripts/attached.gd"), "Script folder appears in Assets")
	check(Store.save_project(project).is_empty(), "Save attached script reference")
	check(_import_generated(project), "Generated attached-script project imports headlessly")
	check(_run_generated(project, "LUCKY_ATTACHED_SCRIPT_EXECUTED"), "Attached GDScript executes in generated 3D project")
	var attached_snapshot = Store.backup(project)
	var detached = project.duplicate(true)
	detached["objects"][0].erase("script")
	var attached_restore = Store.restore_latest(detached)
	check(not attached_snapshot.is_empty() and not attached_restore.has("error") and attached_restore["objects"][0].get("script") == "scripts/attached.gd", "Snapshot restores attachment relative to project folder")
	check(attached_restore.get("path") == project.get("path"), "Attached snapshot uses original project location")
	check(not attached_restore.has("error") and Store.save_project(attached_restore).is_empty() and _run_generated(attached_restore, "LUCKY_ATTACHED_SCRIPT_EXECUTED"), "Restored attached script executes successfully")
	var runtime = test_root.path_join("runtime.exe")
	var runtime_file = FileAccess.open(runtime, FileAccess.WRITE)
	runtime_file.store_string("test runtime fixture")
	runtime_file.close()
	for license_name in ["GODOT-LICENSE.txt", "GODOT-COPYRIGHT.txt"]:
		var license_file = FileAccess.open(test_root.path_join(license_name), FileAccess.WRITE)
		license_file.store_string("test license fixture")
		license_file.close()
	var export_folder = test_root.path_join("export")
	check(Store.export_portable(project, export_folder, runtime).is_empty(), "Portable export")
	check(FileAccess.file_exists(export_folder.path_join("Game.exe")) and FileAccess.file_exists(export_folder.path_join("assets/fixture.txt")), "Export bundles runtime and assets")
	check(FileAccess.file_exists(export_folder.path_join("scripts/attached.gd")), "Export includes attached user scripts")
	check(FileAccess.file_exists(export_folder.path_join("licenses/GODOT-LICENSE.txt")) and FileAccess.file_exists(export_folder.path_join("licenses/GODOT-COPYRIGHT.txt")), "Export bundles engine and third party license notices")
	check(not Store.export_portable(project, export_folder, runtime).is_empty(), "Export protects nonempty folders")
	var cloned = Store.clone_project(project, test_root.path_join("clone"), "Cloned")
	check(not cloned.has("error") and cloned.get("name") == "Cloned" and Store.list_assets(cloned).has("scripts/attached.gd") and Store.list_assets(cloned).has("assets/fixture.txt"), "Clone project, assets, and scripts")
	check(_run_generated(cloned, "LUCKY_ATTACHED_SCRIPT_EXECUTED"), "Cloned project preserves working script attachment")
	var platformer = Store.create_project(test_root.path_join("platformer"), "Platformer", "2D", "Platformer")
	check(not platformer.has("error"), "Create 2D platformer")
	check(Store.generate_scene(platformer).contains("CharacterBody2D"), "Platformer includes playable character")
	check(_run_generated(platformer), "Generated platformer starts headlessly without scene or script errors")
	var attachment = FileAccess.open(str(platformer["path"]).path_join("assets/player.gd"), FileAccess.WRITE)
	attachment.store_string("extends CharacterBody2D\n\nfunc _ready() -> void:\n\tprint(\"LUCKY_PLAYER_SCRIPT_EXECUTED\")\n")
	attachment.close()
	platformer["objects"][0]["script"] = "assets/player.gd"
	check(Store.save_project(platformer).is_empty() and _run_generated(platformer, "LUCKY_PLAYER_SCRIPT_EXECUTED"), "2D player script attachment works")
	var invalid = project.duplicate(true)
	invalid["objects"][0]["asset"] = "assets/../../escape.png"
	check(not Store.validate(invalid).is_empty(), "Reject unsafe asset paths")
	invalid = project.duplicate(true)
	invalid["objects"][1]["id"] = invalid["objects"][0]["id"]
	check(not Store.validate(invalid).is_empty(), "Reject duplicate IDs")
	invalid = project.duplicate(true)
	invalid["objects"][0]["script"] = "scripts/../../escape.gd"
	check(not Store.validate(invalid).is_empty(), "Reject unsafe script paths")
	check(Store.create_project(str(project["path"]), "Overwrite", "2D").has("error"), "Create protects existing projects")
	_remove_test_directory(test_root)
	print("PROJECT_STORE_TESTS checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

func _run_generated(project: Dictionary, expected: String = "") -> bool:
	var output: Array = []
	var exit_code = OS.execute(OS.get_executable_path(), ["--headless", "--log-file", str(project["path"]).path_join("test-run.log"), "--path", str(project["path"]), "--quit-after", "4"], output, true, false)
	var log = "\n".join(output)
	var clean: bool = exit_code == 0 and not log.contains("SCRIPT ERROR") and not log.contains("Parse Error") and not log.contains("Failed loading resource") and (expected.is_empty() or log.contains(expected))
	if not clean:
		printerr(log)
	return clean

func _import_generated(project: Dictionary) -> bool:
	var output: Array = []
	var exit_code = OS.execute(OS.get_executable_path(), ["--headless", "--editor", "--log-file", str(project["path"]).path_join("test-import.log"), "--path", str(project["path"]), "--import"], output, true, false)
	var log = "\n".join(output)
	var clean: bool = exit_code == 0 and not log.contains("SCRIPT ERROR") and not log.contains("Parse Error") and not log.contains("Failed loading resource")
	if not clean:
		printerr(log)
	return clean

func _remove_test_directory(folder: String) -> void:
	# Only recurse within the unique folder created by this test run.
	if not folder.begins_with(test_root) or test_root.is_empty():
		return
	var directory = DirAccess.open(folder)
	if directory == null:
		return
	for file_name in directory.get_files():
		DirAccess.remove_absolute(folder.path_join(file_name))
	for subfolder in directory.get_directories():
		_remove_test_directory(folder.path_join(subfolder))
	DirAccess.remove_absolute(folder)
