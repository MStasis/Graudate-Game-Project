class_name LocalAIClient
extends Node
## UI나 게임 규칙을 변경하지 않는 로컬 AI 통신 전용 노드입니다.

signal started
signal partial_text(text: String)
signal completed(record: Dictionary)
signal attempt_recorded(record: Dictionary)
signal failed(message: String)
signal readiness(message: String)

@export var settings: LocalNPCSettings
@onready var health_request: HTTPRequest = $HealthRequest

const MAX_RESPONSE_BYTES := 4 * 1024 * 1024
const MAX_EVENT_BYTES := 256 * 1024

var busy := false
var log_dir := ""
var client := HTTPClient.new()
var request_sent := false
var buffer := PackedByteArray()
var response_bytes := 0
var _request_generation := 0
var generated := ""
var started_usec := 0
var first_usec := 0
var first_thought_usec := 0
var last_thought_usec := 0
var wire_content := ""
var inline_boundary := false
var native_off_supported: Variant = null
var verified_model := ""
var checking_template := false
var structured_text := RegEx.new()
var previous_frame_usec := 0
var generation_frames := 0
var max_frame_ms := 0.0
var thinking_character_count := 0
var request_state := {}
var request_prompt := ""
var request_system := ""
var request_question := ""
var output_schema := {}
var chat_messages: Array = []

func check_connection() -> void:
	if not health_request.request_completed.is_connected(_connection_checked):
		health_request.request_completed.connect(_connection_checked)
	health_request.timeout = 5
	health_request.body_size_limit = MAX_EVENT_BYTES
	health_request.request("http://%s:%d/api/tags" % [settings.host, settings.port])

