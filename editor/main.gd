extends Control

const Store = preload("res://project_store.gd")
const Canvas = preload("res://viewport.gd")
const Bridge = preload("res://ai_bridge.gd")
const VERSION = "0.1.0-beta"
var config := ConfigFile.new()
var project: Dictionary = {}
var selected := -1
var history: Array = []
var future: Array = []
var dirty := false
var light := false
var ai_visible := true
var scene_list: ItemList
var asset_list: ItemList
var inspector: VBoxContainer
var viewport: Control
var console: RichTextLabel
var status: Label
var title_label: Label
var workspace: VBoxContainer
var ai_panel: VBoxContainer
var ai: Node
var chat: RichTextLabel
var prompt: TextEdit
var model_picker: OptionButton
var effort_picker: OptionButton
var provider_picker: OptionButton
var ai_status: Label
var speed: CheckBox
var script_editor: CodeEdit
var script_path := ""
var attachment_label: Label
var attachments: Array = []
var models: Array = []
var run_pid := -1
var autosave_elapsed := 0.0
var output_lines: Array[String] = []
var rebuilding := false
var script_dirty := false
var editor_tabs: TabContainer
var project_filter := ""
var game_pipes: Dictionary = {}
var game_output := ""

func _ready() -> void:
	get_tree().auto_accept_quit = false
	DisplayServer.window_set_title("Lucky · " + VERSION)
	config.load("user://settings.cfg")
	light = config.get_value("appearance", "light", false)
	ai = Bridge.new()
	add_child(ai)
	ai.status_changed.connect(_ai_status)
	ai.models_changed.connect(_models_changed)
	ai.response_delta.connect(_ai_delta)
	ai.response_done.connect(func(): _ai_status("Ready"))
	ai.failure.connect(func(message): _ai_status(message); _ai_message("LUCKY", message))
	ai.login_required.connect(_login_link)
	ai.plugins_changed.connect(_plugins_loaded)
	_apply_theme()
	_home()
	if "--self-test-ui" in OS.get_cmdline_user_args():
		call_deferred("_self_test_ui")

func _process(delta: float) -> void:
	autosave_elapsed += delta
	if autosave_elapsed > float(config.get_value("editor", "autosave_seconds", 60)):
		autosave_elapsed = 0.0
		if not project.is_empty() and dirty and config.get_value("editor", "autosave", true):
			_save()
	if run_pid > 0 and not OS.is_process_running(run_pid):
		_drain_game_output()
		run_pid = -1
		game_pipes.clear()
		_log("Game stopped.")
	elif run_pid > 0:
		_drain_game_output()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if dirty or script_dirty:
			_confirm("Save changes before closing?", func(): _save(); if not dirty and not script_dirty: _stop(); get_tree().quit())
		else:
			_stop()
			get_tree().quit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.ctrl_pressed and event.keycode == KEY_K:
		_palette()
		get_viewport().set_input_as_handled()
	elif event.ctrl_pressed and event.keycode == KEY_S and not project.is_empty():
		_save_script() if editor_tabs.current_tab == 1 else _save()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F5 and not project.is_empty():
		_run()
	elif event.keycode == KEY_F8:
		_stop()
	elif not project.is_empty() and not get_viewport().gui_get_focus_owner() is TextEdit and not get_viewport().gui_get_focus_owner() is LineEdit:
		if event.ctrl_pressed and event.keycode == KEY_Z:
			_redo() if event.shift_pressed else _undo()
		elif event.ctrl_pressed and event.keycode == KEY_Y:
			_redo()
		elif event.ctrl_pressed and event.keycode == KEY_D:
			_duplicate()
		elif event.keycode == KEY_DELETE:
			_delete()
		elif event.keycode == KEY_F:
			viewport.frame_selection()

func _box_style(background: Color, border: Color, radius: int = 6, pad: int = 9) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = pad
	box.content_margin_right = pad
	box.content_margin_top = pad
	box.content_margin_bottom = pad
	return box

func _apply_theme() -> void:
	var th := Theme.new()
	var bg := Color.WHITE if light else Color.BLACK
	var fg := Color.BLACK if light else Color.WHITE
	var line := Color(0.76, 0.76, 0.76) if light else Color(0.22, 0.22, 0.22)
	th.default_font_size = 14
	var defaults := ThemeDB.get_default_theme()
	for kind in defaults.get_type_list():
		for style_name in defaults.get_stylebox_list(kind):
			var original := defaults.get_stylebox(style_name, kind)
			if original is StyleBoxFlat:
				var mono: StyleBoxFlat = original.duplicate()
				mono.bg_color = bg
				mono.border_color = line
				mono.shadow_color = Color.TRANSPARENT
				th.set_stylebox(style_name, kind, mono)
		for color_name in defaults.get_color_list(kind):
			if "font" in color_name or "title" in color_name or "icon" in color_name:
				th.set_color(color_name, kind, fg)
	for cls in ["Label", "Button", "CheckBox", "OptionButton", "LineEdit", "TextEdit", "CodeEdit", "RichTextLabel", "ItemList", "Tree", "SpinBox", "TabBar", "PopupMenu"]:
		th.set_color("font_color", cls, fg)
		th.set_color("font_hover_color", cls, fg)
		th.set_color("font_pressed_color", cls, bg)
		th.set_color("font_focus_color", cls, fg)
		th.set_color("font_disabled_color", cls, fg * Color(1, 1, 1, 0.4))
		th.set_color("selection_color", cls, fg * Color(1, 1, 1, 0.2))
		th.set_color("caret_color", cls, fg)
		for state in ["normal", "panel", "read_only"]:
			th.set_stylebox(state, cls, _box_style(bg, line))
		th.set_stylebox("focus", cls, _box_style(Color.TRANSPARENT, fg))
		th.set_stylebox("hover", cls, _box_style(bg, fg))
		th.set_stylebox("pressed", cls, _box_style(fg, fg))
		th.set_stylebox("disabled", cls, _box_style(bg, line))
	th.set_stylebox("panel", "Panel", _box_style(bg, line, 0))
	th.set_stylebox("panel", "PanelContainer", _box_style(bg, line, 6, 16))
	th.set_stylebox("panel", "TabContainer", _box_style(bg, line, 0, 0))
	th.set_stylebox("tab_selected", "TabBar", _box_style(bg, fg, 0))
	th.set_stylebox("tab_unselected", "TabBar", _box_style(bg, line, 0))
	th.set_color("font_selected_color", "TabBar", fg)
	th.set_color("font_unselected_color", "TabBar", fg * Color(1, 1, 1, 0.6))
	th.set_color("background_color", "TextEdit", bg)
	th.set_color("background_color", "CodeEdit", bg)
	th.set_constant("separation", "HBoxContainer", 10)
	th.set_constant("separation", "VBoxContainer", 10)
	th.set_constant("h_separation", "GridContainer", 10)
	th.set_constant("v_separation", "GridContainer", 10)
	theme = th
	if is_inside_tree():
		for button in get_tree().get_nodes_in_group("lucky_primary"):
			_style_primary(button)
		for window in get_tree().get_nodes_in_group("lucky_dialogs"):
			window.theme = th
	RenderingServer.set_default_clear_color(bg)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE if light else Color.BLACK)

