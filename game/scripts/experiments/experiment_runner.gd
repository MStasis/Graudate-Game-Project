extends Node

signal progress(done: int, total: int, message: String)
signal recorded(row: Dictionary)
signal finished(message: String)

const Factory := preload("res://scripts/experiments/scenario_factory.gd")
const Store := preload("res://scripts/experiments/experiment_store.gd")
const WORLD := preload("res://scenes/World.tscn")
const BRAIN := preload("res://scenes/NPCBrain.tscn")
var factory := Factory.new()
var store := Store.new()
var viewport := SubViewport.new()
var world: DemoWorld
var brain: NPCBrain
var session := ""
var kind := ""
var running := false
var jobs: Array = []
var done := 0
var current := {}
var start_state := {}
var terminal := {}
var attempts: Array = []
var issues: Array = []
var baselines := {}
var started_usec := 0
var requested_ms: Variant
var answered_ms: Variant
var phase := ""
var replay_tick := 0
var replay_done := ""
var timeline: Array = []
var resource_changes: Array = []
var last_resources := {}
var unsaved: Array = []
var fingerprint := ""
var scenario_version := ""

func _ready() -> void:
	viewport.size = Vector2i(720, 360)
	viewport.world_2d = World2D.new()
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	if "--experiment-test" in OS.get_cmdline_user_args(): store.run_kind = "development"

func _release_world() -> void:
	if is_instance_valid(brain):
		remove_child(brain)
		brain.free()
	if is_instance_valid(world):
		viewport.remove_child(world)
		world.free()

func prepare(item: Dictionary, provider: int) -> bool:
	_release_world()
	world = WORLD.instantiate()
	world.use_fleet_demo = true
	world.process_mode = Node.PROCESS_MODE_DISABLED
	viewport.add_child(world)
	for label in ["RoomTitle", "GoalText", "ControlsHint", "Ending"]:
		world.get_node(label).visibility_layer = 0
	brain = BRAIN.instantiate()
	brain.auto_enabled = false
	add_child(brain)
	brain.settings = brain.settings.duplicate()
	brain.settings.provider = provider
	brain.run_kind = store.run_kind
	brain.setup(world, "")
	var ok := factory.apply(world, item)
	if item.has("seconds"):
		world.can_move = false
		var camera := Camera2D.new()
		world.player.add_child(camera)
		camera.make_current()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if fingerprint.is_empty():
		var source := brain.project_fingerprint
		if not OS.has_feature("template"):
			for path in ["res://scripts/experiments", "res://scenes/experiments"]:
				for file in DirAccess.get_files_at(path):
					if file.ends_with(".gd") or file.ends_with(".tscn"):
						source += FileAccess.get_sha256(path.path_join(file))
			for path in ["res://scripts/rift_turret.gd","res://scripts/mika_healer.gd","res://scenes/NPCBrain.tscn"]:
				source += FileAccess.get_sha256(path)
		scenario_version = factory.catalog.version + "-" + (FileAccess.get_sha256(Factory.SCENARIOS) + FileAccess.get_sha256(Factory.QUESTIONS)).sha256_text().left(12)
		fingerprint = (source + scenario_version).sha256_text()
	return ok

func start(mode: String, cases: Array, repetitions: int) -> bool:
	if running or not unsaved.is_empty() or cases.is_empty() or repetitions not in [1,5,10,20]: return false
	session = Store.utc().replace("-", "").replace(":", "") + "_" + Store.uid().left(12)
	kind = mode
	jobs.clear()
	baselines.clear()
	done = 0
	for trial in range(1, repetitions + 1):
		for index in cases.size():
			var pair := Store.uid()
			var order := [0,1] if (trial + index) % 2 == 1 else [1,0]
			for p in order:
				jobs.append({"item":cases[index].item, "question":cases[index].get("question",""), "question_id":cases[index].get("question_id",""), "provider":p, "trial":trial, "pair_id":pair, "order":order.duplicate()})
	var manifest := {
		"event":"session_started", "timestamp_utc":Store.utc(), "session_id":session,
		"kind":kind, "run_kind":store.run_kind, "total":jobs.size(), "cases":cases,
		"repetitions":repetitions, "engine":Engine.get_version_info().string,
		"display":DisplayServer.get_name(), "window_size":str(get_window().size),
		"cpu":OS.get_processor_name(), "gpu":RenderingServer.get_video_adapter_name(),
		"physics_ticks_per_second":Engine.physics_ticks_per_second
	}
	if not store.append("sessions", session, manifest):
		finished.emit(store.error)
		return false
	running = true
	phase = "next"
	return true

