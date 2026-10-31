extends Node
## Subscription-backed assistant transport. No API keys, web scraping or UI embedding.
## JSON-RPC protocol: https://learn.chatgpt.com/docs/app-server

signal status_changed(message: String)
signal models_changed(models: Array)
signal response_delta(text: String)
signal response_done()
signal plugins_changed(plugins: Array)
signal login_required(url: String)
signal failure(message: String)

var is_connected: bool = false
var is_authenticated: bool = false
var supports_fast: bool = false
var models: Array = []
var plugins: Array = []
var account: Dictionary = {}
var command: String = ""
var thread_id: String = ""
var turn_id: String = ""
var busy: bool = false
var _process_id: int = -1
var _stdio: FileAccess
var _stderr: FileAccess
var _read_bytes: PackedByteArray = PackedByteArray()
var _request_id: int = 0
var _pending: Dictionary = {}
var _queued_turn: Dictionary = {}
var _thread_project: String = ""
var _connection_started: int = 0
var _last_response: int = 0
var _streamed_items: Dictionary = {}
var _model_pages: Array = []
var _plugin_pages: Array = []
var _conversation_epoch: int = 0
var _ignored_turns: Dictionary = {}
var _configuring_mcp: bool = false

func _ready() -> void:
	set_process(false)

func discover() -> Dictionary:
	var candidates: Array[String] = []
	var executable_folder: String = OS.get_executable_path().get_base_dir()
	for root in [executable_folder, executable_folder.get_base_dir(), ProjectSettings.globalize_path("res://..")]:
		candidates.append(String(root).path_join("tools/codex/bin/codex-app-server.exe"))
	var separator: String = ";" if OS.get_name() == "Windows" else ":"
	for directory in OS.get_environment("PATH").split(separator, false):
		candidates.append(directory.strip_edges().trim_prefix('"').trim_suffix('"').path_join("codex-app-server.exe" if OS.get_name() == "Windows" else "codex-app-server"))
		candidates.append(directory.strip_edges().trim_prefix('"').trim_suffix('"').path_join("codex.exe" if OS.get_name() == "Windows" else "codex"))
	var local: String = OS.get_environment("LOCALAPPDATA")
	var roaming: String = OS.get_environment("APPDATA")
	if not roaming.is_empty():
		candidates.append(roaming.path_join("npm/node_modules/@openai/codex/vendor/x86_64-pc-windows-msvc/codex/codex.exe"))
	for root in [local.path_join("Programs/ChatGPT"), local.path_join("Programs/Codex"), local.path_join("OpenAI/ChatGPT"), local.path_join("OpenAI/Codex")]:
		if not local.is_empty():
			_find_command(String(root), candidates, 4)
	for candidate in candidates:
		if FileAccess.file_exists(candidate):
			return {"found": true, "command": candidate, "provider": "ChatGPT / Codex", "supports_fast": false}
	return {"found": false, "command": "", "provider": "ChatGPT / Codex", "supports_fast": false, "message": "Choose the installed Codex app-server executable. A ChatGPT window alone does not provide an embeddable chat service."}

func _find_command(folder: String, candidates: Array[String], depth: int) -> void:
	if depth < 0 or not DirAccess.dir_exists_absolute(folder):
		return
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	var count: int = 0
	while not entry.is_empty() and count < 200:
		count += 1
		if not entry.begins_with("."):
			var child: String = folder.path_join(entry)
			if dir.current_is_dir():
				if entry != "node_modules" and entry != "Cache":
					_find_command(child, candidates, depth - 1)
			elif entry.to_lower() in ["codex.exe", "codex-app-server.exe"] or entry in ["codex", "codex-app-server"]:
				candidates.append(child)
		entry = dir.get_next()
	dir.list_dir_end()

