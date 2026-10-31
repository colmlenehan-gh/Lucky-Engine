extends RefCounted
## Portable Lucky project storage and Godot scene generation.
## No machine-specific paths are stored in the project manifest.

const VERSION = "0.1.0-beta"
const MANIFEST = "project.lucky.json"
const MAX_OBJECTS = 10000
const TYPES_2D = ["Rectangle", "Circle", "Label", "Sprite"]
const TYPES_3D = ["Box", "Sphere", "Plane", "Capsule"]

static func create_project(folder: String, project_name: String, dimension: String, template: String = "Blank") -> Dictionary:
	var clean_name = project_name.strip_edges()
	if clean_name.is_empty() or clean_name.length() > 120:
		return {"error": "Use a project name between 1 and 120 characters."}
	if dimension not in ["2D", "3D"]:
		return {"error": "Choose a 2D or 3D project."}
	if not folder.is_absolute_path():
		return {"error": "Choose an absolute project folder."}
	var target = folder.simplify_path()
	if DirAccess.dir_exists_absolute(target):
		var existing = DirAccess.open(target)
		if existing == null or existing.get_files().size() > 0 or existing.get_directories().size() > 0:
			return {"error": "Choose an empty folder to protect existing files."}
	var mkdir_error = DirAccess.make_dir_recursive_absolute(target)
	if mkdir_error != OK:
		return {"error": "Cannot create project folder: " + error_string(mkdir_error)}
	DirAccess.make_dir_recursive_absolute(target.path_join("assets"))
	var project = {"name": clean_name, "dimension": dimension, "version": VERSION, "objects": [], "path": target}
	project["objects"] = template_objects(dimension, template)
	var problem = save_project(project)
	if not problem.is_empty():
		return {"error": problem}
	return project

static func make_object(object_name: String, kind: String, position: Array, color: String = "#ffffff", object_scale: Array = [1.0, 1.0, 1.0]) -> Dictionary:
	return {"id": str(Time.get_ticks_usec()) + "-" + str(randi()), "name": object_name, "type": kind,
		"position": position.duplicate(), "rotation": [0.0, 0.0, 0.0], "scale": object_scale.duplicate(), "color": color, "visible": true}

static func template_objects(dimension: String, template: String) -> Array:
	var items: Array = []
	if template.to_lower() == "blank":
		return items
	if dimension == "2D":
		if template.to_lower().contains("platform"):
			var player = make_object("Player", "Rectangle", [250.0, 400.0, 0.0], "#ffffff", [0.6, 1.0, 1.0])
			player["player"] = true
			items.append(player)
			items.append(make_object("Ground", "Rectangle", [640.0, 640.0, 0.0], "#777777", [16.0, 1.0, 1.0]))
			items.append(make_object("Platform A", "Rectangle", [470.0, 490.0, 0.0], "#aaaaaa", [3.0, 0.4, 1.0]))
			items.append(make_object("Platform B", "Rectangle", [810.0, 350.0, 0.0], "#dddddd", [3.0, 0.4, 1.0]))
			var hint = make_object("Controls", "Label", [55.0, 55.0, 0.0], "#ffffff")
			hint["text"] = "A / D or arrows to move. Space to jump."
			items.append(hint)
		else:
			items.append(make_object("Card", "Rectangle", [640.0, 360.0, 0.0], "#444444", [5.0, 4.0, 1.0]))
			items.append(make_object("Orb", "Circle", [640.0, 300.0, 0.0], "#ffffff", [1.8, 1.8, 1.0]))
			var label = make_object("Title", "Label", [510.0, 420.0, 0.0])
			label["text"] = "Made with Lucky"
			items.append(label)
	else:
		items.append(make_object("Ground", "Plane", [0.0, -0.6, 0.0], "#303030", [1.5, 1.0, 1.5]))
		var hero = make_object("Hero", "Box", [0.0, 0.5, 0.0], "#ffffff", [1.8, 1.8, 1.8])
		hero["rotation"] = [0.0, 30.0, 0.0]
		hero["animate"] = true
		items.append(hero)
		items.append(make_object("Satellite", "Sphere", [-3.0, 0.4, -1.0], "#999999", [1.4, 1.4, 1.4]))
		items.append(make_object("Marker", "Capsule", [3.0, 0.5, -1.0], "#dddddd"))
	return items