func _clear() -> void:
	for child in get_children():
		if child != ai:
			remove_child(child)
			child.queue_free()
	console = null
	status = null

func _label(text: String, font_size: int = 14) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _muted(text: String, font_size: int = 13) -> Label:
	var label := _label(text, font_size)
	label.modulate.a = 0.55
	return label

func _button(text: String, action: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	if primary:
		button.add_to_group("lucky_primary")
		_style_primary(button)
	return button

func _style_primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _box_style(Color.BLACK if light else Color.WHITE, Color.BLACK if light else Color.WHITE))
	button.add_theme_color_override("font_color", Color.WHITE if light else Color.BLACK)

func _vbox(parent: Node) -> VBoxContainer:
	var box := VBoxContainer.new()
	parent.add_child(box)
	return box

func _hbox(parent: Node) -> HBoxContainer:
	var box := HBoxContainer.new()
	parent.add_child(box)
	return box

func _spacer(parent: Node) -> void:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)

func _margin(parent: Node, amount: int = 20) -> MarginContainer:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, amount)
	parent.add_child(margin)
	return margin

func _home() -> void:
	_clear()
	DisplayServer.window_set_title("Lucky · Launcher")
	var margin := _margin(self, 40)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := _vbox(margin)
	root.add_theme_constant_override("separation", 28)
	var header := _hbox(root)
	header.add_child(_label("L★  LUCKY", 22))
	header.add_child(_muted(VERSION))
	_spacer(header)
	header.add_child(_button("Connections", _connections))
	header.add_child(_button("Examples", _examples))
	header.add_child(_button("Settings", _settings))
	header.add_child(_button("Guide", _guide))
	root.add_child(HSeparator.new())
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.split_offset = 350
	root.add_child(body)
	var left := _vbox(_margin(body, 12))
	left.custom_minimum_size.x = 315
	left.add_child(_muted("MAKE SOMETHING THAT MATTERS", 12))
	left.add_child(_label("Start here.\nGo anywhere.", 46))
	var intro := _label("Your ideas. Your tools.\nOne focused space to build.", 17)
	intro.modulate.a = 0.65
	left.add_child(intro)
	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	left.add_child(gap)
	left.add_child(_button("＋  Create a project", _new_project, true))
	left.add_child(_button("↗  Open a project", _open_project_dialog))
	left.add_child(_muted("2D + 3D  /  GDScript  /  AI workspace"))
	var breathing := Control.new()
	breathing.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(breathing)
	left.add_child(_label("Built for focus.", 23))
	left.add_child(_muted("Pure black. Clear intent. No clutter."))
	var right := _vbox(_margin(body, 20))
	var row := _hbox(right)
	row.add_child(_label("Your projects", 24))
	_spacer(row)
	var filter := LineEdit.new()
	filter.placeholder_text = "Find a project…"
	filter.custom_minimum_size.x = 230
	filter.text = project_filter
	row.add_child(filter)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	var list := _vbox(scroll)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_populate_projects(list)
	filter.text_changed.connect(func(value): project_filter = value; _populate_projects(list))
	var footer := _hbox(root)
	footer.add_child(_muted("LUCKY ENGINE   /   WINDOWS x64"))
	_spacer(footer)
	footer.add_child(_muted("Ctrl K  Command palette"))

func _populate_projects(list: VBoxContainer) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	var recent: Array = config.get_value("projects", "recent", [])
	var shown := 0
	for path in recent:
		var loaded: Dictionary = Store.load_project(path)
		if loaded.has("error") or (not project_filter.is_empty() and not str(loaded.name).to_lower().contains(project_filter.to_lower())):
			continue
		shown += 1
		var panel := PanelContainer.new()
		list.add_child(panel)
		var row := _hbox(panel)
		var info := _vbox(row)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(_label(loaded.name, 21))
		info.add_child(_muted("%s  /  %d objects" % [loaded.dimension, loaded.objects.size()]))
		var location := _muted(str(loaded.path))
		location.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		location.custom_minimum_size.x = 200
		info.add_child(location)
		row.add_child(_button("Open  →", func(): _load_project(str(path)), true))
		row.add_child(_button("×", func(): _forget_project(str(path)); _populate_projects(list)))
	if shown == 0:
		list.add_child(_label("A blank canvas is a good beginning.", 23))
		list.add_child(_muted("Create a project or open a project.lucky.json file."))

func _forget_project(path: String) -> void:
	var recent: Array = config.get_value("projects", "recent", [])
	recent.erase(path)
	config.set_value("projects", "recent", recent)
	config.save("user://settings.cfg")

func _new_project() -> void:
	if dirty or script_dirty:
		_confirm("Save your current project before creating another?", func(): _save(); if not dirty and not script_dirty: _new_project())
		return
	var dialog := AcceptDialog.new()
	dialog.title = "Create your next project"
	dialog.ok_button_text = "Choose location & create"
	var box := _vbox(dialog)
	box.custom_minimum_size = Vector2(460, 230)
	box.add_child(_label("Make it yours.", 28))
	var name_input := LineEdit.new()
	name_input.placeholder_text = "Project name"
	name_input.text = "Untitled Project"
	box.add_child(name_input)
	var dimension := OptionButton.new()
	dimension.add_item("3D")
	dimension.add_item("2D")
	box.add_child(dimension)
	var template := OptionButton.new()
	for item in ["Blank", "Showcase", "Platformer"]:
		template.add_item(item)
	box.add_child(template)
	box.add_child(_muted("A dedicated folder is created inside your chosen location."))
	dialog.confirmed.connect(func():
		var project_name := name_input.text.strip_edges()
		if project_name.is_empty():
			_notice("Give your project a name first.")
			return
		var dim := dimension.get_item_text(dimension.selected)
		var preset := template.get_item_text(template.selected)
		if preset == "Platformer": dim = "2D"
		_pick_directory("Choose a parent folder", func(parent):
			var safe := project_name.validate_filename().strip_edges().trim_suffix(".")
			if safe.is_empty(): safe = "LuckyProject"
			var created: Dictionary = Store.create_project(parent.path_join(safe), project_name, dim, preset)
			if created.has("error"): _notice(created.error)
			else: _activate(created)
		)
	)
	_popup(dialog, Vector2i(520, 350))