func connect_provider(command_path: String = "") -> void:
	disconnect_provider()
	command = command_path.strip_edges().trim_prefix('"').trim_suffix('"')
	if command.is_empty():
		command = String(discover().get("command", ""))
	if command.is_empty() or not FileAccess.file_exists(command):
		failure.emit("Codex app-server was not found. Install Codex or choose codex.exe in AI settings; sign in with your ChatGPT account.")
		return
	# Call the executable directly: no shell interpolation or hidden browser automation.
	var command_name: String = command.get_file().get_basename().to_lower()
	var arguments: PackedStringArray = PackedStringArray() if command_name == "codex-app-server" else PackedStringArray(["app-server"])
	var pipes: Dictionary = OS.execute_with_pipe(command, arguments, false)
	if pipes.is_empty():
		failure.emit("Could not start this executable as Codex app-server.")
		return
	_stdio = pipes.get("stdio")
	_stderr = pipes.get("stderr")
	_process_id = int(pipes.get("pid", -1))
	_connection_started = Time.get_ticks_msec()
	_last_response = _connection_started
	set_process(true)
	status_changed.emit("Connecting to the installed Codex app-server…")
	_request("initialize", {"clientInfo": {"name": "lucky_engine", "title": "Lucky Engine", "version": "0.1.0-beta"}})

func disconnect_provider() -> void:
	set_process(false)
	if _process_id > 0 and OS.is_process_running(_process_id):
		OS.kill(_process_id)
	_process_id = -1
	_stdio = null
	_stderr = null
	_read_bytes = PackedByteArray()
	_pending.clear()
	_queued_turn.clear()
	thread_id = ""
	turn_id = ""
	_thread_project = ""
	_streamed_items.clear()
	_conversation_epoch += 1
	_ignored_turns.clear()
	_configuring_mcp = false
	busy = false
	is_connected = false
	is_authenticated = false
	supports_fast = false
	account = {}
	models = []
	plugins = []

func request_models() -> void:
	if is_connected:
		_model_pages = []
		_request("model/list", {"limit": 100, "includeHidden": false})

func list_plugins() -> void:
	if is_connected:
		_plugin_pages = []
		_request("mcpServerStatus/list", {"limit": 100})

func login() -> void:
	if not is_connected:
		failure.emit("Connect to the installed Codex executable before signing in.")
		return
	# A URL is emitted for the interface to open only after the user's Login action.
	_request("account/login/start", {"type": "chatgpt"})

func login_plugin(server_name: String) -> void:
	if not is_connected or server_name.is_empty():
		return
	_request("mcpServer/oauth/login", {"name": server_name})

func configure_mcp(server_name: String, server_url: String) -> void:
	if not is_connected:
		failure.emit("Connect the AI provider before adding an MCP server.")
		return
	if busy or _configuring_mcp:
		failure.emit("Wait for the current assistant or configuration request to finish.")
		return
	var name_pattern: RegEx = RegEx.new()
	name_pattern.compile("^[A-Za-z0-9_-]{1,64}$")
	if name_pattern.search(server_name) == null:
		failure.emit("Use 1–64 letters, numbers, underscores or hyphens for the MCP server name.")
		return
	var url: String = server_url.strip_edges()
	var url_pattern: RegEx = RegEx.new()
	url_pattern.compile("^https://[^\\s/@]+(?:/[^\\s]*)?$")
	if url_pattern.search(url) == null:
		failure.emit("Use an HTTPS MCP server URL without embedded credentials.")
		return
	_configuring_mcp = true
	# Called only by an explicit Add MCP action. This is shared provider configuration,
	# not a project setting; the UI must say so before invoking this method.
	_request("config/value/write", {"keyPath": "mcp_servers." + server_name, "value": {"url": url}, "mergeStrategy": "upsert"})
	status_changed.emit("Saving MCP server to the connected provider's configuration…")

func new_chat() -> void:
	if not turn_id.is_empty():
		_ignored_turns[turn_id] = true
	if busy:
		cancel()
	_conversation_epoch += 1
	_queued_turn.clear()
	busy = false
	thread_id = ""
	turn_id = ""
	_thread_project = ""
	_streamed_items.clear()

func model_supports_fast(record: Dictionary) -> bool:
	for tier in record.get("serviceTiers", []):
		var tier_id: String = String(tier.get("id", "")) if tier is Dictionary else str(tier)
		if tier_id in ["priority", "fast"]:
			return true
	return "fast" in record.get("additionalSpeedTiers", [])

