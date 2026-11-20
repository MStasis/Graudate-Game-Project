class_name NPCBrain
extends Node
signal dialogue_ready(text: String)
signal dialogue_error(message: String)
signal status_changed(message: String)
signal measured(record: Dictionary)
signal event_recorded(record: Dictionary)
@export var settings: ExperimentSettings
@onready var local_dialogue: LocalAIClient = $LocalDialogue
@onready var local_decision: LocalAIClient = $LocalDecision
@onready var jev: HTTPRequest = $JevRequest
var world: DemoWorld
var provider := 0
var auto_enabled := true
var dialogue_pending := {}
var tactical_pending := {}
# 하나의 추론 슬롯을 두 채널이 공유한다. 공통 긴급 실행기는 슬롯을 기다리지 않는다.
var pending: Dictionary:
 get: return dialogue_pending if not dialogue_pending.is_empty() else tactical_pending
 set(value):
  if value.is_empty():
   dialogue_pending = {}
   tactical_pending = {}
  elif value.get("kind", "") == "dialogue": dialogue_pending = value
  else: tactical_pending = value
var queued_question := ""
var queued_epoch := -1
var dialogue_grounding := {}
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
const MAX_JEV_RESPONSE_BYTES := 256 * 1024

func setup(mission: DemoWorld, directory: String) -> void:
 world = mission
 if OS.has_feature("template"):
  # 내보낸 게임에서는 원본 스크립트 대신 실제 배포된 데이터 파일을 식별한다.
  var executable := OS.get_executable_path()
  var pack := executable.get_basename() + ".pck"
  project_fingerprint = FileAccess.get_sha256(pack if FileAccess.file_exists(pack) else executable)
 else:
  var sources := ""
  for path in ["res://project.godot", "res://main.gd", "res://main.tscn", "res://world.gd", "res://scripts/npc_brain.gd", "res://scripts/npc_policy.gd", "res://scripts/local_ai_client.gd", "res://scripts/local_npc_settings.gd", "res://scripts/experiment_settings.gd", "res://scripts/mission_drone.gd", "res://scripts/mission_projectile.gd", "res://scripts/player.gd", "res://scripts/interactable.gd", "res://scenes/World.tscn", "res://scenes/Drone.tscn", "res://scenes/Player.tscn", "res://scenes/NPC.tscn", "res://resources/flashlight.gdshader", "res://resources/NPCSettings.tres", "res://resources/ExperimentSettings.tres"]:
   sources += FileAccess.get_file_as_string(path)
  project_fingerprint = (sources + FileAccess.get_file_as_string("res://scripts/chat_input.gd") + FileAccess.get_file_as_string("res://resources/GameTheme.tres")).sha256_text()
  project_fingerprint = (project_fingerprint + FileAccess.get_file_as_string("res://scripts/hud_frame.gd") + FileAccess.get_sha256("res://assets/fleet_sprites/characters/mika/mika_clavis_final_atlas.png")).sha256_text()
  project_fingerprint = (project_fingerprint + FileAccess.get_sha256("res://native/windows_ime/windows_ime.dll")).sha256_text()
  for path in ["res://scripts/companion_motion.gd", "res://scripts/companion_navigation.gd", "res://scripts/mika_actor.gd", "res://scripts/temporary_actor_aim.gd", "res://scripts/mika_character.gd", "res://resources/MikaCharacter.tres", "res://scripts/cooperative_locker.gd", "res://scenes/CooperativeLocker.tscn", "res://scripts/rounded_obstacle.gd", "res://scripts/mika_dialogue.gd", "res://scripts/system_notifications.gd"]:
   project_fingerprint = (project_fingerprint + FileAccess.get_file_as_string(path)).sha256_text()
  for path in ["res://scripts/combat_interface.gd", "res://scripts/actor_status.gd", "res://scripts/mission_save_store.gd", "res://scripts/story_progress.gd", "res://scripts/message_journal.gd", "res://scripts/exploration_map.gd", "res://resources/mika_style_examples.json", "res://scripts/fleet_demo.gd", "res://scripts/fleet_demo_lines.gd"]:
   project_fingerprint = (project_fingerprint + FileAccess.get_file_as_string(path)).sha256_text()
 log_dir = directory
 provider = settings.provider
 for client in [local_dialogue, local_decision]:
  client.log_dir = log_dir
  client.settings = client.settings.duplicate(true)
  client.completed.connect(_local_completed)
  client.failed.connect(func(message): _client_failed(message, client))
 local_decision.settings.max_tokens = 48
 # 전술은 기존 짧은 후보 선택 조건을 보존한다. 긴급 대응/명시적 지시는 공통 실행기다.
 local_decision.settings.thinking = false
 local_decision.settings.temperature = 0.1
 local_decision.settings.timeout_seconds = settings.request_timeout
 jev.timeout = settings.request_timeout
 jev.body_size_limit = MAX_JEV_RESPONSE_BYTES
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
 _log({"event": "trial_started", "config": world.game_state().scenario_config, "seed": settings.scenario_seed, "decision_interval": settings.decision_interval, "max_decision_age": settings.max_decision_age, "local_model": local_dialogue.settings.model, "local_options": local_dialogue.settings.generation_options(), "jev_configured_model": settings.jev_model, "dialogue_method": "state_grounded_generation" if provider == 1 else "intent_template"})
 status_changed.emit("새 회차 · " + PROVIDERS[provider])

