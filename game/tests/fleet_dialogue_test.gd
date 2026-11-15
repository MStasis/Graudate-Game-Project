extends SceneTree
## Frozen dialogue fixtures. fleet_demo_test.gd verifies how play reaches these states.

const Fleet := preload("res://scripts/fleet_demo.gd")
const Mission := preload("res://main.gd")
const QUESTIONS := ["지금 뭘 해야 해?", "퓨즈는 어디 있어?", "통신은 돼?", "저 적들은 뭐야?", "레버는 언제 당겨?"]
const CASES := [
	["before_mika", Fleet.Step.FIND_MIKA, "corridor", 2],
	["after_mika", Fleet.Step.FIND_FUSE, "mika_quarters", 0],
	["cabinet_open", Fleet.Step.FIND_FUSE, "supply_room", 1],
	["fuse_held", Fleet.Step.FUSE_HELD, "supply_room", 1],
	["hall_enemy", Fleet.Step.AMBUSH, "corridor", 3],
	["hall_clear", Fleet.Step.TO_POWER, "corridor", 0],
	["power_restored", Fleet.Step.TO_LAB, "corridor", 2],
	["lab_combat", Fleet.Step.WAVES, "research_lab_b", 4],
	["waves_clear", Fleet.Step.LEVER, "research_lab_b", 4],
	["signal_armed", Fleet.Step.ARMED, "research_lab_b", 4],
]
const RULE_ANCHORS := [
	["첫 번째 문", "확인 못", "확인한 게 없어", "못 봤", "확인 못"],
	["비품실", "정확히", "먹통", "못 봤", "확인 못"],
	["앞 바닥", "앞 바닥", "먹통", "못 봤", "확인 못"],
	["아래쪽 문", "네가 갖고", "먹통", "못 봤", "확인 못"],
	["복도에 있는 선원", "네가 갖고", "먹통", "머리 없는", "확인 못"],
	["전기실", "네가 갖고", "먹통", "제압한", "확인 못"],
	["연구실 B동", "주 퓨즈함", "다시 연결됐다는 확인은 없어", "제압한", "확인 못"],
	["2차", "주 퓨즈함", "먹통", "침식된 선원", "아직"],
	["신호를 기다려", "주 퓨즈함", "먹통", "모두 제압", "신호하면"],
	["E를 한 번", "주 퓨즈함", "먹통", "모두 제압", "E를 한 번"],
]

var app: Mission
var world: DemoWorld
var checks := {}
var records: Array[Dictionary] = []
var samples := []
var live := false
var limit := ""

func _initialize() -> void:
	run.call_deferred()

func check(id: String, passed: bool) -> void:
	checks[id] = passed
	if not passed: push_error("FLEET_DIALOGUE_FAILED " + id)

func fixture(item: Array) -> void:
	app.brain.new_trial(1 if live else 0)
	var demo := world.fleet_demo
	demo.clear_cues()
	var step: int = item[1]
	demo.step = step as Fleet.Step
	world.story.advance("blackout", "blackout")
	world.fuse_collected = step >= Fleet.Step.FUSE_HELD
	if world.fuse_collected: world.story.advance("fuse_return", "fuse_collected")
	demo.inserted = step >= Fleet.Step.ALARM
	world.power_restored = demo.inserted
	if world.power_restored:
		world.story.advance("power_restored", "power_restored")
		world.story.advance("anomaly_alarm", "anomaly_alarm")
	if step >= Fleet.Step.CORES:
		world.story.tutorial_completed = true
		world.story.advance("main_entry", "main_entered")
		world.story.advance("containment", "containment_briefed")
		demo.core_seen = true
		demo.wave = 2 if step == Fleet.Step.WAVES else 3
	if item[0] == "cabinet_open" or world.fuse_collected: demo.cabinets["cabinet_fuse"] = true
	if step == Fleet.Step.AMBUSH: demo.unit_pool[0].reset_enemy()
	if step == Fleet.Step.WAVES:
		for enemy in demo.unit_pool:
			if enemy.get_meta("wave") == demo.wave: enemy.reset_enemy()
	world._change_map(item[2], world.bounds_for(item[2]).get_center())
	if step == Fleet.Step.ARMED:
		world.player.position = demo.room().approach("eroded_stop")
		world.npc.position = demo.room().approach("normal_stop")
	world._sync_state()

func ask(question: String) -> Dictionary:
	var before := records.size()
	var started := app.brain.request_dialogue(question)
	if live and started:
		var deadline := Time.get_ticks_msec() + ceili((app.brain.local_dialogue.settings.timeout_seconds * 2 + 3) * 1000.0)
		while records.size() == before and not app.brain.pending.is_empty() and Time.get_ticks_msec() < deadline:
			await create_timer(0.025).timeout
	return records.back() if records.size() > before else {}

