extends Control
## Lucky's scene canvas. All colors are monochrome; project data stays portable.

signal selection_changed(index: int)
signal object_changed(index: int, data: Dictionary)

class CanvasHUD extends Control:
	var canvas: Control
	func _draw() -> void:
		if is_instance_valid(canvas):
			canvas._draw_hud(self)

var project: Dictionary = {}
var objects: Array = []
var dimension: String = "3D"
var selected: int = -1
var grid_visible: bool = true
var snap_enabled: bool = false
var light_mode: bool = false
var playing: bool = false
var zoom: float = 1.0
var pan: Vector2 = Vector2.ZERO
var orbit_target: Vector3 = Vector3.ZERO
var orbit_yaw: float = 0.65
var orbit_pitch: float = 0.38
var orbit_distance: float = 9.0
var dragging: bool = false
var panning: bool = false
var orbiting: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var drag_plane: Plane
var drag_origin: Vector3 = Vector3.ZERO
var drag_start: Vector3 = Vector3.ZERO
var world_container: SubViewportContainer
var world_view: SubViewport
var world_root: Node3D
var mesh_root: Node3D
var camera: Camera3D
var grid_mesh: MeshInstance3D
var selection_mesh: MeshInstance3D
var environment: Environment
var hud: CanvasHUD
var mesh_nodes: Array = []
var texture_cache: Dictionary = {}

func _ready() -> void:
	custom_minimum_size = Vector2(320, 260)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	_ensure_nodes()
	resized.connect(_on_resize)
	_on_resize()
	_refresh_dimension()

func _ensure_nodes() -> void:
	if is_instance_valid(world_container):
		return
	world_container = SubViewportContainer.new()
	world_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world_container.stretch = true
	world_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world_container)
	world_view = SubViewport.new()
	world_view.size = Vector2i(800, 600)
	world_view.own_world_3d = true
	world_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_view.gui_disable_input = true
	world_view.msaa_3d = Viewport.MSAA_2X
	world_container.add_child(world_view)
	world_root = Node3D.new()
	world_view.add_child(world_root)
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.65
	world_environment.environment = environment
	world_root.add_child(world_environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -28, 0)
	sun.light_energy = 1.0
	world_root.add_child(sun)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 145, 0)
	fill.light_energy = 0.3
	world_root.add_child(fill)
	mesh_root = Node3D.new()
	world_root.add_child(mesh_root)
	camera = Camera3D.new()
	camera.current = true
	camera.near = 0.05
	camera.far = 2000.0
	camera.fov = 50.0
	world_root.add_child(camera)
	grid_mesh = MeshInstance3D.new()
	world_root.add_child(grid_mesh)
	selection_mesh = MeshInstance3D.new()
	world_root.add_child(selection_mesh)
	selection_mesh.visible = false
	hud = CanvasHUD.new()
	hud.canvas = self
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(hud)
	_update_camera()
	_build_grid()

func set_project(data: Dictionary) -> void:
	var changed_project: bool = str(project.get("path", "")) != str(data.get("path", "")) or dimension != str(data.get("dimension", "3D"))
	project = data
	objects = data.get("objects", []).duplicate(true)
	dimension = str(data.get("dimension", "3D"))
	if selected >= objects.size():
		selected = -1
	texture_cache.clear()
	if is_inside_tree():
		_ensure_nodes()
		_rebuild_meshes()
		_refresh_dimension()
		if changed_project:
			reset_view()
	queue_redraw()

func select_object(index: int) -> void:
	selected = index if index >= 0 and index < objects.size() else -1
	_update_selection()
	queue_redraw()

func set_dimension(value: String) -> void:
	dimension = value
	if is_inside_tree():
		_refresh_dimension()
	queue_redraw()

func set_grid_visible(value: bool) -> void:
	grid_visible = value
	if is_instance_valid(grid_mesh):
		grid_mesh.visible = value
	queue_redraw()

func set_snap(value: bool) -> void:
	snap_enabled = value
	queue_redraw()

func set_light_mode(value: bool) -> void:
	light_mode = value
	if is_instance_valid(environment):
		environment.background_color = Color.WHITE if light_mode else Color.BLACK
		_build_grid()
		_update_selection()
	queue_redraw()

func set_playing(value: bool) -> void:
	playing = value
	dragging = false
	queue_redraw()

func reset_view() -> void:
	zoom = 1.0
	if dimension == "2D" and size.x > 0 and size.y > 0:
		zoom = clampf(minf((size.x - 80.0) / 1280.0, (size.y - 80.0) / 720.0), 0.1, 1.0)
	pan = Vector2.ZERO
	orbit_target = Vector3.ZERO
	orbit_yaw = 0.65
	orbit_pitch = 0.38
	orbit_distance = 9.0
	_update_camera()
	queue_redraw()