static func load_project(file_or_folder: String) -> Dictionary:
	var manifest_path = file_or_folder
	if DirAccess.dir_exists_absolute(file_or_folder):
		manifest_path = file_or_folder.path_join(MANIFEST)
		if not FileAccess.file_exists(manifest_path):
			manifest_path = file_or_folder.path_join(".lucky.json")
	elif file_or_folder.get_file() == "project.godot":
		manifest_path = file_or_folder.get_base_dir().path_join(MANIFEST)
	var file = FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return {"error": "This folder does not contain a readable Lucky project."}
	if file.get_length() > 33554432:
		return {"error": "Project manifest exceeds the 32 MB safety limit."}
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {"error": "Project file is not valid JSON."}
	var project: Dictionary = json.data
	project["path"] = manifest_path.get_base_dir().simplify_path()
	var errors = validate(project)
	if not errors.is_empty():
		return {"error": "Invalid project: " + "; ".join(errors)}
	return project

static func validate(project: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not project.get("name", "") is String or str(project.get("name", "")).strip_edges().is_empty():
		errors.append("Project needs a name")
	if project.get("dimension", "") not in ["2D", "3D"]:
		errors.append("Unknown project dimension")
	if not project.get("path", "") is String or not str(project.get("path", "")).is_absolute_path():
		errors.append("Project needs an absolute folder")
	if not project.get("objects", null) is Array:
		errors.append("Scene objects must be an array")
		return errors
	if project["objects"].size() > MAX_OBJECTS:
		errors.append("Project exceeds 10,000 scene objects")
		return errors
	var seen: Dictionary = {}
	var kinds = TYPES_2D if project.get("dimension") == "2D" else TYPES_3D
	for item in project["objects"]:
		if not item is Dictionary:
			errors.append("Every scene object must be a dictionary")
			continue
		var object_name = str(item.get("name", "Object"))
		if str(item.get("id", "")).is_empty() or seen.has(str(item.get("id", ""))):
			errors.append(object_name + ": missing or duplicate object ID")
		seen[str(item.get("id", ""))] = true
		if item.get("type", "") not in kinds:
			errors.append(object_name + ": unsupported object type")
		for key in ["position", "rotation", "scale"]:
			var vector = item.get(key, null)
			if not vector is Array or vector.size() != 3:
				errors.append(object_name + ": " + key + " needs three numbers")
				continue
			for component in vector:
				if (not component is float and not component is int) or not is_finite(float(component)):
					errors.append(object_name + ": " + key + " contains an invalid number")
		if not item.get("color", "#ffffff") is String or not Color.html_is_valid(str(item.get("color", "#ffffff"))):
			errors.append(object_name + ": invalid color")
		if item.has("asset") and not _safe_asset(str(item["asset"])):
			errors.append(object_name + ": asset must be inside the assets folder")
		if item.has("script") and not str(item["script"]).is_empty():
			if not _safe_script(str(item["script"])):
				errors.append(object_name + ": script must be a .gd file in assets or scripts")
			elif not FileAccess.file_exists(str(project.get("path", "")).path_join(str(item["script"]))):
				errors.append(object_name + ": attached script is missing")
	return errors

static func save_project(project: Dictionary) -> String:
	var problems = validate(project)
	if not problems.is_empty():
		return "; ".join(problems)
	var folder: String = project["path"]
	if not DirAccess.dir_exists_absolute(folder):
		return "Project folder no longer exists."
	var data = project.duplicate(true)
	data.erase("path")
	data.erase("modified")
	data["version"] = VERSION
	var files = {
		MANIFEST: JSON.stringify(data, "\t"),
		"project.godot": _project_config(project),
		"main.tscn": generate_scene(project),
		"LuckyRuntime.gd": _runtime_script()
	}
	for relative in files:
		var error = _atomic_write(folder.path_join(relative), files[relative])
		if not error.is_empty():
			return error
	return ""

static func _project_config(project: Dictionary) -> String:
	return "config_version=5\n\n[application]\nconfig/name=%s\nrun/main_scene=\"res://main.tscn\"\n\n[display]\nwindow/size/viewport_width=1280\nwindow/size/viewport_height=720\nwindow/stretch/mode=\"canvas_items\"\n\n[rendering]\nrenderer/rendering_method=\"gl_compatibility\"\nrenderer/rendering_method.mobile=\"gl_compatibility\"\nenvironment/defaults/default_clear_color=Color(0, 0, 0, 1)\n" % _q(str(project["name"]))

static func generate_scene(project: Dictionary) -> String:
	var is_3d: bool = project.get("dimension", "2D") == "3D"
	var resources: Array[String] = []
	var external: Array[String] = ['[ext_resource type="Script" path="res://LuckyRuntime.gd" id="1_runtime"]\n']
	var nodes: Array[String] = []
	var resource_count = 1
	if is_3d:
		resources.append('[sub_resource type="Environment" id="Environment_lucky"]\nbackground_mode = 1\nbackground_color = Color(0, 0, 0, 1)\nambient_light_source = 3\nambient_light_color = Color(1, 1, 1, 1)\nambient_light_energy = 0.7\n')
		resource_count += 1
	for i in range(project.get("objects", []).size()):
		var item: Dictionary = project["objects"][i]
		var suffix = str(i)
		var attachment = ""
		if not str(item.get("script", "")).is_empty() and _safe_script(str(item.get("script", ""))):
			external.append('[ext_resource type="Script" path=%s id="Script_%s"]\n' % [_q("res://" + str(item["script"]).replace("\\", "/")), suffix])
			resource_count += 1
			attachment = 'script = ExtResource("Script_%s")\n' % suffix
		var kind: String = str(item.get("type", "Box"))
		var color = Color(str(item.get("color", "#ffffff")))
		var node_name = _node_name(str(item.get("name", "Object")), i)
		var visible = "true" if item.get("visible", true) else "false"
		var p: Array = item.get("position", [0, 0, 0])
		var r: Array = item.get("rotation", [0, 0, 0])
		var s: Array = item.get("scale", [1, 1, 1])
		if is_3d:
			resources.append('[sub_resource type="StandardMaterial3D" id="Material_%s"]\nalbedo_color = %s\nroughness = 0.55\n' % [suffix, _color_string(color)])
			var mesh_type = {"Box": "BoxMesh", "Sphere": "SphereMesh", "Plane": "PlaneMesh", "Capsule": "CapsuleMesh"}.get(kind, "BoxMesh")
			var extra = "size = Vector2(8, 8)\n" if kind == "Plane" else ""
			resources.append('[sub_resource type="%s" id="Mesh_%s"]\nmaterial = SubResource("Material_%s")\n%s' % [mesh_type, suffix, suffix, extra])
			resource_count += 2
			nodes.append('[node name=%s type="MeshInstance3D" parent="."]\nposition = %s\nrotation = %s\nscale = %s\nvisible = %s\nmesh = SubResource("Mesh_%s")\n%smetadata/animate = %s\n' % [_q(node_name), _vector3(p), _radians3(r), _vector3(s), visible, suffix, attachment, "true" if item.get("animate", false) else "false"])
		else:
			var body_type = "CharacterBody2D" if item.get("player", false) else "Node2D"
			nodes.append('[node name=%s type="%s" parent="."]\nposition = Vector2(%s, %s)\nrotation = %s\nscale = Vector2(%s, %s)\nvisible = %s\n%smetadata/player = %s\n' % [_q(node_name), body_type, _num(p[0]), _num(p[1]), _num(deg_to_rad(float(r[2]))), _num(s[0]), _num(s[1]), visible, attachment, "true" if item.get("player", false) else "false"])
			var parent_path = _q(node_name)
			if kind == "Label":
				nodes.append('[node name="Text" type="Label" parent=%s]\ntext = %s\nmodulate = %s\ntheme_override_font_sizes/font_size = 26\n' % [parent_path, _q(str(item.get("text", item.get("name", "Label")))), _color_string(color)])
			elif kind == "Sprite" and _safe_asset(str(item.get("asset", ""))):
				nodes.append('[node name="Image" type="Sprite2D" parent=%s]\nmodulate = %s\nmetadata/asset = %s\n' % [parent_path, _color_string(color), _q(str(item.get("asset")))])
			else:
				var points: Array[String] = []
				if kind == "Circle":
					for k in range(48):
						points.append(_num(cos(float(k) / 48.0 * TAU) * 32.0))
						points.append(_num(sin(float(k) / 48.0 * TAU) * 32.0))
				else:
					points.assign(["-40", "-30", "40", "-30", "40", "30", "-40", "30"])
				nodes.append('[node name="Shape" type="Polygon2D" parent=%s]\npolygon = PackedVector2Array(%s)\ncolor = %s\n' % [parent_path, ", ".join(points), _color_string(color)])
				if kind == "Rectangle":
					resources.append('[sub_resource type="RectangleShape2D" id="Collision_%s"]\nsize = Vector2(80, 60)\n' % suffix)
					resource_count += 1
					if item.get("player", false):
						nodes.append('[node name="Collision" type="CollisionShape2D" parent=%s]\nshape = SubResource("Collision_%s")\n' % [parent_path, suffix])
					else:
						nodes.append('[node name="Body" type="StaticBody2D" parent=%s]\n\n[node name="Collision" type="CollisionShape2D" parent=%s]\nshape = SubResource("Collision_%s")\n' % [parent_path, _q(node_name + "/Body"), suffix])
	var header = '[gd_scene load_steps=%d format=3]\n\n' % (resource_count + 1)
	header += "\n".join(external) + "\n"
	var root = '[node name="World" type="%s"]\nscript = ExtResource("1_runtime")\n\n' % ("Node3D" if is_3d else "Node2D")
	if is_3d:
		root += '[node name="Environment" type="WorldEnvironment" parent="."]\nenvironment = SubResource("Environment_lucky")\n\n[node name="KeyLight" type="DirectionalLight3D" parent="."]\nrotation_degrees = Vector3(-50, -25, 0)\nlight_energy = 1.6\n\n[node name="Camera" type="Camera3D" parent="."]\nposition = Vector3(9, 7, 11)\ncurrent = true\n\n'
	return header + "\n".join(resources) + "\n" + root + "\n".join(nodes)

static func _runtime_script() -> String:
	return '''extends Node
var camera: Camera3D
var player: CharacterBody2D
var orbit_angle: float = 0.68
var orbit_distance: float = 16.0
var orbit_height: float = 7.0

func _ready() -> void:
	camera = get_node_or_null("Camera") as Camera3D
	if camera != null:
		camera.look_at(Vector3.ZERO, Vector3.UP)
	for child in get_children():
		if child is CharacterBody2D and child.get_meta("player", false):
			player = child
	_load_images(self)

func _load_images(parent: Node) -> void:
	for child in parent.get_children():
		if child is Sprite2D and child.has_meta("asset"):
			var image = Image.load_from_file(ProjectSettings.globalize_path("res://" + str(child.get_meta("asset"))))
			if image != null:
				child.texture = ImageTexture.create_from_image(image)
		_load_images(child)

func _process(delta: float) -> void:
	for child in get_children():
		if child is Node3D and child.get_meta("animate", false):
			child.rotate_y(delta * 0.35)

func _physics_process(delta: float) -> void:
	if player == null:
		return
	var direction: float = 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		direction -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		direction += 1.0
	player.velocity.x = direction * 330.0
	player.velocity.y += 1150.0 * delta
	if player.is_on_floor() and Input.is_physical_key_pressed(KEY_SPACE):
		player.velocity.y = -630.0
	player.move_and_slide()
	if player.position.y > 1400.0:
		player.position = Vector2(250, 400)
		player.velocity = Vector2.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		orbit_angle -= event.relative.x * 0.01
		orbit_height = clampf(orbit_height + event.relative.y * 0.04, 1.0, 20.0)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_distance = maxf(3.0, orbit_distance - 1.0)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance = minf(40.0, orbit_distance + 1.0)
	camera.position = Vector3(sin(orbit_angle) * orbit_distance, orbit_height, cos(orbit_angle) * orbit_distance)
	camera.look_at(Vector3.ZERO, Vector3.UP)
'''

static func list_assets(project: Dictionary) -> Array[String]:
	var assets: Array[String] = []
	_list_files(str(project.get("path", "")).path_join("assets"), "assets", assets)
	_list_files(str(project.get("path", "")).path_join("scripts"), "scripts", assets)
	assets.sort()
	return assets

static func _list_files(folder: String, relative: String, out: Array[String]) -> void:
	var dir = DirAccess.open(folder)
	if dir == null:
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".import"):
			out.append(relative.path_join(file_name))
	for subfolder in dir.get_directories():
		if not subfolder.begins_with(".") and not dir.is_link(folder.path_join(subfolder)):
			_list_files(folder.path_join(subfolder), relative.path_join(subfolder), out)

