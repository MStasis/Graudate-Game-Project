class_name NPCBrain
extends Node
signal dialogue_ready(text: String)
signal dialogue_error(message: String)
signal status_changed(message: String)
signal measured(record: Dictionary)
@export var settings: ExperimentSettings
@onready var local_dialogue: LocalAIClient = $LocalDialogue
@onready var local_decision: LocalAIClient = $LocalDecision
@onready var jev: HTTPRequest = $JevRequest
var world: DemoWorld
var provider := 0
var auto_enabled := true
var pending := {}
var queued_question := ""
var history: Array[Dictionary] = []
var clock := 0.0
var trial := 0
var serial := 0
var jev_calls := 0
var jev_disabled := ""
var log_dir := ""
var frame_count := 0
var max_frame_ms := 0.0
var run_kind := "interactive"
var project_fingerprint := ""
const PROVIDERS := ["RuleBased", "LocalLLM", "Jev"]

func setup(mission: DemoWorld, directory: String) -> void:
 world = mission
 var sources := ""
 for path in ["res://project.godot", "res://main.gd", "res://main.tscn", "res://world.gd", "res://scripts/npc_brain.gd", "res://scripts/npc_policy.gd", "res://scripts/local_ai_client.gd", "res://scripts/local_npc_settings.gd", "res://scripts/experiment_settings.gd", "res://scripts/mission_drone.gd", "res://scripts/mission_projectile.gd", "res://scripts/player.gd", "res://scripts/interactable.gd", "res://scenes/World.tscn", "res://scenes/Drone.tscn", "res://scenes/Player.tscn", "res://scenes/NPC.tscn", "res://resources/flashlight.gdshader", "res://resources/NPCSettings.tres", "res://resources/ExperimentSettings.tres"]:
  sources += FileAccess.get_file_as_string(path)
 project_fingerprint = (sources + FileAccess.get_file_as_string("res://scripts/chat_input.gd") + FileAccess.get_file_as_string("res://resources/GameTheme.tres")).sha256_text()
 project_fingerprint = (project_fingerprint + FileAccess.get_file_as_string("res://scripts/hud_frame.gd") + FileAccess.get_sha256("res://assets/ui/harin_canva.png")).sha256_text()
 project_fingerprint = (project_fingerprint + FileAccess.get_sha256("res://native/windows_ime/windows_ime.dll")).sha256_text()
 log_dir = directory
 provider = settings.provider
 for client in [local_dialogue, local_decision]:
  client.log_dir = log_dir
  client.settings = client.settings.duplicate(true)
  client.completed.connect(_local_completed)
  client.failed.connect(_failed)
 local_decision.settings.max_tokens = 48
 local_decision.settings.temperature = 0.1
 local_decision.settings.timeout_seconds = settings.request_timeout
 jev.timeout = settings.request_timeout
 jev.request_completed.connect(_jev_completed)
 world.game_event.connect(_world_event)
 new_trial()

func new_trial(mode: int = -1) -> void:
 cancel_pending("trial_reset")
 if mode >= 0: provider = mode
 trial += 1
 queued_question = ""
 history.clear()
 clock = 0.0
 jev_disabled = ""
 world.reset_world()
 _log({"event": "trial_started", "config": world.game_state().scenario_config, "seed": settings.scenario_seed, "decision_interval": settings.decision_interval, "max_decision_age": settings.max_decision_age, "local_model": local_dialogue.settings.model, "local_options": local_dialogue.settings.generation_options(), "jev_configured_model": settings.jev_model, "dialogue_method": "free_generation" if provider == 1 else "intent_template"})
 status_changed.emit("새 회차 · " + PROVIDERS[provider])

func _process(delta: float) -> void:
 if not world: return
 if not pending.is_empty():
  frame_count += 1
  max_frame_ms = maxf(max_frame_ms, delta * 1000.0)
  return
 if not queued_question.is_empty():
  var text := queued_question
  queued_question = ""
  request_dialogue(text)
  return
 if not auto_enabled or world.finished or world.defeated or not jev_disabled.is_empty(): return
 clock += delta
 if clock < settings.decision_interval or not world.active_action.is_empty(): return
 clock = 0.0
 if (world.map_id == "storage" and world.enemies_remaining() > 0) or world.player_hp <= 55 or world.ammo <= 4:
  request_decision()

func request_decision() -> bool:
 return _request("decision", "")

func request_dialogue(text: String) -> bool:
 text = text.strip_edges().substr(0, 300)
 if text.is_empty(): return false
 if not pending.is_empty():
  if pending.kind == "decision":
   queued_question = text
   status_changed.emit("지원 판단 뒤 질문에 답합니다.")
   return true
  return false
 return _request("dialogue", text)