func send_prompt(prompt: String, project_path: String, model: String = "", effort: String = "", fast: bool = false, attachments: Array = []) -> void:
	if not is_connected or not is_authenticated:
		failure.emit("Connect and sign in with a ChatGPT account before sending a prompt.")
		return
	if busy:
		failure.emit("Wait for the current response or press Stop first.")
		return
	if fast:
		var selected_model: Dictionary = {}
		for record in models:
			if String(record.get("model", record.get("id", ""))) == model or (model.is_empty() and bool(record.get("isDefault", false))):
				selected_model = record
				break
		if not model_supports_fast(selected_model):
			failure.emit("The selected model does not advertise Fast mode. Turn Fast off or select a supported model.")
			return
	if prompt.strip_edges().is_empty() and attachments.is_empty():
		return
	if not DirAccess.dir_exists_absolute(project_path):
		failure.emit("Open a project before starting an AI conversation.")
		return
	var inputs: Array = [{"type": "text", "text": prompt}]
	for attachment in attachments:
		var file_path: String = String(attachment.get("path", "")) if attachment is Dictionary else String(attachment)
		if not FileAccess.file_exists(file_path):
			failure.emit("Attachment does not exist: " + file_path.get_file())
			return
		var ext: String = file_path.get_extension().to_lower()
		if ext in ["png", "jpg", "jpeg", "webp", "gif"]:
			inputs.append({"type": "localImage", "path": file_path})
		else:
			var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
			if file == null or file.get_length() > 262144:
				failure.emit("Text attachments must be readable and no larger than 256 KB. Images can be attached directly.")
				return
			if not ext in ["txt", "md", "gd", "json", "tscn", "tres", "godot", "csv", "svg", "glsl", "gdshader", "cs", "cpp", "h", "py", "yaml", "yml", "toml", "log"]:
				failure.emit("Unsupported attachment type: " + ext + ". Attach images or text/code files.")
				return
			inputs.append({"type": "text", "text": "Attached file: " + file_path.get_file() + "\n\n" + file.get_as_text()})
	# Explicit null clears a previous turn's tier when the user switches Fast off.
	_queued_turn = {"input": inputs, "cwd": project_path, "model": model, "effort": effort, "serviceTier": "priority" if fast else null}
	busy = true
	_streamed_items.clear()
	if thread_id.is_empty() or _thread_project != project_path:
		# The stable turn-level policy below is authoritative; avoid version-specific
		# legacy thread sandbox enum spellings. No model turn starts before that policy.
		var params: Dictionary = {"cwd": project_path, "approvalPolicy": "never"}
		if not model.is_empty():
			params["model"] = model
		_thread_project = project_path
		_request("thread/start", params)
	else:
		_start_queued_turn()
	status_changed.emit("Waiting for assistant…")

func _start_queued_turn() -> void:
	if _queued_turn.is_empty() or thread_id.is_empty():
		return
	var params: Dictionary = _queued_turn.duplicate(true)
	params["threadId"] = thread_id
	params["approvalPolicy"] = "never"
	params["sandboxPolicy"] = {"type": "readOnly"}
	if String(params.get("model", "")).is_empty():
		params.erase("model")
	if String(params.get("effort", "")).is_empty():
		params.erase("effort")
	_queued_turn.clear()
	_request("turn/start", params)

func cancel() -> void:
	if is_connected and not thread_id.is_empty() and not turn_id.is_empty():
		_request("turn/interrupt", {"threadId": thread_id, "turnId": turn_id})
	elif busy:
		_queued_turn.clear()
		busy = false
		response_done.emit()

func _request(method: String, params: Dictionary = {}) -> void:
	_request_id += 1
	_pending[str(_request_id)] = {"method": method, "time": Time.get_ticks_msec(), "epoch": _conversation_epoch}
	_write({"id": _request_id, "method": method, "params": params})

func _write(packet: Dictionary) -> void:
	if _stdio == null:
		return
	_stdio.store_buffer((JSON.stringify(packet) + "\n").to_utf8_buffer())
	_stdio.flush()
	var result: Error = _stdio.get_error()
	if result != OK:
		failure.emit("App-server pipe write failed (" + str(result) + "). Reconnect to retry.")

