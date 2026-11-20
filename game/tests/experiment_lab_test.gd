extends SceneTree
## Real UI, brains, Fleet worlds and filesystem. Only the transport payload is injected in fixture mode.
const Hub := preload("res://scripts/experiments/experiment_hub.gd")
const Runner := preload("res://scripts/experiments/experiment_runner.gd")
var lab: Hub
var runner: Runner
var title: Control
var live := false
var render := false
var checks := {}
var rows := []
var evidence := ProjectSettings.globalize_path("res://../evidence/experiment_lab")
var test_sessions := {}
var save_path := ""
var save_hash := ""

func _initialize() -> void:
	run.call_deferred()

func check(id: String, ok: bool) -> void:
	checks[id] = ok
	if not ok: push_error("LAB_FAILED " + id)

func frames() -> void:
	for i in 3: await process_frame

func capture(id: String) -> void:
	if not render: return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	check("gpu_" + id, img.get_size() == root.size and not img.is_invisible() and img.save_png(evidence.path_join(id + ".png")) == OK)

func choose(id: String) -> void:
	for i in lab.scenario.item_count:
		var data: Dictionary = lab.scenario.get_item_metadata(i)
		if data.get("id") == id:
			lab.scenario.select(i)
			lab.scenario.item_selected.emit(i)
			return

func select_session(id: String) -> void:
	for i in lab.session_picker.item_count:
		if lab.session_picker.get_item_text(i) == id:
			lab.session_picker.select(i)
			lab._load_session(i)
			return

func simulate_response(tag: String) -> void:
	var brain := runner.brain
	var client := brain.local_dialogue if runner.kind == "dialogue" else brain.local_decision
	client.set_process(false)
	if tag == "cancel":
		runner.stop()
		return
	if tag == "failure":
		client._fail("fixture transport failure")
		return
	if tag == "late": brain.tactical_pending.started_usec -= 4000000
	if tag == "retry":
		client._consume_event(JSON.stringify({"response":"", "done":false}))
		client._consume_event(JSON.stringify({"response":"통신도 복구됐어.", "done":true,"model":"fixture"}))
		if not client.busy: return
	var action := NPCPolicy.rule_action(NPCPolicy.model_state(runner.start_state))
	if tag == "late": action = "heal"
	if tag == "wrong": action = "deploy_cover"
	if tag == "invalid": action = "unknown_fixture_action"
	var answer := "비품실 아래쪽 문으로 가자." if runner.kind == "dialogue" else JSON.stringify({"action":action})
	client._consume_event(JSON.stringify({"response":answer,"done":true,"model":"fixture"}))

func wait_batch(tag := "") -> void:
	var deadline_ms := Time.get_ticks_msec() + (1200000 if live else 60000)
	while runner.running and Time.get_ticks_msec() < deadline_ms:
		if not live and not runner.current.is_empty() and runner.current.provider == "LocalLLM":
			# Run before HTTPClient.poll; do not require an installed model for fixtures.
			if runner.phase == "readiness": runner.phase = "request"
			if runner.phase == "request": runner._request()
			if not runner.brain.pending.is_empty(): simulate_response(tag)
		await process_frame
	check("completed_" + runner.session, not runner.running)
	if runner.running: runner.stop("test_deadline")
	test_sessions[runner.session] = {"kind":runner.kind,"rows":runner.store.results(runner.session).size()}

func compare(kind: String, id: String, repeats: int, tag := "") -> Array:
	lab.open_mode(kind)
	choose(id)
	if kind == "dialogue": lab.question.text = "이제 어디로 가?"
	lab.repeat.select([1,5,10,20].find(repeats))
	rows.clear()
	lab._start(false)
	await wait_batch(tag)
	return rows.duplicate(true)