func _request(kind: String, question: String) -> bool:
 if not pending.is_empty(): return false
 serial += 1
 var snapshot := world.game_state().duplicate(true)
 var allowed: Array = snapshot.valid_actions if kind == "decision" else NPCPolicy.INTENTS.keys()
 pending = {"request_id": serial, "kind": kind, "question": question, "snapshot": snapshot, "snapshot_hash": JSON.stringify(snapshot).sha256_text(), "allowed": allowed.duplicate(), "started_usec": Time.get_ticks_usec(), "epoch": world.epoch}
 frame_count = 0
 max_frame_ms = 0.0
 if provider == 0:
  var result := NPCPolicy.rule_action(snapshot) if kind == "decision" else NPCPolicy.rule_intent(question)
  _resolve(result, {"actual_model": "rules_v1", "dialogue_method": "intent_template"})
 elif provider == 1:
  var system := ""
  var prompt := ""
  var schema := {}
  if kind == "decision":
   system = NPCPolicy.DECISION_INSTRUCTIONS + " Return only JSON with one action from valid_actions."
   var choices := {}
   for action in allowed: choices[action] = NPCPolicy.ACTIONS[action]
   prompt = JSON.stringify({"game": NPCPolicy.model_state(snapshot), "actions": choices})
   schema = {"type": "object", "properties": {"action": {"type": "string", "enum": allowed}}, "required": ["action"], "additionalProperties": false}
  else:
   system = "너는 %s이다. %s\n%s" % [world.npc.display_name, world.npc.description, local_dialogue.settings.system_prompt]
   prompt = "하린과 플레이어의 관계: " + str(snapshot.relationship) + "\n현재 장소: " + str(snapshot.location) + "\n현재 임무 안내: " + str(snapshot.current_guidance) + "\n공유한 사건: " + JSON.stringify(snapshot.recent_shared_events) + "\n상태: 체력 %d/%d, 탄약 %d, 남은 치료 키트 %d개, 보급품 %d개.\n최근 대화: %s\n플레이어 질문: %s\n질문에 직접 답해. 임무 질문이면 현재 임무 안내를 정확히 설명해. 일상 질문이면 질문 내용에 맞게 친한 동료의 반말로 대답해." % [snapshot.player_hp, snapshot.max_hp, snapshot.ammo, snapshot.medkits, snapshot.supply_packs, JSON.stringify(history), question]
   system += "\n생각 과정 없이 한국어 대사만 dialogue 필드에 넣은 JSON 객체 하나를 출력한다."
   prompt += "\n출력 형식: {\"dialogue\": \"하린이 지금 실제로 할 한국어 대사\"}"
   schema = {"type": "object", "properties": {"dialogue": {"type": "string", "maxLength": 160}}, "required": ["dialogue"], "additionalProperties": false}
  var client := local_decision if kind == "decision" else local_dialogue
  var request_state := snapshot.duplicate(true)
  request_state["_channel"] = kind
  status_changed.emit("로컬 LLM " + ("지원 판단 중" if kind == "decision" else "대화 생성 중"))
  client.generate(system, prompt, request_state, question, schema)
 else:
  var key := OS.get_environment("TYPESAFE_API_KEY").strip_edges()
  if key.is_empty():
   jev_disabled = "missing_api_key"
   _failed("Jev 설정 필요: TYPESAFE_API_KEY 없음 · 네트워크 추론 0회")
   return false
  if jev_calls >= settings.jev_call_limit:
   jev_disabled = "call_limit"
   _failed("Jev 현재 실행의 호출 한도 도달: %d회" % settings.jev_call_limit)
   return false
  var payload := NPCPolicy.jev_payload(kind, snapshot, question, settings.jev_model)
  jev_calls += 1
  var error := jev.request("https://api.typesafe.ai/v1/systemone", PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + key]), HTTPClient.METHOD_POST, JSON.stringify(payload))
  if error != OK: _failed("Jev 연결 시작 실패: %d" % error)
  else: status_changed.emit("Jev " + ("지원 판단 중" if kind == "decision" else "대화 의도 선택 중"))
 return true

func _local_completed(record: Dictionary) -> void:
 if pending.is_empty(): return
 var selected: String = record.response
 if pending.kind == "decision":
  var parsed = JSON.parse_string(selected)
  if not parsed is Dictionary or not parsed.get("action", "") is String:
   _failed("로컬 행동 JSON 해석 실패")
   return
  selected = parsed.action
 else:
  var parsed = JSON.parse_string(selected)
  if not parsed is Dictionary or not parsed.get("dialogue", "") is String:
   _failed("로컬 대사 JSON 해석 실패")
   return
  selected = parsed.dialogue
 _resolve(selected, {"actual_model": record.metrics.get("model", local_dialogue.settings.model), "raw_response": record.response, "first_transport_text_ms": record.first_text_ms, "server_metrics": record.metrics, "dialogue_method": "free_generation_structured" if pending.kind == "dialogue" else "structured_choice"})