func _process(delta: float) -> void:
 if not world: return
 if world.finished or world.defeated:
  if not pending.is_empty() or not queued_question.is_empty(): cancel_pending("mission_ended")
  return
 if auto_enabled and not world.finished and not world.defeated:
  var urgent := world.emergency_support()
  if not urgent.is_empty():
   # 전술 추론은 긴급 실행 이후의 낡은 판단을 적용하지 않도록 취소한다.
   cancel_channel("decision", "emergency_preempted")
   _log({"event": "common_emergency", "action": urgent, "during_dialogue": not dialogue_pending.is_empty(), "executor_version": 2})
 if not pending.is_empty():
  frame_count += 1
  max_frame_ms = maxf(max_frame_ms, delta * 1000.0)
  return
 if not queued_question.is_empty():
  var text := queued_question
  queued_question = ""
  if queued_epoch != world.epoch:
   dialogue_error.emit("장소나 상황이 바뀌어 대기 중이던 질문을 취소했습니다.")
   return
  request_dialogue(text)
  return
 if not auto_enabled or world.finished or world.defeated or not jev_disabled.is_empty(): return
 clock += delta
 if clock < settings.decision_interval or not world.active_action.is_empty(): return
 clock = 0.0
 if (world.is_combat_area() and world.enemies_remaining() > 0) or world.player_hp <= 55 or world.ammo <= 4 or world.current_panel().needs_assistance():
  request_decision()

func request_decision() -> bool:
 return _request("decision", "")

func request_dialogue(text: String) -> bool:
 if world.finished or world.defeated: return false
 text = text.strip_edges().left(MikaDialogue.QUESTION_LIMIT)
 if text.is_empty(): return false
 var action := NPCPolicy.requested_action(text, world.use_fleet_demo)
 if world.use_fleet_demo and world.map_id == "research_lab_b" and world.fleet_demo.npc_target().is_finite() and action in ["follow", "wait"]:
  action = ""
 if not action.is_empty():
  queued_question = ""
  cancel_channel("decision", "player_order_preempted")
  if not dialogue_pending.is_empty(): cancel_channel("dialogue", "player_order_preempted")
  var receipt := world.request_player_order(action)
  serial += 1
  _remember_dialogue(text, receipt.text)
  dialogue_grounding = {"action": action, "action_accepted": receipt.accepted, "status": receipt.status, "epoch": world.epoch}
  dialogue_ready.emit(receipt.text)
  var record := {"event": "response", "kind": "dialogue", "request_id": serial, "question": text, "selected": action, "accepted": true, "action_accepted": receipt.accepted, "action_status": receipt.status, "actual_model": "common_executor", "dialogue_method": "executor_receipt", "prompt_version": NPCPolicy.PROMPT_VERSION, "elapsed_ms": 0.0, "frames_pending": 0, "max_frame_ms": 0.0, "rejected_reason": ""}
  _log(record)
  measured.emit(record)
  return true
 if not pending.is_empty():
  if pending.kind == "decision":
   queued_question = text
   queued_epoch = world.epoch
   status_changed.emit("지원 판단 뒤 질문에 답합니다.")
   return true
  return false
 return _request("dialogue", text)