static func import_assets(project: Dictionary, paths: Array) -> Array:
	var results: Array = []
	var folder = str(project.get("path", "")).path_join("assets")
	if not str(project.get("path", "")).is_absolute_path():
		return [{"error": "Open a project before importing assets."}]
	DirAccess.make_dir_recursive_absolute(folder)
	for source in paths:
		var original = str(source)
		if not FileAccess.file_exists(original):
			results.append({"error": "Cannot read " + original.get_file()})
			continue
		var file_name = original.get_file().validate_filename()
		var destination = folder.path_join(file_name)
		var counter = 1
		while FileAccess.file_exists(destination):
			var extension = "." + file_name.get_extension() if not file_name.get_extension().is_empty() else ""
			destination = folder.path_join(file_name.get_basename() + "_" + str(counter) + extension)
			counter += 1
		var err = DirAccess.copy_absolute(original, destination)
		if err == OK:
			results.append("assets/" + destination.get_file())
		else:
			results.append({"error": "Import failed: " + error_string(err)})
	return results

static func backup(project: Dictionary) -> String:
	var problems = validate(project)
	if not problems.is_empty():
		return ""
	var folder = str(project["path"]).path_join(".lucky/backups")
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return ""
	var data = project.duplicate(true)
	data.erase("path")
	var stamp = Time.get_datetime_string_from_system().replace(":", "-") + "-" + str(Time.get_ticks_usec()).pad_zeros(20)
	var target = folder.path_join(stamp + ".json")
	if not _atomic_write(target, JSON.stringify(data, "\t")).is_empty():
		return ""
	return target