func _process(_delta: float) -> void:
	if _stdio == null:
		return
	# Nonblocking pipe reads keep the editor responsive and preserve split UTF-8/JSON frames.
	var incoming: PackedByteArray = _stdio.get_buffer(65536)
	if not incoming.is_empty():
		_read_bytes.append_array(incoming)
		_last_response = Time.get_ticks_msec()
	if _read_bytes.size() > 8 * 1024 * 1024:
		failure.emit("App-server sent an oversized message. Reconnect to continue.")
		disconnect_provider()
		return
	var newline: int = _read_bytes.find(10)
	var handled: int = 0
	while newline >= 0 and handled < 100:
		var line: String = _read_bytes.slice(0, newline).get_string_from_utf8().strip_edges()
		_read_bytes = _read_bytes.slice(newline + 1)
		if not line.is_empty():
			var packet: Variant = JSON.parse_string(line)
			if packet is Dictionary:
				_handle_packet(packet)
		if _stdio == null:
			return
		newline = _read_bytes.find(10)
		handled += 1
	# Drain stderr so a verbose child cannot deadlock; never expose auth/config secrets.
	if _stderr != null:
		_stderr.get_buffer(16384)
	if _process_id > 0 and not OS.is_process_running(_process_id):
		failure.emit("Codex app-server stopped. Select a compatible executable and reconnect.")
		disconnect_provider()
		return
	if not is_connected and Time.get_ticks_msec() - _connection_started > 20000:
		failure.emit("App-server initialization timed out. Check the selected Codex executable.")
		disconnect_provider()
		return
	var expired: Array = []
	for key in _pending:
		var request: Dictionary = _pending[key]
		if Time.get_ticks_msec() - int(request.get("time", 0)) > 120000:
			expired.append(key)
	for key in expired:
		var method: String = String(_pending[key].get("method", "request"))
		_pending.erase(key)
		if method in ["thread/start", "turn/start"]:
			busy = false
			response_done.emit()
		if method in ["config/value/write", "config/mcpServer/reload"]:
			_configuring_mcp = false
		failure.emit("App-server request timed out: " + method)

func _handle_packet(packet: Dictionary) -> void:
	if packet.has("id") and not packet.has("method"):
		var id_key: String = str(int(packet["id"])) if packet["id"] is float or packet["id"] is int else str(packet["id"])
		var pending: Dictionary = _pending.get(id_key, {})
		_pending.erase(id_key)
		var method: String = String(pending.get("method", ""))
		if method in ["thread/start", "turn/start"] and int(pending.get("epoch", _conversation_epoch)) != _conversation_epoch:
			return
		if packet.has("error"):
			var err: Variant = packet["error"]
			var message: String = String(err.get("message", "Request failed")) if err is Dictionary else str(err)
			if method in ["config/value/write", "config/mcpServer/reload"]:
				_configuring_mcp = false
			if method in ["thread/start", "turn/start"]:
				busy = false
				_queued_turn.clear()
				response_done.emit()
			failure.emit(method + ": " + message)
			return
		var result: Dictionary = packet.get("result", {}) if packet.get("result") is Dictionary else {}
		_handle_result(method, result)
		return
	var method: String = String(packet.get("method", ""))
	var params: Dictionary = packet.get("params", {}) if packet.get("params") is Dictionary else {}
	if packet.has("id"):
		# Chat-only beta never grants execution, file-write, network or elicitation approval.
		if method in ["item/commandExecution/requestApproval", "item/fileChange/requestApproval"]:
			_write({"id": packet["id"], "result": {"decision": "decline"}})
		else:
			_write({"id": packet["id"], "error": {"code": -32601, "message": "Lucky beta does not support this interactive request; continue in the provider app."}})
		status_changed.emit("An interactive provider request needs its original app. Lucky remains in chat-only mode.")
		return
	if method.begins_with("item/") or method.begins_with("turn/"):
		if thread_id.is_empty():
			return
		if params.has("threadId") and String(params["threadId"]) != thread_id:
			return
		var event_turn: String = String(params.get("turnId", ""))
		if params.get("turn") is Dictionary:
			event_turn = String(params["turn"].get("id", event_turn))
		if _ignored_turns.has(event_turn):
			return
	match method:
		"item/agentMessage/delta":
			var item_id: String = String(params.get("itemId", ""))
			_streamed_items[item_id] = true
			response_delta.emit(String(params.get("delta", "")))
		"item/completed":
			var item: Dictionary = params.get("item", {})
			if item.get("type", "") == "agentMessage" and not _streamed_items.has(String(item.get("id", ""))):
				response_delta.emit(String(item.get("text", "")))
		"turn/started":
			turn_id = String(params.get("turn", {}).get("id", ""))
		"turn/completed":
			busy = false
			turn_id = ""
			var turn: Dictionary = params.get("turn", {})
			if turn.get("status", "") == "failed":
				failure.emit(String(turn.get("error", {}).get("message", "The assistant turn failed.")))
			status_changed.emit("Connected · ChatGPT subscription")
			response_done.emit()
		"account/login/completed":
			if bool(params.get("success", false)):
				_request("account/read", {"refreshToken": false})
			else:
				failure.emit("ChatGPT sign-in did not complete. " + String(params.get("error", "")))
		"account/updated":
			_request("account/read", {"refreshToken": false})
		"mcpServer/oauthLogin/completed":
			list_plugins()
		"error":
			failure.emit(String(params.get("error", {}).get("message", "App-server error")))
		"warning":
			status_changed.emit(String(params.get("message", "Provider warning")))
		"configWarning":
			status_changed.emit(String(params.get("summary", "Provider configuration warning")))