func _pick_directory(title: String, callback: Callable) -> void:
	var dialog := FileDialog.new()
	dialog.title = title
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.use_native_dialog = true
	dialog.dir_selected.connect(callback)
	_popup(dialog, Vector2i(850, 550))

func _open_project_dialog() -> void:
	if dirty or script_dirty:
		_confirm("Save your current project before opening another?", func(): _save(); if not dirty and not script_dirty: _open_project_dialog())
		return
	var dialog := FileDialog.new()
	dialog.title = "Open Lucky project"
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.json ; Lucky project"])
	dialog.use_native_dialog = true
	dialog.file_selected.connect(_load_project)
	_popup(dialog, Vector2i(850, 550))

func _load_project(path: String) -> void:
	var loaded: Dictionary = Store.load_project(path)
	if loaded.has("error"): _notice(loaded.error)
	else: _activate(loaded)

func _activate(data: Dictionary) -> void:
	ai.new_chat()
	project = data
	selected = -1
	history.clear()
	future.clear()
	dirty = false
	script_dirty = false
	script_path = ""
	var recent: Array = config.get_value("projects", "recent", [])
	recent.erase(project.path)
	recent.push_front(project.path)
	config.set_value("projects", "recent", recent.slice(0, 30))
	config.save("user://settings.cfg")
	_editor()
	_log("Opened " + project.name + ". Everything you save stays in your project folder.")

func _editor() -> void:
	_clear()
	DisplayServer.window_set_title("Lucky · " + str(project.name))
	workspace = _vbox(self)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.add_theme_constant_override("separation", 0)
	var header := _hbox(_margin(workspace, 12))
	header.add_child(_button("L★", _return_home))
	title_label = _label(str(project.name), 18)
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.custom_minimum_size.x = 100
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	header.add_child(_muted(str(project.dimension)))
	_spacer(header)
	header.add_child(_button("⌕  Commands", _palette))
	header.add_child(_button("Save", _save))
	header.add_child(_button("▶  Run", _run, true))
	header.add_child(_button("■", _stop))
	header.add_child(_button("Export", _export))
	header.add_child(_button("Project", _project_tools))
	header.add_child(_button("AI  ✦", _toggle_ai))
	header.add_child(_button("Settings", _settings))
	workspace.add_child(HSeparator.new())
	var main := HSplitContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.split_offset = 230
	workspace.add_child(main)
	_build_left(main)
	var rest := HSplitContainer.new()
	rest.split_offset = 780
	main.add_child(rest)
	var center_and_inspector := HSplitContainer.new()
	center_and_inspector.split_offset = 560
	rest.add_child(center_and_inspector)
	var center := _vbox(center_and_inspector)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_center(center)
	var inspector_scroll := ScrollContainer.new()
	inspector_scroll.custom_minimum_size.x = 230
	center_and_inspector.add_child(inspector_scroll)
	inspector = _vbox(_margin(inspector_scroll, 14))
	inspector.custom_minimum_size.x = 205
	_build_inspector()
	ai_panel = _vbox(_margin(rest, 16))
	ai_panel.custom_minimum_size.x = 300
	ai_panel.visible = ai_visible
	_build_ai()
	var bottom := _hbox(_margin(workspace, 7))
	status = _muted("Ready  /  " + VERSION, 12)
	bottom.add_child(status)
	_spacer(bottom)
	bottom.add_child(_muted("Ctrl S  Save     Ctrl Z  Undo     F5  Run     F  Frame", 12))
	_refresh_scene()
	_refresh_assets()
	_update_view()

func _build_left(parent: Node) -> void:
	var side := _vbox(_margin(parent, 12))
	side.custom_minimum_size.x = 205
	var row := _hbox(side)
	row.add_child(_label("SCENE", 12))
	_spacer(row)
	row.add_child(_button("＋", _add_dialog))
	var search := LineEdit.new()
	search.placeholder_text = "Filter objects…"
	side.add_child(search)
	scene_list = ItemList.new()
	scene_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scene_list.custom_minimum_size.y = 180
	side.add_child(scene_list)
	scene_list.item_selected.connect(func(index):
		selected = int(scene_list.get_item_metadata(index))
		viewport.select_object(selected)
		_build_inspector()
	)
	search.text_changed.connect(_refresh_scene)
	var tools := _hbox(side)
	tools.add_child(_button("↑", func(): _reorder(-1)))
	tools.add_child(_button("↓", func(): _reorder(1)))
	tools.add_child(_button("Clone", _duplicate))
	tools.add_child(_button("−", _delete))
	side.add_child(HSeparator.new())
	row = _hbox(side)
	row.add_child(_label("ASSETS", 12))
	_spacer(row)
	row.add_child(_button("Import", _import_assets))
	asset_list = ItemList.new()
	asset_list.custom_minimum_size.y = 180
	asset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(asset_list)
	asset_list.item_activated.connect(_asset_activated)
	side.add_child(_muted("Double-click images to add a sprite.\nDouble-click scripts to edit.", 11))

func _build_center(parent: Node) -> void:
	var toolbar := _hbox(_margin(parent, 8))
	toolbar.add_child(_button("＋ Add", _add_dialog))
	toolbar.add_child(_button("↶", _undo))
	toolbar.add_child(_button("↷", _redo))
	_spacer(toolbar)
	var grid := CheckBox.new()
	grid.text = "Grid"
	grid.button_pressed = true
	grid.toggled.connect(func(value): viewport.set_grid_visible(value))
	toolbar.add_child(grid)
	var snap := CheckBox.new()
	snap.text = "Snap"
	snap.button_pressed = config.get_value("editor", "snap", true)
	snap.toggled.connect(func(value): viewport.set_snap(value); config.set_value("editor", "snap", value); config.save("user://settings.cfg"))
	toolbar.add_child(snap)
	toolbar.add_child(_button("Frame", func(): viewport.frame_selection()))
	editor_tabs = TabContainer.new()
	editor_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(editor_tabs)
	viewport = Canvas.new()
	viewport.name = "Scene"
	viewport.custom_minimum_size = Vector2(350, 280)
	viewport.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor_tabs.add_child(viewport)
	viewport.selection_changed.connect(_viewport_selected)
	viewport.object_changed.connect(_viewport_changed)
	viewport.set_light_mode(light)
	viewport.set_snap(config.get_value("editor", "snap", true))
	var script := _vbox(editor_tabs)
	script.name = "Script"
	var script_tools := _hbox(_margin(script, 8))
	script_tools.add_child(_button("New script", _new_script))
	script_tools.add_child(_button("Save script", _save_script, true))
	script_tools.add_child(_button("Check project", _validate))
	script_editor = CodeEdit.new()
	script_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	script_editor.gutters_draw_line_numbers = true
	script_editor.auto_brace_completion_enabled = true
	script_editor.code_completion_enabled = false
	script_editor.text = "# Double-click a script in Assets, or choose New script.\n# Scripts are saved inside this project's scripts folder.\n"
	var highlighter := CodeHighlighter.new()
	for keyword in ["func", "var", "const", "if", "else", "elif", "return", "extends", "for", "while", "in", "class_name", "signal", "await", "pass", "true", "false", "null"]:
		highlighter.add_keyword_color(keyword, Color(0.7, 0.7, 0.7))
	highlighter.add_color_region("#", "", Color(0.45, 0.45, 0.45), true)
	highlighter.add_color_region('"', '"', Color(0.85, 0.85, 0.85))
	script_editor.syntax_highlighter = highlighter
	script.add_child(script_editor)
	script_editor.text_changed.connect(func(): script_dirty = true)
	var output := _vbox(_margin(parent, 8))
	var row := _hbox(output)
	row.add_child(_muted("OUTPUT", 11))
	_spacer(row)
	row.add_child(_button("Validate", _validate))
	row.add_child(_button("Snapshot", _backup))
	row.add_child(_button("Clear", func(): output_lines.clear(); console.clear()))
	console = RichTextLabel.new()
	console.custom_minimum_size.y = 100
	console.scroll_following = true
	console.selection_enabled = true
	output.add_child(console)
	for line in output_lines: console.append_text(line + "\n")

