extends SceneTree
var checks := {}
var events: Array[Dictionary] = []
var app: Control
var world: DemoWorld
var render := false
var directory := ""

func _initialize() -> void:
 render = "--render-mechanics" in OS.get_cmdline_user_args()
 call_deferred("run")

func check(label: String, result: bool) -> void:
 checks[label] = result
 if not result: push_error("MECHANICS_FAILED " + label + " save_error=" + (app.save_store.last_error if app else ""))

func wait_for(condition: Callable, seconds := 5.0) -> bool:
 var deadline := Time.get_ticks_msec() + int(seconds * 1000)
 while not condition.call() and Time.get_ticks_msec() < deadline:
  await create_timer(0.02).timeout
 return condition.call()

func frames(count := 3) -> void:
 for index in range(count): await physics_frame

func interact_event() -> void:
 var event := InputEventAction.new()
 event.action = "interact"
 event.pressed = true
 root.push_input(event, true)

func key(code: int) -> void:
 var event := InputEventKey.new()
 event.physical_keycode = code
 event.keycode = code
 event.pressed = true
 root.push_input(event, true)
 await frames()

func aim(point: Vector2) -> void:
 app._update_world_view()
 var event := InputEventMouseMotion.new()
 event.position = world.get_global_transform_with_canvas() * point
 root.push_input(event, true)
 await frames()

func capture(stem: String) -> void:
 if not render: return
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(directory.path_join(stem + ".png"))