func frame_selection() -> void:
	if selected < 0 or selected >= objects.size():
		reset_view()
		return
	var data: Dictionary = objects[selected]
	var pos: Vector3 = _vector(data.get("position", [0, 0, 0]), Vector3.ZERO)
	if dimension == "2D":
		pan = (Vector2(640, 360) - Vector2(pos.x, pos.y)) * zoom
	else:
		orbit_target = pos
		var object_scale: Vector3 = _vector(data.get("scale", [1, 1, 1]), Vector3.ONE).abs()
		orbit_distance = clampf(maxf(object_scale.x, maxf(object_scale.y, object_scale.z)) * 4.0, 3.0, 200.0)
		_update_camera()
	queue_redraw()

func screenshot(path: String) -> Error:
	if not is_instance_valid(world_view):
		return ERR_UNCONFIGURED
	if dimension == "3D":
		var image: Image = world_view.get_texture().get_image()
		return image.save_png(path)
	return ERR_UNAVAILABLE

func _on_resize() -> void:
	# SubViewportContainer owns the viewport dimensions while stretch is enabled.
	queue_redraw()

func _refresh_dimension() -> void:
	world_container.visible = dimension == "3D"
	world_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if dimension == "3D" else SubViewport.UPDATE_DISABLED
	_rebuild_meshes()
	_update_selection()
	queue_redraw()

func _process(_delta: float) -> void:
	if is_instance_valid(hud):
		hud.queue_redraw()

func _draw() -> void:
	var background: Color = Color.WHITE if light_mode else Color.BLACK
	draw_rect(Rect2(Vector2.ZERO, size), background)
	if dimension != "2D":
		return
	var center: Vector2 = size * 0.5 + pan - Vector2(640, 360) * zoom
	var grid_color: Color = Color(0.88, 0.88, 0.88) if light_mode else Color(0.09, 0.09, 0.09)
	var axis_color: Color = Color(0.72, 0.72, 0.72) if light_mode else Color(0.22, 0.22, 0.22)
	if grid_visible:
		var spacing: float = 32.0 * zoom
		while spacing < 16.0:
			spacing *= 2.0
		while spacing > 96.0:
			spacing *= 0.5
		var x: float = fposmod(center.x, spacing)
		while x < size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), grid_color)
			x += spacing
		var y: float = fposmod(center.y, spacing)
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), grid_color)
			y += spacing
		draw_line(Vector2(center.x, 0), Vector2(center.x, size.y), axis_color)
		draw_line(Vector2(0, center.y), Vector2(size.x, center.y), axis_color)
	draw_rect(Rect2(center, Vector2(1280, 720) * zoom), axis_color, false, 1.0)
	for index in range(objects.size()):
		_draw_object_2d(index)