func _refresh_scene(filter: String = "") -> void:
	if not is_instance_valid(scene_list): return
	scene_list.clear()
	for i in project.objects.size():
		var object: Dictionary = project.objects[i]
		if not filter.is_empty() and not str(object.name).to_lower().contains(filter.to_lower()): continue
		var item := scene_list.add_item(("◇  " if object.get("visible", true) else "·  ") + str(object.name))
		scene_list.set_item_metadata(item, i)
		if i == selected: scene_list.select(item)

func _build_inspector() -> void:
	if not is_instance_valid(inspector): return
	rebuilding = true
	for child in inspector.get_children():
		inspector.remove_child(child)
		child.queue_free()
	inspector.add_child(_label("INSPECTOR", 12))
	if selected < 0 or selected >= project.objects.size():
		inspector.add_child(_label("Shape your world.", 23))
		var hint := _muted("Select an object to edit its properties.\n\nAdd objects with ＋ Add.\n\n2D: drag to move, wheel to zoom.\n3D: right-drag to orbit.\n\nUse F to frame a selection.")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size.x = 195
		inspector.add_child(hint)
		rebuilding = false
		return
	var object: Dictionary = project.objects[selected]
	inspector.add_child(_muted(str(object.type).to_upper()))
	var name_input := LineEdit.new()
	name_input.text = str(object.name)
	inspector.add_child(name_input)
	name_input.text_submitted.connect(func(value): _property("name", value))
	name_input.focus_exited.connect(func(): if is_instance_valid(name_input) and selected >= 0 and str(project.objects[selected].name) != name_input.text: _property("name", name_input.text))
	var visible_check := CheckBox.new()
	visible_check.text = "Visible"
	visible_check.button_pressed = object.get("visible", true)
	visible_check.toggled.connect(func(value): _property("visible", value))
	inspector.add_child(visible_check)
	for property in ["position", "rotation", "scale"]:
		inspector.add_child(_muted(str(property).capitalize(), 12))
		var values: Array = object.get(property, [0.0, 0.0, 0.0])
		var axes: Array = [0, 1, 2] if project.dimension == "3D" else ([2] if property == "rotation" else [0, 1])
		for axis in axes:
			var row := _hbox(inspector)
			row.add_child(_muted(["X", "Y", "Z"][axis]))
			var spin := SpinBox.new()
			spin.min_value = -100000
			spin.max_value = 100000
			spin.step = 0.1 if project.dimension == "3D" or property == "scale" else 1.0
			spin.value = float(values[axis])
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(spin)
			spin.value_changed.connect(func(value):
				if rebuilding or selected < 0: return
				var changed: Array = project.objects[selected][property].duplicate()
				changed[axis] = value
				_property(property, changed, false)
			)
	inspector.add_child(_muted("Material", 12))
	var color := ColorPickerButton.new()
	color.color = Color(str(object.get("color", "#ffffff")))
	color.custom_minimum_size.y = 30
	color.color_changed.connect(func(value): _property("color", "#" + value.to_html(), false))
	inspector.add_child(color)
	if object.type == "Label":
		var text := LineEdit.new()
		text.text = object.get("text", "Lucky")
		text.placeholder_text = "Label text"
		text.text_submitted.connect(func(value): _property("text", value))
		inspector.add_child(text)
	if object.has("asset"): inspector.add_child(_muted(str(object.asset)))
	inspector.add_child(_muted("Script attachment", 12))
	var script_choice := OptionButton.new()
	script_choice.add_item("None")
	script_choice.set_item_metadata(0, "")
	for asset in Store.list_assets(project):
		if str(asset).get_extension() != "gd": continue
		var item := script_choice.item_count
		script_choice.add_item(str(asset).get_file())
		script_choice.set_item_metadata(item, asset)
		if object.get("script", "") == asset: script_choice.select(item)
	script_choice.item_selected.connect(func(index): _property("script", script_choice.get_item_metadata(index)))
	inspector.add_child(script_choice)
	if not str(object.get("script", "")).is_empty():
		inspector.add_child(_button("Edit attached script", func(): _open_script(str(project.path).path_join(str(object.script)))))
	inspector.add_child(HSeparator.new())
	inspector.add_child(_button("Duplicate object", _duplicate))
	inspector.add_child(_button("Delete object", _delete))
	rebuilding = false

func _property(key: String, value: Variant, rebuild: bool = true) -> void:
	if selected < 0 or rebuilding: return
	_remember()
	project.objects[selected][key] = value
	_mark_dirty()
	_update_view()
	_refresh_scene()
	if rebuild: _build_inspector()

func _viewport_selected(index: int) -> void:
	selected = index
	_refresh_scene()
	_build_inspector()

func _viewport_changed(index: int, data: Dictionary) -> void:
	if index < 0 or index >= project.objects.size(): return
	_remember()
	project.objects[index] = data.duplicate(true)
	_mark_dirty()
	_build_inspector()

func _update_view() -> void:
	if is_instance_valid(viewport):
		viewport.set_project(project)
		viewport.select_object(selected)

func _add_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Add to your scene"
	dialog.get_ok_button().hide()
	var box := _vbox(dialog)
	box.custom_minimum_size.x = 300
	box.add_child(_label("A world starts with a shape.", 21))
	var types: Array = ["Box", "Sphere", "Plane", "Capsule"] if project.dimension == "3D" else ["Rectangle", "Circle", "Label"]
	for type in types:
		box.add_child(_button(str(type), func(): _add_object(str(type)); dialog.hide()))
	_popup(dialog, Vector2i(360, 330))

