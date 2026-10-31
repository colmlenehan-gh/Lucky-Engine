extends SceneTree
## Supply a compiled tests/fixtures/fake_app_server.cs executable after `--`.
## This exercises actual process pipes; the fixture makes no external requests.

var bridge: Node
var reply: String = ""
var got_models: bool = false
var got_plugins: bool = false
var expected_failure: bool = false
var phase: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_cmdline_user_args().is_empty():
		_fail("Pass the compiled offline fixture executable after --")
		return
	bridge = load("res://ai_bridge.gd").new()
	root.add_child(bridge)
	bridge.failure.connect(func(message):
		if expected_failure:
			expected_failure = false
		else:
			_fail(message)
	)
	bridge.models_changed.connect(func(items): got_models = items.size() == 2)
	bridge.plugins_changed.connect(func(items):
		got_plugins = items.size() == 1
		if phase == 2:
			_finish()
	)
	bridge.response_delta.connect(func(text): reply += text)
	bridge.response_done.connect(_response_done)
	bridge.connect_provider(OS.get_cmdline_user_args()[0])
	for i in range(200):
		await create_timer(0.02).timeout
		if bridge.is_authenticated and got_models and got_plugins:
			if not bridge.supports_fast or not bridge.model_supports_fast(bridge.models[0]) or bridge.model_supports_fast(bridge.models[1]):
				_fail("Incorrect model capability detection")
				return
			expected_failure = true
			bridge.send_prompt("unsupported tier", ProjectSettings.globalize_path("res://"), "fixture-standard", "low", true)
			if expected_failure or bridge.busy:
				_fail("Unsupported Fast mode was not rejected")
				return
			bridge.send_prompt("hello", ProjectSettings.globalize_path("res://"), "fixture-fast", "medium", true, [ProjectSettings.globalize_path("res://tests/ai_bridge_test.gd")])
			return
	_fail("Connection/catalog timeout")

func _response_done() -> void:
	if reply != "Hello Lucky ★":
		_fail("Streamed response was missing, corrupt or duplicated: " + reply)
		return
	if phase == 0:
		phase = 1
		reply = ""
		bridge.send_prompt("Fast off", ProjectSettings.globalize_path("res://"), "fixture-fast", "medium", false)
	else:
		phase = 2
		bridge.configure_mcp("fixture", "https://mcp.example.test/mcp")
		create_timer(4).timeout.connect(func(): if phase == 2: _fail("MCP reload timeout"))

func _finish() -> void:
	phase = 3
	bridge.new_chat()
	bridge.disconnect_provider()
	print("LUCKY_AI_TRANSPORT_TEST_PASS: pipes, auth fixture, catalog, reasoning, Fast on/off, text attachment, MCP config/reload, UTF-8 streaming, completion and disconnect")
	quit(0)

func _fail(message: String) -> void:
	push_error("LUCKY_AI_TRANSPORT_TEST_FAIL: " + message)
	if is_instance_valid(bridge):
		bridge.disconnect_provider()
	quit(1)
