extends SceneTree
var checks := {}
var app: Control
var world: DemoWorld
var hud: CombatInterface
var directory := ""
var rendered := false

func _initialize() -> void:
 call_deferred("run")

func check(label: String, value: bool) -> void:
 checks[label] = value
 if not value: push_error("STORY_UI_FAILED " + label)

func frames(count := 4) -> void:
 for index in range(count): await process_frame

func key(code: int) -> void:
 var event := InputEventKey.new()
 event.keycode = code
 event.pressed = true
 root.push_input(event, true)
 await frames()

func capture(stem: String) -> void:
 if not rendered: return
 await RenderingServer.frame_post_draw
 var image := root.get_texture().get_image()
 check(stem + "_actual_pixels", image.get_width() > 0 and not image.is_invisible())
 image.save_png(directory.path_join(stem + ".png"))

func run() -> void:
 rendered = "--render-story-ui" in OS.get_cmdline_user_args()
 directory = ProjectSettings.globalize_path("res://../evidence/story_ui")
 DirAccess.make_dir_recursive_absolute(directory)
 root.size = Vector2i(1280, 800)
 app = load("res://main.tscn").instantiate()
 root.add_child(app)
 world = app.world
 hud = app.combat_hud
 app.brain.auto_enabled = false
 world.set_physics_process(false)
 for enemy in world.get_node("Enemies").get_children(): enemy.set_physics_process(false)
 app.save_store.directory = "user://story_ui_%d" % OS.get_process_id()
 await frames()
 app.close_dialogue()
 check("starts_on_familiar_security_shift", world.story.stage == "on_shift" and "보안 직원" in MikaDialogue.CHARACTER.identity)
 await capture("01_before_blackout")
 world.trigger_blackout()
 check("blackout_has_actual_lighting_and_event", world.get_node("Darkness").material.get_shader_parameter("ambient_enabled") == false and "blackout" in world.story.events and not world.power_restored)
 var before_light := MikaDialogue.facts(world.game_state(), "지금 뭘 해야 해?", "mission")
 world.story.elapsed += 3.0
 check("story_clock_alone_does_not_invalidate_reply", before_light == MikaDialogue.facts(world.game_state(), "지금 뭘 해야 해?", "mission"))
 check("early_goal_is_equipment", "손전등" in JSON.stringify(before_light))
 var unchanged := world.ammo
 world.apply_interaction("storage_gate")
 check("gate_keeps_flashlight_requirement", world.map_id == "lab")
 world.npc.position = world.player.position + Vector2(40, 0)
 world.request_flashlight()
 world.apply_interaction("flashlight")
 check("equipment_event_from_actual_pickup", world.flashlight_owned and "flashlight_collected" in world.story.events)
 hud.minimap.remember_position()
 var lab_cells: Array = hud.minimap.explored.lab.duplicate()
 world.apply_interaction("storage_gate")
 check("storage_stage_has_no_fake_completion", world.story.stage == "fuse_search" and not world.finished)
 world.player.position = Vector2(275, 200)
 world.npc.position = Vector2(500, 200)
 world._aim_pointer_seen = false
 # 배관 바로 뒤: 손전등 방향/거리와 무관하게 실제 가구가 시야를 가린다.
 check("wall_blocks_direct_observation", not world.line_of_sight(world.npc.position) and world.visibility_at(world.npc.position) == 0)
 check("hidden_moving_companion_not_tracked", not hud.minimap.visible_companion("storage").is_finite())
 world.npc.position = Vector2(290, 220)
 check("currently_visible_companion_is_located", hud.minimap.visible_companion("storage").is_equal_approx(world.npc.position))
 world.npc.position = Vector2(500, 200)
 check("past_sighting_does_not_track_through_wall", not hud.minimap.visible_companion("storage").is_finite())
 hud.minimap.remember_position()
 check("entering_room_does_not_reveal_all_cells", hud.minimap.explored.storage.size() < 384)
 check("unseen_fuse_not_given_exact_marker", not hud.minimap.known.storage.has("fuse"))
 check("map_geometry_uses_real_collision_footprints", hud.minimap.rooms.storage.obstacles.size() > 0 and hud.minimap.rooms.storage.obstacles.size() == world.obstruction_rects().size())
 var old_cells: Array = hud.minimap.explored.storage.duplicate()
 world.player.position = world.get_node("ToLab").position
 hud.minimap.remember_position()
 check("observed_terrain_persists", old_cells.all(func(cell): return cell in hud.minimap.explored.storage))
 for enemy in world.get_node("Enemies").get_children(): enemy.hp = 0
 world.locker.opened = true # 패널 유지/비프 실제 흐름은 기존 mechanics 검사에서 검증.
 world._sync_state()
 world.player.position = world.fuse.position + Vector2(0, 40)
 hud.minimap.remember_position()
 check("visible_fuse_acquires_marker", hud.minimap.known.storage.has("fuse"))
 world.apply_interaction("fuse")
 hud.minimap.remember_position()
 check("picked_fuse_removes_marker", not hud.minimap.known.storage.has("fuse"))
 check("fuse_updates_story", world.story.stage == "fuse_return")
 world.apply_interaction("lab_gate")
 hud.minimap.remember_position()
 check("room_travel_preserves_discovery", lab_cells.all(func(cell): return cell in hud.minimap.explored.lab) and hud.minimap.explored.has("storage"))
 world.apply_interaction("generator")
 check("restoration_is_not_mission_completion", world.story.stage == "power_restored" and world.power_restored and not world.finished)
 world.trigger_alarm()
 check("alarm_has_world_visual_and_explicit_event", world.get_node("Alarm").visible and "anomaly_alarm" in world.story.events)
 check("alarm_does_not_send_player_back_to_current_room", MikaDialogue.response_issue("연구실로 가자.", world.game_state(), "이제 어디로 가?") == "wrong_departure_destination")
 var restored_facts := JSON.stringify(MikaDialogue.facts(world.game_state(), "이제 불 들어왔는데?", "mission"))
 check("restored_guidance_moves_beyond_fuse", "경보" in restored_facts and not "탈출" in restored_facts)
 check("reject_false_old_goal_and_completion", not MikaDialogue.claims_valid("퓨즈를 찾아야 해", world.game_state()) and not MikaDialogue.claims_valid("임무 끝났어", world.game_state()))
 world.apply_interaction("exit")
 check("departure_enters_real_main_room", world.map_id == "main_entry" and world.get_node("MainDecor").visible and not world.get_node("LabDecor").visible)
 check("tutorial_and_mission_completion_separate", world.story.tutorial_completed and not world.finished and world.can_move)
 world.apply_interaction("anomaly_console")
 check("main_terminal_starts_containment_briefing", "anomaly_observed" in world.story.events and world.containment.stage == "ready" and "봉쇄" in world.current_guidance() and not world.finished)
 hud.minimap.remember_position()
 await frames()
 await capture("02_alarm_main_entry")
 var context := MikaDialogue.build(world.game_state(), "그럼 지금은?", [{"question": "경보가 왜 울려?", "answer": "장치가 침식된 것 같아."}], "", "")
 check("mission_followup_keeps_recent_referent", "침식된 것" in context.prompt and "containment" in context.prompt)
 check("style_examples_are_marked_fictional", "fictional_style_only" in context.prompt)
 var casual := MikaDialogue.build(world.game_state(), "너 은근히 겁 많은 거 아냐?", [], "", "")
 check("banter_not_forced_to_direct_single_sentence", not "one short sentence" in casual.system and "counterquestions" in casual.system)
 check("banter_question_is_allowed", MikaDialogue.response_issue("너는 아닌 것 같고?", world.game_state(), "겁 많지?").is_empty())
 check("style_has_no_fixed_food_or_meal_claim", MikaDialogue.CHARACTER.favorite_food.is_empty() and not "ate_before_departure" in casual.prompt)
 check("fictional_food_order_cannot_become_actual_memory", MikaDialogue.response_issue("오늘 미트 스파게티 주문했어.", world.game_state(), "기억해?") == "invented_food_event")
 check("fictional_work_joke_cannot_become_world_rule", MikaDialogue.response_issue("아, 퇴근은 안 돼.", world.game_state(), "정말 퇴근 금지야?") == "unsupported_world_rule")
 var data = JSON.parse_string(FileAccess.get_file_as_string("res://resources/mika_style_examples.json").trim_prefix("\ufeff"))
 check("all_nine_samples_preserved_separately", data.samples.size() == 9 and data.samples[1].lines.size() == 2)
 check("action_annotations_are_not_spoken_style_lines", not "라이트를 드랍" in JSON.stringify(data.samples[1].lines))
 await test_journal()
 await test_input_and_status()
 await test_save()
 var result := {"passed": not checks.values().has(false), "check_count": checks.size(), "checks": checks, "gpu_rendered": rendered, "created_utc": Time.get_datetime_string_from_system(true), "human_playtest": false, "actual_ime": false, "live_model": false}
 FileAccess.open(directory.path_join("render.json" if rendered else "test.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
 print("STORY_UI_RESULT ", JSON.stringify(result))
 app.queue_free()
 await frames()
 quit(0 if result.passed else 1)

func test_journal() -> void:
 hud.clear_speech()
 var count := hud.journal.entries.size()
 hud.speak("플레이어", "단말 확인했어.")
 hud.speak("미카", "뭐라고 나와?")
 hud.notify("침식 관측 기록")
 check("unified_channels_in_chronological_order", hud.journal.entries.size() == count + 3 and hud.journal.entries.back().channel == "system" and hud.journal.entries[-2].sender == "미카")
 var memory_count: int = app.brain.history.size()
 hud.notify("침식 관측 기록")
 check("repeat_system_notice_coalesced", hud.journal.entries.size() == count + 3 and hud.journal.entries.back().repeat == 2)
 check("system_not_in_model_memory_or_answer", app.brain.history.size() == memory_count and app.answer.text != "침식 관측 기록")
 hud.record("플레이어2", "dialogue", "나도 확인", "remote-test-id")
 var size_before := hud.journal.entries.size()
 hud.record("플레이어2", "dialogue", "나도 확인", "remote-test-id")
 check("same_id_recorded_once", hud.journal.entries.size() == size_before)
 for index in range(60): hud.record("플레이어", "dialogue", "기록 스크롤 검사 %d. 읽던 위치를 유지한다." % index)
 hud.toggle_history()
 await frames(8)
 var bar: VScrollBar = hud.get_node("HistoryPanel/Content").get_v_scroll_bar()
 bar.value = 0
 await frames()
 var old_scroll := bar.value
 hud.notify("새 관측 메시지")
 await frames(8)
 check("new_message_preserves_reader_scroll", is_equal_approx(bar.value, old_scroll) and hud.get_node("HistoryPanel/NewMessages").visible)
 hud.scroll_to_latest()
 await frames()
 hud.notify("최신 위치에서는 자동 따라가기")
 await frames(8)
 check("latest_reader_follows_new_messages", bar.value >= bar.max_value - bar.page - 4 and not hud.get_node("HistoryPanel/NewMessages").visible)
 await capture("03_unified_history")
 hud.close_modal()
 var fixed: Vector2 = hud.system_notices.position
 world.player.position += Vector2(50, 0)
 app._update_world_view()
 hud.update_view(0)
 check("notice_anchor_does_not_follow_player", fixed == hud.system_notices.position)
 check("journal_survives_room_travel", hud.journal.entries.size() > 0)
 for index in range(220): hud.record("시스템", "system", "상한 검사 %d" % index)
 check("journal_limit_is_200", hud.journal.entries.size() == MessageJournal.LIMIT)
 await frames()

func test_input_and_status() -> void:
 app.close_dialogue()
 await key(KEY_M)
 check("m_opens_map_and_blocks_world", hud.get_node("FullMapPanel").visible and not world.can_move)
 var ammo_before := world.ammo
 await key(KEY_SPACE)
 await key(KEY_E)
 check("map_keys_do_not_attack_or_interact", world.ammo == ammo_before and not app.pause_menu.visible)
 await capture("04_discovered_full_map")
 await key(KEY_ESCAPE)
 check("escape_closes_map_first", not hud.modal_open() and not app.pause_menu.visible and world.can_move)
 await key(KEY_ENTER)
 app.question.text = "한글 미전송 초안"
 await key(KEY_M)
 check("m_in_chat_does_not_open_map", app.question.has_focus() and not hud.get_node("FullMapPanel").visible)
 await key(KEY_ESCAPE)
 check("escape_preserves_chat_draft", app.question.text.begins_with("한글 미전송 초안") and not app.question.has_focus())
 app.question.text = ""
 await key(KEY_ENTER)
 await key(KEY_ENTER)
 check("empty_enter_returns_to_movement", not app.question.has_focus() and world.can_move)
 world.player.position = Vector2(550, 340)
 world.npc.position = Vector2(600, 320)
 app._update_world_view()
 hud.update_view(0)
 var status: ActorStatus = hud.statuses[1]
 var fixed := status.position
 var physics_position := world.npc.position
 for index in range(20):
  world.player.position = world.npc.position + Vector2((index % 3 - 1) * 36, -45 + (index % 4) * 30)
  hud.player_bubble.say("플레이어", "겹침 검사")
  hud.npc_bubble.say("미카", "상태바 위치 유지")
  hud.update_view(0)
  check("stable_status_frame_%02d" % index, status.position.is_equal_approx(fixed))
 world.player.position = Vector2(550, 340)
 check("status_keeps_actor_offset_without_physics_change", status.position.is_equal_approx(hud.screen_point(world.npc) + Vector2(-60, -102)) and world.npc.position == physics_position)
 for zoom in [0.8, 1.35]:
  app.get_node("WorldCanvas").scale = Vector2.ONE * zoom
  app.get_node("WorldCanvas").offset = Vector2(34, 70)
  hud.update_view(0)
  check("canvas_zoom_%s" % zoom, status.position.is_equal_approx(hud.screen_point(world.npc) + Vector2(-60, -102)))
 app._update_world_view()
 world.npc.position = Vector2(1700, 320)
 hud.update_view(0)
 check("offscreen_status_is_hidden", not status.visible)
 world.npc.position = physics_position
 for resolution in [Vector2i(960, 600), Vector2i(1280, 800)]:
  root.size = resolution
  await frames(8)
  hud.layout()
  app._update_world_view()
  hud.update_view(0)
  check("status_coordinates_%d" % resolution.x, status.position.is_equal_approx(hud.screen_point(world.npc) + Vector2(-60, -102)))
  check("fixed_ui_fits_%d" % resolution.x, Rect2(Vector2.ZERO, app.size).encloses(hud.minimap.get_rect()) and Rect2(Vector2.ZERO, app.size).encloses(hud.system_notices.get_rect()))
  hud.toggle_map()
  check("map_fits_%d" % resolution.x, Rect2(Vector2.ZERO, app.size).encloses(hud.get_node("FullMapPanel").get_rect()))
  await capture("05_map_%d" % resolution.x)
  hud.close_modal()
  hud.toggle_history()
  check("history_fits_%d" % resolution.x, Rect2(Vector2.ZERO, app.size).encloses(hud.get_node("HistoryPanel").get_rect()))
  await capture("06_history_%d" % resolution.x)
  hud.close_modal()

func test_save() -> void:
 app.question.text = ""
 var story_before := world.story.snapshot()
 check("v3_save_writes", app.save_slot(1))
 var bytes := FileAccess.get_file_as_string(app.save_store.path_for(1))
 var data: Dictionary = app.save_store.read_slot(1)
 check("v3_contains_separate_exploration_journal_memory", data.version == 3 and data.has("journal") and data.has("atlas") and data.has("history"))
 world.reset_world()
 hud.reset()
 check("load_restores_story_and_three_rooms", app.load_slot(1) and world.map_id == "main_entry" and world.story.stage == story_before.stage and hud.minimap.explored.size() == 3)
 check("load_restores_user_journal_separately", hud.journal.entries.size() > 0 and app.brain.history.is_empty())
 check("validation_and_load_preserve_source_slot", bytes == FileAccess.get_file_as_string(app.save_store.path_for(1)))
 for index in range(3):
  check("repeated_load_save_%d" % index, app.load_slot(1) and app.save_slot(2) and hud.minimap.explored.values().all(func(cells): return cells.size() <= 384))
 var corrupt: Dictionary = data.duplicate(true)
 corrupt.world.story.stage = "made_up"
 check("invalid_story_rejected", not app.save_store.validate(corrupt, world))
 corrupt = data.duplicate(true)
 corrupt.journal[1].id = corrupt.journal[0].id
 check("duplicate_saved_message_id_rejected", not app.save_store.validate(corrupt, world))
 corrupt = data.duplicate(true)
 corrupt.atlas.known.main_entry = {"bad": {"position": [99999, 0]}}
 check("invalid_atlas_rejected", not app.save_store.validate(corrupt, world))
 world.apply_interaction("lab_gate")
 var legacy := {"version": 2, "scenario": JSON.stringify(world.scenario_configuration()).sha256_text(), "saved_at": "legacy", "provider": 0, "world": world.save_snapshot(), "exploration": hud.minimap.explored.duplicate(true), "history": []}
 legacy.world.erase("story")
 legacy.exploration.erase("main_entry")
 check("legacy_v2_validates_and_migrates", app.save_store.validate(legacy, world) and legacy.version == 3 and legacy.world.story.stage == "anomaly_alarm")
 app.reset_demo(0)
 check("new_trial_clears_story_exploration_journal", world.story.stage == "on_shift" and hud.minimap.explored.is_empty() and hud.journal.entries.is_empty())