func _add_object(type: String, asset: String = "") -> void:
	_remember()
	var position: Array = [0.0, 0.5, 0.0] if project.dimension == "3D" else [640.0, 360.0, 0.0]
	var object := {"id": str(Time.get_unix_time_from_system()) + "_" + str(randi()), "name": type + str(project.objects.size() + 1), "type": type, "position": position, "rotation": [0.0, 0.0, 0.0], "scale": [1.0, 1.0, 1.0], "color": "#ffffff", "visible": true}
	if type == "Label": object["text"] = "Hello, Lucky."
	if not asset.is_empty(): object["asset"] = asset
	project.objects.append(object)
	selected = project.objects.size() - 1
	_mark_dirty()
	_update_view()
	_refresh_scene()
	_build_inspector()

func _remember() -> void:
	history.append(project.duplicate(true))
	if history.size() > 150: history.pop_front()
	future.clear()

func _undo() -> void:
	if history.is_empty(): return
	future.append(project.duplicate(true))
	project = history.pop_back()
	_after_history()

func _redo() -> void:
	if future.is_empty(): return
	history.append(project.duplicate(true))
	project = future.pop_back()
	_after_history()

func _after_history() -> void:
	selected = mini(selected, project.objects.size() - 1)
	_mark_dirty()
	_update_view()
	_refresh_scene()
	_build_inspector()

func _duplicate() -> void:
	if selected < 0: return
	_remember()
	var object: Dictionary = project.objects[selected].duplicate(true)
	object.id = str(randi()) + str(Time.get_ticks_msec())
	object.name = str(object.name) + " copy"
	object.position[0] += 1.0 if project.dimension == "3D" else 32.0
	project.objects.append(object)
	selected = project.objects.size() - 1
	_after_history()

func _delete() -> void:
	if selected < 0: return
	_remember()
	project.objects.remove_at(selected)
	selected = -1
	_after_history()

func _reorder(direction: int) -> void:
	if selected < 0: return
	var target := selected + direction
	if target < 0 or target >= project.objects.size(): return
	_remember()
	var object: Dictionary = project.objects.pop_at(selected)
	project.objects.insert(target, object)
	selected = target
	_after_history()

func _mark_dirty() -> void:
	dirty = true
	if is_instance_valid(title_label): title_label.text = str(project.name) + " •"

func _save() -> void:
	if project.is_empty(): return
	var error: String = Store.save_project(project)
	if not error.is_empty(): _notice(error); return
	dirty = false
	if is_instance_valid(title_label): title_label.text = project.name
	_log("Saved project and generated main.tscn.")
	if script_dirty: _save_script()

func _runtime() -> String:
	return OS.get_executable_path()

func _run() -> void:
	_save()
	if dirty or script_dirty: return
	_stop()
	game_pipes = OS.execute_with_pipe(_runtime(), PackedStringArray(["--path", project.path, "--rendering-method", "gl_compatibility"]), false)
	run_pid = int(game_pipes.get("pid", -1))
	game_output = ""
	_log("Running project. F8 stops the game." if run_pid > 0 else "Could not start the runtime.")

func _drain_game_output() -> void:
	for channel in ["stdio", "stderr"]:
		var pipe: FileAccess = game_pipes.get(channel)
		if pipe == null: continue
		var data := pipe.get_buffer(16384)
		if not data.is_empty(): game_output += data.get_string_from_utf8()
	while game_output.contains("\n"):
		var newline := game_output.find("\n")
		_log("GAME  " + game_output.left(newline).strip_edges())
		game_output = game_output.substr(newline + 1)
	if game_output.length() > 32768: game_output = game_output.right(32768)

func _stop() -> void:
	if run_pid > 0 and OS.is_process_running(run_pid): OS.kill(run_pid)
	run_pid = -1
	game_pipes.clear()

func _export() -> void:
	_save()
	if dirty or script_dirty: return
	_pick_directory("Choose a new or empty export folder", func(folder):
		var error: String = Store.export_portable(project, folder, _runtime())
		_log("Export ready: " + folder if error.is_empty() else error)
		_notice("Portable Windows project created. Use RUN_GAME.cmd in the export folder." if error.is_empty() else error)
	)

func _validate() -> void:
	var issues: Array = Store.validate(project)
	_log("Project validation passed." if issues.is_empty() else "Validation: " + "\n".join(issues))

func _backup() -> void:
	_save()
	var result: String = Store.backup(project)
	_log("Snapshot saved: " + result if not result.is_empty() else "Could not save snapshot.")

func _restore() -> void:
	_confirm("Restore the latest saved snapshot? Current changes will be replaced.", func():
		var restored: Dictionary = Store.restore_latest(project)
		if restored.has("error"): _notice(restored.error)
		else: _remember(); project = restored; _after_history(); _save()
	)

func _refresh_assets() -> void:
	if not is_instance_valid(asset_list): return
	asset_list.clear()
	for asset in Store.list_assets(project):
		var index := asset_list.add_item(str(asset).get_file())
		asset_list.set_item_metadata(index, asset)
		asset_list.set_item_tooltip(index, asset)

func _import_assets() -> void:
	var dialog := FileDialog.new()
	dialog.title = "Import files into project"
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	dialog.use_native_dialog = true
	dialog.files_selected.connect(func(paths):
		var imported: Array = Store.import_assets(project, Array(paths))
		_log("Imported %d files." % imported.size())
		_refresh_assets()
	)
	_popup(dialog, Vector2i(850, 550))

func _project_tools() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Project tools"
	dialog.get_ok_button().hide()
	var box := _vbox(dialog)
	box.custom_minimum_size.x = 390
	box.add_child(_label(str(project.name), 25))
	box.add_child(_muted("%s  /  %d objects  /  %d assets" % [project.dimension, project.objects.size(), Store.list_assets(project).size()]))
	box.add_child(_button("Rename project", func(): dialog.hide(); _rename_project()))
	box.add_child(_button("Clone project", func(): dialog.hide(); _clone_project()))
	box.add_child(_button("Create snapshot", func(): dialog.hide(); _backup()))
	box.add_child(_button("Restore latest snapshot", func(): dialog.hide(); _restore()))
	box.add_child(_button("Validate scene", func(): dialog.hide(); _validate()))
	box.add_child(_button("Copy project location", func(): DisplayServer.clipboard_set(str(project.path))))
	box.add_child(_button("Open project folder", func(): OS.shell_open(str(project.path))))
	_popup(dialog, Vector2i(450, 450))