func _request(kind: String, question: String) -> bool:
 if not pending.is_empty() or world.finished or world.defeated: return false
 var snapshot := world.game_state().duplicate(true)
 var allowed: Array = snapshot.valid_actions if kind == "decision" else NPCPolicy.INTENTS.keys()
 if allowed.is_empty(): return false
 serial += 1
 pending = {"request_id": serial, "kind": kind, "question": question, "snapshot": snapshot, "snapshot_hash": JSON.stringify(snapshot).sha256_text(), "allowed": allowed.duplicate(), "started_usec": Time.get_ticks_usec(), "epoch": world.epoch}
 frame_count = 0
 max_frame_ms = 0.0
 if provider == 0:
  var result := NPCPolicy.rule_action(NPCPolicy.model_state(snapshot)) if kind == "decision" else MikaDialogue.topic_for(question, history, world.use_fleet_demo)
  _resolve(result, {"actual_model": "rules_v1", "dialogue_method": "intent_template"})
 elif provider == 1:
  var system := ""
  var prompt := ""
  var schema := {}
  var messages: Array = []
  if kind == "decision":
   system = NPCPolicy.DECISION_INSTRUCTIONS + " Return only JSON with one action from valid_actions."
   var choices := {}
   for action in allowed: choices[action] = NPCPolicy.action_description(action, snapshot)
   prompt = JSON.stringify({"game": NPCPolicy.model_state(snapshot), "actions": choices})
   schema = {"type": "object", "properties": {"action": {"type": "string", "enum": allowed}}, "required": ["action"], "additionalProperties": false}
  else:
   var dialogue := MikaDialogue.build(snapshot, question, history, world.npc.description, local_dialogue.settings.system_prompt)
   system = dialogue.system
   prompt = dialogue.prompt
   schema = dialogue.schema
   messages = dialogue.messages
  var client := local_decision if kind == "decision" else local_dialogue
  var request_state := snapshot.duplicate(true)
  request_state["_channel"] = kind
  request_state["_request_id"] = pending.request_id
  status_changed.emit("로컬 LLM " + ("지원 판단 중" if kind == "decision" else "대화 생성 중"))
  if not client.generate(system, prompt, request_state, question, schema, messages): _failed("로컬 추론 채널이 이미 사용 중이거나 시작하지 못했습니다.")
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
 var source = record.get("state", {})
 if not source is Dictionary: return
 if source.get("_request_id", -1) != pending.request_id or source.get("_channel", "") != pending.kind or source.get("_attempt", 0) != pending.get("retry", 0):
  _log({"event": "transport_response_ignored", "reason": "request_id_mismatch", "state": source})
  return
 var selected = record.get("response")
 if not selected is String:
  _failed("모델 응답의 텍스트 형식이 올바르지 않습니다.")
  return
 if pending.kind == "decision":
  var parsed = JSON.parse_string(selected)
  if not parsed is Dictionary or not parsed.get("action") is String:
   _failed("로컬 행동 JSON 해석 실패")
   return
  selected = parsed.action
 else:
  # 대화는 모델이 생성한 최종 발화 그대로 받는다. 전술 후보만 JSON 스키마로 제한한다.
  selected = selected.strip_edges().left(MikaDialogue.ANSWER_LIMIT)
  var live := world.game_state()
  var issue := MikaDialogue.response_issue(selected, live, pending.question)
  var stale := _dialogue_facts_changed(pending, live)
  if not issue.is_empty() and not stale and int(pending.get("retry", 0)) < 1 and world.epoch == int(pending.epoch):
   # 같은 모델에 한 번만 재생성 요청. 실험 기록에는 실패 원문도 남긴다.
   _log({"event": "dialogue_validation_failed", "request_id": pending.request_id, "attempt": 0, "reason": issue, "raw_response": record.response})
   dialogue_pending["retry"] = 1
   var retry := MikaDialogue.build(live, pending.question, history, world.npc.description, local_dialogue.settings.system_prompt)
   var retry_state := live.duplicate(true)
   retry_state.merge({"_channel": "dialogue", "_request_id": pending.request_id, "_attempt": 1})
   var repair := "현재 사실과 맞지 않는 주장만 고쳐서 자연스럽게 다시 답해. 반문과 장난은 가능해."
   if issue == "formal_voice": repair = "존댓말 어미 '~요/~습니다'를 쓰지 말고 한국어 반말로 다시 답해."
   elif issue == "invented_food_event": repair = "실제 주문/함께 식사한 사건은 없어. 가상 예시를 기억으로 만들지 마. 먹고 싶은 메뉴 제안은 가능해."
   elif issue == "unsupported_world_rule": repair = "퇴근 금지 규정은 설정된 적 없어. 예시 농담을 실제 규정으로 확정하지 마."
   elif issue.begins_with("fleet_lever_"): repair = "레버를 당기려면 모든 전투가 끝나고 내 신호가 있어야 해. 둘 중 하나만 말하면 조작 조건이 빠진다. 지금 신호를 줬다고 말하지 마."
   elif issue.begins_with("fleet_"): repair = "최신 Fleet 사실을 다시 읽고 질문에 직접 답해. 확인되지 않은 정보에는 짧게 모른다고 해. 이전 대사의 잘못된 주장은 반복하지 마."
   retry.prompt += "\n[재생성 이유: " + issue + "] " + repair
   retry.messages.insert(retry.messages.size() - 1, {"role": "system", "content": "재생성 이유: " + issue + ". " + repair})
   if not local_dialogue.generate(retry.system, retry.prompt, retry_state, pending.question, retry.schema, retry.messages): _failed("대사 재생성을 시작하지 못했습니다.")
   return
 var metrics = record.get("metrics", {})
 if not metrics is Dictionary:
  _failed("모델 응답의 측정 정보 형식이 올바르지 않습니다.")
  return
 var channel := local_dialogue if pending.kind == "dialogue" else local_decision
 _resolve(selected, {"actual_model": metrics.get("model", channel.settings.model), "raw_response": record.response, "first_transport_text_ms": record.get("first_text_ms"), "server_metrics": metrics, "dialogue_method": "state_grounded_generation_plain" if pending.kind == "dialogue" else "structured_choice"})

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
 if pending.is_empty(): return
 var job := pending.duplicate(true)
 var elapsed := (Time.get_ticks_usec() - int(job.started_usec)) / 1000.0
 var reason := ""
 if world.finished or world.defeated: reason = "mission_ended"
 if world.epoch != int(job.epoch): reason = "stale_epoch"
 var live := world.game_state()
 var topic := MikaDialogue.topic_for(job.question, history, world.use_fleet_demo) if job.kind == "dialogue" else ""
 if job.kind == "dialogue" and reason.is_empty():
  if world.use_fleet_demo and provider == 2 and selected in ["mission", "support"]:
   topic = selected
   if MikaDialogue.grounding_facts(job.snapshot, job.question, topic) != MikaDialogue.grounding_facts(live, job.question, topic): reason = "stale_facts"
  elif _dialogue_facts_changed(job, live): reason = "stale_facts"
 var allowed_age := settings.max_decision_age
 # 정지된 패널 과제는 8초까지 허용하되 실행 직전 유지/위치 조건을 다시 검사한다.
 if selected == "assist_panel": allowed_age = maxf(allowed_age, minf(settings.request_timeout, 8.0))
 if job.kind == "decision" and elapsed > allowed_age * 1000.0: reason = "stale_age"
 if (job.kind == "decision" or provider != 1) and selected not in job.allowed: reason = "invalid_candidate"
 var accepted := false
 var no_change := false
 if reason.is_empty() and job.kind == "decision":
  no_change = selected in ["follow", "wait"] and selected in live.valid_actions and world.npc_hp > 0
  if not no_change:
   accepted = world.request_support(selected, {"request_id": job.request_id, "provider": PROVIDERS[provider], "trial": trial})
   if not accepted: reason = "no_longer_valid"
 elif reason.is_empty():
  var text := selected.left(MikaDialogue.ANSWER_LIMIT) if provider == 1 else NPCPolicy.template_response(selected, job.snapshot, job.question)
  if text.strip_edges().is_empty(): reason = "empty_dialogue"
  elif provider == 1: reason = MikaDialogue.response_issue(text, live, job.question)
  if reason.is_empty():
   accepted = true
   _remember_dialogue(job.question, text)
   dialogue_grounding = {"question": job.question, "topic": topic, "facts": MikaDialogue.grounding_facts(live, job.question, topic), "epoch": world.epoch}
   dialogue_ready.emit(text)
 pending = {}
 var record := {"event": "response", "request_id": job.request_id, "kind": job.kind, "question": job.question, "snapshot": job.snapshot, "snapshot_hash": job.snapshot_hash, "allowed": job.allowed, "selected": selected, "accepted": accepted, "rejected_reason": reason, "elapsed_ms": elapsed, "frames_pending": frame_count, "max_frame_ms": max_frame_ms}
 if job.kind == "decision":
  record["action_outcome"] = "accepted" if accepted else ("no_change" if no_change else "rejected")
 record["prompt_version"] = NPCPolicy.FLEET_DIALOGUE_VERSION if job.kind == "dialogue" and world.use_fleet_demo else NPCPolicy.PROMPT_VERSION
 record["snapshot_msec"] = int(job.started_usec) / 1000.0
 record["response_msec"] = Time.get_ticks_msec()
 record["quality_review"] = "manual_required"
 record["generation_attempts"] = 1 + int(job.get("retry", 0))
 if job.kind == "dialogue" and accepted: record["display_ready_ms"] = elapsed
 record.merge(metadata)
 _log(record)
 measured.emit(record)
 if not reason.is_empty() and job.kind == "dialogue":
  dialogue_error.emit("상황이 바뀌어 이전 답변을 버렸습니다. 다시 질문하세요." if reason in ["stale_epoch", "stale_facts"] else "미카의 답변을 확인하지 못했습니다. 다시 질문하세요.")
 clock = 0.0