func verify_prompt(id: String, question: String, state: Dictionary) -> void:
	var result := MikaDialogue.build(state, question, [], world.npc.description, app.brain.local_dialogue.settings.system_prompt)
	var prompt: Dictionary = JSON.parse_string(result.prompt)
	var actual: Dictionary = prompt.get("CURRENT FACTS (최신 사실)", {})
	var serialized_scene = JSON.parse_string(JSON.stringify(state.fleet_context))
	check(id + "_state", actual.get("진행 상황") == serialized_scene and actual.get("현재 장소") == state.location and actual.get("전력 복구") == state.power_restored and actual.get("다음 단계") == state.fleet_context["현재 목표"])
	check(id + "_scope", result.messages[-1].content == question and result.messages[-2].role == "system" and not NPCPolicy.has_word(result.prompt, ["외곽", "북쪽 중앙 보관함", "비품실 전투", "비프"]))

func verify_boundaries() -> void:
	fixture(CASES[0])
	var state := world.game_state()
	check("earlier_facts_are_unknown", not state.fleet_context["통신 장애 확인"] and state.fleet_context["퓨즈 위치"] == "미확인" and not state.fleet_context["복도 적 발견"])
	check("reject_future_comms", not MikaDialogue.claims_valid("통신은 먹통이야.", state))
	check("opening_radio_does_not_prove_network", not MikaDialogue.claims_valid("응, 통신 돼.", state))
	check("opening_does_not_imply_comms_failure", MikaDialogue.response_issue("전원 끊어졌어. 통신 안 돼.", state, QUESTIONS[2]) == "fleet_comms_not_reported")
	check("reject_future_enemy", not MikaDialogue.claims_valid("아까 본 건 침식된 선원이야.", state))
	check("reject_future_fuse", not MikaDialogue.claims_valid("왼쪽 캐비닛 앞 바닥에 있어.", state))
	check("reject_future_plan", not MikaDialogue.claims_valid("정상 코어 옆에서 두 레버를 함께 당겨.", state))
	fixture(CASES[1])
	check("report_observed_in_existing_opening_line", world.game_state().fleet_context["통신 장애 확인"] and "먹통" in Fleet.Lines.QUARTERS[1][1])
	var history := [{"question": "레버 어디야?", "answer": "위쪽에 있어."}]
	var casual := MikaDialogue.build(world.game_state(), "오늘 좀 피곤하다.", history, "", "")
	check("casual_avoids_manual_and_mission_history", not NPCPolicy.has_word(casual.prompt, ["캐비닛", "레버", "비품실", "다음 단계"]))
	fixture(CASES[3])
	check("held_fuse_cannot_be_picked_up_again", not MikaDialogue.claims_valid("이미 갖고 있으니 E로 직접 뽑아서 끝내자.", world.game_state()))
	fixture(CASES[6])
	state = world.game_state()
	check("reject_comms_repair", not MikaDialogue.claims_valid("조명이 켜져서 통신도 복구됐어.", state))
	check("reject_comms_cause", not MikaDialogue.claims_valid("정전 때문에 통신이 끊겼어.", state))
	check("reject_wrong_cabinet_and_pickup_actor", not MikaDialogue.claims_valid("비품실 오른쪽 퓨즈 찾아야 돼.", state) and not MikaDialogue.claims_valid("퓨즈 앞 바닥이야. 놓아줄게.", state))
	check("reject_legacy_gear", not MikaDialogue.claims_valid("외곽 관측 단말로 가고 봉쇄 패널을 1초 유지해.", state))
	fixture(CASES[7])
	state = world.game_state()
	var support := MikaDialogue.facts(state, "네가 쐈어?", "support")
	check("no_fleet_shoot_claim", not support["미카 직접 사격"] and not MikaDialogue.claims_valid("내가 쐈어.", state))
	check("no_unexecuted_support_claim", not MikaDialogue.claims_valid("탄약 채워줬어.", state))
	check("future_lever_still_locked", not MikaDialogue.claims_valid("지금 당겨.", state) and not MikaDialogue.claims_valid("격벽은 설치됐어.", state))
	check("wave_two_alone_cannot_unlock_lever", MikaDialogue.response_issue("2차 제압 끝나면 당겨!", state, QUESTIONS[4]) == "fleet_lever_not_ready")
	check("all_waves_alone_cannot_unlock_lever", MikaDialogue.response_issue("B동 전투 다 끝나면 당겨.", state, QUESTIONS[4]) == "fleet_lever_signal_missing")
	check("fleet_panel_question_not_legacy_order", NPCPolicy.requested_action("패널 같이 누르자.", true).is_empty() and NPCPolicy.requested_action("패널 같이 누르자.") == "assist_panel")
	check("lever_wait_question_does_not_order_npc", NPCPolicy.requested_action("레버는 신호를 기다려?", true).is_empty() and NPCPolicy.requested_action("여기서 기다려.", true) == "wait")
	for word in ["코어", "레버", "격벽", "B동", "캐비닛", "전기실"]:
		check("intent_" + word, MikaDialogue.topic_for(word + "는 어떻게 해?", [], true) == "mission")
	var jev := NPCPolicy.jev_payload("dialogue", state, QUESTIONS[4], "fixture")
	check("jev_dialogue_uses_same_fleet_facts", jev.state.dialogue_context == MikaDialogue.facts(state, QUESTIONS[4], "mission"))
	check("jev_tactical_input_unchanged", not NPCPolicy.jev_payload("decision", state, "", "fixture").state.has("dialogue_context"))
	app.brain.provider = 2
	app.brain.pending = {"kind": "dialogue", "question": QUESTIONS[4], "snapshot": state, "epoch": world.epoch, "request_id": 100, "started_usec": Time.get_ticks_usec(), "allowed": NPCPolicy.INTENTS.keys(), "snapshot_hash": "fixture"}
	var selection := NPCPolicy.parse_jev({"answers": {"selection": {"type": "choice", "choice": "mission", "probabilities": {"mission": 1.0}}}, "model": "fixture"}, NPCPolicy.INTENTS.keys())
	app.brain._resolve(selection.choice, {"actual_model": "synthetic_jev", "dialogue_method": "intent_template"})
	check("jev_fixture_uses_fleet_reply", records.back().accepted and "레버는 아직" in app.brain.history.back().answer)
	app.brain.provider = 1
	app.brain.pending = {"kind": "dialogue", "question": QUESTIONS[4], "snapshot": state, "epoch": world.epoch, "request_id": 101, "started_usec": Time.get_ticks_usec(), "allowed": NPCPolicy.INTENTS.keys(), "snapshot_hash": "fixture"}
	world.fleet_demo.step = Fleet.Step.LEVER
	app.brain._resolve("레버는 아직이야.", {"actual_model": "synthetic_stale"})
	check("stale_facts_after_combat", records.back().rejected_reason == "stale_facts")
	check("unrelated_kill_does_not_stale_comms", MikaDialogue.grounding_facts(state, QUESTIONS[2], "mission") == MikaDialogue.grounding_facts(world.game_state(), QUESTIONS[2], "mission"))
	world.use_fleet_demo = false
	app.brain.new_trial(0)
	world.trigger_blackout()
	world.flashlight_owned = true
	world.apply_interaction("storage_gate")
	state = world.game_state()
	var legacy := MikaDialogue.build(state, "보관함 패널은 어떻게 작동해?", [], world.npc.description, "")
	check("old_mission_uses_old_panel_prompt", "1초" in legacy.prompt and "진행 상황" not in legacy.prompt and "패널" in NPCPolicy.template_response("mission", state, "패널은 어떻게 작동해?"))