func _rename_project() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Rename project"
	var field := LineEdit.new()
	field.text = project.name
	field.custom_minimum_size.x = 350
	dialog.add_child(field)
	dialog.confirmed.connect(func():
		var value := field.text.strip_edges()
		if value.is_empty(): return
		_remember()
		project.name = value
		_mark_dirty()
		_save()
		DisplayServer.window_set_title("Lucky · " + value)
	)
	_popup(dialog, Vector2i(420, 140))

func _clone_project() -> void:
	_save()
	if dirty or script_dirty: return
	_pick_directory("Choose a parent folder for the copy", func(folder):
		var new_name: String = str(project.name) + " copy"
		var target: String = folder.path_join(new_name.validate_filename())
		var copy: Dictionary = Store.clone_project(project, target, new_name)
		if copy.has("error"): _notice(copy.error)
		else: _activate(copy)
	)

func _examples() -> void:
	var root: String = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("examples")
	if not DirAccess.dir_exists_absolute(root):
		_notice("Optional examples are not installed. Create a project using the Showcase or Platformer template, or rerun setup and select Example projects.")
		return
	var dialog := AcceptDialog.new()
	dialog.title = "Start from an example"
	dialog.get_ok_button().hide()
	var box := _vbox(dialog)
	box.custom_minimum_size.x = 390
	box.add_child(_label("A running start.", 27))
	box.add_child(_muted("Creates an editable copy in a location you choose."))
	var directory := DirAccess.open(root)
	for entry in directory.get_directories():
		var data: Dictionary = Store.load_project(root.path_join(entry))
		if data.has("error"): continue
		box.add_child(_button(str(data.name) + "  →", func():
			dialog.hide()
			_pick_directory("Choose where to copy the example", func(parent):
				var copy: Dictionary = Store.clone_project(data, parent.path_join(str(data.name).validate_filename()))
				if copy.has("error"): _notice(copy.error)
				else: _activate(copy)
			)
		))
	_popup(dialog, Vector2i(460, 300))

func _asset_activated(index: int) -> void:
	var relative: String = asset_list.get_item_metadata(index)
	var path: String = str(project.path).path_join(relative)
	if relative.get_extension() == "gd":
		if script_dirty:
			_confirm("Save this script before opening another?", func(): _save_script(); _open_script(path))
		else: _open_script(path)
	elif relative.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "bmp"]:
		if project.dimension == "2D": _add_object("Sprite", relative)
		else: _notice("Image sprites are available in 2D projects. The imported image remains in Assets.")
	else:
		_notice("Imported file: " + relative + "\nUse it from a GDScript in your project.")

func _open_script(path: String) -> void:
	if script_dirty:
		_confirm("Save this script before opening another?", func(): _save_script(); if not script_dirty: _open_script(path))
		return
	script_path = path
	script_editor.text = FileAccess.get_file_as_string(path)
	script_dirty = false
	editor_tabs.current_tab = 1
	_log("Editing " + path.get_file())

func _new_script() -> void:
	if script_dirty:
		_confirm("Save this script before creating another?", func(): _save_script(); if not script_dirty: _new_script())
		return
	var dialog := AcceptDialog.new()
	dialog.title = "New GDScript"
	var field := LineEdit.new()
	field.text = "main.gd"
	field.custom_minimum_size.x = 350
	dialog.add_child(field)
	dialog.confirmed.connect(func():
		var filename := field.text.get_file().validate_filename()
		if filename.is_empty(): return
		if not filename.ends_with(".gd"): filename += ".gd"
		var folder: String = str(project.path).path_join("scripts")
		DirAccess.make_dir_recursive_absolute(folder)
		var path: String = folder.path_join(filename)
		if FileAccess.file_exists(path): _notice("That script already exists."); return
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null: _notice("Could not write script."); return
		file.store_string("extends Node\n\nfunc _ready() -> void:\n\tprint(\"Hello from Lucky\")\n\nfunc _process(delta: float) -> void:\n\tpass\n")
		file.close()
		_open_script(path)
		_refresh_assets()
	)
	_popup(dialog, Vector2i(410, 130))

func _save_script() -> void:
	if script_path.is_empty(): _notice("Choose New script or open a script from Assets first."); return
	var file := FileAccess.open(script_path, FileAccess.WRITE)
	if file == null: _notice("Could not save script."); return
	file.store_string(script_editor.text)
	file.close()
	script_dirty = false
	_refresh_assets()
	_build_inspector()
	_log("Saved " + script_path.get_file() + ". Choose it in an object's Script attachment field.")

func _build_ai() -> void:
	var row := _hbox(ai_panel)
	row.add_child(_label("✦  LUCKY ASSIST", 15))
	_spacer(row)
	row.add_child(_button("×", _toggle_ai))
	ai_panel.add_child(_muted("Think, build, refine. Side by side."))
	provider_picker = OptionButton.new()
	for item in ["ChatGPT / Codex", "Claude Code — unavailable", "Cursor — unavailable", "Grok — unavailable", "OpenCode — unavailable"]:
		provider_picker.add_item(item)
	for index in range(1, provider_picker.item_count): provider_picker.set_item_disabled(index, true)
	ai_panel.add_child(provider_picker)
	var actions := _hbox(ai_panel)
	actions.add_child(_button("Connect", func(): ai.connect_provider(str(config.get_value("ai", "command", "")))))
	actions.add_child(_button("Sign in", func(): ai.login()))
	actions.add_child(_button("MCP", func(): ai.list_plugins()))
	actions.add_child(_button("New", func(): ai.new_chat(); chat.clear(); _ai_message("LUCKY", "New conversation. Your project is the working context.")))
	actions.add_child(_button("…", _connections))
	ai_status = _muted("Connect an installed Codex app-server. No API key.", 11)
	ai_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ai_status.custom_minimum_size.x = 285
	ai_panel.add_child(ai_status)
	model_picker = OptionButton.new()
	model_picker.add_item("Connect to discover models")
	model_picker.item_selected.connect(_model_selected)
	ai_panel.add_child(model_picker)
	row = _hbox(ai_panel)
	effort_picker = OptionButton.new()
	effort_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effort_picker.add_item("Provider default")
	effort_picker.set_item_metadata(0, "")
	row.add_child(effort_picker)
	speed = CheckBox.new()
	speed.text = "Fast"
	speed.disabled = true
	speed.tooltip_text = "This provider does not expose a documented speed control through this integration."
	row.add_child(speed)
	chat = RichTextLabel.new()
	chat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat.selection_enabled = true
	chat.scroll_following = true
	chat.custom_minimum_size.y = 180
	ai_panel.add_child(chat)
	_ai_message("LUCKY", "Connect to use the models available to your account. Your prompt, attachments, and project files the assistant reads may be sent to your provider. Project files are read-only in this beta; AI can explain and suggest changes.")
	attachment_label = _muted("No attachments", 11)
	ai_panel.add_child(attachment_label)
	prompt = TextEdit.new()
	prompt.placeholder_text = "What would you like to build?"
	prompt.custom_minimum_size.y = 100
	prompt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	ai_panel.add_child(prompt)
	row = _hbox(ai_panel)
	row.add_child(_button("＋ Files", _attach_files))
	row.add_child(_button("Clear", func(): attachments.clear(); attachment_label.text = "No attachments"))
	_spacer(row)
	row.add_child(_button("Stop", func(): ai.cancel()))
	row.add_child(_button("Send ↑", _send_prompt, true))
	if not models.is_empty(): _models_changed(models)