func _remember_dialogue(question: String, answer: String) -> void:
 history.append({"question": question.left(MikaDialogue.QUESTION_LIMIT), "answer": answer.left(MikaDialogue.ANSWER_LIMIT)})
 if history.size() > MikaDialogue.HISTORY_LIMIT: history.pop_front()

func _dialogue_facts_changed(job: Dictionary, live: Dictionary) -> bool:
 var fleet: bool = live.get("fleet_demo", false)
 if fleet != job.snapshot.get("fleet_demo", false): return true
 var topic := MikaDialogue.topic_for(job.question, history, fleet)
 if topic in ["mission", "support"]:
  return MikaDialogue.grounding_facts(job.snapshot, job.question, topic) != MikaDialogue.grounding_facts(live, job.question, topic)
 return false

func _failed(message: String) -> void:
 if pending.is_empty(): return
 var job := pending.duplicate(true)
 pending = {}
 _log({"event": "request_failed", "kind": job.kind, "request_id": job.request_id, "snapshot": job.snapshot, "question": job.question, "error": message, "elapsed_ms": (Time.get_ticks_usec() - int(job.started_usec)) / 1000.0, "jev_calls": jev_calls})
 if job.kind == "dialogue": dialogue_error.emit(message)
 status_changed.emit(message)
 clock = -2.0