func run() -> void:
	live = "--fleet-dialogue-live" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fleet-case="): limit = arg.trim_prefix("--fleet-case=")
	app = load("res://main.tscn").instantiate() as Mission
	app.world_starts_fleet_demo = true
	root.add_child(app)
	app.brain.auto_enabled = false
	world = app.world
	world.set_physics_process(false)
	for enemy in world.all_enemies(): enemy.set_physics_process(false)
	app.brain.measured.connect(func(record): records.append(record.duplicate(true)))
	var directory := ProjectSettings.globalize_path("res://../evidence/fleet_dialogue")
	DirAccess.make_dir_recursive_absolute(directory)
	for client in [app.brain.local_dialogue, app.brain.local_decision]: client.log_dir = directory
	app.brain.log_dir = directory
	for index in CASES.size():
		var item: Array = CASES[index]
		if not limit.is_empty() and limit != item[0]: continue
		fixture(item)
		var state := world.game_state()
		for q in QUESTIONS.size():
			if live and q != item[3]: continue
			var question: String = QUESTIONS[q]
			var id := "%s_%d" % [item[0], q]
			verify_prompt(id, question, state)
			var record := await ask(question)
			var accepted: bool = record.get("accepted", false)
			var reply: String = app.brain.history.back().answer if accepted else ""
			var expected_model := app.brain.local_dialogue.settings.model if live else "rules_v1"
			check(id + "_provider", accepted and record.get("actual_model") == expected_model and record.get("prompt_version") == NPCPolicy.FLEET_DIALOGUE_VERSION)
			if not live: check(id + "_answer", RULE_ANCHORS[index][q] in reply)
			samples.append({"id": id, "question": question, "text": reply, "record": record})
			if live: print("FLEET_DIALOGUE_SAMPLE ", JSON.stringify({"id": id, "text": reply, "accepted": accepted, "elapsed_ms": record.get("elapsed_ms")}))
	if not live: verify_boundaries()
	var result := {"passed": not checks.is_empty() and not checks.values().has(false), "check_count": checks.size(),
		"actual_inference": live, "created_utc": Time.get_datetime_string_from_system(true), "checks": checks, "samples": samples}
	FileAccess.open(directory.path_join("live_" + (limit if not limit.is_empty() else "suite") + ".json" if live else "test.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	print("FLEET_DIALOGUE_RESULT ", JSON.stringify({"passed": result.passed, "check_count": checks.size(), "actual_inference": live}))
	app.queue_free()
	await process_frame
	quit(0 if result.passed else 1)