func _handle_result(method: String, result: Dictionary) -> void:
	match method:
		"initialize":
			_write({"method": "initialized", "params": {}})
			is_connected = true
			_request("account/read", {"refreshToken": false})
			status_changed.emit("App-server connected. Checking ChatGPT sign-in…")
		"account/read":
			account = result.get("account", {}) if result.get("account") is Dictionary else {}
			is_authenticated = String(account.get("type", "")) in ["chatgpt", "chatgptAuthTokens"]
			if is_authenticated:
				status_changed.emit("Connected · ChatGPT " + String(account.get("planType", "subscription")))
				request_models()
				list_plugins()
			else:
				status_changed.emit("App-server connected. Sign in with ChatGPT; API-key mode is not used by Lucky.")
		"account/login/start":
			var url: String = String(result.get("authUrl", result.get("verificationUrl", "")))
			if url.begins_with("https://"):
				login_required.emit(url)
				status_changed.emit("Finish sign-in in your browser, then return to Lucky.")
		"model/list":
			_model_pages.append_array(result.get("data", []))
			var cursor: Variant = result.get("nextCursor")
			if cursor != null and not str(cursor).is_empty():
				_request("model/list", {"limit": 100, "includeHidden": false, "cursor": cursor})
			else:
				models = _model_pages.duplicate(true)
				supports_fast = false
				for record in models:
					if record is Dictionary and model_supports_fast(record):
						supports_fast = true
				models_changed.emit(models)
		"mcpServerStatus/list":
			_plugin_pages.append_array(result.get("data", []))
			var cursor: Variant = result.get("nextCursor")
			if cursor != null and not str(cursor).is_empty():
				_request("mcpServerStatus/list", {"limit": 100, "cursor": cursor})
			else:
				plugins = _plugin_pages.duplicate(true)
				plugins_changed.emit(plugins)
		"mcpServer/oauth/login":
			var url: String = String(result.get("authorizationUrl", ""))
			if url.begins_with("https://"):
				login_required.emit(url)
		"config/value/write":
			_request("config/mcpServer/reload", {})
		"config/mcpServer/reload":
			_configuring_mcp = false
			status_changed.emit("MCP configuration saved and reloaded. Sign in to the server if required.")
			list_plugins()
		"thread/start":
			thread_id = String(result.get("thread", {}).get("id", ""))
			if thread_id.is_empty():
				busy = false
				failure.emit("App-server did not return a conversation ID.")
				response_done.emit()
			else:
				_start_queued_turn()
		"turn/start":
			turn_id = String(result.get("turn", {}).get("id", ""))

func _exit_tree() -> void:
	disconnect_provider()