func _process(_delta: float) -> void:
	if not running: return
	match phase:
		"next": _next()
		"request": _request()
		"waiting":
			if not terminal.is_empty() and (kind != "combat" or not replay_done.is_empty()): _complete()

func _next() -> void:
	if done == jobs.size():
		_end("완료")
		return
	var job: Dictionary = jobs[done]
	var item: Dictionary = job.item
	current = {}
	var ok := prepare(item, job.provider)
	start_state = world.game_state().duplicate(true)
	var fixture := world.save_snapshot()
	var fixture_hash := JSON.stringify(fixture).sha256_text()
	var state_hash := JSON.stringify(start_state).sha256_text()
	var signature := state_hash + fixture_hash
	var matches: bool = baselines.get(item.id, signature) == signature
	baselines[item.id] = baselines.get(item.id, signature)
	var client := brain.local_dialogue if kind == "dialogue" else brain.local_decision
	var local: bool = job.provider == 1
	current = {
		"experiment_id":Store.uid(), "pair_id":job.pair_id, "session_id":session,
		"scenario_id":item.id, "scenario_version":scenario_version, "trial":job.trial,
		"session_order":job.order, "kind":kind, "run_kind":store.run_kind,
		"provider":NPCBrain.PROVIDERS[job.provider], "question":job.question, "question_id":job.question_id,
		"snapshot_hash":state_hash, "snapshot_matches":matches, "fixture_hash":fixture_hash,
		"initial_state":{"game":start_state,"world":fixture}, "allowed":start_state.valid_actions,
		"observation":NPCPolicy.model_state(start_state) if kind != "dialogue" else null,
		"acceptable_actions":item.get("acceptable_actions"), "project_fingerprint":fingerprint,
		"requested_model":client.settings.model if local else null,
		"model_options":client.settings.generation_options() if local else null,
		"model_thinking":client.settings.effective_thinking() if local else null,
		"timeout_seconds":client.settings.timeout_seconds if local else null,
		"max_decision_age":brain.settings.max_decision_age, "model_readiness":"unknown" if local else null,
		"common_emergency_enabled":false, "timestamp_utc":Store.utc(),
		"prompt_version":NPCPolicy.FLEET_DIALOGUE_VERSION if kind == "dialogue" else NPCPolicy.PROMPT_VERSION
	}
	attempts = []
	issues = []
	terminal = {}
	timeline = []
	resource_changes = []
	last_resources = {}
	replay_done = ""
	replay_tick = 0
	started_usec = 0
	requested_ms = null
	answered_ms = null
	brain.event_recorded.connect(_event)
	client.attempt_recorded.connect(func(record): attempts.append(record.duplicate(true)))
	progress.emit(done, jobs.size(), "%s  ·  %s  ·  %d회차" % [item.id,current.provider,job.trial])
	if not ok or not matches:
		terminal = {"event":"request_failed","error":"invalid_fixture" if not ok else "snapshot_mismatch"}
		_complete()
		if running: _end("시작 상태 검증 실패")
		return
	phase = "request"
	if local:
		var health := HTTPRequest.new()
		brain.add_child(health)
		health.timeout = 2
		health.body_size_limit = 262144
		health.request_completed.connect(_readiness.bind(client.settings.model))
		if health.request("http://%s:%d/api/ps" % [client.settings.host,client.settings.port]) == OK: phase = "readiness"

func _readiness(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, model: String) -> void:
	if phase != "readiness" or not running: return
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if data is Dictionary and data.get("models") is Array:
			current.model_readiness = {"resident":false}
			for entry in data.models:
				if entry is Dictionary and entry.get("name") == model:
					current.model_readiness = {"resident":true,"digest":entry.get("digest"),"details":entry.get("details")}
			if not current.model_readiness.resident:
				var tags := HTTPRequest.new()
				brain.add_child(tags)
				tags.timeout = 2
				tags.body_size_limit = 1048576
				tags.request_completed.connect(_installed_model.bind(model))
				var settings := brain.local_dialogue.settings
				if tags.request("http://%s:%d/api/tags" % [settings.host,settings.port]) == OK: return
	phase = "request"