func _jev_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
 if pending.is_empty(): return
 if result != HTTPRequest.RESULT_SUCCESS or code != 200:
  if code in [401, 403, 429] or code >= 500: jev_disabled = "http_%d" % code
  _failed("Jev HTTP %d / transport %d. 자동 대체 없이 오류를 기록했습니다." % [code, result])
  return
 var data = JSON.parse_string(body.get_string_from_utf8())
 if not data is Dictionary: _failed("Jev 응답 JSON 해석 실패"); return
 var parsed := NPCPolicy.parse_jev(data, pending.allowed)
 if parsed.has("error"): _failed("Jev " + str(parsed.error)); return
 parsed["dialogue_method"] = "intent_template"
 _resolve(parsed.choice, parsed)

func _resolve(selected: String, metadata: Dictionary) -> void:
 var job := pending.duplicate(true)
 var elapsed := (Time.get_ticks_usec() - int(job.started_usec)) / 1000.0
 var reason := ""
 if world.epoch != int(job.epoch): reason = "stale_epoch"
 if job.kind == "decision" and elapsed > settings.max_decision_age * 1000.0: reason = "stale_age"
 if (job.kind == "decision" or provider != 1) and selected not in job.allowed: reason = "invalid_candidate"
 var accepted := false
 if reason.is_empty() and job.kind == "decision":
  accepted = world.request_support(selected, {"request_id": job.request_id, "provider": PROVIDERS[provider], "trial": trial})
  if not accepted: reason = "no_longer_valid"
 elif reason.is_empty():
  var text := selected if provider == 1 else NPCPolicy.template_response(selected, job.snapshot)
  if text.strip_edges().is_empty(): reason = "empty_dialogue"
  else:
   accepted = true
   history.append({"question": job.question, "answer": text})
   if history.size() > 3: history.pop_front()
   dialogue_ready.emit(text)
 pending = {}
 var record := {"event": "response", "request_id": job.request_id, "kind": job.kind, "question": job.question, "snapshot": job.snapshot, "snapshot_hash": job.snapshot_hash, "allowed": job.allowed, "selected": selected, "accepted": accepted, "rejected_reason": reason, "elapsed_ms": elapsed, "frames_pending": frame_count, "max_frame_ms": max_frame_ms}
 record["prompt_version"] = NPCPolicy.PROMPT_VERSION
 record["snapshot_msec"] = int(job.started_usec) / 1000.0
 record["response_msec"] = Time.get_ticks_msec()
 record["quality_review"] = "manual_required"
 if job.kind == "dialogue" and accepted: record["display_ready_ms"] = elapsed
 record.merge(metadata)
 _log(record)
 measured.emit(record)
 if not reason.is_empty() and job.kind == "dialogue": dialogue_error.emit("상황이 바뀌어 이전 답변을 버렸습니다. 다시 질문하세요.")
 clock = 0.0

func _failed(message: String) -> void:
 if pending.is_empty(): return
 var job := pending.duplicate(true)
 pending = {}
 _log({"event": "request_failed", "kind": job.kind, "request_id": job.request_id, "snapshot": job.snapshot, "question": job.question, "error": message, "elapsed_ms": (Time.get_ticks_usec() - int(job.started_usec)) / 1000.0, "jev_calls": jev_calls})
 if job.kind == "dialogue": dialogue_error.emit(message)
 status_changed.emit(message)
 clock = -2.0

func cancel_pending(reason: String) -> void:
 if pending.is_empty(): return
 _failed(reason)
 jev.cancel_request()
 local_dialogue.cancel(reason)
 local_decision.cancel(reason)

func _world_event(event: Dictionary) -> void:
 _log({"event": "world_event", "details": event})

func _log(record: Dictionary) -> void:
 if log_dir.is_empty(): return
 record["project_fingerprint"] = project_fingerprint
 record.merge({"schema_version": 4, "timestamp_utc": Time.get_datetime_string_from_system(true, true) + "Z", "run_id": OS.get_process_id(), "trial": trial, "provider": PROVIDERS[provider], "scenario_id": settings.scenario_id, "run_kind": run_kind, "synthetic_test": "--mission-test" in OS.get_cmdline_user_args(), "automated_evidence": "--mission-evidence" in OS.get_cmdline_user_args()})
 DirAccess.make_dir_recursive_absolute(log_dir)
 var path := log_dir.path_join("npc_events.jsonl")
 var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
 if file:
  file.seek_end()
  file.store_line(JSON.stringify(record))
