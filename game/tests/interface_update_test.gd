extends SceneTree
var checks := {}
var app: Control
var directory := ""
var render := false
var store: MissionSaveStore

func _initialize() -> void:
 call_deferred("run")

func check(name: String, value: bool) -> void:
 checks[name] = value
 if not value: push_error("INTERFACE_CHECK_FAILED " + name)

func frames(count: int = 3) -> void:
 for index in range(count): await process_frame

func physics(count: int = 3) -> void:
 for index in range(count): await physics_frame

func key(code: int) -> void:
 var event := InputEventKey.new()
 event.keycode = code
 event.physical_keycode = code
 event.pressed = true
 root.push_input(event, true)
 await frames()

func click(point: Vector2) -> void:
 var event := InputEventMouseButton.new()
 event.button_index = MOUSE_BUTTON_LEFT
 event.position = point
 event.global_position = point
 event.pressed = true
 root.push_input(event, true)
 event = event.duplicate()
 event.pressed = false
 root.push_input(event, true)
 await frames()

func capture(stem: String) -> void:
 if not render: return
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(directory.path_join(stem + ".png"))

func run() -> void:
 directory = ProjectSettings.globalize_path("res://../evidence/interface_update")
 DirAccess.make_dir_recursive_absolute(directory)
 render = "--render-interface" in OS.get_cmdline_user_args()
 root.size = Vector2i(1280, 800)
 app = load("res://main.tscn").instantiate()
 root.add_child(app)
 await frames()
 app.brain.auto_enabled = false
 app.brain.set_process(false)
 store = app.save_store
 # 일회성 테스트 전용 폴더. 플레이어 슬롯에는 접근하지 않는다.
 store.directory = "user://interface_test_%d" % OS.get_process_id()
 var world: DemoWorld = app.world
 var hud: CombatInterface = app.combat_hud
 var field: ChatInput = app.question
 var field_id := field.get_instance_id()
 var speed: float = world.player.move_speed
 var hitbox: float = world.player.get_node("CollisionShape2D").shape.radius
 check("lab_uses_larger_camera", app._camera_zoom > 1)
 check("camera_does_not_scale_physics", world.scale == Vector2.ONE and world.player.scale == Vector2.ONE and world.player.move_speed == speed and world.player.get_node("CollisionShape2D").shape.radius == hitbox)
 await capture("01_noncombat")
 world.flashlight_owned = true # Fixture: 기존 회귀의 전투/입력 조건. 지급 흐름은 mission_mechanics_test에서 별도 검증.
 world.apply_interaction("storage_gate")
 await frames()
 check("combat_uses_wide_camera", app._camera_zoom == 1)
 check("combat_keeps_single_native_composer", field.get_instance_id() == field_id and field.get_signal_connection_list("text_submitted").size() == 1)
 check("compact_composer_in_combat", not app.answer.visible and not app.get_node("RadioPanel/LabPortrait").visible and app.dialogue_panel.size.y == 64)
 check("top_left_exploration_map", hud.minimap.visible and hud.minimap.global_position == Vector2(22, 22))
 check("companion_and_enemy_statuses_preserved", hud.statuses.size() == 1 + world.all_enemies().size() and hud.statuses[0].target == world.npc)
 world.player_hp = 68
 world.ammo = 4
 world.npc_hp = 53
 world.npc_ammo = 13
 world.player.position = Vector2(510, 315)
 world.npc.position = Vector2(620, 300)
 world.state_changed.emit()
 world.set_physics_process(false)
 for enemy in world.get_node("Enemies").get_children(): enemy.set_physics_process(false)
 await frames()
 hud.update_view(0)
 var player_status: Control = hud.hud.get_node("Vitals")
 check("player_hud_matches_actual_health", hud.hud.get_node("%HealthBar").value == 68)
 check("player_hud_matches_total_ammo", hud.hud.get_node("%Rounds").text == "04" and hud.hud.get_node("%Capacity").text == "/ 20")
 check("npc_hud_matches_real_health_ammo", hud.statuses[0].get_node("Health").value == 53 and hud.statuses[0].get_node("Ammo").text == "13 / 20")
 check("weapon_icon_is_independent_asset", player_status.get_node("Values/AmmoRow/Icon").texture.resource_path.ends_with("pulse_pistol.svg"))
 var before := player_status.position
 world.player.position.x += 85
 app._update_world_view()
 hud.update_view(0)
 check("player_vitals_stay_screen_anchored", player_status.position.is_equal_approx(before))
 check("player_vitals_are_in_bottom_left", player_status.position.x == 22 and player_status.get_rect().end.y == app.size.y - 22)
 world.npc.position = world.player.position
 hud.update_view(0)
 check("player_status_does_not_overlap_companion_in_view", not player_status.get_rect().intersects(hud.statuses[0].get_rect()))
 # Keep both observation points on the current floor and isolate this memory
 # check from the live mouse aim used by the flashlight.
 var had_flashlight := world.flashlight_owned
 world.flashlight_owned = false
 hud.minimap.explored.erase("storage")
 world.player.position = Vector2(510, 315)
 check("first_exploration_point_inside_room", world.room_rect.has_point(world.player.position))
 hud.minimap.remember_position()
 var initial_cells: Array = hud.minimap.explored.storage.duplicate()
 world.player.position = Vector2(200, 315)
 check("second_exploration_point_inside_room", world.room_rect.has_point(world.player.position))
 hud.minimap.remember_position()
 check("minimap_remembers_previous_exploration", initial_cells.all(func(cell): return cell in hud.minimap.explored.storage) and hud.minimap.explored.storage.size() > initial_cells.size())
 world.flashlight_owned = had_flashlight
 world.apply_interaction("lab_gate")
 hud.minimap.remember_position()
 check("exploration_is_separate_per_room", hud.minimap.explored.has("lab") and hud.minimap.explored.has("storage"))
 var stored_cells: Array = hud.minimap.explored.storage.duplicate()
 world.flashlight_owned = true # Fixture: 기존 회귀의 전투/입력 조건. 지급 흐름은 mission_mechanics_test에서 별도 검증.
 world.apply_interaction("storage_gate")
 check("room_return_keeps_exploration", hud.minimap.explored.storage == stored_cells)
 await key(KEY_ENTER)
 check("enter_focuses_combat_input", field.has_focus() and not world.can_move)
 var ammo_before := world.ammo
 await key(KEY_SPACE)
 check("space_in_composer_does_not_fire", world.ammo == ammo_before and field.has_focus())
 field.text = "안녕하세요 마지막 글자"
 await key(KEY_ENTER)
 check("submitted_player_text_uses_committed_message", hud.player_bubble.full_text == "안녕하세요 마지막 글자" and not field.has_focus())
 check("npc_reply_uses_existing_provider", hud.npc_bubble.full_text == app.answer.text and app.brain.history.size() == 1)
 check("reply_appears_once_in_bottom_caption", hud.hud.get_node("%Dialogue").visible and hud.hud.get_node("%Line").text == app.answer.text and not hud.npc_bubble.visible)
 field.text = "아직 전송하지 않은 초안"
 check("unsent_draft_not_exposed_in_bubble", hud.player_bubble.full_text != field.text)
 app._chat_idle = 0
 app._process(4.1)
 check("combat_composer_stays_closed_after_send", not app.dialogue_panel.visible and app.dialogue_panel.modulate.a == 1)
 await key(KEY_ENTER)
 check("enter_reopens_compact_input", field.has_focus() and app.dialogue_panel.visible and app.dialogue_panel.modulate.a == 1)
 await key(KEY_ESCAPE)
 check("first_escape_only_ends_editing", not field.has_focus() and not app.pause_menu.visible)
 world.player.position = Vector2(610, 300)
 world.npc.position = Vector2(700, 270)
 app._update_world_view()
 hud.speak("미카", "이쪽이야. 탄약이 부족하면 알려 줘.")
 hud.update_view(0)
 check("onscreen_speech_has_no_edge_direction", hud.npc_bubble.visible and hud.npc_bubble.direction.is_empty())
 world.npc.position = Vector2(1600, 270)
 hud.update_view(0)
 check("offscreen_npc_has_direction", "오른쪽" in hud.npc_bubble.direction)
 check("offscreen_speech_fits_play_rect", app.play_rect().encloses(hud.npc_bubble.get_rect()))
 check("edge_speech_does_not_overlap_minimap", not hud.npc_bubble.get_rect().intersects(hud.minimap.get_global_rect()))
 check("speech_does_not_cover_objective", not hud.npc_bubble.get_rect().intersects(hud.hud.get_node("%ObjectivePanel").get_global_rect()))
 world.npc.position = Vector2(-800, -900)
 hud.update_view(0)
 check("opposite_edge_speech_fits", app.play_rect().encloses(hud.npc_bubble.get_rect()) and not hud.npc_bubble.direction.is_empty())
 world.npc.position = Vector2(700, 270)
 hud.update_view(0)
 check("edge_speech_returns_to_actor", hud.npc_bubble.direction.is_empty() and hud.npc_bubble.visible)
 var long_text := "긴 한국어 대사와 연속 발언. ".repeat(30)
 hud.speak("미카", long_text)
 check("full_long_speech_kept_in_history", hud.journal.entries.back().body == long_text and hud.npc_bubble.full_text == long_text)
 hud.npc_bubble.tick(20)
 check("speech_expires_after_duration", not hud.npc_bubble.visible)
 hud.speak("미카", "동쪽으로 이동하자. 전투가 계속되고 있어.")
 hud.update_view(0)
 await capture("02_combat")
 world.npc.position = Vector2(1600, 260)
 hud.update_view(0)
 await capture("03_offscreen_speech")
 world.npc.position = Vector2(700, 270)
 field.text = "메뉴를 열어도 유지되는 초안"
 var old_hp := world.player_hp
 await key(KEY_ESCAPE)
 check("escape_opens_pause_menu", app.pause_menu.visible and paused and not world.can_move)
 check("pause_preserves_draft", field.text == "메뉴를 열어도 유지되는 초안")
 world.set_physics_process(true)
 var location_before := world.player.position
 var enemy_before: Vector2 = world.get_node("Enemies/DroneA").position
 var cooldown_before := world.npc_shoot_cd
 Input.action_press("move_right")
 await physics(5)
 Input.action_release("move_right")
 check("pause_freezes_world_and_cooldowns", world.player.position == location_before and world.get_node("Enemies/DroneA").position == enemy_before and world.npc_shoot_cd == cooldown_before and world.player_hp == old_hp)
 var old_ammo := world.ammo
 await click(Vector2(20, 20))
 check("pause_blocks_world_clicks", world.ammo == old_ammo)
 var title_button := app.pause_menu.get_node("Window/ReturnToTitle") as Button
 check("paused_world_offers_title_return", title_button.is_visible_in_tree() and not title_button.disabled and paused and world.ammo == old_ammo)
 app.pause_menu.show_slots(true)
 check("empty_save_slots_show_disabled_entries", app.pause_menu.get_node("Window/Slots/Slot1").disabled and "비어 있음" in app.pause_menu.get_node("Window/Slots/Slot1").text)
 app.pause_menu.get_node("Window/Slots/Back").pressed.emit()
 var gear = app.pause_menu.get_node("Window/Gear")
 gear.spin()
 gear.spin()
 await create_timer(0.85).timeout
 check("gear_rotates_once_without_accumulation", gear.completed_turns == 1 and not gear.spinning and gear.rotation == 0)
 await capture("04_pause_menu")
 var settings := app.pause_menu.get_node("Window/Settings") as Button
 await click(settings.get_global_rect().get_center())
 var audio_settings := app.pause_menu.get_node("Window/AudioSettings") as Control
 var volume := audio_settings.get_node("MasterVolume") as HSlider
 var original_volume := volume.value
 check("pause_settings_keeps_world_paused", audio_settings.is_visible_in_tree() and volume.has_focus()
  and paused and not world.can_move and not title_button.is_visible_in_tree())
 volume.value = 62
 check("pause_settings_changes_master_volume", is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.62))
  and audio_settings.get_node("VolumeValue").text == "62%" and world.ammo == old_ammo)
 await capture("04b_pause_settings")
 await key(KEY_ESCAPE)
 check("escape_returns_from_settings_to_pause", paused and settings.has_focus() and not audio_settings.visible and title_button.visible)
 await click(settings.get_global_rect().get_center())
 check("pause_settings_reads_saved_volume", is_equal_approx(volume.value, 62.0))
 volume.value = original_volume
 var settings_back := audio_settings.get_node("Back") as Button
 await click(settings_back.get_global_rect().get_center())
 check("settings_back_leaves_pause_menu_open", paused and app.pause_menu.visible and not audio_settings.visible)
 world.player_hp = 71
 world.ammo = 5
 world.npc_hp = 49
 world.npc_ammo = 9
 world.medkits = 1
 world.cache_used = true
 world.fuse_collected = false
 world.heal_cd = 3.25
 world.cover_time = 6.5
 world.active_action = "resupply"
 world.get_node("Enemies/DroneA").hp = 25
 world.get_node("Enemies/DroneB").hp = 0
 world._sync_state()
 app.brain.history.assign([{"question": "우리 임무?", "answer": "퓨즈를 찾자."}])
 var snapshot := world.save_snapshot()
 var explored := hud.minimap.explored.duplicate(true)
 check("combat_save_writes_slot", app.save_slot(1) and FileAccess.file_exists(store.path_for(1)))
 app.pause_menu.show_slots(false)
 app.pause_menu.choose_slot(1)
 check("overwrite_needs_second_slot_click", app.pause_menu.overwrite_slot == 1)
 app.pause_menu.choose_slot(1)
 check("overwrite_confirmation_completes", app.pause_menu.overwrite_slot == 0 and "저장 완료" in app.pause_menu.get_node("Window/Message").text)
 app.pause_menu.show_slots(true)
 check("saved_slot_lists_room_and_date", not app.pause_menu.get_node("Window/Slots/Slot1").disabled and "비품실" in app.pause_menu.get_node("Window/Slots/Slot1").text)
 await capture("05_load_slots")
 world.player_hp = 12
 world.ammo = 1
 world.npc_hp = 1
 world.npc_ammo = 0
 world.cache_used = false
 world.player.position = Vector2(100, 100)
 hud.minimap.explored.clear()
 app.brain.history.clear()
 var epoch_before := world.epoch
 app.brain.pending = {"kind": "dialogue", "request_id": 888, "snapshot": {}, "question": "불러오기 전 질문", "started_usec": Time.get_ticks_usec()}
 app.brain.queued_question = "이전 대기 질문"
 check("saved_state_loads_successfully", app.load_slot(1))
 check("load_restores_player_resources", world.player_hp == 71 and world.ammo == 5 and world.medkits == 1 and world.cache_used)
 check("load_restores_companion_resources", world.npc_hp == 49 and world.npc_ammo == 9)
 check("load_restores_exact_positions", world.player.position == Vector2(snapshot.player_position[0], snapshot.player_position[1]) and world.npc.position == Vector2(snapshot.npc_position[0], snapshot.npc_position[1]))
 check("load_restores_enemy_damage_and_death", world.get_node("Enemies/DroneA").hp == 25 and world.get_node("Enemies/DroneB").hp == 0 and not world.get_node("Enemies/DroneB").visible)
 check("load_restores_cooldowns_and_cover", world.heal_cd == 3.25 and world.cover_time == 6.5)
 check("load_cancels_active_support_without_resource_charge", world.active_action.is_empty() and world.supply_packs == int(snapshot.supply_packs))
 check("load_invalidates_pending_ai_epoch_and_queue", world.epoch > epoch_before and app.brain.pending.is_empty() and app.brain.queued_question.is_empty())
 app.brain._local_completed({"response": "{\"dialogue\":\"古い返事\"}", "metrics": {}})
 check("late_completion_after_load_is_ignored", not "古い返事" in app.answer.text and app.brain.history.size() == 1)
 check("load_restores_memory_exploration", app.brain.history[0].question == "우리 임무?" and explored.keys().all(func(room): return explored[room].all(func(cell): return cell in hud.minimap.explored.get(room, []))))
 check("load_returns_control_and_clears_old_bubbles", not paused and not app.pause_menu.visible and field.text.is_empty() and not hud.npc_bubble.visible and not hud.player_bubble.visible)
 world.set_physics_process(false)
 var protected_state := world.save_snapshot()
 check("missing_slot_does_not_mutate_world", not app.load_slot(3) and world.save_snapshot() == protected_state)
 FileAccess.open(store.path_for(3), FileAccess.WRITE).store_string("{broken")
 check("corrupt_json_does_not_mutate_world", not app.load_slot(3) and world.save_snapshot() == protected_state)
 var malformed := store.read_slot(1)
 malformed.world.player_hp = -1
 store.write_slot(3, malformed)
 check("invalid_health_is_rejected_before_mutation", not app.load_slot(3) and world.save_snapshot() == protected_state)
 malformed = store.read_slot(1)
 malformed.world.enemies.DroneA.position = ["invalid", 200]
 store.write_slot(3, malformed)
 check("invalid_enemy_position_is_rejected", not app.load_slot(3) and world.save_snapshot() == protected_state)
 malformed = store.read_slot(1)
 malformed.scenario = "other_version"
 store.write_slot(3, malformed)
 check("incompatible_scenario_is_rejected", not app.load_slot(3))
 world.finished = true
 check("completed_mission_cannot_overwrite_save", not app.save_slot(1))
 world.finished = false
 world.defeated = true
 check("defeated_player_cannot_overwrite_save", not app.save_slot(1))
 world.defeated = false
 await key(KEY_ESCAPE)
 check("pause_reopens_after_load", paused and app.pause_menu.visible)
 await key(KEY_ESCAPE)
 check("escape_resumes_game", not paused and not app.pause_menu.visible and world.can_move)
 app.reset_demo(0)
 world.set_physics_process(false)
 check("restart_clears_exploration", hud.minimap.explored.is_empty() or not hud.minimap.explored.has("storage"))
 check("restart_resets_companion_hp_ammo", world.npc_hp == world.npc_max_hp and world.npc_ammo == world.npc_initial_ammo)
 world.flashlight_owned = true # Fixture: 기존 회귀의 전투/입력 조건. 지급 흐름은 mission_mechanics_test에서 별도 검증.
 world.apply_interaction("storage_gate")
 world.npc.position = Vector2(420, 300)
 world.player.position = Vector2(200, 300)
 var enemy: MissionDrone = world.get_node("Enemies/DroneA")
 enemy.position = Vector2(510, 300)
 enemy.set_physics_process(false)
 world.npc_shoot_cd = 0
 var npc_ammo_before := world.npc_ammo
 var player_ammo_before := world.ammo
 var enemy_hp := enemy.hp
 world._npc_fire()
 await physics(12)
 check("npc_shot_consumes_own_ammo", world.npc_ammo == npc_ammo_before - 1 and world.ammo == player_ammo_before)
 check("npc_projectile_deals_real_damage", enemy.hp == enemy_hp - world.npc_bullet_damage)
 var hp_before := world.player_hp
 var npc_hp_before := world.npc_hp
 enemy.position = world.npc.position + Vector2(20, 0)
 enemy.companion_alive = true
 enemy.attack_wait = 0
 enemy.reset_animation()
 enemy.set_physics_process(true)
 await physics(30)
 enemy.set_physics_process(false)
 check("drone_can_target_and_damage_companion", world.npc_hp == npc_hp_before - enemy.contact_damage and world.player_hp == hp_before)
 world.active_action = "heal"
 world.take_npc_damage(1000)
 check("npc_zero_hp_cancels_support", world.npc_hp == 0 and world.active_action.is_empty() and not world.request_support("heal"))
 check("downed_npc_only_has_wait_action", world.valid_actions() == ["wait"] and NPCPolicy.rule_action(world.game_state()) == "wait")
 world.npc_shoot_cd = 0
 var downed_ammo := world.npc_ammo
 world.set_physics_process(true)
 await physics(3)
 check("downed_npc_does_not_shoot", world.npc_ammo == downed_ammo)
 world.set_physics_process(false)
 world.npc_hp = 100
 world.npc_ammo = 0
 world.npc_shoot_cd = 0
 world._npc_fire()
 check("npc_empty_ammo_never_goes_negative", world.npc_ammo == 0)
 world.player.position = Vector2(400, 300)
 world.npc.position = Vector2(320, 300)
 world.ammo = 6
 world.shoot_cd = 0
 enemy.hp = enemy.max_hp
 enemy.position = Vector2(500, 300)
 enemy.visible = true
 app._update_world_view()
 hud.update_view(0)
 await click(hud.screen_point(enemy))
 await physics(12)
 check("mouse_aim_uses_camera_canvas_transform", enemy.hp == enemy.max_hp - world.bullet_damage and world.ammo == 5)
 world.npc_hp = 35
 world.npc_ammo = 2
 world.apply_interaction("lab_gate")
 check("room_transition_does_not_refill_companion", world.npc_hp == 35 and world.npc_ammo == 2)
 app.size = Vector2(960, 600)
 world.flashlight_owned = true # Fixture: 기존 회귀의 전투/입력 조건. 지급 흐름은 mission_mechanics_test에서 별도 검증.
 world.apply_interaction("storage_gate")
 await frames()
 hud.speak("미카", "작은 화면에서도 방향과 대사를 확인해.")
 world.npc.position = Vector2(1700, -200)
 hud.update_view(0)
 check("small_canvas_composer_fits", Rect2(Vector2.ZERO, app.size).encloses(app.dialogue_panel.get_rect()) and Rect2(Vector2.ZERO, app.size).encloses(field.get_global_rect()))
 check("small_canvas_edge_bubble_fits", app.play_rect().encloses(hud.npc_bubble.get_rect()))
 app.toggle_pause()
 var pause_card := app.pause_menu.get_node("Window") as Panel
 check("small_canvas_pause_card_fits", Rect2(Vector2.ZERO, app.size).encloses(pause_card.get_global_rect())
  and pause_card.get_global_rect().encloses(pause_card.get_node("Gear").get_global_rect()) and not pause_card.has_node("Peek"))
 app.toggle_pause()
 if render:
  app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  root.size = Vector2i(960, 600)
  await frames(5)
  await capture("06_small_canvas")
  check("rendered_small_window_is_960_600", root.get_texture().get_image().get_size() == Vector2i(960, 600))
  root.size = Vector2i(1280, 800)
 app.size = Vector2(1280, 800)
 app.reset_demo(0)
 await frames()
 check("final_reset_keeps_ime_singleton", field.get_instance_id() == field_id and FileAccess.get_sha256("res://native/windows_ime/windows_ime.dll") == "72082b7d2f61f9b1f2435be8f70f2012ccb63d656dd73c3d12ba6777c66851a6")
 # 생성한 테스트 슬롯만 정리한다.
 for name in DirAccess.get_files_at(store.directory): DirAccess.remove_absolute(store.directory.path_join(name))
 DirAccess.remove_absolute(store.directory)
 var result := {"suite": "interface_update", "passed": not checks.values().has(false), "check_count": checks.size(), "checks": checks, "gpu_rendered": render, "synthetic_input_events": true, "actual_windows_ime_tested": false, "live_model_calls": 0}
 FileAccess.open(directory.path_join("interface_update_render_test.json" if render else "interface_update_test.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
 print("INTERFACE_UPDATE_TEST ", JSON.stringify(result))
 app.queue_free()
 await frames()
 quit(0 if result.passed else 1)