func _toggle_ai() -> void:
	ai_visible = not ai_visible
	if is_instance_valid(ai_panel): ai_panel.visible = ai_visible

func _ai_status(message: String) -> void:
	if is_instance_valid(ai_status): ai_status.text = message

func _models_changed(catalog: Array) -> void:
	models = catalog
	if not is_instance_valid(model_picker): return
	model_picker.clear()
	for model in models: model_picker.add_item(str(model.get("displayName", model.get("model", model.get("id", "Model")))))
	if models.is_empty(): model_picker.add_item("No models available")
	else: _model_selected(0)

func _model_selected(index: int) -> void:
	effort_picker.clear()
	effort_picker.add_item("Provider default")
	effort_picker.set_item_metadata(0, "")
	if index < 0 or index >= models.size(): return
	var fast_available: bool = ai.model_supports_fast(models[index])
	speed.disabled = not fast_available
	if not fast_available: speed.button_pressed = false
	speed.tooltip_text = "Uses the provider's advertised Fast tier. This can use more of your plan allowance." if fast_available else "This model does not advertise a Fast tier."
	var choices: Array = models[index].get("supportedReasoningEfforts", [])
	for choice in choices:
		var value: String = str(choice.get("reasoningEffort", choice.get("effort", ""))) if choice is Dictionary else str(choice)
		if not value.is_empty():
			var item := effort_picker.item_count
			effort_picker.add_item(value.capitalize())
			effort_picker.set_item_metadata(item, value)

func _send_prompt() -> void:
	var text := prompt.text.strip_edges()
	if text.is_empty(): return
	if not ai.is_connected or not ai.is_authenticated:
		_ai_status("Connect and sign in before sending a prompt.")
		return
	if ai.busy:
		_ai_status("Wait for the current response or press Stop.")
		return
	var model := ""
	if model_picker.selected >= 0 and model_picker.selected < models.size():
		var item: Dictionary = models[model_picker.selected]
		model = str(item.get("model", item.get("id", "")))
	var effort: String = str(effort_picker.get_selected_metadata()) if effort_picker.item_count > 0 else ""
	ai.send_prompt(text, project.path, model, effort, speed.button_pressed, attachments.duplicate())
	if not ai.busy: return
	_ai_message("YOU", text + ("\n[%d attachments]" % attachments.size() if not attachments.is_empty() else ""))
	_ai_message("ASSISTANT", "")
	prompt.text = ""
	attachments.clear()
	attachment_label.text = "No attachments"

func _ai_message(who: String, text: String) -> void:
	if is_instance_valid(chat): chat.append_text("\n" + who + "\n" + text + "\n")

func _ai_delta(text: String) -> void:
	if is_instance_valid(chat): chat.append_text(text)

func _attach_files() -> void:
	var dialog := FileDialog.new()
	dialog.title = "Attach files to next AI message"
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	dialog.use_native_dialog = true
	dialog.files_selected.connect(func(paths):
		for path in paths:
			if not attachments.has(path): attachments.append(path)
		attachment_label.text = "%d files attached" % attachments.size()
	)
	_popup(dialog, Vector2i(850, 550))

func _login_link(url: String) -> void:
	_confirm("Continue sign-in in your browser?\n" + url, func(): OS.shell_open(url))

func _plugins_loaded(plugins: Array) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "MCP connections"
	var box := _vbox(dialog)
	box.custom_minimum_size.x = 490
	box.add_child(_label("Tools that work with you.", 25))
	box.add_child(_muted("Servers configured in your connected provider."))
	for plugin in plugins:
		var row := _hbox(box)
		var name: String = str(plugin.get("name", plugin.get("id", "Server")))
		row.add_child(_label(name + "  ·  " + str(plugin.get("authStatus", ""))))
		_spacer(row)
		row.add_child(_button("Sign in", func(): ai.login_plugin(name)))
	if plugins.is_empty(): box.add_child(_muted("No MCP servers configured yet."))
	box.add_child(_button("＋ Connect an HTTPS MCP server", func(): dialog.hide(); _add_mcp()))
	box.add_child(_muted("Your provider controls tool permissions and remote access."))
	_popup(dialog, Vector2i(570, 360))

func _add_mcp() -> void:
	if not ai.is_connected: _notice("Connect the AI provider first."); return
	var dialog := AcceptDialog.new()
	dialog.title = "Connect MCP server"
	dialog.ok_button_text = "Save connection"
	var box := _vbox(dialog)
	box.custom_minimum_size.x = 490
	var name_input := LineEdit.new()
	name_input.placeholder_text = "Server name (letters, numbers, underscores)"
	box.add_child(name_input)
	var url := LineEdit.new()
	url.placeholder_text = "https://your-server.example/mcp"
	box.add_child(url)
	var info := _label("This updates your shared Codex MCP configuration. A connection with the same name will be replaced. Sign-in and tool permissions are handled by the provider.")
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 480
	box.add_child(info)
	dialog.confirmed.connect(func(): ai.configure_mcp(name_input.text.strip_edges(), url.text.strip_edges()))
	_popup(dialog, Vector2i(550, 240))

func _connections() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "AI connection"
	dialog.ok_button_text = "Save"
	var box := _vbox(dialog)
	box.custom_minimum_size.x = 500
	box.add_child(_label("Your account. Your models.", 26))
	var text := _label("Lucky connects to the documented Codex app-server installed with a compatible ChatGPT/Codex setup. Existing account access is checked by that provider. No API key or model download is required. Other providers are unavailable in this beta.")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 490
	box.add_child(text)
	box.add_child(_muted("Codex executable (leave blank to auto-detect)"))
	var field := LineEdit.new()
	field.text = str(config.get_value("ai", "command", ""))
	field.placeholder_text = "Auto-detect"
	box.add_child(field)
	box.add_child(_button("Choose executable", func():
		var picker := FileDialog.new()
		picker.access = FileDialog.ACCESS_FILESYSTEM
		picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		picker.use_native_dialog = true
		picker.filters = PackedStringArray(["*.exe ; Executable"])
		picker.file_selected.connect(func(path): field.text = path)
		_popup(picker, Vector2i(800, 500))
	))
	box.add_child(_button("Detect installed provider", func():
		var found: Dictionary = ai.discover()
		_notice(JSON.stringify(found, "  "))
	))
	box.add_child(_muted("MCP servers are managed by your provider. No credentials are copied by Lucky."))
	dialog.confirmed.connect(func(): config.set_value("ai", "command", field.text.strip_edges()); config.save("user://settings.cfg"))
	_popup(dialog, Vector2i(560, 410))

