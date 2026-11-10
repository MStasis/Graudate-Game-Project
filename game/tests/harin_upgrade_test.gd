extends SceneTree
var checks := {}
var app: Control
var world: DemoWorld
var rendered := false
var directory := ""

func _initialize() -> void:
 call_deferred("run")

func check(label: String, value: bool) -> void:
 checks[label] = value
 if not value: push_error("HARIN_FAILED " + label)

func run() -> void:
 rendered = "--render-harin" in OS.get_cmdline_user_args()
 directory = ProjectSettings.globalize_path("res://../evidence/harin_upgrade")
 DirAccess.make_dir_recursive_absolute(directory)
 app = load("res://main.tscn").instantiate()
 root.add_child(app)
 world = app.world
 app.brain.auto_enabled = false
 world.set_physics_process(false)
 for enemy in world.get_node("Enemies").get_children(): enemy.set_physics_process(false)
 test_context()
 test_orders()
 test_execution_and_requests()
 test_speech_priority()
 await test_navigation()
 await test_resources_and_progression()
 await test_recovery_mission()
 await test_visuals()
 var result := {"passed": not checks.values().has(false), "check_count": checks.size(), "checks": checks, "created_utc": Time.get_datetime_string_from_system(true), "human_playtest": false, "gpu_rendered": rendered}
 FileAccess.open(directory.path_join("render.json" if rendered else "test.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
 print("HARIN_RESULT ", JSON.stringify(result))
 app.queue_free()
 await process_frame
 quit(0 if result.passed else 1)

func test_context() -> void:
 var state := world.game_state()
 var casual := HarinDialogue.build(state, "밥 먹었어?", [], "첫 문장. 두 번째 역할 설명.", "")
 check("no_answer_template_in_casual", not "대화 방향" in casual.prompt and not "대답의 의미 기준" in casual.prompt)
 check("whole_persona_preserved", "두 번째 역할 설명" in casual.prompt)
 var preference := HarinDialogue.build(state, "뭐 먹고 싶어?", [], "", "")
 check("editable_character_has_food_and_meal_background", "미확정" in preference.prompt and not "ate_before_departure" in casual.prompt)
 var turns := [{"question": "패널은 어떻게 눌러?", "answer": "너는 한쪽, 나는 반대쪽이야."}]
 var followup := HarinDialogue.build(state, "그럼 반대쪽은 네가 맡아?", turns, "", "")
 check("mission_followup_inherits_history_and_roles", "너는 한쪽" in followup.prompt and "역할" in followup.prompt)
 state.flashlight_owned = true
 var current := HarinDialogue.build(state, "손전등 어디 있어?", [{"question": "손전등 어디 있어?", "answer": "바닥에 있어."}], "", "")
 check("old_memory_separate_from_current_facts", "바닥에 있어" in current.prompt and "네가 소지 중" in current.prompt and "최신 사실" in current.system)
 var large := []
 for index in range(40): large.append({"question": "임무?".repeat(80), "answer": "답변".repeat(300)})
 var bounded := HarinDialogue.recent_history(large, false)
 check("history_has_bounded_char_budget", JSON.stringify(bounded).length() < 1600 and bounded.size() <= HarinDialogue.HISTORY_LIMIT)
 check("food_rules_answer_first", not "출발 전에 먹었어" in NPCPolicy.template_response("everyday", state, "밥 먹었어?"))
 check("preference_rules_answer_self", not "김치볶음밥" in NPCPolicy.template_response("everyday", state, "뭐 먹고 싶어?"))

func test_orders() -> void:
 world.player.position = Vector2(550, 330)
 world.npc.position = Vector2(400, 280)
 world.npc_motion.reset()
 var first := world.npc_motion.formation_target(world, 0.016)
 world.npc_motion.elapsed = 50
 check("formation_stable_across_time", first == world.npc_motion.formation_target(world, 0.016))
 check("wait_order_accepted", world.request_support("wait"))
 var anchor := world.npc.position
 world.player.position += Vector2(120, 0)
 check("wait_does_not_follow_player", world.npc_motion.formation_target(world, 1) == anchor)
 world.request_support("follow", {"provider": "LocalLLM"})
 check("automatic_tactic_cannot_override_wait", world.npc_motion.mode == "wait")
 world.request_support("follow")
 check("explicit_follow_releases_wait", world.npc_motion.mode == "follow" and world.npc_motion.formation_target(world, 1) != anchor)
 world.npc_motion.reset()
 world.npc_motion.move_to(world, world.npc.position + Vector2(5, 0), 0.016)
 check("arrival_stops_small_adjustments", world.npc_motion.arrived and world.npc_motion.velocity == Vector2.ZERO)

func fake_job(kind: String, request_id: int) -> Dictionary:
 var state := world.game_state()
 return {"kind": kind, "request_id": request_id, "question": "손전등 어디 있어?", "epoch": world.epoch, "snapshot": state, "snapshot_hash": "test", "allowed": state.valid_actions if kind == "decision" else NPCPolicy.INTENTS.keys(), "started_usec": Time.get_ticks_usec()}

func test_execution_and_requests() -> void:
 app.reset_demo(0)
 app.brain.auto_enabled = false
 world.player_hp = 40
 world.npc.position = world.player.position + Vector2(180, 0)
 var hp := world.player_hp
 app.brain.request_dialogue("치료해줘")
 check("clear_heal_request_runs_executor_before_reply", world.active_action == "heal" and "갈게" in app.answer.text and world.player_hp == hp and world.medkits == 2)
 world.npc.position = world.player.position + Vector2(40, 0)
 world._finish_support()
 check("heal_effect_only_on_completion", world.player_hp == hp + world.heal_amount and world.medkits == 1)
 world.active_action = ""
 world.medkits = 0
 app.brain.request_dialogue("치료 좀 해줄래?")
 check("no_kit_rejected_honestly", world.active_action.is_empty() and "다 떨어졌" in app.answer.text)
 app.brain.request_dialogue("여기서 기다려")
 check("wait_language_sets_real_mode", world.npc_motion.mode == "wait")
 app.brain.request_dialogue("따라와")
 check("follow_language_releases_wait", world.npc_motion.mode == "follow")
 app.brain.request_dialogue("패널 같이 누르자")
 check("words_cannot_open_or_start_unheld_panel", not world.locker.opened and world.active_action.is_empty() and "먼저" in app.answer.text)
 app.brain.request_dialogue("도와줘")
 check("ambiguous_request_clarifies_without_execution", world.active_action.is_empty() and "아니면" in app.answer.text)
 check("negative_request_not_executed", NPCPolicy.requested_action("치료하지 마") == "")
 check("negated_and_quoted_movement_not_executed", NPCPolicy.requested_action("따라오지 마") == "" and NPCPolicy.requested_action("따라와 라고 말하면 어떻게 돼?") == "")
 world.flashlight_requested = true
 world.request_player_order("wait")
 check("wait_cancels_nonurgent_flashlight_delivery", not world.flashlight_requested and world.npc_motion.mode == "wait")
 world.request_player_order("follow")
 var unsupported := world.request_player_order("unsupported")
 check("unsupported_action_has_no_execution_promise", not unsupported.accepted and unsupported.status == "unsupported" and world.active_action.is_empty())
 world.medkits = 2
 world.heal_cd = 0
 world.player_hp = 20
 app.brain.pending = fake_job("dialogue", 900)
 app.brain.auto_enabled = true
 app.brain._process(0.016)
 check("emergency_during_dialogue_without_second_inference", world.active_action == "heal" and not app.brain.dialogue_pending.is_empty() and app.brain.tactical_pending.is_empty())
 app.brain.auto_enabled = false
 app.brain.cancel_pending("test_cancel")
 app.brain.pending = fake_job("dialogue", 901)
 app.brain._local_completed({"state": {"_channel": "dialogue", "_request_id": 900}, "response": "{\"dialogue\":\"늦은 답변\"}"})
 check("old_request_id_cannot_complete_new_job", app.brain.dialogue_pending.get("request_id") == 901)
 app.brain.cancel_channel("decision", "test_unrelated_cancel")
 check("tactical_cancel_does_not_cancel_dialogue", not app.brain.dialogue_pending.is_empty())
 app.brain.cancel_pending("test_cleanup")
 check("both_channels_clear_on_load_or_reset", app.brain.dialogue_pending.is_empty() and app.brain.tactical_pending.is_empty())
 world.active_action = ""

func test_speech_priority() -> void:
 var hud: CombatInterface = app.combat_hud
 hud.clear_speech()
 hud.speak("하린", "질문에 대한 답변", 60)
 hud.speak("하린", "자동 잡담", 10)
 check("automatic_line_cannot_replace_answer", hud.npc_bubble.full_text == "질문에 대한 답변" and hud.speech_queue.size() == 1)
 hud.speak("하린", "긴급 경고", 100)
 check("urgent_line_preempts_answer", hud.npc_bubble.full_text == "긴급 경고")
 world.epoch += 1
 hud.npc_bubble.remaining = 0
 hud.update_view(0)
 check("queued_old_map_speech_discarded", hud.speech_queue.is_empty() and hud.npc_bubble.full_text != "자동 잡담")
 hud.clear_speech()
 hud.speak("하린", "내가 갈게.", 100, "heal_started")
 hud.speak("하린", "치료 완료.", 30, "heal_done")
 check("completion_replaces_its_own_approach_line", hud.npc_bubble.full_text == "치료 완료." and hud.speech_priority == 30)
 hud.clear_speech()
 hud.speak("하린", "긴급 경고", 100)
 app.brain.dialogue_grounding = {"question": "손전등 어디 있어?", "topic": "mission", "facts": HarinDialogue.facts(world.game_state(), "손전등 어디 있어?", "mission")}
 hud.speak("하린", "손전등은 내 손에 있어.", 60, "answer")
 world.flashlight_owned = true
 hud.npc_bubble.remaining = 0
 hud.update_view(0)
 check("queued_answer_rechecks_current_facts_without_epoch_change", hud.npc_bubble.full_text != "손전등은 내 손에 있어." and hud.speech_queue.is_empty())

func test_navigation() -> void:
 world.reset_world()
 world.flashlight_owned = true
 world.apply_interaction("storage_gate")
 world.npc.position = Vector2(570, 190)
 world.npc_motion.reset()
 world.npc_navigation.reset()
 await physics_frame
 var goal := Vector2(740, 190)
 var deviated := false
 var inside := false
 var pipe := Rect2(Vector2(624, 94), Vector2(57, 152))
 for index in range(300):
  await physics_frame
  world.npc_motion.move_to(world, goal, 1.0 / 60, 8, true)
  deviated = deviated or world.npc.position.y > 260 or world.npc.position.y < 78
  inside = inside or pipe.grow(10).has_point(world.npc.position)
  if world.npc.position.distance_to(goal) < 22: break
 check("npc_is_collision_body_with_interaction_area", world.npc is CharacterBody2D and world.npc.get_node("Interaction") is Area2D and world.npc.collision_mask == 5)
 check("navigation_routes_around_pipe", deviated and not inside and world.npc.position.distance_to(goal) < 24)
 check("navigation_replans_and_respects_obstacle_destination", world.npc_navigation.replans > 1)
 var start := world.npc.position
 world.npc_motion.reset()
 for index in range(45):
  await physics_frame
  world.npc_motion.move_to(world, Vector2(650, 170), 1.0 / 60, 8, true)
 check("blocked_destination_never_enters_furniture", not pipe.grow(10).has_point(world.npc.position) and world.npc.position != start)
 world._change_map("lab", Vector2(300, 350))
 world.npc_navigation.plan(world, Vector2(650, 190))
 check("map_change_rebuilds_navigation", world.npc_navigation.map_key == "lab")
 var barrier := RoundedObstacle.new()
 barrier.position = Vector2(800, 279)
 barrier.footprint = Vector2(40, 430)
 world.add_child(barrier)
 await physics_frame
 world.npc.position = Vector2(740, 300)
 world.npc_navigation.reset()
 world.npc_navigation.plan(world, Vector2(930, 300))
 check("unreachable_goal_reported_without_teleport", not world.npc_navigation.reachable and world.npc.position == Vector2(740, 300))
 barrier.position.x = 400
 world.npc_motion.reset()
 for index in range(100):
  await physics_frame
  world.npc_motion.move_to(world, Vector2(930, 300), 1.0 / 60, 8, true)
 check("terrain_change_is_replanned_after_block", world.npc.position.x > 830 and world.npc_navigation.reachable)
 barrier.queue_free()
 world.npc_motion.order("wait", world.npc.position)
 var anchor := world.npc.position
 for index in range(50):
  await physics_frame
  world.player.position += Vector2(1, 0)
  world.npc_motion.move_to(world, world.npc_motion.formation_target(world, 1.0 / 60), 1.0 / 60)
 check("wait_holds_position_over_physics_frames", world.npc.position.distance_to(anchor) < 2)

func test_resources_and_progression() -> void:
 app.reset_demo(0)
 app.brain.auto_enabled = false
 app.save_store.directory = "user://harin_upgrade_%d" % OS.get_process_id()
 world.flashlight_owned = true
 world.apply_interaction("storage_gate")
 world.npc_ammo = 0
 world.npc_reserve = 7
 world._npc_reload(0.01)
 check("empty_magazine_starts_timed_reload", world.npc_reload_time > 0 and world.npc_ammo == 0 and world.npc_reserve == 7)
 world._npc_reload(world.npc_reload_seconds + 0.1)
 check("reload_conserves_rounds_and_partial_reserve", world.npc_ammo == 7 and world.npc_reserve == 0)
 world.npc_ammo = 0
 var packs := world.supply_packs
 world._npc_reload(0.01)
 check("empty_reserve_consumes_shared_supply_pack", world.supply_packs == packs - 1 and world.npc_reserve == world.resupply_amount and world.npc_ammo == 0)
 world._npc_reload(world.npc_reload_seconds + 0.1)
 check("supply_reload_completes_without_free_ammo", world.npc_ammo == world.resupply_amount and world.npc_reserve == 0)
 world.npc_ammo = 0
 world.active_action = "resupply"
 var reserved_packs := world.supply_packs
 world._npc_reload(0.01)
 check("npc_reload_does_not_steal_pending_player_supply", world.supply_packs == reserved_packs and world.npc_reload_time == 0)
 world.active_action = ""
 world.npc_ammo = 0
 world.supply_packs = 0
 world.ammo = world.max_ammo
 world.apply_interaction("cache")
 check("cache_recovers_companion_even_when_player_full", world.cache_used and world.npc_reserve == 20)
 world._npc_reload(0.01)
 world.npc_motion.order("wait", world.npc.position)
 for index in range(8): app.brain.history.append({"question": "문답 %d" % index, "answer": "응"})
 check("save_accepts_eight_turn_memory", app.save_slot(1))
 var saved := world.save_snapshot()
 world.npc_reserve = 0
 world.npc_reload_time = 0
 world.npc_motion.order("follow", world.npc.position)
 check("load_restores_reload_wait_and_history", app.load_slot(1) and world.npc_reserve == saved.npc_reserve and world.npc_reload_time == saved.npc_reload_time and world.npc_motion.mode == "wait" and app.brain.history.size() == 8)
 var legacy: Dictionary = app.save_store.read_slot(1)
 var scenario := world.scenario_configuration()
 scenario.erase("companion_rules")
 legacy.scenario = JSON.stringify(scenario).sha256_text()
 for key in ["npc_reserve", "npc_reload_time", "companion_mode", "wait_position", "completed_support"]: legacy.world.erase(key)
 app.save_store.write_slot(2, legacy)
 var old_hash := FileAccess.get_sha256(app.save_store.path_for(2))
 check("old_v2_save_loads_without_file_rewrite", app.load_slot(2) and FileAccess.get_sha256(app.save_store.path_for(2)) == old_hash and world.npc_reserve == world.npc_initial_reserve)
 world.medkits = 1
 world.player.position = Vector2(300, 330)
 world.npc.position = world.player.position + Vector2(45, 0)
 world.take_npc_damage(1000)
 check("downed_npc_has_recovery_guidance", not world.defeated and "소생" in world.current_guidance() and not world.locker.opened)
 check("actual_down_event_updates_visible_pose", world.npc.pose == "down")
 app.interact("npc")
 check("real_interaction_revives_with_one_kit", world.npc_hp == 35 and world.medkits == 0 and not world.defeated)
 check("revive_does_not_bypass_locker", not world.locker.opened and world.locker.progress == 0)
 world.take_npc_damage(1000)
 check("no_revive_resources_causes_explicit_failure", world.defeated and world.npc_hp == 0 and world.player_hp > 0 and not world.player.movement_enabled)
 app.reset_demo(0)
 app.brain.auto_enabled = false
 check("retry_restores_companion_and_resources", not world.defeated and world.npc_hp == world.npc_max_hp and world.npc_reserve == world.npc_initial_reserve and world.medkits == world.initial_medkits)
 check("unsupported_completed_claim_is_rejected", not HarinDialogue.claims_valid("치료했어. 탄약도 채워줬어.", world.game_state()))
 var job := fake_job("dialogue", 950)
 app.brain.provider = 1
 app.brain.pending = job
 var records := []
 app.brain.measured.connect(func(record): records.append(record))
 world.flashlight_dropped = true
 app.brain._resolve("내 손에 있어.", {"actual_model": "synthetic_stale_fact"})
 check("changed_live_facts_reject_generated_answer", not records.is_empty() and records.back().rejected_reason == "stale_facts" and not records.back().accepted)
 app.brain.provider = 0
 world.flashlight_owned = true
 world.apply_interaction("storage_gate")
 world.ammo = 0
 world.npc_ammo = 0
 world.npc_reserve = 0
 world.supply_packs = 0
 world.cache_used = true
 world._physics_process(0.016)
 check("unrecoverable_total_ammo_exhaustion_is_explicit_failure", world.defeated and world.player_hp > 0)

func test_recovery_mission() -> void:
 world.reset_world()
 app.brain.auto_enabled = false
 world.npc.position = world.player.position + Vector2(40, 0)
 world.request_flashlight()
 world.apply_interaction("flashlight")
 world.apply_interaction("storage_gate")
 world.npc.position = world.player.position + Vector2(40, 0)
 world.take_npc_damage(1000)
 world.apply_interaction("revive_npc")
 for enemy in world.get_node("Enemies").get_children():
  enemy.hp = 0 # 전투는 기존 실탄환 통합 검사에서 검증. 여기서는 소생 이후 기믹 경로를 격리한다.
  enemy.active = false
 world._sync_state()
 world.player.position = world.locker.panel_position(0) + Vector2(0, 35)
 world.npc.position = Vector2(640, 300)
 world.npc_motion.reset()
 Input.action_press("interact")
 world.apply_interaction("panel_a")
 var receipt := world.request_player_order("assist_panel")
 check("revived_npc_accepts_real_panel_support", receipt.accepted and world.active_action == "assist_panel" and not world.locker.opened)
 world.set_physics_process(true)
 var deadline := Time.get_ticks_msec() + 10000
 while not world.locker.opened and Time.get_ticks_msec() < deadline: await create_timer(0.02).timeout
 Input.action_release("interact")
 world.set_physics_process(false)
 check("revived_npc_completes_actual_hold_and_beeps", world.locker.opened and world.locker.progress >= world.locker.hold_seconds and world.locker.beep_index == 6)
 world.apply_interaction("fuse")
 world.apply_interaction("lab_gate")
 world.apply_interaction("generator")
 world.apply_interaction("exit")
 check("recovery_route_can_finish_existing_mission", world.map_id == "main_entry" and world.story.tutorial_completed and not world.finished and not world.defeated and world.npc_hp == 35)

func test_visuals() -> void:
 world.reset_world()
 app.combat_hud.clear_speech()
 app._radio_error = false
 app.close_dialogue()
 world.npc.position = Vector2(500, 330)
 world.player.position = Vector2(400, 330)
 var seen := {}
 for pose in ["idle", "move", "aim", "support", "wait", "reload", "down"]:
  world.npc.show_pose(pose, world.npc.position + Vector2(80, -10))
  check("visible_pose_" + pose, pose == world.npc.pose and world.npc.get_node("NameLabel").text.contains("·"))
  if rendered:
   await process_frame
   await RenderingServer.frame_post_draw
   var picture := root.get_texture().get_image()
   picture.save_png(directory.path_join("pose_" + pose + ".png"))
   var point: Vector2 = app.combat_hud.screen_point(world.npc)
   var crop := picture.get_region(Rect2i(Vector2i(point) - Vector2i(40, 40), Vector2i(80, 80)))
   seen[pose] = crop.get_data().hex_encode().sha256_text()
 if rendered: check("gpu_support_and_down_are_visually_distinct", seen.support != seen.aim and seen.down != seen.idle and seen.wait != seen.idle and seen.move != seen.idle and seen.aim != seen.idle)