func _client_failed(message: String, source: LocalAIClient) -> void:
 if pending.is_empty(): return
 if source.request_state.get("_request_id", -1) == pending.get("request_id", -2) and source.request_state.get("_channel") == pending.get("kind"):
  _failed(message)

func cancel_channel(kind: String, reason: String) -> void:
 var job := dialogue_pending if kind == "dialogue" else tactical_pending
 if job.is_empty(): return
 if kind == "dialogue": dialogue_pending = {}
 else: tactical_pending = {}
 _log({"event": "request_cancelled", "kind": kind, "request_id": job.get("request_id"), "reason": reason})
 if provider == 2: jev.cancel_request()
 var client := local_dialogue if kind == "dialogue" else local_decision
 client.cancel(reason)
 if kind == "dialogue": dialogue_error.emit("답변 요청을 취소했습니다: " + reason)

func cancel_pending(reason: String) -> void:
 queued_question = ""
 queued_epoch = -1
 cancel_channel("dialogue", reason)
 cancel_channel("decision", reason)

func _world_event(event: Dictionary) -> void:
 if event.event in ["mission_completed", "mission_failed"]: cancel_pending("mission_ended")
 _log({"event": "world_event", "details": event})

func _log(record: Dictionary) -> void:
 record["project_fingerprint"] = project_fingerprint
 record.merge({"schema_version": 4, "timestamp_utc": Time.get_datetime_string_from_system(true, true) + "Z", "run_id": OS.get_process_id(), "trial": trial, "provider": PROVIDERS[provider], "scenario_id": settings.scenario_id, "run_kind": run_kind, "synthetic_test": "--mission-test" in OS.get_cmdline_user_args(), "automated_evidence": "--mission-evidence" in OS.get_cmdline_user_args()})
 event_recorded.emit(record)
 if log_dir.is_empty(): return
 DirAccess.make_dir_recursive_absolute(log_dir)
 var path := log_dir.path_join("npc_events.jsonl")
 var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
 if file:
  file.seek_end()
  file.store_line(JSON.stringify(record))