static func restore_latest(project: Dictionary) -> Dictionary:
	var folder = str(project.get("path", "")).path_join(".lucky/backups")
	var directory = DirAccess.open(folder)
	if directory == null:
		return {"error": "No snapshots have been saved for this project."}
	var files: Array[String] = []
	for file_name in directory.get_files():
		if file_name.ends_with(".json"):
			files.append(file_name)
	files.sort()
	if files.is_empty():
		return {"error": "No snapshots have been saved for this project."}
	var file = FileAccess.open(folder.path_join(files[-1]), FileAccess.READ)
	if file == null:
		return {"error": "The latest snapshot could not be read."}
	if file.get_length() > 33554432:
		return {"error": "Snapshot exceeds the 32 MB safety limit."}
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {"error": "The latest snapshot is not valid project JSON."}
	var restored: Dictionary = json.data
	# Resolve attachments against the real project before validating snapshot data.
	restored["path"] = project.get("path", "")
	var errors = validate(restored)
	if not errors.is_empty():
		return {"error": "Invalid snapshot: " + "; ".join(errors)}
	return restored

static func export_portable(project: Dictionary, destination: String, runtime_path: String) -> String:
	var errors = validate(project)
	if not errors.is_empty():
		return "; ".join(errors)
	if not destination.is_absolute_path() or not FileAccess.file_exists(runtime_path):
		return "Choose a valid export folder and a bundled Windows engine executable."
	var runtime_folder = runtime_path.get_base_dir()
	var license_sources: Dictionary = {}
	for license_name in ["GODOT-LICENSE.txt", "GODOT-COPYRIGHT.txt"]:
		for candidate in [runtime_folder.path_join(license_name), runtime_folder.path_join("licenses").path_join(license_name), runtime_folder.get_base_dir().path_join("licenses").path_join(license_name)]:
			if FileAccess.file_exists(candidate):
				license_sources[license_name] = candidate
				break
		if not license_sources.has(license_name):
			return "Bundled engine license is missing: " + license_name
	var target = destination.simplify_path()
	var source = str(project["path"]).simplify_path()
	var compared_target = target.replace("\\", "/").trim_suffix("/")
	var compared_source = source.replace("\\", "/").trim_suffix("/")
	if OS.get_name() == "Windows":
		compared_target = compared_target.to_lower()
		compared_source = compared_source.to_lower()
	if compared_target == compared_source or compared_target.begins_with(compared_source + "/"):
		return "Export to a separate folder outside the project."
	if DirAccess.dir_exists_absolute(target):
		var dir = DirAccess.open(target)
		if dir == null or dir.get_files().size() > 0 or dir.get_directories().size() > 0:
			return "Export folder must be empty to protect existing files."
	var err = DirAccess.make_dir_recursive_absolute(target)
	if err != OK:
		return "Cannot create export folder: " + error_string(err)
	var exported = project.duplicate(true)
	exported["path"] = target
	for asset in list_assets(project):
		var asset_target = target.path_join(asset)
		DirAccess.make_dir_recursive_absolute(asset_target.get_base_dir())
		err = DirAccess.copy_absolute(source.path_join(asset), asset_target)
		if err != OK:
			return "Cannot export asset " + asset + ": " + error_string(err)
	var problem = save_project(exported)
	if not problem.is_empty():
		return problem
	err = DirAccess.copy_absolute(runtime_path, target.path_join("Game.exe"))
	if err != OK:
		return "Cannot copy engine runtime: " + error_string(err)
	DirAccess.make_dir_recursive_absolute(target.path_join("licenses"))
	for license_name in license_sources:
		err = DirAccess.copy_absolute(license_sources[license_name], target.path_join("licenses").path_join(license_name))
		if err != OK:
			return "Cannot copy engine license: " + license_name
	problem = _atomic_write(target.path_join("RUN_GAME.cmd"), "@echo off\r\nstart \"\" \"%~dp0Game.exe\" --path \"%~dp0.\"\r\n")
	if not problem.is_empty():
		return problem
	_atomic_write(target.path_join("README.txt"), "Made with Lucky " + VERSION + "\r\nRun Game.exe or RUN_GAME.cmd. Keep all files together.\r\nWindows x64. OpenGL 3.3 compatible graphics required.\r\nEngine source and licenses: https://github.com/godotengine/godot\r\n")
	return ""