func _installed_model(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, model: String) -> void:
	if phase != "readiness" or not running: return
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if data is Dictionary and data.get("models") is Array:
			current.model_readiness.installed = false
			for entry in data.models:
				if entry is Dictionary and entry.get("name") == model:
					current.model_readiness.merge({"installed":true, "digest":entry.get("digest"), "details":entry.get("details")}, true)
	phase = "request"

func _request() -> void:
	if JSON.stringify(world.game_state()).sha256_text() != current.snapshot_hash:
		current.snapshot_matches = false
		_failure("snapshot_changed_before_request")
		_complete()
		if running: _end("요청 직전 상태가 변경되어 중단했습니다.")
		return
	if not store.append("sessions", session, {"event":"request_started","experiment_id":current.experiment_id,"initial":current,"timestamp_utc":Store.utc()}):
		var reason := store.error
		stop("storage_error")
		finished.emit(reason)
		return
	phase = "waiting"
	if kind == "combat":
		world.process_mode = Node.PROCESS_MODE_INHERIT
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		world.state_changed.connect(_sample_resources)
		_sample_resources()
	started_usec = Time.get_ticks_usec()
	requested_ms = Time.get_ticks_msec()
	var ok := brain.request_dialogue(current.question) if kind == "dialogue" else brain.request_decision()
	if not ok and terminal.is_empty(): _failure("request_not_started")

func _event(record: Dictionary) -> void:
	if current.is_empty(): return
	match record.event:
		"response", "request_cancelled", "request_failed":
			terminal = record.duplicate(true)
			answered_ms = Time.get_ticks_msec()
			terminal["wall_elapsed_ms"] = (Time.get_ticks_usec() - started_usec) / 1000.0 if started_usec > 0 else null
		"dialogue_validation_failed": issues.append(record.duplicate(true))
		"world_event":
			if kind == "combat" and phase == "waiting":
				var detail: Dictionary = record.details.duplicate(true)
				detail.tick = replay_tick
				detail.source = detail.get("request",{}).get("source", detail.get("request",{}).get("provider","world"))
				timeline.append(detail)

func _physics_process(_delta: float) -> void:
	if not running or phase != "waiting" or kind != "combat" or not replay_done.is_empty(): return
	replay_tick += 1
	var item: Dictionary = jobs[done].item
	_sample_resources()
	if world.defeated or world.enemies_remaining() == 0 or replay_tick >= int(item.seconds) * Engine.physics_ticks_per_second:
		replay_done = "defeated" if world.defeated else ("cleared" if world.enemies_remaining() == 0 else "survived")
		world.process_mode = Node.PROCESS_MODE_DISABLED
		brain.cancel_pending("combat_ended")
		return
	if replay_tick % int(item.shot_interval_ticks) == 0:
		var target := Vector2(item.aim[0], item.aim[1])
		timeline.append({"event":"replay_fire","tick":replay_tick,"target":item.aim,"fired":world.shoot(target)})

func _sample_resources() -> void:
	var sample := {"hp":world.player_hp,"ammo":world.ammo,"magazines":world.magazines,"medkits":world.medkits,"supply_packs":world.supply_packs,"cover_charges":world.cover_charges,"enemies":world.enemies_remaining()}
	if last_resources != sample:
		last_resources = sample.duplicate()
		sample.tick = replay_tick
		resource_changes.append(sample)

func _combat_result() -> Dictionary:
	var started := 0
	var completed := 0
	var rejected := 0
	var direct_healing := 0
	var health_gained := 0
	var no_effect := 0
	for i in range(1, resource_changes.size()):
		health_gained += maxi(0, int(resource_changes[i].hp) - int(resource_changes[i-1].hp))
	for e in timeline:
		match e.event:
			"support_started": started += 1
			"support_rejected": rejected += 1
			"support_completed":
				if e.action != "guide_to_cover": completed += 1
				if e.action == "heal": direct_healing += int(e.effect)
				if e.action in ["heal","resupply"] and e.effect == 0: no_effect += 1
	var device_healing := maxi(0, health_gained - direct_healing)
	if world.completed_support.get("deploy_cover",0) > 0 and device_healing == 0: no_effect += 1
	return {
		"outcome":replay_done, "duration_seconds":float(replay_tick)/Engine.physics_ticks_per_second,
		"events":timeline, "resource_changes":resource_changes, "completed":world.completed_support.duplicate(),
		"support_failures":rejected, "unfinished_support":maxi(0, started-completed-rejected),
		"resource_uses_without_observed_effect":no_effect, "device_hp_gained":device_healing,
		"replay":jobs[done].item
	}

