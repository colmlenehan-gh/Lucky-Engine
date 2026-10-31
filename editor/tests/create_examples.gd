extends SceneTree
const Store = preload("res://project_store.gd")
func _initialize() -> void:
	var destination: String = OS.get_environment("LUCKY_EXAMPLES_DIR")
	if not destination.is_absolute_path():
		printerr("Set LUCKY_EXAMPLES_DIR to a new absolute examples folder.")
		quit(2)
		return
	for spec in [["Monochrome Playground", "3D", "Showcase"], ["First Steps", "2D", "Platformer"], ["Canvas Study", "2D", "Showcase"]]:
		var result: Dictionary = Store.create_project(destination.path_join(spec[0]), spec[0], spec[1], spec[2])
		if result.has("error"):
			printerr(result.error)
			quit(1)
			return
	print("LUCKY_EXAMPLES_CREATED")
	quit()