func run() -> void:
 directory = ProjectSettings.globalize_path("res://../evidence/mission_mechanics")
 DirAccess.make_dir_recursive_absolute(directory)
 app = load("res://main.tscn").instantiate()
 root.add_child(app)
 world = app.world
 app.brain.auto_enabled = false
 app.save_store.directory = "user://mechanics_test_%d" % OS.get_process_id()
 world.game_event.connect(func(event): events.append(event.duplicate(true)))
 check("starts_without_flashlight", not world.flashlight_owned and world.map_id == "lab")
 world.apply_interaction("storage_gate")
 check("dark_room_requires_pickup", world.map_id == "lab" and not world.flashlight_owned and (world.flashlight_requested or world.flashlight_dropped))
 world.player.position = world.get_node("ToStorage").position + Vector2(65, 0)
 check("harin_approaches_and_drops_real_pickup", await wait_for(func(): return world.flashlight_dropped, 6))
 check("ground_pickup_is_visible", world.get_node("FlashlightPickup").is_visible_in_tree() and not world.flashlight_owned)
 await capture("01_flashlight_drop")
 # 실제 E 입력 경로로 줍는다. 가까운 NPC보다 줍기 물체를 우선한다.
 world.player.position = world.get_node("FlashlightPickup").position + Vector2(0, 20)
 interact_event()
 await frames()
 check("e_collects_flashlight_without_opening_chat", world.flashlight_owned and not world.flashlight_dropped and not app.question.has_focus())
 world.apply_interaction("storage_gate")
 check("storage_entry_after_pickup", world.map_id == "storage" and world.get_node("Darkness").visible)
 check("storage_chat_hidden_until_enter", not app.is_noncombat() and not app.dialogue_panel.visible)
 check("storage_never_shows_portrait", not app.get_node("RadioPanel/LabPortrait").is_visible_in_tree())
 world.player.position = Vector2(375, 330)
 world.player.facing_direction = Vector2.RIGHT
 await aim(world.player.position + Vector2(300, 0))
 world.update_visibility()
 var forward := world.player.position + Vector2(240, 0)
 var far_point := world.player.position + Vector2(350, 0)
 check("beam_extends_beyond_circle", world.visibility_at(forward) > 0.2 and world.visibility_at(world.player.position - Vector2(240, 0)) < 0.01)
 check("beam_fades_with_distance", world.visibility_at(forward) > world.visibility_at(far_point) and world.visibility_at(far_point) > 0)
 check("beam_is_sector_not_full_circle", world.visibility_at(world.player.position + Vector2(0, 240)) < 0.01)
 world.player.position = Vector2(420, 288)
 await aim(world.player.position + Vector2(0, 300))
 Input.action_press("move_down")
 await frames(6)
 Input.action_release("move_down")
 check("beam_follows_mouse_aim", world.flashlight_direction().y > 0.9)
 await capture("02_flashlight_sector")
 if render:
  var picture := root.get_texture().get_image()
  var transform := world.get_global_transform_with_canvas()
  var lit := picture.get_pixelv(Vector2i(transform * (world.player.position + Vector2(0, 230))))
  var edge := picture.get_pixelv(Vector2i(transform * (world.player.position + Vector2(230, 0))))
  var distant := picture.get_pixelv(Vector2i(transform * (world.player.position + Vector2(0, 280))))
  check("rendered_beam_is_directional", lit.r + lit.g + lit.b > edge.r + edge.g + edge.b + 0.015)
  check("rendered_beam_fades_with_distance", lit.r + lit.g + lit.b > distant.r + distant.g + distant.b + 0.002)
 world.player.facing_direction = Vector2.RIGHT
 world.npc_combat_enabled = false
 for enemy in world.get_node("Enemies").get_children(): enemy.set_physics_process(false)
 for index in world.room_enemies().size():
  var enemy: MissionDrone = world.room_enemies()[index]
  enemy.position = world.fleet_rooms.storage.cell([6 + index * 2, 4])
  for shot in range(4):
   if enemy.hp <= 0: break
   world.player.position = enemy.position + Vector2(0, 100)
   world.ammo = 20
   world.shoot_cd = 0
   world.shoot(enemy.position)
   await frames(14)
 check("real_projectiles_clear_current_wave", world.enemies_remaining() == 0)
 check("clear_does_not_open_full_dialogue", not app.is_noncombat() and not app.dialogue_panel.visible and not app.get_node("RadioPanel/LabPortrait").is_visible_in_tree())
 check("locker_keeps_fuse_hidden_after_combat", not world.locker.opened and not world.fuse.visible)
 world.apply_interaction("fuse")
 check("fuse_cannot_bypass_locker", not world.fuse_collected)
 await key(KEY_ENTER)
 check("enter_opens_only_small_composer", app.dialogue_panel.visible and app.dialogue_panel.size.y == 64 and app.question.has_focus() and not app.answer.is_visible_in_tree())
 app.question.text = "패널은 어떻게 해?"
 await key(KEY_ENTER)
 check("submit_closes_chat_and_clears_sent_text", not app.dialogue_panel.visible and app.question.text.is_empty() and world.can_move)
 check("reply_only_in_bottom_caption", app.combat_hud.hud.get_node("%Line").text == app.answer.text and "패널" in app.answer.text and not app.dialogue_panel.visible and not app.combat_hud.npc_bubble.visible)
 await key(KEY_ENTER)
 app.question.text = "보내지 않은 초안"
 await key(KEY_ESCAPE)
 check("escape_closes_chat_and_keeps_draft", not app.dialogue_panel.visible and app.question.text == "보내지 않은 초안" and not app.pause_menu.visible)
 world.player.position = world.locker.panel_position(0) + Vector2(0, 35)
 world.npc.position = world.player.position - Vector2(110, 0)
 world.npc_motion.reset()
 Input.action_press("interact")
 app.interact("panel_a")
 check("panel_hint_uses_system_notice_not_dialogue", "E" in app.combat_hud.system_notices.latest_text and not app.dialogue_panel.visible)
 check("rule_policy_sees_panel_task", "assist_panel" in world.valid_actions() and NPCPolicy.rule_action(world.game_state()) == "assist_panel")
 app.brain.request_decision()
 check("shared_executor_accepts_panel_choice", world.active_action == "assist_panel")
 await frames(10)
 check("one_panel_alone_never_charges", world.locker.progress == 0 and not world.locker.opened)
 check("npc_reaches_opposite_panel_smoothly", await wait_for(func(): return world.locker.hold_started, 6))
 await create_timer(0.35).timeout
 Input.action_release("interact")
 await frames()
 check("early_release_resets_progress", world.locker.progress == 0 and not world.locker.opened and world.active_action.is_empty())
 Input.action_press("interact")
 world.apply_interaction("panel_a")
 app.brain.request_decision()
 check("two_panels_reach_one_second", await wait_for(func(): return world.locker.sequence_elapsed >= 0, 4))
 check("one_second_starts_beeps_before_open", not world.locker.opened and world.locker.progress >= 1.0)
 check("committed_unlock_survives_save_load", app.save_slot(1) and app.load_slot(1) and world.locker.sequence_elapsed >= 0 and not world.locker.opened)
 Input.action_release("interact")
 check("beeps_then_unlock", await wait_for(func(): return world.locker.opened, 2))
 var beeps := events.filter(func(event): return event.event == "locker_beep")
 check("exactly_three_beep_pairs", beeps.size() == 6 and beeps[5].index == 5)
 check("fuse_and_supply_spawn_after_unlock", world.fuse.is_visible_in_tree() and world.get_node("LockerSupply").is_visible_in_tree())
 check("successful_cooperation_is_logged", events.any(func(event): return event.event == "support_completed" and event.get("action") == "assist_panel"))
 await capture("03_locker_open_combat_ui")
 world.player.position = world.fuse.position + Vector2(0, 30)
 interact_event()
 await frames()
 check("e_recovers_unlocked_fuse", world.fuse_collected)
 world.ammo = 3
 world.apply_interaction("locker_supply")
 world.apply_interaction("locker_supply")
 check("locker_supply_can_only_be_taken_once", world.ammo == 13 and world.locker.supply_taken)
 await test_motion()
 check("new_mechanics_save_to_slot", app.save_slot(1))
 world.flashlight_owned = false
 world.locker.opened = false
 check("load_restores_light_and_locker", app.load_slot(1) and world.flashlight_owned and world.locker.opened and world.locker.supply_taken)
 world.apply_interaction("lab_gate")
 check("lab_restores_full_dialogue_profile", app.is_noncombat() and app.dialogue_panel.noncombat_mode)
 world.apply_interaction("generator")
 world.apply_interaction("storage_gate")
 check("power_restore_removes_blackout_permanently", world.power_restored and world.get_node("Darkness").material.get_shader_parameter("ambient_enabled") == true and world.visibility_at(world.player.position) == 1.0)
 app.combat_hud.minimap.remember_position()
 check("powered_map_keeps_discovery", app.combat_hud.minimap.explored.storage.size() > 0 and world.visibility_at(world.player.position) == 1.0)
 await capture("04_power_restored_storage")
 check("powered_state_saves", app.save_slot(2))
 world.power_restored = false
 check("powered_state_loads_without_blackout", app.load_slot(2) and world.power_restored and world.get_node("Darkness").material.get_shader_parameter("ambient_enabled") == true)
 var before_beeps := events.filter(func(event): return event.event == "locker_beep").size()
 await frames(8)
 check("loaded_open_locker_does_not_beep_again", events.filter(func(event): return event.event == "locker_beep").size() == before_beeps)
 var data: Dictionary = app.save_store.read_slot(2)
 var broken: Dictionary = data.duplicate(true)
 broken.world.locker.opened = false
 var protected_state := world.save_snapshot()
 check("contradictory_locker_save_rejected", not app.save_store.validate(broken, world) and world.save_snapshot() == protected_state)
 var legacy: Dictionary = data.duplicate(true)
 legacy.version = 1
 var legacy_config := world.scenario_configuration().duplicate(true)
 legacy_config.erase("mechanics")
 legacy.scenario = JSON.stringify(legacy_config).sha256_text()
 for field in ["flashlight_owned", "flashlight_dropped", "flashlight_position", "facing", "locker"]: legacy.world.erase(field)
 FileAccess.open(app.save_store.path_for(3), FileAccess.WRITE).store_string(JSON.stringify(legacy))
 var legacy_hash := FileAccess.get_sha256(app.save_store.path_for(3))
 check("compatible_legacy_save_migrates", app.load_slot(3) and world.flashlight_owned and world.locker.opened)
 check("legacy_slot_file_is_preserved", legacy_hash == FileAccess.get_sha256(app.save_store.path_for(3)))
 world.apply_interaction("lab_gate")
 world.apply_interaction("exit")
 check("mechanics_roundtrip_enters_main", world.map_id == "main_entry" and world.story.tutorial_completed and not world.finished)
 for slot in range(1, 4): DirAccess.remove_absolute(app.save_store.path_for(slot))
 DirAccess.remove_absolute(app.save_store.directory)
 Input.action_release("interact")
 var result := {"suite": "mission_mechanics_v2", "passed": not checks.values().has(false), "check_count": checks.size(), "checks": checks, "gpu_rendered": render, "human_playtest": false, "actual_ime_tested": false, "live_llm_calls": 0}
 FileAccess.open(directory.path_join("render.json" if render else "test.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
 print("MECHANICS_RESULT ", JSON.stringify(result))
 app.queue_free()
 await process_frame
 await create_timer(0.15).timeout
 quit(0 if result.passed else 1)

func test_motion() -> void:
 world.player.position = Vector2(450, 300)
 world.npc.position = Vector2(420, 280)
 world.player.facing_direction = Vector2.RIGHT
 var targets := []
 for phase in range(4):
  world.npc_motion.elapsed = phase * 5.0
  targets.append(world.npc_motion.formation_target(world, 0.016))
 check("formation_has_no_clock_side_switch", targets[0] == targets[1] and targets[2] == targets[1])
 world.npc_motion.reset()
 var rear: Vector2 = world.npc_motion.formation_target(world, 0.016)
 check("ranged_profile_stays_behind", rear.x < world.player.position.x - 60)
 world.npc.position = rear
 world.npc.velocity = Vector2.ZERO
 var target: MissionDrone = world.get_node("Enemies/DroneA")
 target.position = world.player.position + Vector2(72, 64)
 target.hp = target.max_hp
 target.visible = true
 target.collision_layer = 2
 var ammo_before := world.npc_ammo
 world.npc_combat_enabled = true
 world.npc_shoot_cd = 0
 world._npc_fire()
 await frames(28)
 check("rear_companion_can_hit_while_covering", world.npc_ammo == ammo_before - 1 and target.hp == target.max_hp - world.npc_bullet_damage)
 world.npc_combat_enabled = false
 target.hp = 0
 target.visible = false
 target.collision_layer = 0
 world.npc_role = 2
 var front: Vector2 = world.npc_motion.formation_target(world, 0.016)
 check("vanguard_profile_leads", front.x > world.player.position.x + 60)
 world.npc_role = 0
 world.npc_motion.reset()
 var before := world.npc.position
 world.npc_motion.move_to(world, Vector2(800, 330), 1.0 / 60.0)
 check("movement_accelerates_without_teleport", world.npc_motion.velocity.length() <= 13 and world.npc.position.distance_to(before) < 1)
 world.npc.position = world.player.position
 world.npc_motion.reset()
 var separation: Vector2 = world.npc_motion.formation_target(world, 0.016)
 check("close_companion_yields_space", separation.distance_to(world.player.position) > 80)
 world.npc.position = Vector2(170, 200)
 world.npc_motion.reset()
 world.npc_motion.formation_target(world, 0.016)
 check("distant_companion_uses_catchup", world.npc_motion.pattern == "따라잡기")
