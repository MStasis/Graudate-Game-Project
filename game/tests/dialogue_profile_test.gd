extends SceneTree

const Hub = preload("res://scripts/experiments/experiment_hub.gd")
var lab: Hub
var live := false
var gpu := false
var checks := {}
var sessions := []
var evidence := ProjectSettings.globalize_path("res://../evidence/dialogue_profiles")

func _initialize() -> void:
	run.call_deferred()

func check(id: String, result: bool) -> void:
	checks[id] = result
	if not result: push_error("PROFILE_FAILED " + id)

func capture(name_: String) -> void:
	if not gpu: return
	# Nested containers settle their minimum sizes over idle frames when the page changes.
	for frame in 4: await process_frame
	RenderingServer.force_draw.call_deferred(false)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	print("PROFILE_CAPTURE ", name_, " window=", root.size, " texture=", img.get_size())
	check("render_" + name_, img.get_size() == root.size and img.save_png(evidence.path_join(name_ + ".png")) == OK)

func batch(cases: Array, profiles: Array, test := "") -> Array:
	var runner := lab.runner
	check("start_" + test,runner.start("dialogue",cases,1,profiles))
	var deadline := Time.get_ticks_msec() + 210000 * cases.size() * profiles.size()
	while runner.running and Time.get_ticks_msec() < deadline:
		if not live and not runner.current.is_empty():
			if runner.phase == "readiness": runner.phase = "request"
			if runner.phase == "request": runner._request()
			var client := runner.brain.local_dialogue
			if client.busy:
				client.set_process(false)
				var id := client.settings.dialogue_profile
				if client.settings.effective_thinking(): client._consume_event('{"message":{"thinking":"fixture"},"done":false}')
				elif id != "D":
					client._consume_event('{"response":"private fixture</thi","done":false}')
					if test != "length": client._consume_event('{"response":"nk>  ","done":false}')
				var answer := "통신도 복구됐어." if runner.brain.dialogue_pending.get("retry",0) == 0 else "전기실로 가자."
				if test == "speaker" and runner.brain.dialogue_pending.get("retry",0) == 0:
					answer = "미카 클라비스가 동료에게 말하는 한국어 반말 한두 마디: '이제 어디로 가?'."
				if id == "D": answer = JSON.stringify({"dialogue":answer})
				if test == "malformed": answer = '{"dialogue":'
				if test == "empty" or test == "length": answer = ""
				client._consume_event(JSON.stringify({"response":answer,"model":"fixture","done":true,
					"done_reason":"length" if test == "length" else "stop","prompt_eval_count":126,"eval_count":256}))
		await process_frame
	check("finished_" + test,not runner.running)
	if runner.running: runner.stop("test_deadline")
	await process_frame
	var rows := runner.store.results(runner.session)
	var exported := runner.store.export_csv(runner.session)
	sessions.append({"name":test,"id":runner.session,"csv":exported})
	if gpu:
		var csv := FileAccess.open(exported, FileAccess.READ)
		csv.get_buffer(3)
		var header := csv.get_csv_line()
		var matches := true
		for row in rows:
			var cells := csv.get_csv_line()
			var shown := cells[header.find("screen_display_ms")]
			matches = matches and cells[header.find("experiment_id")] == row.experiment_id
			if row.accepted: matches = matches and row.screen_display_ms != null and not shown.is_empty() and is_equal_approx(float(shown),float(row.screen_display_ms))
			else: matches = matches and shown.is_empty()
		check("drawn_before_csv_" + test, matches)
	for row in rows:
		print("PROFILE_ROW ",test," ",row.profile_id," ",row.scenario_id," ",row.status," ",row.elapsed_ms)
	return rows

func entry(id: String, q: String) -> Dictionary:
	return {"item":lab.runner.factory.find_scenario(id),"question":q}

