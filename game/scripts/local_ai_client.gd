class_name LocalAIClient
extends Node
## UI나 게임 규칙을 변경하지 않는 로컬 AI 통신 전용 노드입니다.

signal started
signal partial_text(text: String)
signal completed(record: Dictionary)
signal failed(message: String)
signal readiness(message: String)

@export var settings: LocalNPCSettings
@onready var health_request: HTTPRequest = $HealthRequest

var busy := false
var log_dir := ""
var client := HTTPClient.new()
var request_sent := false
var buffer := PackedByteArray()
var generated := ""
var started_usec := 0
var first_usec := 0
var previous_frame_usec := 0
var generation_frames := 0
var max_frame_ms := 0.0
var thinking_character_count := 0
var request_state := {}
var request_prompt := ""
var request_system := ""
var request_question := ""
var output_schema := {}

func check_connection() -> void:
	health_request.request_completed.connect(_connection_checked)
	health_request.timeout = 5
	health_request.request("http://%s:%d/api/tags" % [settings.host, settings.port])

func _connection_checked(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if busy: return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		readiness.emit("로컬 서버 연결 실패. START_DEMO.cmd로 실행하세요.")
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	var found := false
	if parsed is Dictionary:
		for item in parsed.get("models", []):
			if item.get("name", "") == settings.model: found = true
	readiness.emit("로컬 모델 준비 완료" if found else "%s 모델 준비가 필요합니다." % settings.model)

func generate(system_text: String, prompt: String, state: Dictionary, question_text: String, schema: Dictionary = {}) -> void:
	if busy: return
	request_state = state.duplicate(true)
	request_system = system_text
	request_prompt = prompt
	request_question = question_text
	output_schema = schema.duplicate(true)
	busy = true
	request_sent = false
	buffer = PackedByteArray()
	generated = ""
	started_usec = Time.get_ticks_usec()
	first_usec = 0
	generation_frames = 0
	max_frame_ms = 0.0
	thinking_character_count = 0
	started.emit()
	var error := client.connect_to_host(settings.host, settings.port)
	if error != OK: _fail("연결 시작 실패: %s" % error)

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
	if client.poll() != OK:
		_fail("HTTP 연결 처리 오류")
		return
	var state := client.get_status()
	if state == HTTPClient.STATUS_CONNECTED and not request_sent:
		var payload := {"model": settings.model, "system": request_system, "prompt": request_prompt, "stream": true, "keep_alive": "15m", "options": settings.generation_options()}
		if not output_schema.is_empty(): payload["format"] = output_schema
		payload["think"] = settings.thinking
		var error := client.request(HTTPClient.METHOD_POST, "/api/generate", PackedStringArray(["Content-Type: application/json"]), JSON.stringify(payload))
		if error != OK: _fail("요청 전송 실패: %s" % error)
		else: request_sent = true
	elif state == HTTPClient.STATUS_BODY:
		if client.get_response_code() != 200:
			_fail("로컬 서버 HTTP %s. 서버와 모델 설치를 확인하세요." % client.get_response_code())
			return
		buffer.append_array(client.read_response_body_chunk())
		_consume_lines(false)
	elif request_sent and state in [HTTPClient.STATUS_CONNECTED, HTTPClient.STATUS_DISCONNECTED]:
		_consume_lines(true)
		if busy: _fail("완료 표시 없이 연결이 끝났습니다.")
	elif state in [HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR]:
		_fail("로컬 서버에 연결할 수 없습니다.")

func _consume_lines(flush: bool) -> void:
	while busy:
		var newline := buffer.find(10)
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
		_fail(str(event.error))
		return
	thinking_character_count += str(event.get("thinking", "")).length()
	var token := str(event.get("response", ""))
	if not token.is_empty():
		if first_usec == 0: first_usec = Time.get_ticks_usec()
		generated += token
		partial_text.emit(generated)
	if event.get("done", false):
		if event.get("done_reason", "") == "length": _fail("응답 길이 제한에 도달했습니다. 생성 설정을 확인하세요.")
		elif generated.strip_edges().is_empty(): _fail("모델이 빈 대사를 반환했습니다.")
		else: _finish(event)

func _base_record() -> Dictionary:
	return {"schema_version": 4, "run_id": OS.get_process_id(), "timestamp_utc": Time.get_datetime_string_from_system(true, true) + "Z", "source": "godot_scene_stream", "model": settings.model, "thinking": settings.thinking, "output_schema": output_schema, "options": settings.generation_options(), "state": request_state, "question": request_question, "prompt": request_prompt, "system_prompt": request_system}

func _finish(metrics: Dictionary) -> void:
	metrics.erase("context")
	var record := _base_record()
	record.merge({"success": true, "response": generated, "first_text_ms": (first_usec - started_usec) / 1000.0, "elapsed_ms": (Time.get_ticks_usec() - started_usec) / 1000.0, "frames_while_generating": generation_frames, "max_frame_ms": max_frame_ms, "thinking_character_count": thinking_character_count, "metrics": metrics, "quality_review": "not_automated"})
	_append_record(record)
	_end_request()
	completed.emit(record)

func _fail(message: String) -> void:
	if not busy: return
	var record := _base_record()
	record.merge({"success": false, "error": message, "partial_response": generated})
	_append_record(record)
	_end_request()
	failed.emit(message)

func _end_request() -> void:
	busy = false
	client.close()

func _append_record(record: Dictionary) -> void:
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
