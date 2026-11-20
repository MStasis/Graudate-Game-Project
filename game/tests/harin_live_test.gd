extends SceneTree
const BlackoutGoal := preload("res://tests/blackout_goal_check.gd")
var checks := {}
var samples: Array[Dictionary] = []
var measurements: Array[Dictionary] = []
var app: Control
var world: DemoWorld

func _initialize() -> void:
 call_deferred("run")

func check(label: String, value: bool) -> void:
 checks[label] = value
 if not value: push_error("HARIN_LIVE_FAILED " + label)

func wait_until(condition: Callable, seconds := 85.0) -> bool:
 var deadline := Time.get_ticks_msec() + int(seconds * 1000)
 while not condition.call() and Time.get_ticks_msec() < deadline:
  await create_timer(0.02).timeout
 return condition.call()

func ask(label: String, question: String, generated := true) -> String:
 var before := measurements.size()
 app.brain.request_dialogue(question)
 var finished := await wait_until(func(): return measurements.size() > before or app.brain.pending.is_empty())
 var record: Dictionary = measurements.back() if measurements.size() > before else {}
 var accepted: bool = finished and record.get("accepted", false) and record.get("actual_model") == (app.brain.local_dialogue.settings.model if generated else "common_executor")
 check(label + "_source_and_acceptance", accepted)
 var text: String = app.brain.history.back().answer if accepted else ""
 samples.append({"case": label, "question": question, "answer": text, "actual_model": record.get("actual_model"), "action_accepted": record.get("action_accepted"), "state": world.game_state()})
 print("HARIN_LIVE_SAMPLE ", JSON.stringify(samples.back()))
 return text

