extends SceneTree
## 자동 통합 검사. 위치 고정/부분 상태 fixtures를 사용하며 사람 완주로 집계하지 않는다.
var checks := {}
var events: Array[Dictionary] = []
var app: Control
var world: DemoWorld
var mission: ContainmentMission
var directory := ""
var rendered := false

func _initialize() -> void:
 call_deferred("run")

func check(label: String, value: bool) -> void:
 checks[label] = value
 if not value: push_error("CONTAINMENT_FAILED " + label)

func frames(count := 3) -> void:
 for index in range(count): await physics_frame

func until(predicate: Callable, seconds := 10.0) -> bool:
 var elapsed := 0.0
 while not predicate.call() and elapsed < seconds:
  await create_timer(0.05).timeout
  elapsed += 0.05
 return predicate.call()

func capture(stem: String) -> void:
 if not rendered: return
 await process_frame
 await process_frame
 await RenderingServer.frame_post_draw
 var picture := root.get_texture().get_image()
 check(stem + "_gpu_pixels", picture.get_width() >= 960 and not picture.is_invisible())
 picture.save_png(directory.path_join(stem + ".png"))

func envelope() -> Dictionary:
 return {"version": MissionSaveStore.VERSION, "scenario": JSON.stringify(world.scenario_configuration()).sha256_text(), "saved_at": "containment_test", "provider": 0, "world": world.save_snapshot(), "exploration": {}, "atlas": {}, "history": [], "journal": []}

func freeze_enemies() -> void:
 for enemy in world.all_enemies(): enemy.set_physics_process(false)

func aim_origin(enemy: MissionDrone) -> Vector2:
 for offset in [Vector2(-100, 0), Vector2(100, 0), Vector2(0, 100), Vector2(0, -100)]:
  var point: Vector2 = enemy.position + offset
  if world.room_rect.grow(-25).has_point(point) and world.clear_line(point, enemy.position): return point
 return enemy.position - Vector2(50, 0)

func fire_at(enemy: MissionDrone) -> void:
 if world.ammo < 1 and world.map_id == "storage" and not world.cache_used: world.apply_interaction("cache")
 world.player.position = aim_origin(enemy)
 var hp := enemy.hp
 await until(func(): return world.shoot_cd <= 0, 1)
 check("projectile_fired_%d" % checks.size(), world.shoot(enemy.position))
 check("projectile_hits_%d" % checks.size(), await until(func(): return enemy.hp < hp, 2))

func clear_wave() -> void:
 var enemies := world.room_enemies().filter(func(enemy): return enemy.hp > 0)
 for enemy in enemies:
  for shot in range(4):
   if enemy.hp <= 0: break
   await fire_at(enemy)
 check("wave_cleared_%d" % checks.size(), enemies.all(func(enemy): return enemy.hp == 0))

func operate_panel(panel: CooperativeLocker, kind: String, save_committed := false) -> void:
 world.player.position = panel.panel_position(0) + Vector2(0, 36)
 world.npc.position = world.player.position + Vector2(-75, 30)
 world.npc_motion.reset()
 Input.action_press("interact")
 world.apply_interaction(kind)
 if world.active_action.is_empty(): app.brain.request_decision()
 check("panel_real_navigation_%s" % kind, await until(func(): return panel.sequence_elapsed >= 0, 12))
 if save_committed:
  check("committed_final_panel_save_load", app.save_slot(2) and app.load_slot(2) and mission.panel.sequence_elapsed >= 0 and not world.finished)
 Input.action_release("interact")
 check("panel_beeps_then_opens_%s" % kind, await until(func(): return panel.opened, 2))