func run() -> void:
	live = "--profiles-live" in OS.get_cmdline_user_args()
	gpu = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(evidence)
	lab = load("res://scenes/experiments/ExperimentHub.tscn").instantiate()
	root.add_child(lab)
	await process_frame
	lab.runner.store.run_kind = "development_live" if live else "development_fixture"
	lab.open_mode("profiles")
	check("independent_directory",lab.runner.store.directory().begins_with("user://dialogue_optimization/"))
	check("default_group",lab.profile_picker.get_item_text(0) == "A·B·C 교차 비교")
	var mission := entry("D04","이제 어디로 가?")
	var rest := entry("D01","미카, 오늘 좀 피곤해.")
	var dinner := entry("D01","저녁 뭐 먹을래?")
	if live and "--profiles-followup" in OS.get_cmdline_user_args():
		var transport := await batch([mission,rest,dinner],["C_ON","C_FAST"],"transport")
		check("transport_only_difference",transport.size() == 6 and transport.all(func(r): return r.model_thinking and r.model_options == transport[0].model_options and r.prompt_version == MikaDialogue.CHARACTER_PROMPT_VERSION and r.snapshot_matches))
		for index in [0,2,4]:
			check("same_transport_prompt_" + str(index),transport[index].attempts[0].chat_messages == transport[index+1].attempts[0].chat_messages)
		var focused := await batch([mission,rest,dinner,entry("D02","퓨즈는 어디에 있어?"),entry("D08","레버는 언제 당겨?")],["D"],"structured")
		check("structured_transport",focused.size() == 5 and focused.all(func(r): return r.snapshot_matches and r.rating == null and r.prompt_version == MikaDialogue.STRUCTURED_PROMPT_VERSION and not r.attempts.is_empty() and r.attempts[0].metrics.has("eval_count")))
		await capture("structured")
		finish_report("followup")
		return
	var cases := [mission,rest,dinner] if live else [mission]
	var rows := await batch(cases,["A","B","C"],"abc")
	check("matched_states",rows.size() == cases.size()*3 and rows.all(func(r): return r.snapshot_matches and r.rating == null and r.profile_version == LocalNPCSettings.PROFILE_VERSION))
	var a: Dictionary = rows[0]
	var b: Dictionary = rows[1]
	var c: Dictionary = rows[2]
	check("same_question_and_world",a.question == c.question and a.fixture_hash == b.fixture_hash and b.fixture_hash == c.fixture_hash)
	check("controlled_profiles",a.model_thinking and not b.model_thinking and not c.model_thinking and a.model_options.num_predict == 4096 and b.model_options.num_predict == 256 and b.model_options == c.model_options and a.prompt_version == b.prompt_version and a.prompt_version != c.prompt_version)
	check("original_messages_identical",not a.attempts.is_empty() and not b.attempts.is_empty() and a.attempts[0].chat_messages == b.attempts[0].chat_messages)
	if live:
		check("actual_server_counts",rows.all(func(r): return r.attempts.size() > 0 and r.attempts[0].metrics.has("eval_count")))
		await batch([mission,rest,dinner],["D"],"short_json")
		await batch([mission],["B512","C512","C4096"],"capacity")
		await batch([mission,rest,dinner],["C","A","B"],"repeat")
		await batch([entry("D02","퓨즈는 어디에 있어?"),entry("D08","레버는 언제 당겨?")],["D"],"facts")
		await batch([mission,rest,dinner],["C_ON","C_FAST"],"voice_only")
	else:
		check("retry_timing_and_first_issue",rows.all(func(r): return r.accepted and r.regeneration_count == 1 and r.first_validation_error != null and r.final_attempt_first_dialogue_ms >= r.first_dialogue_ms and r.elapsed_ms >= r.final_attempt_first_dialogue_ms))
		check("split_marker_isolated",b.response_text == "전기실로 가자." and b.attempts[0].thinking_character_count > 0 and b.attempts[0].response.strip_edges() == "통신도 복구됐어.")
		var variants := await batch([mission],["B512","C512","C4096","D","C_ON"],"variants")
		check("variant_options",variants[0].model_options.num_predict == 512 and variants[1].model_options.num_predict == 512 and variants[2].model_options.num_ctx == 4096 and variants[3].response_text == "전기실로 가자.")
		check("voice_only_options",variants[4].model_options == a.model_options and variants[4].model_thinking and variants[4].prompt_version == c.prompt_version and variants[4].accepted)
		var failed := await batch([mission],["C"],"length")
		check("length_fails_with_server_metrics",failed[0].status == "request_failed" and failed[0].first_dialogue_ms == null and failed[0].attempts[0].metrics.eval_count == 256 and failed[0].response_text == null)
		failed = await batch([mission],["A"],"empty")
		check("empty_fails",not failed[0].accepted and failed[0].display_ready_ms == null)
		var labeled := await batch([mission],["D"],"speaker")
		check("speaker_annotation_regenerates",labeled[0].accepted and labeled[0].first_validation_error == "speaker_annotation" and labeled[0].regeneration_count == 1)
		failed = await batch([mission],["D"],"malformed")
		check("malformed_is_failure",not failed[0].accepted and failed[0].response_text == null and failed[0].attempts[0].wire_content == '{"dialogue":')
		var state := lab.runner.world.game_state()
		var casual := MikaDialogue.build_character(state,rest.question,[])
		check("casual_no_mission",not casual.system.contains("퓨즈") and not casual.system.contains("현재 게임 사실") and casual.messages.back().content == rest.question)
		check("combat_options",lab.runner.brain.local_decision.settings.max_tokens == 48 and not lab.runner.brain.local_decision.settings.thinking and is_equal_approx(lab.runner.brain.local_decision.settings.temperature,0.1) and lab.runner.brain.settings.max_decision_age == 3)
	await capture("comparison")
	lab.open_mode("profile_records")
	for i in lab.session_picker.item_count:
		if lab.session_picker.get_item_text(i) == a.session_id:
			lab.session_picker.select(i)
			lab._load_session(i)
			break
	for i in lab.history_rows.size():
		if lab.history_rows[i].experiment_id != a.experiment_id: continue
		lab.row_picker.select(i)
		lab._show_record(i)
		if a.accepted:
			check("blind_before_rating",lab.scores.size() == 4 and lab.details.find_children("*","Label",true,false).all(func(l): return not l.text.contains("프로필") and not l.text.contains(" ms")))
			await capture("blind")
			check("screen_or_headless",lab.history_rows[i].screen_display_ms >= a.elapsed_ms if gpu else lab.history_rows[i].screen_display_ms == null)
			if not live:
				for picker in lab.scores: picker.select(1)
				lab._save_rating(i)
				var rated: Array = lab.runner.store.results(a.session_id).filter(func(r): return r.experiment_id == a.experiment_id)
				check("explicit_zero_and_reveal",rated[0].rating.total == 0 and lab.details.find_children("*","Label",true,false).any(func(l): return l.text.begins_with("프로필 A")))
		break
	lab.open_mode("home")
	check("ordinary_store_restored",lab.runner.store.directory().begins_with("user://experiments/"))
	if not live:
		var mission_ui = load("res://main.tscn").instantiate()
		var dialogue: LocalAIClient = mission_ui.get_node("NPCBrain/LocalDialogue")
		dialogue.settings = dialogue.settings.duplicate(true)
		dialogue.settings.campaign_dialogue_profile = "D"
		root.add_child(mission_ui)
		check("campaign_dialogue_opt_in",mission_ui.brain.local_dialogue.settings.dialogue_profile == "D" and not mission_ui.brain.local_dialogue.settings.thinking)
		check("campaign_tactics_unaffected",mission_ui.brain.local_decision.settings.max_tokens == 48 and mission_ui.brain.local_decision.settings.dialogue_profile == "A" and mission_ui.brain.settings.max_decision_age == 3)
		mission_ui.queue_free()
		await process_frame
	finish_report("live" if live else "fixture")

func finish_report(name_: String) -> void:
	var passed := not checks.values().has(false)
	var file := FileAccess.open(evidence.path_join(name_ + ("_gpu" if gpu else "") + ".json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"checks":checks,"sessions":sessions,"live":live,"gpu":gpu}, "\t"))
	file.close()
	print("PROFILE_CHECKS ",checks.size()," passed=",passed)
	quit(0 if passed else 1)