func verify_export(kind: String, count: int) -> void:
	lab._export_current()
	var f := FileAccess.open(lab.notice.text,FileAccess.READ)
	if not f:
		check(kind + "_export_open",false)
		return
	f.get_buffer(3)
	var header := f.get_csv_line()
	var ids := {}
	while f.get_position() < f.get_length():
		var cells := f.get_csv_line()
		if cells.size() != header.size(): break
		if cells[header.find("kind")] == kind: ids[cells[header.find("experiment_id")]] = true
	check(kind + "_export_" + runner.session,ids.size() == count)

func run() -> void:
	live = "--experiment-live" in OS.get_cmdline_user_args()
	render = "--experiment-render" in OS.get_cmdline_user_args()
	if OS.has_environment("NPC_LAB_TEST_EVIDENCE"): evidence = OS.get_environment("NPC_LAB_TEST_EVIDENCE")
	root.size = Vector2i(1280,800)
	DirAccess.make_dir_recursive_absolute(evidence)
	change_scene_to_file("res://scenes/ui/TitleMenu.tscn")
	await frames()
	title = current_scene
	check("button_order",title.get_node("%ExperimentLab").get_index() == title.get_node("%Continue").get_index()+1)
	if not live:
		title._store.directory = "user://lab_save_probe_%d" % OS.get_process_id()
		title._show_actions()
		title.get_node("%NewGame").pressed.emit()
		await frames()
		var mission = title.get_node("Main")
		var factory := Runner.Factory.new()
		check("campaign_slot_fixture",factory.apply(mission.world,factory.find_scenario("D04")) and mission.save_slot(1))
		save_path = title._store.path_for(1)
		save_hash = FileAccess.get_sha256(save_path)
		mission.title_requested.emit()
		await frames()
	title.get_node("%ExperimentLab").pressed.emit()
	await frames()
	lab = title.get_node("ExperimentHub") as Hub
	runner = lab.runner
	runner.store.run_kind = "development_live" if live else "development_fixture"
	runner.recorded.connect(func(row): rows.append(row.duplicate(true)))
	check("isolated_world",not title.get_node("Menu").visible and not title.has_node("Main") and runner.viewport.world_2d != root.world_2d)
	await capture("hub")
	if not live:
		lab.open_mode("dialogue")
		var expected := ["FIND_MIKA","FIND_FUSE","FIND_FUSE","FUSE_HELD","AMBUSH","TO_POWER","TO_LAB","WAVES","LEVER","ARMED"]
		for i in 10:
			var id := "D%02d" % (i+1)
			choose(id)
			var state := runner.world.game_state()
			var ctx: Dictionary = state.fleet_context
			check(id + "_story",ctx["진행 단계"] == expected[i] and state.power_restored == (i >= 6) and state.fuse_in_inventory == (i >= 3 and i < 6) and ctx["통신 장애 확인"] == (i > 0) and ctx["레버 조작 가능"] == (i == 9) and ctx["복도 적 발견"] == (i >= 4) and (state.enemy_count > 0) == (i in [4,7]))
			var q: Dictionary = runner.factory.questions[i]
			check(id + "_rule",runner.brain.request_dialogue(q.text) and not runner.brain.history.is_empty())
		choose("D04")
		var before := runner.world.game_state()
		await create_timer(0.2).timeout
		check("world_frozen_full_state",before == runner.world.game_state() and runner.brain.history.is_empty())
		lab.open_mode("decision")
		var expected_actions := ["heal","resupply","heal","deploy_cover","guide_to_cover","follow","follow","follow"]
		for i in 8:
			var id := "B%02d" % (i+1)
			choose(id)
			var state := runner.world.game_state()
			var item := runner.factory.find_scenario(id)
			check(id + "_observations",state.player_hp == item.hp and state.ammo == item.ammo and state.magazines == item.magazines and state.inside_cover == (i == 5) and state.cover_active == (i in [4,5]) and (state.enemy_count > 0) == (i != 7))
			check(id + "_actions",NPCPolicy.rule_action(NPCPolicy.model_state(state)) == expected_actions[i] and item.acceptable_actions.all(func(a): return a in state.valid_actions))
	var d := await compare("dialogue","D04",5,"retry")
	check("dialogue_ten_rows",d.size() == 10)
	if d.size() == 10:
		check("dialogue_hash_and_latency",d.all(func(r): return r.snapshot_matches and r.snapshot_hash == d[0].snapshot_hash and r.elapsed_ms != null and r.question == "이제 어디로 가?"))
		check("rule_actual_text",d[0].actual_model == "rules_v1" and "아래쪽 문" in d[0].response_text)
		var local: Array = d.filter(func(r): return r.provider == "LocalLLM")
		if live: check("qwen_dialogue_transport",local.all(func(r): return r.actual_model == "qwen3:4b" and r.attempts.size() > 0))
		else: check("first_and_regenerated",local.all(func(r): return r.generation_attempts == 2 and r.attempts[0].attempt == 0 and r.attempts[1].attempt == 1 and r.validation_errors.size() == 1 and r.attempts[0].response != r.response_text and r.attempts[1].response == r.response_text and r.actual_model == "fixture"))
		check("counterbalance",d[0].provider == "RuleBased" and d[2].provider == "LocalLLM" and d[0].pair_id == d[1].pair_id and d[0].experiment_id != d[1].experiment_id)
	await capture("dialogue")
	lab.open_mode("results")
	select_session(runner.session)
	check("results_reloaded",lab.history_rows.size() == 10)
	if lab.scores.size() == 4 and not live:
		for s in lab.scores: s.select(2)
		lab._save_rating(0)
		check("manual_rating_persisted",runner.store.results(runner.session)[0].rating.total == 4)
	var csv := runner.store.export_csv(runner.session)
	var f := FileAccess.open(csv,FileAccess.READ)
	check("csv_bom",f != null and f.get_buffer(3) == PackedByteArray([239,187,191]))
	if f:
		var header := f.get_csv_line()
		var line := f.get_csv_line()
		check("csv_roundtrip",line.size() == header.size() and line[header.find("question")] == "이제 어디로 가?")
		await capture("records")
	var b := await compare("decision","B01",5,"late")
	check("decision_ten_rows",b.size() == 10)
	if b.size() == 10:
		verify_export("decision",10)
		check("decision_same_candidates",b.all(func(r): return r.allowed == b[0].allowed and r.snapshot_hash == b[0].snapshot_hash and r.observation == b[0].observation))
		var llm: Array = b.filter(func(r): return r.provider == "LocalLLM")
		if live: check("qwen_decision_transport",llm.any(func(r): return r.actual_model == "qwen3:4b" and r.selected_action != null))
		else: check("late_action_retained",llm.all(func(r): return r.status == "timeout" and r.appropriate and not r.timely_valid and r.elapsed_ms > 3000 and r.selected_action == "heal"))
	if not live:
		lab.open_mode("dialogue")
		choose("D04")
		lab._start(true)
		await wait_batch()
		var preset_rows := runner.store.results(runner.session)
		check("question_set_provenance",preset_rows.size() == 2 and preset_rows.all(func(r): return r.question_id == "Q04"))
		lab.open_mode("results")
		select_session(runner.session)
		lab.provider_filter.select(2)
		lab._filter_rows()
		check("provider_filter",lab.history_rows.size() == 1 and lab.history_rows[0].provider == "LocalLLM")
		var orphan_id := runner.store.uid()
		var journal := runner.store.read_rows("sessions",runner.session)
		var interrupted_row: Dictionary = journal[1].initial.duplicate(true)
		interrupted_row.experiment_id = orphan_id
		var orphan_session := "00000000_" + orphan_id
		interrupted_row.session_id = orphan_session
		interrupted_row.erase("status")
		interrupted_row.erase("elapsed_ms")
		runner.store.append("sessions",orphan_session,{"event":"request_started","initial":interrupted_row,"experiment_id":orphan_id})
		var interrupted := runner.store.results(orphan_session)
		check("interrupted_start_visible",interrupted.size() == 1 and interrupted[0].status == "unfinished" and interrupted[0].elapsed_ms == null)
		var wrong := await compare("decision","B01",1,"wrong")
		check("accepted_but_inappropriate",wrong.size() == 2 and wrong[-1].accepted and wrong[-1].status == "inappropriate")
		var invalid := await compare("decision","B01",1,"invalid")
		check("invalid_action_logged",invalid.size() == 2 and invalid[-1].selected_action == "unknown_fixture_action" and invalid[-1].status == "invalid_action")
		var failed := await compare("decision","B02",1,"failure")
		check("failed_request_logged",failed.size() == 2 and failed[-1].status == "request_failed" and not failed[-1].rejected_reason.is_empty())
		var stopped := await compare("dialogue","D04",1,"cancel")
		check("cancel_saved",stopped.size() == 2 and stopped[-1].status == "cancelled" and stopped[-1].attempts.size() == 1)
		lab.open_mode("dialogue")
		choose("D04")
		lab.question.text = "여기서 기다려."
		rows.clear()
		lab._start(false)
		await wait_batch()
		check("common_receipt_provenance",rows.size() == 2 and rows.all(func(r): return r.common_executor and r.generation_attempts == 0 and r.dialogue_method == "executor_receipt"))
		var all_cases := []
		for item in runner.factory.catalog.decision: all_cases.append({"item":item})
		lab.open_mode("decision")
		rows.clear()
		lab._launch(all_cases,1)
		await wait_batch()
		check("all_scenarios",rows.size() == 16 and rows.all(func(r): return r.snapshot_matches and r.appropriate and r.timely_valid))
		root.size = Vector2i(960,600)
		await frames()
		check("small_controls_fit",root.get_visible_rect().encloses(lab.stop_button.get_global_rect()) and root.get_visible_rect().encloses(lab.back.get_global_rect()))
		await capture("decision_small")
	for id in ["C01","C02","C03"]:
		var c := await compare("combat",id,1)
		check(id + "_replay",c.size() == 2 and c[0].fixture_hash == c[1].fixture_hash and c.all(func(r): return r.combat.outcome in ["survived","cleared","defeated"] and r.combat.duration_seconds > 0 and r.combat.events.size() > 0))
		if c.size() == 2:
			verify_export("combat",2)
			check(id + "_actual_support",c[0].combat.events.any(func(e): return e.event == "support_completed" and e.source == "RuleBased"))
			check(id + "_enemy_attack",c[0].combat.events.any(func(e): return e.event == "player_damage"))
		if id == "C01": await capture("combat")
	lab._back()
	lab._back()
	await frames()
	check("returned_to_title",title.get_node("Menu").visible and not title.has_node("ExperimentHub") and title.get_node("%ExperimentLab").has_focus())
	if not live:
		check("campaign_save_unchanged",not save_hash.is_empty() and FileAccess.get_sha256(save_path) == save_hash)
		title.get_node("%Continue").pressed.emit()
		title.get_node("%Slot1").pressed.emit()
		await frames()
		var mission = title.get_node("Main")
		check("continue_after_lab",mission.world.map_id == "supply_room" and mission.world.game_state().fuse_in_inventory)
		mission.title_requested.emit()
		await frames()
		title.get_node("%NewGame").pressed.emit()
		await frames()
		mission = title.get_node("Main")
		check("new_game_after_lab",mission.world.map_id == "corridor" and not mission.world.fuse_collected and mission.brain.history.is_empty())
		mission.title_requested.emit()
		await frames()
	var result := {"passed":not checks.values().has(false),"check_count":checks.size(),"checks":checks,"actual_inference":live,"gpu":render,"created_utc":Time.get_datetime_string_from_system(true),"sessions":test_sessions}
	var name := "live" if live else ("gpu" if render else "fixture")
	FileAccess.open(evidence.path_join(name + ".json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("EXPERIMENT_LAB_RESULT ",name," ",checks.size()," passed=",result.passed)
	quit(0 if result.passed else 1)