func run() -> void:
 rendered = "--render-containment" in OS.get_cmdline_user_args()
 directory = ProjectSettings.globalize_path("res://../evidence/containment")
 DirAccess.make_dir_recursive_absolute(directory)
 root.size = Vector2i(1280, 800)
 app = load("res://main.tscn").instantiate()
 root.add_child(app)
 world = app.world
 mission = world.containment
 world.game_event.connect(func(event): events.append(event))
 app.brain.auto_enabled = false
 app.save_store.directory = "user://containment_test_%d" % OS.get_process_id()
 app.close_dialogue()
 freeze_enemies()
 world.npc_combat_enabled = false
 await frames()
 check("new_game_before_containment", world.map_id == "lab" and mission.stage == "unobserved" and mission.remaining() == 0 and not app.result_screen.visible)
 check("lab_not_combat_area", not world.is_combat_area() and not world.shoot(Vector2(900, 300)))
 world.apply_interaction("storage_gate")
 check("tutorial_equipment_gate_preserved", world.map_id == "lab" and not world.flashlight_owned)
 world.npc.position = world.player.position + Vector2(65, 0)
 world.request_flashlight()
 check("tutorial_flashlight_dropped", world.flashlight_dropped)
 world.player.position = world.get_node("FlashlightPickup").position + Vector2(0, 30)
 var interact := InputEventAction.new()
 interact.action = "interact"
 interact.pressed = true
 world._unhandled_input(interact)
 check("tutorial_e_pickup", world.flashlight_owned)
 world.apply_interaction("storage_gate")
 await clear_wave()
 check("tutorial_clear_still_requires_panel", not world.locker.opened and not world.fuse.visible)
 await operate_panel(world.locker, "panel_a")
 world.apply_interaction("fuse")
 world.apply_interaction("lab_gate")
 world.apply_interaction("generator")
 world.apply_interaction("exit")
 check("full_tutorial_to_main_entry", world.map_id == "main_entry" and world.story.tutorial_completed and world.power_restored and not world.finished)
 check("tutorial_panel_separate_from_final", world.locker.opened and not mission.panel.opened)
 await capture("01_main_entry")
 world.apply_interaction("containment_device")
 world.apply_interaction("containment_panel_a")
 check("no_device_or_panel_skip", mission.stage == "unobserved" and mission.remaining() == 0 and not mission.panel.opened)
 world.apply_interaction("anomaly_console")
 var event_count := events.filter(func(event): return event.event == "story_event").size()
 for index in range(3): world.apply_interaction("anomaly_console")
 check("observation_idempotent", mission.stage == "ready" and events.filter(func(event): return event.event == "story_event").size() == event_count)
 check("latest_context_has_containment_goal", "봉쇄 장치" in JSON.stringify(HarinDialogue.facts(world.game_state(), "지금 뭘 해야 해?", "mission")))
 world.apply_interaction("containment_device")
 check("supply_prevents_unprepared_start", mission.stage == "ready")
 world.apply_interaction("containment_supply")
 check("one_use_supply_refills_both_and_shared", world.ammo == world.max_ammo and world.npc_ammo == world.npc_initial_ammo and world.npc_reserve == world.npc_initial_reserve and world.medkits == world.initial_medkits and world.supply_packs == world.initial_supply_packs)
 world.apply_interaction("containment_supply")
 check("supply_does_not_duplicate", events.filter(func(event): return event.event == "containment_supply_collected").size() == 1)
 await test_legacy_and_validation()
 world.apply_interaction("containment_supply") # 이전 v3에는 새 보급함 사용 기록이 없다.
 var ready := world.save_snapshot()
 world.request_player_order("wait")
 check("wait_blocks_start_with_follow_hint", "따라와" in world.apply_interaction("containment_device") and mission.stage == "ready")
 app.brain.request_dialogue("따라와")
 check("rule_order_releases_wait_without_server", world.npc_motion.mode == "follow")
 world.apply_interaction("containment_device")
 check("first_wave_is_two", mission.stage == "wave_one" and mission.remaining() == 2 and world.game_state().enemy_count == 2)
 check("safe_separated_spawns", valid_spawns())
 world.apply_interaction("containment_device")
 world.apply_interaction("anomaly_console")
 world.apply_interaction("containment_panel_a")
 check("repeat_start_no_duplicate_or_skip", mission.remaining() == 2 and not mission.panel.opened and events.filter(func(event): return event.event == "containment_wave_started").size() == 1)
 check("combat_exit_has_reason", "격리" in world.apply_interaction("lab_gate") and world.map_id == "main_entry" and "격리" in world.get_node("ToLab").display_name)
 await test_live_combat()
 # 위의 전투 경계 fixture를 버리고 실제 가동 직후 상태에서 연속 진행한다.
 world.restore_snapshot(ready)
 world.apply_interaction("containment_device")
 await fire_at(mission.enemies()[0])
 check("partial_enemy_hp_before_save", mission.enemies()[0].hp == 25)
 var mid := world.save_snapshot()
 check("mid_wave_save", app.save_slot(1))
 var source_bytes := FileAccess.get_file_as_string(app.save_store.path_for(1))
 world.reset_world()
 check("mid_wave_load", app.load_slot(1) and mission.snapshot() == mid.containment and world.ammo == mid.ammo and world.player_hp == mid.player_hp and world.npc_reserve == mid.npc_reserve)
 check("load_preserves_source_bytes", source_bytes == FileAccess.get_file_as_string(app.save_store.path_for(1)))
 freeze_enemies()
 world.npc_combat_enabled = false
 check("mid_wave_no_respawn", mission.stage == "wave_one" and mission.remaining() == 2 and mission.enemies()[0].hp == 25 and not mission.get_node("Supply").visible)
 await clear_wave()
 check("second_wave_is_three", mission.stage == "wave_two" and mission.remaining() == 3)
 check("second_wave_safe_spawns", valid_spawns())
 await capture("02_second_wave")
 check("second_wave_save_load", app.save_slot(1) and app.load_slot(1) and mission.stage == "wave_two" and mission.remaining() == 3)
 await clear_wave()
 check("all_waves_enable_panel", mission.stage == "panel_ready" and mission.remaining() == 0)
 check("cleared_context_no_old_fuse_or_drone_goal", "패널" in NPCPolicy.template_response("mission", world.game_state(), "지금 뭘 해야 해?") and not HarinDialogue.claims_valid("퓨즈를 찾아야 해", world.game_state()))
 var used := mission.snapshot()
 world.apply_interaction("lab_gate")
 world.apply_interaction("exit")
 check("roundtrip_preserves_mission_and_supply", mission.snapshot() == used and mission.stage == "panel_ready" and not mission.get_node("Supply").visible)
 world.request_player_order("wait")
 check("wait_final_panel_explains_follow", "따라와" in world.apply_interaction("containment_panel_a") and mission.panel.player_panel == -1)
 app.brain.request_dialogue("따라와")
 world.npc_hp = 0 # 다운 안내/소생 경계 fixture. 다음 실제 상호작용으로 회복한다.
 check("down_final_panel_explains_revive", "소생" in world.apply_interaction("containment_panel_a") and not mission.panel.opened)
 world.player.position = world.npc.position + Vector2(0, 30)
 var kits := world.medkits
 world.apply_interaction("revive_npc")
 check("revive_resumes_final_panel", world.npc_hp == 35 and world.medkits == kits - 1)
 world.player_hp = 50 # 패널을 잡기 전에 시작한 공통 지원이 있어도 모델 없이 이어져야 한다.
 world.heal_cd = 0
 world.request_support("heal", {"source": "support_before_final_panel_fixture"})
 var ending_count := events.filter(func(event): return event.event == "mission_completed").size()
 await operate_panel(mission.panel, "containment_panel_a", true)
 check("final_panel_continues_after_support_without_ai", events.any(func(event): return event.event == "support_started" and event.get("action") == "assist_panel" and event.get("request", {}).get("source") == "fixed_mission_panel"))
 check("completed_only_after_final_beeps", world.finished and mission.stage == "complete" and world.story.stage == "contained" and not world.get_node("Alarm").visible)
 check("no_attacks_or_requests_after_ending", world.get_node("Projectiles").get_child_count() == 0 and not world.shoot(Vector2(800, 400)) and not app.brain.request_dialogue("지금 뭘 해야 해?"))
 var hp := world.player_hp
 world.take_damage(100)
 world.take_npc_damage(100)
 world.apply_interaction("containment_device")
 mission.panel_completed()
 check("completion_idempotent_and_damage_stops", world.player_hp == hp and events.filter(func(event): return event.event == "mission_completed").size() == ending_count + 1)
 check("ending_fixed_line_and_journal", "보고서" in app.combat_hud.npc_bubble.full_text and app.combat_hud.journal.entries.any(func(item): return "봉쇄 성공" in item.body))
 await frames()
 var ending_body: Label = app.combat_hud.npc_bubble.get_node("Body")
 check("ending_line_fits_bubble", ending_body.get_line_count() <= ending_body.max_lines_visible)
 await capture("03_ending_dialogue")
 check("ending_no_false_whole_lab_resolution", not HarinDialogue.claims_valid("연구소 전체가 해결됐어", world.game_state()))
 check("ending_result_after_dialogue", await until(func(): return app.result_screen.visible, 7))
 for resolution in [Vector2i(1280, 800), Vector2i(960, 600)]:
  root.size = resolution
  await frames(5)
  var card: Control = app.result_screen.get_node("Center/Card")
  check("result_fits_%d" % resolution.x, Rect2(Vector2.ZERO, app.size).encloses(card.get_global_rect()))
  await capture("03_result_%d" % resolution.x)
 var ending_hp := world.player_hp
 await frames(15)
 check("result_background_remains_quiet", world.player_hp == ending_hp and app.brain.pending.is_empty() and app.brain.queued_question.is_empty() and mission.enemies().all(func(enemy): return not enemy.active))
 app.result_screen.get_node("Center/Card/Margin/Content/Buttons/Restart").pressed.emit()
 check("result_restart_resets_everything", world.map_id == "lab" and world.story.stage == "on_shift" and not world.finished and not world.defeated and mission.stage == "unobserved" and not mission.supply_used and not world.locker.opened and not mission.panel.opened and app.brain.history.is_empty() and app.combat_hud.journal.entries.is_empty() and not app.result_screen.visible and mission.remaining() == 0)
 await test_failure_restart(ready)
 var result := {"passed": not checks.values().has(false), "check_count": checks.size(), "checks": checks, "gpu_rendered": rendered, "created_utc": Time.get_datetime_string_from_system(true), "human_playtest": false, "position_and_boundary_fixtures": true, "live_model": false, "provider": "RuleBased"}
 FileAccess.open(directory.path_join("render.json" if rendered else "test.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
 print("CONTAINMENT_RESULT ", JSON.stringify(result))
 Input.action_release("interact")
 app.queue_free()
 await process_frame
 quit(0 if result.passed else 1)

func valid_spawns() -> bool:
 var alive := mission.enemies().filter(func(enemy): return enemy.hp > 0)
 for enemy in alive:
  if not world.room_rect.grow(-30).has_point(enemy.position) or enemy.position.distance_to(world.player.position) < 100 or enemy.position.distance_to(world.npc.position) < 100: return false
  for rect in world.obstruction_rects():
   if rect.grow(28).has_point(enemy.position): return false
  for other in alive:
   if enemy != other and enemy.position.distance_to(other.position) < 65: return false
 return true

func test_live_combat() -> void:
 var before := world.save_snapshot()
 var drone: MissionDrone = mission.enemies()[0]
 world.player.position = Vector2(420, 360)
 world.npc.position = Vector2(170, 400)
 drone.position = Vector2(720, 360)
 drone.set_physics_process(true)
 var distance := drone.position.distance_to(world.player.position)
 await frames(35)
 check("research_drone_moves_and_paths", drone.position.distance_to(world.player.position) < distance - 15 and drone.navigation.reachable and drone.collision_mask == 5)
 world.player.position = drone.position + Vector2(-30, 0)
 drone.attack_wait = 0
 var hp := world.player_hp
 app.open_dialogue()
 await frames(5)
 check("research_drone_actual_attack_while_typing", world.player_hp < hp and app.question.has_focus())
 app.close_dialogue()
 app.toggle_pause()
 var paused_position := drone.position
 var paused_hp := world.player_hp
 await create_timer(0.15, true).timeout
 check("pause_freezes_research_combat", drone.position == paused_position and world.player_hp == paused_hp)
 app.toggle_pause()
 drone.set_physics_process(false)
 world.npc_combat_enabled = true
 world.player.position = Vector2(250, 420)
 world.npc.position = Vector2(820, 360)
 drone.position = Vector2(1020, 360)
 world.npc_ammo = 2
 world.npc_shoot_cd = 0
 var enemy_hp := drone.hp
 check("research_harin_real_shot_damage", await until(func(): return drone.hp < enemy_hp and world.npc_ammo < 2, 2))
 world.npc_ammo = 0
 world.npc_reserve = 20
 check("research_harin_reload", await until(func(): return world.npc_ammo > 0 and world.npc_reserve < 20, 3))
 world.npc_hp = 10
 world.take_npc_damage(12)
 check("research_harin_down", world.npc_hp == 0 and "소생" in world.current_guidance())
 world.player.position = world.npc.position + Vector2(0, 30)
 world.apply_interaction("revive_npc")
 check("research_harin_revive", world.npc_hp == 35)
 world.player_hp = 50
 world.heal_cd = 0
 world.npc.position = world.player.position + Vector2(35, 0)
 check("research_shared_heal_accepted", world.request_support("heal"))
 check("research_shared_heal_completed", await until(func(): return world.player_hp > 50, 2))
 # 가구 뒤 탄환/근접 공격 차단과 드론의 가구 우회.
 world.active_action = ""
 world.npc_combat_enabled = false
 world.clear_projectiles()
 world.player.position = Vector2(460, 310)
 drone.position = Vector2(680, 310)
 var blocked_hp := drone.hp
 world.shoot_cd = 0
 world.shoot(drone.position)
 await frames(30)
 check("research_projectile_stops_on_furniture", drone.hp == blocked_hp and not world.clear_line(world.player.position, drone.position))
 drone.set_physics_process(true)
 check("research_drone_routes_around_device", await until(func(): return drone.position.x < 525, 6))
 drone.set_physics_process(false)
 world.npc_combat_enabled = false
 world.restore_snapshot(before)
 freeze_enemies()

func test_legacy_and_validation() -> void:
 DirAccess.make_dir_recursive_absolute(app.save_store.directory)
 var data := envelope()
 check("ready_save_valid", app.save_store.validate(data, world))
 var old := envelope()
 var config := world.scenario_configuration().duplicate(true)
 config.erase("containment")
 old.scenario = JSON.stringify(config).sha256_text()
 old.world.erase("containment")
 old.world.story.stage = "main_entry"
 old.world.story.events.erase("containment_briefed")
 FileAccess.open(app.save_store.path_for(3), FileAccess.WRITE).store_string(JSON.stringify(old))
 var bytes := FileAccess.get_file_as_string(app.save_store.path_for(3))
 check("old_v3_observed_terminal_migrates", app.load_slot(3) and mission.stage == "ready" and world.story.stage == "containment")
 check("old_v3_original_preserved", bytes == FileAccess.get_file_as_string(app.save_store.path_for(3)))
 var earlier := old.duplicate(true)
 config.erase("companion_rules")
 earlier.scenario = JSON.stringify(config).sha256_text()
 check("earlier_v3_companion_compatibility_preserved", app.save_store.validate(earlier, world) and earlier.world.containment.stage == "ready")
 var corrupt_legacy := old.duplicate(true)
 corrupt_legacy.world.story = "broken"
 check("invalid_legacy_story_rejected_safely", not app.save_store.validate(corrupt_legacy, world))
 var bad := envelope()
 bad.world.containment.stage = "panel_ready"
 check("inconsistent_phase_events_rejected", not app.save_store.validate(bad, world))
 bad = envelope()
 bad.world.containment.enemies.Wave2Drone1.hp = 50
 check("unspawned_wave_alive_rejected", not app.save_store.validate(bad, world))
 bad = envelope()
 bad.world.containment.panel.opened = true
 check("premature_panel_save_rejected", not app.save_store.validate(bad, world))

func test_failure_restart(ready: Dictionary) -> void:
 world.restore_snapshot(ready)
 world.apply_interaction("containment_device")
 world.take_damage(1000)
 check("research_player_death_uses_failure", world.defeated and not world.finished and world.get_node("Projectiles").get_child_count() == 0)
 app.toggle_pause()
 app.get_node("DebugPanel/RestartButton").pressed.emit()
 check("failure_restart_button", not world.defeated and world.map_id == "lab" and mission.stage == "unobserved" and not paused and world.ammo == world.initial_ammo)
 world.restore_snapshot(ready)
 world.apply_interaction("containment_device")
 world.ammo = 0
 world.npc_ammo = 0
 world.npc_reserve = 0
 world.supply_packs = 0
 world._physics_process(0.02)
 check("no_ammunition_softlock", world.defeated)
 app.reset_demo(0)