func run() -> void:
 app = load("res://main.tscn").instantiate()
 root.add_child(app)
 app.brain.new_trial(1)
 app.brain.auto_enabled = false
 world = app.world
 world.set_physics_process(false)
 for enemy in world.get_node("Enemies").get_children(): enemy.set_physics_process(false)
 app.brain.measured.connect(func(record): measurements.append(record.duplicate(true)))
 var text := await ask("meal_direct", "밥 먹었어?")
 check("meal_answers_whether_she_ate", not text.is_empty() and not "퓨즈" in text)
 text = await ask("preference_direct", "끝나면 뭐 먹고 싶어?")
 check("preference_answers_her_own_taste", not text.is_empty() and not NPCPolicy.has_word(text, ["퓨즈", "패널"]))
 text = await ask("preference_followup", "그 음식 원래 좋아했어?")
 check("casual_followup_remembers_food", not text.is_empty() and not "퓨즈" in text)
 text = await ask("meal_paraphrase", "아까 식사는 했니?")
 check("meal_paraphrase_consistent", not text.is_empty() and not "출발 전에 먹었" in text)
 text = await ask("anxious", "오늘 좀 긴장돼.")
 check("emotion_does_not_become_manual", not NPCPolicy.has_word(text, ["퓨즈", "패널", "보관함", "1초", "볶음밥", "먹었"]))
 world.trigger_blackout()
 text = await ask("mission", "지금 뭘 해야 해?")
 check("mission_answer_has_current_goal", BlackoutGoal.matches(text))
 text = await ask("panel_roles", "패널은 어떻게 나눠 맡아?")
 check("panel_has_two_roles", NPCPolicy.has_word(text, ["반대", "한쪽", "동시"]) or ("왼쪽" in text and "오른쪽" in text))
 text = await ask("panel_followup", "그럼 반대쪽은 네가 맡아?")
 check("mission_followup_understands_partner", NPCPolicy.has_word(text, ["내가", "나는", "반대", "한쪽"]) and not "뭐" in text)
 text = await ask("light_before", "손전등은 아직 네가 가지고 있어?")
 check("no_fake_handoff", NPCPolicy.has_word(text, ["내가", "내 손", "갖", "가지"]) and not "네가 주웠" in text)
 world.npc.position = world.player.position + Vector2(40, 0)
 world.request_flashlight()
 world.apply_interaction("flashlight")
 text = await ask("light_after", "그 손전등 지금 어디 있어?")
 check("latest_state_overrides_old_history", NPCPolicy.has_word(text, ["네가", "너한테", "네 손", "네게"]) and not NPCPolicy.has_word(text, ["바닥", "내가 갖", "내 손"]))
 text = await ask("taste_after_mission", "좋아하는 음식이 뭐야?")
 check("casual_returns_to_character_without_mission", not text.is_empty() and not NPCPolicy.has_word(text, ["퓨즈", "패널", "손전등"]))
 world.player_hp = 40
 world.npc.position = world.player.position + Vector2(180, 0)
 text = await ask("heal_order", "치료 좀 해줄래?", false)
 check("heal_ack_matches_started_not_completed", world.active_action == "heal" and world.player_hp == 40 and "갈게" in text)
 world.npc.position = world.player.position + Vector2(40, 0)
 world._finish_support()
 world.medkits = 0
 text = await ask("heal_no_supplies", "치료 부탁해", false)
 check("heal_refusal_no_resource_mutation", "다 떨어졌" in text and world.medkits == 0 and world.active_action.is_empty())
 await ask("wait_order", "여기서 기다려", false)
 text = await ask("wait_state", "내가 멀리 가도 여기서 대기하는 거지?")
 check("wait_answer_matches_actual_order", world.npc_motion.mode == "wait" and NPCPolicy.has_word(text, ["여기", "대기", "기다", "경계"]) and not "거지?" in text)
 await ask("follow_order", "따라와", false)
 check("follow_order_executes", world.npc_motion.mode == "follow")
 await test_live_emergency()
 await test_live_timeout_and_cancel()
 var directory := ProjectSettings.globalize_path("res://../evidence/harin_upgrade")
 DirAccess.make_dir_recursive_absolute(directory)
 var result := {"passed": not checks.values().has(false), "check_count": checks.size(), "checks": checks, "samples": samples, "measurements": measurements, "actual_inference": true, "actual_model": app.brain.local_dialogue.settings.model, "created_utc": Time.get_datetime_string_from_system(true), "human_playtest": false, "general_naturalness_proven": false}
 FileAccess.open(directory.path_join("live_%d.json" % OS.get_process_id()), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
 print("HARIN_LIVE_RESULT ", JSON.stringify({"passed": result.passed, "checks": checks, "check_count": checks.size()}))
 app.queue_free()
 await process_frame
 quit(0 if result.passed else 1)

func test_live_emergency() -> void:
 app.brain.new_trial(1)
 app.brain.auto_enabled = false
 world.flashlight_owned = true
 world.apply_interaction("storage_gate")
 world.player.position = Vector2(400, 330)
 world.npc.position = Vector2(360, 330)
 for enemy in world.get_node("Enemies").get_children():
  enemy.hp = 0
  enemy.active = false
 var enemy: MissionDrone = world.get_node("Enemies/DroneA")
 enemy.hp = enemy.max_hp
 enemy.position = Vector2(480, 330)
 world._sync_state()
 world.player_hp = 20
 world.npc_ammo = 0
 world.npc_reserve = 7
 var shots := []
 world.game_event.connect(func(event):
  if event.event == "npc_shot": shots.append(event))
 app.brain.request_dialogue("밥 먹었어? 오늘 무슨 음식이 생각나?")
 check("real_dialogue_transport_pending", app.brain.local_dialogue.busy and not app.brain.dialogue_pending.is_empty())
 app.brain.auto_enabled = true
 world.set_physics_process(true)
 var before := world.player.position
 Input.action_press("move_right")
 await create_timer(0.22).timeout
 Input.action_release("move_right")
 check("real_emergency_while_generation_is_pending", world.active_action == "heal" or world.player_hp > 20)
 check("player_movement_continues_during_live_generation", world.player.position.x > before.x + 10)
 await wait_until(func(): return world.player_hp > 20 and world.npc_ammo > 0 and not shots.is_empty(), 8)
 check("live_emergency_effect_and_reload_fire_continue", world.player_hp >= 55 and world.medkits == 1 and not shots.is_empty())
 await wait_until(func(): return app.brain.pending.is_empty())
 app.brain.auto_enabled = false
 world.set_physics_process(false)

func test_live_timeout_and_cancel() -> void:
 app.brain.cancel_pending("test_prepare")
 var before: int = app.brain.history.size()
 var timeout_seconds: float = app.brain.local_dialogue.settings.timeout_seconds
 app.brain.local_dialogue.settings.timeout_seconds = 0.01
 app.brain.request_dialogue("오늘 무슨 생각을 해?")
 await wait_until(func(): return app.brain.pending.is_empty(), 3)
 check("real_timeout_keeps_failure_without_template_success", app.brain.history.size() == before and not app.brain.local_dialogue.busy and app._radio_error)
 app.brain.local_dialogue.settings.timeout_seconds = timeout_seconds
 app.brain.request_dialogue("오늘 무슨 생각을 해?")
 await process_frame
 var old_id: int = app.brain.pending.get("request_id", -1)
 app.brain.cancel_channel("dialogue", "live_cancel_probe")
 check("real_cancel_closes_only_requested_stream", not app.brain.local_dialogue.busy and app.brain.dialogue_pending.is_empty() and app.brain.history.size() == before)
 var text := await ask("after_cancel", "뭐 먹고 싶어?")
 check("new_request_after_cancel_keeps_identity", not text.is_empty() and int(measurements.back().request_id) > old_id)