func _settings() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Make Lucky yours"
	dialog.ok_button_text = "Done"
	var box := _vbox(dialog)
	box.custom_minimum_size.x = 450
	box.add_child(_label("A little more you.", 28))
	var theme_choice := OptionButton.new()
	theme_choice.add_item("Dark  /  Pure black + white")
	theme_choice.add_item("Light  /  Pure white + black")
	theme_choice.select(1 if light else 0)
	box.add_child(theme_choice)
	theme_choice.item_selected.connect(func(index):
		light = index == 1
		config.set_value("appearance", "light", light)
		config.save("user://settings.cfg")
		_apply_theme()
		if is_instance_valid(viewport): viewport.set_light_mode(light)
	)
	var autosave := CheckBox.new()
	autosave.text = "Autosave every 60 seconds"
	autosave.button_pressed = config.get_value("editor", "autosave", true)
	autosave.toggled.connect(func(value): config.set_value("editor", "autosave", value); config.save("user://settings.cfg"))
	box.add_child(autosave)
	box.add_child(_button("AI connections", _connections))
	box.add_child(_button("Keyboard shortcuts & guide", _guide))
	box.add_child(_muted("Lucky " + VERSION + "\nBuilt on the Godot 4.7.2 runtime. MIT licensed."))
	_popup(dialog, Vector2i(510, 350))

func _palette() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Command palette"
	dialog.get_ok_button().hide()
	var box := _vbox(dialog)
	box.custom_minimum_size.x = 480
	var filter := LineEdit.new()
	filter.placeholder_text = "What do you want to do?"
	box.add_child(filter)
	var list := ItemList.new()
	list.custom_minimum_size.y = 340
	box.add_child(list)
	var commands: Array = [["Create project", _new_project], ["Open project", _open_project_dialog], ["Settings & theme", _settings], ["AI connections", _connections], ["Guide & shortcuts", _guide]]
	if not project.is_empty():
		commands.append_array([["Save project  ·  Ctrl S", _save], ["Run project  ·  F5", _run], ["Stop game  ·  F8", _stop], ["Add object", _add_dialog], ["Duplicate selection  ·  Ctrl D", _duplicate], ["Undo  ·  Ctrl Z", _undo], ["Redo  ·  Ctrl Y", _redo], ["Import assets", _import_assets], ["Create snapshot", _backup], ["Restore latest snapshot", _restore], ["Validate project", _validate], ["Export Windows portable", _export], ["Toggle AI panel", _toggle_ai], ["Reset viewport", func(): viewport.reset_view()], ["Back to launcher", _return_home]])
	var populate := func(text):
		list.clear()
		for i in commands.size():
			if str(commands[i][0]).to_lower().contains(str(text).to_lower()):
				var item := list.add_item(commands[i][0])
				list.set_item_metadata(item, i)
		if list.item_count > 0: list.select(0)
	populate.call("")
	filter.text_changed.connect(populate)
	var execute := func(index):
		var command: Callable = commands[int(list.get_item_metadata(index))][1]
		dialog.hide()
		command.call()
	list.item_activated.connect(execute)
	filter.text_submitted.connect(func(_text): if list.item_count > 0: execute.call(list.get_selected_items()[0] if not list.get_selected_items().is_empty() else 0))
	_popup(dialog, Vector2i(540, 440))
	filter.grab_focus()

func _guide() -> void:
	_notice("LUCKY " + VERSION + "\n\nCreate a project from Blank, Showcase, or the playable 2D Platformer template.\n\nSCENE — Add shapes, select objects, edit transforms and materials, reorder, duplicate and delete. 2D supports drag movement. 3D supports orbit and selection; edit transforms in Inspector.\n\nASSETS — Import files. Double-click images to add 2D sprites. Double-click .gd files to edit. Scripts can be attached through the Script controls.\n\nSAVE — Writes project.lucky.json and a native Godot scene. Snapshots preserve project history. Validation checks scene data.\n\nRUN — Launches the real project runtime. F8 stops it. Export creates a portable Windows folder including the runtime.\n\nAI — Connect your installed compatible Codex app-server, sign in if needed, then choose models and supported reasoning modes. Attach files explicitly. Provider MCP configuration is available in the panel.\n\nSHORTCUTS — Ctrl K commands · Ctrl S save · Ctrl Z undo · Ctrl Y redo · Ctrl D duplicate · Delete remove · F frame · F5 run · F8 stop.\n\nBETA SCOPE — This is a new editor built on an unmodified Godot runtime. General Godot scene importing, a complete animation/shader/node editor, other AI providers, collaboration, native platform exports, and parity with mature engines are future work.")

func _return_home() -> void:
	var leave := func(): _stop(); ai.new_chat(); project = {}; script_path = ""; _home()
	if dirty or script_dirty: _confirm("Save changes and return to the launcher?", func(): _save(); if not dirty and not script_dirty: leave.call())
	else: leave.call()

func _log(message: String) -> void:
	var time := Time.get_time_string_from_system()
	var line := time + "  " + message
	output_lines.append(line)
	if output_lines.size() > 200: output_lines.pop_front()
	if is_instance_valid(console): console.append_text(line + "\n")
	if is_instance_valid(status): status.text = message.get_slice("\n", 0)

func _notice(message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Lucky"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(570, 320)
	dialog.add_child(scroll)
	var label := _label(message)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 550
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(label)
	_popup(dialog, Vector2i(640, 410))

func _confirm(message: String, action: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Lucky"
	dialog.dialog_text = message
	dialog.confirmed.connect(action)
	_popup(dialog, Vector2i(520, 180))

func _popup(dialog: Window, dimensions: Vector2i) -> void:
	dialog.theme = theme
	dialog.add_to_group("lucky_dialogs")
	add_child(dialog)
	dialog.popup_centered(dimensions)
	dialog.close_requested.connect(func(): dialog.queue_free())

func _self_test_ui() -> void:
	var data := {"name": "UI test", "path": OS.get_environment("TEMP").path_join("lucky-ui-test"), "dimension": "3D", "objects": [], "version": VERSION}
	_activate(data)
	_add_object("Box")
	_duplicate()
	_undo()
	_redo()
	selected = 0
	_build_inspector()
	_property("name", "Test cube")
	_toggle_ai()
	_toggle_ai()
	light = not light
	_apply_theme()
	viewport.set_light_mode(light)
	print("LUCKY_UI_TEST_PASS")
	get_tree().quit()