static func clone_project(project: Dictionary, destination: String, new_name: String = "") -> Dictionary:
	if not destination.is_absolute_path() or DirAccess.dir_exists_absolute(destination):
		return {"error": "Choose a new project folder."}
	if DirAccess.make_dir_recursive_absolute(destination) != OK:
		return {"error": "Cannot create clone folder."}
	var clone = project.duplicate(true)
	clone["path"] = destination
	if not new_name.strip_edges().is_empty():
		clone["name"] = new_name.strip_edges()
	for asset in list_assets(project):
		var target = destination.path_join(asset)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var err = DirAccess.copy_absolute(str(project["path"]).path_join(asset), target)
		if err != OK:
			return {"error": "Cannot copy asset: " + asset}
	var problem = save_project(clone)
	if not problem.is_empty():
		return {"error": problem}
	return clone

static func _atomic_write(path: String, content: String) -> String:
	var temporary = path + ".tmp-" + str(Time.get_ticks_usec())
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Cannot write " + path.get_file() + ": " + error_string(FileAccess.get_open_error())
	file.store_string(content)
	file.flush()
	var write_error = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return "Write failed for " + path.get_file()
	var previous = path + ".previous"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(previous):
			DirAccess.remove_absolute(previous)
		var move_error = DirAccess.rename_absolute(path, previous)
		if move_error != OK:
			DirAccess.remove_absolute(temporary)
			return "Cannot replace " + path.get_file()
	var err = DirAccess.rename_absolute(temporary, path)
	if err != OK:
		if FileAccess.file_exists(previous):
			DirAccess.rename_absolute(previous, path)
		return "Cannot finish writing " + path.get_file()
	if FileAccess.file_exists(previous):
		DirAccess.remove_absolute(previous)
	return ""