func _draw_object_2d(index: int) -> void:
	var data: Dictionary = objects[index]
	if not bool(data.get("visible", true)):
		return
	var p: Vector3 = _vector(data.get("position", [0, 0, 0]), Vector3.ZERO)
	var s: Vector3 = _vector(data.get("scale", [1, 1, 1]), Vector3.ONE)
	var rotation: Vector3 = _vector(data.get("rotation", [0, 0, 0]), Vector3.ZERO)
	var center: Vector2 = size * 0.5 + pan + (Vector2(p.x, p.y) - Vector2(640, 360)) * zoom
	var color: Color = Color.from_string(str(data.get("color", "#ffffff")), Color.WHITE)
	var kind: String = str(data.get("type", "Rectangle"))
	var rect: Rect2 = _bounds_2d(data)
	var bounds: Vector2 = rect.size
	draw_set_transform(center, deg_to_rad(rotation.z), Vector2(s.x, s.y) * zoom)
	if kind == "Circle":
		var circle_points: PackedVector2Array = PackedVector2Array()
		for n in range(48):
			var a: float = TAU * float(n) / 48.0
			circle_points.append(Vector2(cos(a), sin(a)) * bounds * 0.5)
		draw_colored_polygon(circle_points, color)
	elif kind == "Label":
		var font: Font = ThemeDB.fallback_font
		var line_y: float = 26.0
		for line in str(data.get("text", data.get("name", "Lucky"))).split("\n"):
			draw_string(font, Vector2(0, line_y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, color)
			line_y += font.get_height(26)
	elif kind == "Sprite":
		var texture: Texture2D = _get_texture(str(data.get("asset", "")))
		if texture != null:
			draw_texture_rect(texture, rect, false, color)
		else:
			draw_rect(rect, color, false, 1.0)
			draw_line(rect.position, rect.end, color)
			draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), color)
	else:
		draw_rect(rect, color)
	if index == selected:
		var outline: Color = Color.BLACK if light_mode else Color.WHITE
		var handle_size: float = 3.0 / maxf(zoom * absf(s.x), 0.05)
		var outer: Rect2 = rect.grow(handle_size * 2.0)
		draw_rect(outer, outline, false, 1.0 / zoom)
		for corner in [outer.position, Vector2(outer.end.x, outer.position.y), outer.end, Vector2(outer.position.x, outer.end.y)]:
			draw_rect(Rect2(corner - Vector2.ONE * handle_size, Vector2.ONE * handle_size * 2.0), outline)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_hud(target: Control) -> void:
	var fg: Color = Color.BLACK if light_mode else Color.WHITE
	var muted: Color = Color(0.43, 0.43, 0.43) if light_mode else Color(0.56, 0.56, 0.56)
	var bg: Color = Color(1, 1, 1, 0.92) if light_mode else Color(0, 0, 0, 0.92)
	var font: Font = ThemeDB.fallback_font
	var mode_text: String = dimension + "  /  " + ("RUNNING" if playing else "SCENE VIEW")
	target.draw_style_box(_hud_style(bg), Rect2(16, 16, 168, 30))
	target.draw_string(font, Vector2(27, 36), mode_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, fg)
	var scale_text: String = "%d%%" % int(zoom * 100.0) if dimension == "2D" else "%.1f m" % orbit_distance
	if snap_enabled:
		scale_text += "   SNAP"
	var hint: String = "Wheel zoom  ·  Middle drag pan  ·  F frame" if dimension == "2D" else "Right drag orbit  ·  Middle drag pan  ·  Wheel zoom  ·  F frame"
	var footer: Rect2 = Rect2(12, maxf(0, size.y - 34), maxf(0, size.x - 24), 25)
	target.draw_style_box(_hud_style(bg), footer)
	target.draw_string(font, Vector2(22, size.y - 17), hint, HORIZONTAL_ALIGNMENT_LEFT, maxf(0, size.x - 140), 11, muted)
	target.draw_string(font, Vector2(maxf(16, size.x - 115), size.y - 17), scale_text, HORIZONTAL_ALIGNMENT_RIGHT, 95, 11, fg)
	if objects.is_empty():
		var message: String = "A blank canvas. Add an object to begin."
		var text_width: float = font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		target.draw_string(font, Vector2((size.x - text_width) * 0.5, size.y * 0.5), message, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, muted)