func _failure(reason: String) -> void:
	terminal = {"event":"request_failed","error":reason,"wall_elapsed_ms":(Time.get_ticks_usec() - started_usec) / 1000.0 if started_usec > 0 else null}

func stop(reason := "operator_cancelled") -> void:
	if not running: return
	if not current.is_empty():
		brain.cancel_pending(reason)
		if terminal.is_empty(): terminal = {"event":"request_cancelled","reason":reason}
		if kind == "combat" and replay_done.is_empty(): replay_done = "cancelled"
		_complete()
	if running: _end("중단 · " + reason)

func _complete() -> void:
	var row := current
	var reason: String = terminal.get("rejected_reason",terminal.get("error",terminal.get("reason","")))
	var selected = terminal.get("selected")
	var action = selected if kind != "dialogue" or terminal.get("dialogue_method") == "executor_receipt" else null
	var response = terminal.get("raw_response") if kind == "dialogue" else null
	if kind == "dialogue" and terminal.get("accepted",false) and not brain.history.is_empty(): response = brain.history.back().answer
	var common: bool = terminal.get("actual_model") == "common_executor"
	var appropriate: Variant = null
	if kind == "decision" and selected != null: appropriate = selected in row.acceptable_actions
	var eligible: bool = selected != null and selected in row.allowed
	var used: bool = terminal.get("accepted",false) or terminal.get("action_outcome") == "no_change"
	var status := "success"
	if terminal.event == "request_cancelled": status = "cancelled"
	elif reason == "stale_age" or "시간초과" in reason: status = "timeout"
	elif reason == "invalid_candidate": status = "invalid_action"
	elif terminal.event == "request_failed": status = "request_failed"
	elif not reason.is_empty(): status = "rejected"
	elif kind == "decision": status = "appropriate" if appropriate else "inappropriate"
	var elapsed = terminal.get("elapsed_ms",terminal.get("wall_elapsed_ms"))
	var accepted: bool = terminal.get("accepted",false)
	if kind == "dialogue": elapsed = terminal.get("wall_elapsed_ms",elapsed)
	row.merge({
		"status":status, "response_text":response, "selected_action":action, "accepted":accepted,
		"rejected_reason":reason, "elapsed_ms":elapsed,
		"display_ready_ms":elapsed if kind == "dialogue" and accepted else null,
		"generation_attempts":attempts.size(), "regeneration_count":maxi(0,attempts.size()-1),
		"attempts":attempts, "validation_errors":issues, "actual_model":terminal.get("actual_model"),
		"dialogue_method":terminal.get("dialogue_method"), "handler":"common_executor" if common else row.provider,
		"common_executor":common, "appropriate":appropriate,
		"timely_valid":eligible and used and status != "timeout" if kind != "dialogue" else null,
		"request_id":terminal.get("request_id"), "action_outcome":terminal.get("action_outcome"),
		"action_accepted":terminal.get("action_accepted"), "action_status":terminal.get("action_status"),
		"valid_action":eligible if kind != "dialogue" and selected != null else null,
		"timed_out":status == "timeout", "discarded_stale":reason in ["stale_age","stale_facts","stale_epoch"],
		"decision_started_msec":requested_ms, "decision_finished_msec":answered_ms, "rating":null, "combat":null
	})
	if kind == "combat":
		_sample_resources()
		row.combat = _combat_result()
	current = {}
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	world.process_mode = Node.PROCESS_MODE_DISABLED
	done += 1
	if not store.append(kind, session, row):
		unsaved.append(row)
		_end(store.error)
		return
	recorded.emit(row)
	phase = "next"

func _end(message: String) -> void:
	running = false
	phase = ""
	var ok := store.append("sessions",session,{"event":"session_ended","timestamp_utc":Store.utc(),"finished_requests":done,"total":jobs.size(),"reason":message})
	progress.emit(done,jobs.size(),message)
	finished.emit(message if ok else store.error)

func retry_save() -> bool:
	while not unsaved.is_empty():
		var row: Dictionary = unsaved.front()
		if not store.append(row.kind,row.session_id,row): return false
		unsaved.pop_front()
		recorded.emit(row)
	return true