static func _safe_asset(asset: String) -> bool:
	var normalized = asset.replace("\\", "/")
	return normalized.begins_with("assets/") and not normalized.is_absolute_path() and not normalized.split("/").has("..") and not normalized.contains(":")

static func _safe_script(script: String) -> bool:
	var normalized = script.replace("\\", "/")
	return (normalized.begins_with("scripts/") or normalized.begins_with("assets/")) and normalized.to_lower().ends_with(".gd") and not normalized.is_absolute_path() and not normalized.split("/").has("..") and not normalized.contains(":")

static func _node_name(value: String, index: int) -> String:
	var cleaned = value.validate_node_name().strip_edges()
	if cleaned.is_empty():
		cleaned = "Object"
	return cleaned + "_" + str(index)

static func _q(value: String) -> String:
	return JSON.stringify(value)

static func _num(value) -> String:
	return str(float(value))

static func _vector3(value: Array) -> String:
	return "Vector3(%s, %s, %s)" % [_num(value[0]), _num(value[1]), _num(value[2])]

static func _radians3(value: Array) -> String:
	return "Vector3(%s, %s, %s)" % [_num(deg_to_rad(float(value[0]))), _num(deg_to_rad(float(value[1]))), _num(deg_to_rad(float(value[2])))]

static func _color_string(value: Color) -> String:
	return "Color(%s, %s, %s, %s)" % [_num(value.r), _num(value.g), _num(value.b), _num(value.a)]