func _hud_style(color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event
		if mouse.pressed:
			grab_focus()
		if mouse.button_index == MOUSE_BUTTON_WHEEL_UP and mouse.pressed:
			_zoom_at(mouse.position, 1.12)
			accept_event()
		elif mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse.pressed:
			_zoom_at(mouse.position, 1.0 / 1.12)
			accept_event()
		elif mouse.button_index == MOUSE_BUTTON_MIDDLE:
			panning = mouse.pressed
			accept_event()
		elif mouse.button_index == MOUSE_BUTTON_RIGHT and dimension == "3D":
			orbiting = mouse.pressed
			accept_event()
		elif mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed and not playing:
				var hit: int = _pick_2d(mouse.position) if dimension == "2D" else _pick_3d(mouse.position)
				select_object(hit)
				selection_changed.emit(hit)
				if hit >= 0:
					dragging = true
					var p: Vector3 = _vector(objects[hit].get("position", [0, 0, 0]), Vector3.ZERO)
					if dimension == "2D":
						drag_offset = _screen_to_world(mouse.position) - Vector2(p.x, p.y)
					else:
						drag_plane = Plane(camera.global_basis.z.normalized(), p)
						var intersection: Variant = drag_plane.intersects_ray(camera.project_ray_origin(mouse.position), camera.project_ray_normal(mouse.position))
						drag_origin = intersection if intersection is Vector3 else p
						drag_start = p
			else:
				dragging = false
			accept_event()
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if panning:
			if dimension == "2D":
				pan += motion.relative
			else:
				var speed: float = orbit_distance * 0.0015
				orbit_target += (-camera.global_basis.x * motion.relative.x + camera.global_basis.y * motion.relative.y) * speed
				_update_camera()
			queue_redraw()
		elif orbiting and dimension == "3D":
			orbit_yaw -= motion.relative.x * 0.008
			orbit_pitch = clampf(orbit_pitch + motion.relative.y * 0.008, -1.4, 1.4)
			_update_camera()
		elif dragging and selected >= 0 and selected < objects.size():
			var data: Dictionary = objects[selected].duplicate(true)
			var p: Vector3 = _vector(data.get("position", [0, 0, 0]), Vector3.ZERO)
			if dimension == "2D":
				var new_pos: Vector2 = _screen_to_world(motion.position) - drag_offset
				if snap_enabled:
					new_pos = new_pos.snapped(Vector2(16, 16))
				p.x = new_pos.x
				p.y = new_pos.y
			else:
				var intersection: Variant = drag_plane.intersects_ray(camera.project_ray_origin(motion.position), camera.project_ray_normal(motion.position))
				if intersection is Vector3:
					p = drag_start + intersection - drag_origin
					if snap_enabled:
						p = p.snapped(Vector3(0.5, 0.5, 0.5))
			data["position"] = [p.x, p.y, p.z]
			objects[selected] = data
			if dimension == "3D" and selected < mesh_nodes.size():
				mesh_nodes[selected].position = p
				_update_selection()
			object_changed.emit(selected, data)
			queue_redraw()
	elif event is InputEventKey:
		var key: InputEventKey = event
		if key.pressed and not key.echo and key.keycode == KEY_F:
			frame_selection()
			accept_event()

func _zoom_at(cursor: Vector2, factor: float) -> void:
	if dimension == "2D":
		var before: Vector2 = _screen_to_world(cursor)
		zoom = clampf(zoom * factor, 0.08, 12.0)
		pan = cursor - size * 0.5 - (before - Vector2(640, 360)) * zoom
	else:
		orbit_distance = clampf(orbit_distance / factor, 0.5, 1000.0)
		_update_camera()
	queue_redraw()

func _screen_to_world(cursor: Vector2) -> Vector2:
	return (cursor - size * 0.5 - pan) / zoom + Vector2(640, 360)

func _pick_2d(cursor: Vector2) -> int:
	var point: Vector2 = _screen_to_world(cursor)
	for index in range(objects.size() - 1, -1, -1):
		var data: Dictionary = objects[index]
		if not bool(data.get("visible", true)):
			continue
		var pos: Vector3 = _vector(data.get("position", [0, 0, 0]), Vector3.ZERO)
		var scl: Vector3 = _vector(data.get("scale", [1, 1, 1]), Vector3.ONE)
		var rot: Vector3 = _vector(data.get("rotation", [0, 0, 0]), Vector3.ZERO)
		var local: Vector2 = (point - Vector2(pos.x, pos.y)).rotated(-deg_to_rad(rot.z))
		if absf(scl.x) < 0.001 or absf(scl.y) < 0.001:
			continue
		local /= Vector2(scl.x, scl.y)
		var bounds: Rect2 = _bounds_2d(data)
		if str(data.get("type", "")) == "Circle":
			if (local / Vector2(32, 32)).length_squared() <= 1.0:
				return index
		elif bounds.grow(4.0 / zoom).has_point(local):
			return index
	return -1

func _pick_3d(cursor: Vector2) -> int:
	if not is_instance_valid(camera):
		return -1
	var ray_origin: Vector3 = camera.project_ray_origin(cursor)
	var ray_direction: Vector3 = camera.project_ray_normal(cursor)
	var nearest: float = INF
	var result: int = -1
	for index in range(mesh_nodes.size()):
		var node: MeshInstance3D = mesh_nodes[index]
		if not node.visible or node.mesh == null:
			continue
		var inverse: Transform3D = node.global_transform.affine_inverse()
		var local_origin: Vector3 = inverse * ray_origin
		var local_direction: Vector3 = (inverse.basis * ray_direction).normalized()
		var bounds: AABB = node.mesh.get_aabb().grow(0.04)
		var intersection: Variant = bounds.intersects_ray(local_origin, local_direction)
		if intersection is Vector3:
			var distance: float = ray_origin.distance_to(node.global_transform * intersection)
			if distance < nearest:
				nearest = distance
				result = index
	return result

func _update_camera() -> void:
	if not is_instance_valid(camera):
		return
	var offset: Vector3 = Vector3(sin(orbit_yaw) * cos(orbit_pitch), sin(orbit_pitch), cos(orbit_yaw) * cos(orbit_pitch)) * orbit_distance
	camera.position = orbit_target + offset
	camera.look_at(orbit_target, Vector3.UP)

func _rebuild_meshes() -> void:
	if not is_instance_valid(mesh_root):
		return
	for child in mesh_root.get_children():
		child.free()
	mesh_nodes.clear()
	for data in objects:
		var node: MeshInstance3D = MeshInstance3D.new()
		var kind: String = str(data.get("type", "Box"))
		if kind == "Sphere":
			var sphere: SphereMesh = SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			node.mesh = sphere
		elif kind == "Capsule":
			var capsule: CapsuleMesh = CapsuleMesh.new()
			capsule.radius = 0.5
			capsule.height = 2.0
			node.mesh = capsule
		elif kind == "Plane":
			var plane: PlaneMesh = PlaneMesh.new()
			plane.size = Vector2(8, 8)
			node.mesh = plane
		else:
			node.mesh = BoxMesh.new()
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color.from_string(str(data.get("color", "#ffffff")), Color.WHITE)
		material.roughness = 0.78
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		node.material_override = material
		node.position = _vector(data.get("position", [0, 0, 0]), Vector3.ZERO)
		node.rotation_degrees = _vector(data.get("rotation", [0, 0, 0]), Vector3.ZERO)
		var scl: Vector3 = _vector(data.get("scale", [1, 1, 1]), Vector3.ONE)
		for axis in range(3):
			if absf(scl[axis]) < 0.001:
				scl[axis] = 0.001
		node.scale = scl
		node.visible = bool(data.get("visible", true))
		mesh_root.add_child(node)
		mesh_nodes.append(node)
	_update_selection()

func _build_grid() -> void:
	if not is_instance_valid(grid_mesh):
		return
	var mesh: ImmediateMesh = ImmediateMesh.new()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.82, 0.82, 0.82) if light_mode else Color(0.12, 0.12, 0.12)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for line in range(-20, 21):
		mesh.surface_add_vertex(Vector3(float(line), -0.01, -20))
		mesh.surface_add_vertex(Vector3(float(line), -0.01, 20))
		mesh.surface_add_vertex(Vector3(-20, -0.01, float(line)))
		mesh.surface_add_vertex(Vector3(20, -0.01, float(line)))
	mesh.surface_end()
	grid_mesh.mesh = mesh
	grid_mesh.visible = grid_visible