func _connection_checked(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if busy: return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		readiness.emit("로컬 서버 연결 실패. START_DEMO.cmd로 실행하세요.")
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	var models = parsed.get("models") if parsed is Dictionary else null
	if not models is Array:
		readiness.emit("로컬 서버 모델 목록을 해석할 수 없습니다.")
		return
	var found: bool = models.any(func(item): return item is Dictionary and item.get("name") == settings.model)
	readiness.emit("로컬 모델 준비 완료" if found else "%s 모델 준비가 필요합니다." % settings.model)

func generate(system_text: String, prompt: String, state: Dictionary, question_text: String, schema: Dictionary = {}, messages: Array = []) -> bool:
	if busy: return false
	request_state = state.duplicate(true)
	request_system = system_text
	request_prompt = prompt
	request_question = question_text
	output_schema = schema.duplicate(true)
	chat_messages = messages.duplicate(true)
	busy = true
	_request_generation += 1
	request_sent = false
	buffer = PackedByteArray()
	response_bytes = 0
	generated = ""
	started_usec = Time.get_ticks_usec()
	first_usec = 0
	first_thought_usec = 0
	last_thought_usec = 0
	wire_content = ""
	inline_boundary = false
	if settings.dialogue_profile == "D" and not structured_text.is_valid():
		structured_text.compile('^\\s*\\{\\s*"dialogue"\\s*:\\s*"\\s*[^"\\s}]')
	generation_frames = 0
	max_frame_ms = 0.0
	thinking_character_count = 0
	started.emit()
	var endpoint_key := "%s:%d/%s" % [settings.host,settings.port,settings.model]
	if not settings.effective_thinking() and settings.dialogue_profile not in ["A","D"] and verified_model != endpoint_key:
		# Different installations can use different checkpoints under the same tag.
		var info := HTTPRequest.new()
		add_child(info)
		info.timeout = 2
		info.body_size_limit = MAX_RESPONSE_BYTES
		checking_template = true
		info.request_completed.connect(_model_info.bind(info,endpoint_key,_request_generation))
		if info.request("http://%s:%d/api/show" % [settings.host,settings.port],["Content-Type: application/json"],HTTPClient.METHOD_POST,JSON.stringify({"model":settings.model})) == OK:
			return true
		info.queue_free()
		checking_template = false
		native_off_supported = null
	return _connect_transport()

func _model_info(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, info: HTTPRequest, key: String, generation: int) -> void:
	info.queue_free()
	if not busy or generation != _request_generation: return
	checking_template = false
	native_off_supported = null
	verified_model = ""
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var meta = JSON.parse_string(body.get_string_from_utf8())
		if meta is Dictionary and meta.get("thinking") is Dictionary and meta.thinking.get("values") is Array:
			native_off_supported = false in meta.thinking.get("values")
			verified_model = key
	_connect_transport()

func _connect_transport() -> bool:
	var error := client.connect_to_host(settings.host, settings.port)
	if error != OK:
		_fail("연결 시작 실패: %s" % error)
		return false
	return true

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var gap := (now - previous_frame_usec) / 1000.0 if previous_frame_usec > 0 else 0.0
	previous_frame_usec = now
	if not busy: return
	generation_frames += 1
	max_frame_ms = maxf(max_frame_ms, gap)
	if now - started_usec > settings.timeout_seconds * 1000000.0:
		_fail("로컬 모델 응답 시간초과")
		return
	if checking_template: return
	if client.poll() != OK:
		_finish_stream("HTTP 연결 처리 오류")
		return
	var state := client.get_status()
	if state == HTTPClient.STATUS_CONNECTED and not request_sent:
		var payload := {"model": settings.model, "system": request_system, "prompt": request_prompt, "stream": true, "keep_alive": "15m", "options": settings.generation_options()}
		var endpoint := "/api/generate"
		if not chat_messages.is_empty():
			payload.erase("system")
			payload.erase("prompt")
			payload["messages"] = chat_messages
			endpoint = "/api/chat"
		if not output_schema.is_empty(): payload["format"] = output_schema
		if not settings.model.to_lower().begins_with("qwen2.5"): payload["think"] = settings.effective_thinking()
		var error := client.request(HTTPClient.METHOD_POST, endpoint, PackedStringArray(["Content-Type: application/json"]), JSON.stringify(payload))
		if error != OK: _fail("요청 전송 실패: %s" % error)
		else: request_sent = true
	elif state == HTTPClient.STATUS_BODY:
		if client.get_response_code() != 200:
			_fail("로컬 서버 HTTP %s. 서버와 모델 설치를 확인하세요." % client.get_response_code())
			return
		if settings.dialogue_profile == "C_FAST": _drain_available()
		else: _consume_chunk(client.read_response_body_chunk())
	elif request_sent and state in [HTTPClient.STATUS_CONNECTED, HTTPClient.STATUS_DISCONNECTED]:
		_finish_stream("완료 표시 없이 연결이 끝났습니다.")
	elif state in [HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR]:
		_fail("로컬 서버에 연결할 수 없습니다.")

func _drain_available() -> void:
	# HTTPClient is nonblocking. Limit both time and reads to leave the next game frame responsive.
	var generation := _request_generation
	var deadline := Time.get_ticks_usec() + 1200
	for read_index in 32:
		var bytes := client.read_response_body_chunk()
		if bytes.is_empty(): return
		_consume_chunk(bytes)
		if not busy or generation != _request_generation or Time.get_ticks_usec() >= deadline: return
		if client.poll() != OK:
			_finish_stream("HTTP 연결 처리 오류")
			return
		if client.get_status() != HTTPClient.STATUS_BODY: return

func _finish_stream(connection_error: String) -> void:
	# A complete final JSON record can end at EOF without a trailing newline.
	var generation := _request_generation
	_consume_lines(true)
	if busy and generation == _request_generation: _fail(connection_error)

func _consume_chunk(chunk: PackedByteArray) -> void:
	response_bytes += chunk.size()
	if response_bytes > MAX_RESPONSE_BYTES:
		_fail("모델 응답이 허용 크기를 초과했습니다.")
		return
	buffer.append_array(chunk)
	_consume_lines(false)

func _consume_lines(flush: bool) -> void:
	var generation := _request_generation
	while busy and generation == _request_generation:
		var newline := buffer.find(10)
		if (buffer.size() if newline < 0 else newline) > MAX_EVENT_BYTES:
			_fail("모델 응답 한 줄이 허용 크기를 초과했습니다.")
			return
		if newline < 0:
			if flush and not buffer.is_empty():
				var remaining := buffer
				buffer = PackedByteArray()
				_consume_event(remaining.get_string_from_utf8())
			return
		var line := buffer.slice(0, newline)
		buffer = buffer.slice(newline + 1)
		_consume_event(line.get_string_from_utf8())

func _consume_event(line: String) -> void:
	if line.strip_edges().is_empty(): return
	var event = JSON.parse_string(line)
	if not event is Dictionary:
		_fail("응답 JSON 해석 실패")
		return
	if event.has("error"):
		_fail("로컬 모델 오류: " + str(event.error).left(300), str(event.error))
		return
	var message = event.get("message", {})
	if not message is Dictionary or not event.get("done", false) is bool:
		_fail("모델 응답 형식이 올바르지 않습니다.")
		return
	var thought = event.get("thinking", message.get("thinking", ""))
	var token = event.get("response", message.get("content", ""))
	if not thought is String or not token is String:
		_fail("모델 응답의 텍스트 형식이 올바르지 않습니다.")
		return
	var now := Time.get_ticks_usec()
	if not thought.is_empty(): _count_thought(thought.length(), now)
	if not token.is_empty(): _consume_text(token, now)
	if event.get("done", false):
		if event.get("done_reason", "") == "length": _fail("응답 길이 제한에 도달했습니다. 생성 설정을 확인하세요.", "", event)
		elif settings.dialogue_profile == "D" and not _decode_dialogue(): _fail("구조화된 대사 필드를 해석할 수 없습니다.", "", event)
		elif not settings.effective_thinking() and settings.dialogue_profile not in ["A","D"] and not native_off_supported and not wire_content.is_empty() and generated.is_empty(): _fail("추론 뒤 최종 대사를 확인할 수 없습니다.", "", event)
		elif generated.strip_edges().is_empty(): _fail("모델이 빈 대사를 반환했습니다.", "", event)
		else: _finish(event)

func _count_thought(count: int, now: int) -> void:
	if first_thought_usec == 0: first_thought_usec = now
	last_thought_usec = now
	thinking_character_count += count

func _consume_text(token: String, now: int) -> void:
	if settings.dialogue_profile == "D":
		wire_content += token
		if first_usec == 0 and structured_text.search(wire_content): first_usec = now
		return
	if settings.dialogue_profile != "A":
		wire_content += token
		# The installed Thinking-2507 template opens <think> even for think=false.
		# Quarantine inline analysis until the complete closing tag, possibly split across chunks.
		if not settings.effective_thinking() and not native_off_supported and not inline_boundary and thinking_character_count == 0:
			var boundary := wire_content.find("</think>")
			if boundary < 0:
				if first_thought_usec == 0: first_thought_usec = now
				last_thought_usec = now
				return
			inline_boundary = true
			thinking_character_count = boundary
			token = wire_content.substr(boundary + "</think>".length())
	if first_usec == 0 and not token.strip_edges().is_empty(): first_usec = now
	generated += token
	if first_usec != 0: partial_text.emit(generated)

func _decode_dialogue() -> bool:
	var json := JSON.new()
	if json.parse(wire_content) != OK: return false
	var decoded = json.data
	if not decoded is Dictionary or decoded.size() != 1 or not decoded.get("dialogue") is String: return false
	generated = decoded.dialogue
	return true

func _base_record() -> Dictionary:
	return {"schema_version": 5, "run_id": OS.get_process_id(), "timestamp_utc": Time.get_datetime_string_from_system(true, true) + "Z", "source": "godot_scene_stream", "request_id": request_state.get("_request_id"), "channel": request_state.get("_channel"), "attempt": request_state.get("_attempt", 0), "model": settings.model, "thinking": settings.effective_thinking(), "thinking_requested": settings.thinking, "output_schema": output_schema, "options": settings.generation_options(), "state": request_state, "question": request_question, "prompt": request_prompt, "system_prompt": request_system}

func _finish(metrics: Dictionary) -> void:
	var record := _base_record()
	_add_measurements(record, metrics)
	record.merge({"success": true, "response": generated, "quality_review": "not_automated"})
	_append_record(record)
	_end_request()
	completed.emit(record)

func _add_measurements(record: Dictionary, metrics: Dictionary) -> void:
	var timing := metrics.duplicate()
	timing.erase("context")
	record.merge({"chat_messages":chat_messages.duplicate(true), "metrics":timing,
		"transport_start_usec":started_usec, "elapsed_ms":(Time.get_ticks_usec() - started_usec) / 1000.0,
		"first_text_ms":(first_usec - started_usec) / 1000.0 if first_usec else null,
		"first_thought_ms":(first_thought_usec - started_usec) / 1000.0 if first_thought_usec else null,
		"last_thought_ms":(last_thought_usec - started_usec) / 1000.0 if last_thought_usec else null,
		"thinking_character_count":thinking_character_count, "frames_while_generating":generation_frames, "max_frame_ms":max_frame_ms})
	if request_state.get("_channel") == "dialogue":
		record.merge({"profile_id":settings.dialogue_profile,"profile_version":LocalNPCSettings.PROFILE_VERSION})
		if settings.dialogue_profile != "A":
			record["wire_content"] = wire_content
			record["native_off_supported"] = native_off_supported if verified_model != "" else null
			if first_thought_usec and not inline_boundary and thinking_character_count == 0:
				record["thinking_character_count"] = wire_content.length()

func _fail(message: String, server_error := "", metrics := {}) -> void:
	if not busy: return
	var record := _base_record()
	_add_measurements(record, metrics)
	record.merge({"success": false, "error": message, "partial_response": generated})
	if not server_error.is_empty(): record["server_error"] = server_error
	_append_record(record)
	_end_request()
	failed.emit(message)

func _end_request() -> void:
	busy = false
	checking_template = false
	buffer = PackedByteArray()
	client.close()

func _append_record(record: Dictionary) -> void:
	attempt_recorded.emit(record)
	if log_dir.is_empty(): return
	DirAccess.make_dir_recursive_absolute(log_dir)
	var path := log_dir.path_join("npc_sessions.jsonl")
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file:
		file.seek_end()
		file.store_line(JSON.stringify(record))

func _exit_tree() -> void:
	client.close()

func cancel(reason: String = "cancelled") -> void:
	if busy: _fail(reason)