func _update_selection() -> void:
	if not is_instance_valid(selection_mesh):
		return
	selection_mesh.visible = dimension == "3D" and selected >= 0 and selected < mesh_nodes.size()
	if not selection_mesh.visible:
		return
	var node: MeshInstance3D = mesh_nodes[selected]
	var box: AABB = node.mesh.get_aabb().grow(0.04)
	var corners: Array[Vector3] = []
	for z in range(2):
		for y in range(2):
			for x in range(2):
				corners.append(box.position + box.size * Vector3(x, y, z))
	var mesh: ImmediateMesh = ImmediateMesh.new()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.BLACK if light_mode else Color.WHITE
	material.no_depth_test = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var edges: Array = [[0,1],[0,2],[0,4],[1,3],[1,5],[2,3],[2,6],[3,7],[4,5],[4,6],[5,7],[6,7]]
	for edge in edges:
		mesh.surface_add_vertex(corners[edge[0]])
		mesh.surface_add_vertex(corners[edge[1]])
	mesh.surface_end()
	selection_mesh.mesh = mesh
	selection_mesh.transform = node.transform

func _get_texture(asset: String) -> Texture2D:
	if asset.is_empty():
		return null
	if texture_cache.has(asset):
		return texture_cache[asset]
	var root_path: String = str(project.get("path", ""))
	var full_path: String = root_path.path_join(asset)
	var image: Image = Image.new()
	if image.load(full_path) == OK:
		var texture: ImageTexture = ImageTexture.create_from_image(image)
		texture_cache[asset] = texture
		return texture
	texture_cache[asset] = null
	return null

func _bounds_2d(data: Dictionary) -> Rect2:
	var kind: String = str(data.get("type", "Rectangle"))
	if kind == "Circle":
		return Rect2(-32, -32, 64, 64)
	if kind == "Sprite":
		var texture: Texture2D = _get_texture(str(data.get("asset", "")))
		if texture != null:
			return Rect2(-texture.get_size() * 0.5, texture.get_size())
	if kind == "Label":
		var font: Font = ThemeDB.fallback_font
		var text: String = str(data.get("text", data.get("name", "Lucky")))
		var max_width: float = 20.0
		var lines: PackedStringArray = text.split("\n")
		for line in lines:
			max_width = maxf(max_width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x)
		return Rect2(0, 0, max_width, font.get_height(26) * float(lines.size()))
	return Rect2(-40, -30, 80, 60)

func _vector(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if value is Vector3:
		return value
	return fallback
