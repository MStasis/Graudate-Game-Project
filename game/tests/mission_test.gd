extends SceneTree
var checks := {}
func _initialize() -> void:
 call_deferred("run")
func check(name: String, value: bool) -> void:
 checks[name] = value
 if not value: push_error("CHECK_FAILED " + name)
func frames(count: int) -> void:
 for index in range(count): await physics_frame

func run() -> void:
 var app = load("res://main.tscn").instantiate()
 root.add_child(app)
 await process_frame
 var world: DemoWorld = app.world
 var brain: NPCBrain = app.brain
 brain.auto_enabled = false
 check("starts_in_lab", world.map_id == "lab" and not world.get_node("Darkness").visible)
 check("fuse_not_in_lab", not world.fuse.visible)
 world.apply_interaction("fuse")
 check("cannot_collect_fuse_in_lab", not world.fuse_collected)
 world.apply_interaction("generator")
 check("power_requires_fuse", not world.power_restored)
 world.apply_interaction("exit")
 check("exit_requires_power", not world.finished)
 var start := world.player.position
 Input.action_press("move_right")
 await frames(5)
 Input.action_release("move_right")
 check("keyboard_moves_player", world.player.position.x > start.x + 4)
 app.question.grab_focus()
 var stopped := world.player.position
 Input.action_press("move_right")
 await frames(5)
 Input.action_release("move_right")
 check("typing_blocks_movement", world.player.position.distance_to(stopped) < 1)
 app.question.release_focus()
 world.apply_interaction("storage_gate")
 check("dark_room_and_return_gate", world.map_id == "storage" and world.get_node("Darkness").visible and world.get_node("ToLab").visible)
 world.apply_interaction("fuse")
 check("fuse_requires_combat_clear", not world.fuse_collected and world.enemies_remaining() == 3)
 world.take_damage(20)
 check("combat_has_real_hp_damage", world.player_hp == 80)
 app.question.grab_focus()
 world.take_damage(4)
 check("typing_does_not_pause_combat", world.player_hp == 76)
 app.question.release_focus()
 world.player_hp = 40
 world.npc.position = world.player.position + Vector2(45, 0)
 var npc_before := world.npc.position
 check("heal_order_accepted", world.request_support("heal"))
 await frames(12)
 check("direct_heal_consumes_one_kit", world.player_hp == 75 and world.medkits == 1)
 check("npc_approaches_player", world.npc.position.distance_to(world.player.position) < npc_before.distance_to(world.player.position))
 check("heal_cooldown_rejects_repeat", not world.request_support("heal"))
 world.ammo = 18
 check("resupply_order_accepted", world.request_support("resupply"))
 await frames(12)
 check("supply_capped_and_consumed_once", world.ammo == 20 and world.supply_packs == 1)
 check("supply_not_wasted_when_full", not world.request_support("resupply"))
 world.npc.position = world.safe_position - Vector2(90, 0)
 check("cover_order_accepted", world.request_support("deploy_cover"))
 await frames(45)
 check("cover_installed_with_charge", world.cover_time > 0 and world.cover_charges == 0)
 world.player.position = world.safe_position
 world.player_hp = 100
 world.take_damage(12)
 check("cover_halves_real_damage", world.player_hp == 94)
 world.player.position = world.safe_position - Vector2(0, 120)
 var player_before := world.player.position
 var callouts: Array[String] = []
 world.notice.connect(func(text): callouts.append(text))
 check("guide_order_accepted", world.request_support("guide_to_cover"))
 check("guide_uses_actual_down_direction", callouts.size() > 0 and callouts.back().contains("아래쪽"))
 check("guide_does_not_move_player", world.player.position == player_before)
 world.take_damage(12)
 check("outside_cover_takes_full_damage", world.player_hp == 82)
 world.medkits = 0
 world.heal_cd = 0
 check("no_free_heal_without_kit", not world.request_support("heal"))
 check("unknown_action_rejected", not world.request_support("invent_item"))
 var snapshot := world.game_state()
 var stale_record := {"request_id": 999, "kind": "decision", "question": "", "snapshot": snapshot, "snapshot_hash": "fixture", "allowed": snapshot.valid_actions, "started_usec": Time.get_ticks_usec(), "epoch": world.epoch - 1}
 brain.pending = stale_record
 brain._resolve("follow", {"actual_model": "synthetic_stale_fixture"})
 check("stale_epoch_recorded", brain.pending.is_empty())
 brain.pending = stale_record.duplicate(true)
 brain.pending.epoch = world.epoch
 brain.pending.started_usec = Time.get_ticks_usec() - 5000000
 var late: Array[Dictionary] = []
 brain.measured.connect(func(record): late.append(record))
 brain._resolve("follow", {"actual_model": "synthetic_late_fixture"})
 check("late_decision_rejected", late.size() > 0 and late.back().rejected_reason == "stale_age")
 var fixture := {"model": "fixture-not-live", "answers": {"selection": {"type": "choice", "choice": "heal", "confidence": 0.8, "probabilities": {"heal": 0.9, "wait": 0.1}}}}
 check("jev_fixture_decodes_choice", NPCPolicy.parse_jev(fixture, ["heal", "wait"]).get("choice") == "heal")
 fixture.answers.selection.choice = "invent_item"
 check("jev_rejects_unknown_choice", NPCPolicy.parse_jev(fixture, ["heal", "wait"]).has("error"))
 fixture.answers.selection.choice = "heal"
 fixture.answers.selection.probabilities.heal = 1.5
 check("jev_rejects_invalid_probability", NPCPolicy.parse_jev(fixture, ["heal", "wait"]).has("error"))
 var payload := NPCPolicy.jev_payload("decision", world.game_state(), "", "fixture")
 check("jev_criteria_matches_common_actions", payload.questions.selection.criteria.keys() == world.valid_actions())
 check("everyday_intent_supported", NPCPolicy.rule_intent("오늘 기분은 어때?") == "everyday")
 check("friendship_is_shared_context", world.game_state().relationship.contains("친한 동료"))
 # 실제 입력 이벤트와 물리 레이 판정. 고정 표적은 무기 적중 검사에만 사용한다.
 for enemy in world.get_node("Enemies").get_children(): enemy.active = false
 var victim = world.get_node("Enemies/DroneA")
 world.player.position = victim.position - Vector2(110, 0)
 world.ammo = 20
 var input := InputEventAction.new()
 input.action = "attack"
 input.pressed = true
 root.push_input(input, true)
 await frames(15)
 check("attack_input_spawns_hitting_projectile", victim.hp < victim.max_hp)
 var close_hp: int = victim.hp
 victim.active = false
 world.player.position = victim.position - Vector2(15, 0)
 world.shoot_cd = 0.0
 world.shoot(victim.position)
 await frames(4)
 check("close_range_projectile_hits", victim.hp < close_hp)
 for enemy in world.get_node("Enemies").get_children():
  while enemy.hp > 0:
   for other in world.get_node("Enemies").get_children(): other.active = false
   world.player.position = enemy.position - Vector2(100, 0)
   world.shoot_cd = 0.0
   world.ammo = 20
   world.shoot(enemy.position)
   await frames(15)
 check("real_projectiles_clear_wave", world.enemies_remaining() == 0)
 world.apply_interaction("fuse")
 check("fuse_collects_after_clear", world.fuse_collected and world.game_state().fuse_in_inventory)
 world.apply_interaction("lab_gate")
 check("returns_to_lab_with_item", world.map_id == "lab" and world.fuse_collected and not world.get_node("Darkness").visible)
 world.apply_interaction("generator")
 check("power_consumes_fuse_inventory", world.power_restored and not world.game_state().fuse_in_inventory)
 world.apply_interaction("exit")
 check("roundtrip_can_complete", world.finished)
 brain.new_trial(0)
 check("restart_restores_full_trial", world.player_hp == 100 and world.ammo == world.initial_ammo and world.medkits == 2 and world.cover_charges == 1 and world.enemies_remaining() == 3 and not world.fuse_collected)
 world.player.position = Vector2(world.room_rect.end.x - 20, 260)
 Input.action_press("move_right")
 await frames(18)
 Input.action_release("move_right")
 check("native_wall_collision", world.player.position.x < world.room_rect.end.x - 8)
 var old_key := OS.get_environment("TYPESAFE_API_KEY")
 OS.set_environment("TYPESAFE_API_KEY", "")
 brain.new_trial(2)
 brain.request_decision()
 check("jev_keyless_no_network_or_fallback", brain.jev_calls == 0 and brain.jev_disabled == "missing_api_key" and brain.provider == 2)
 OS.set_environment("TYPESAFE_API_KEY", old_key)
 # 씬 저장/재로드 후 사용자의 설정이 남는지 검증한다.
 var edited := (load("res://scenes/World.tscn") as PackedScene).instantiate() as DemoWorld
 edited.get_node("Player").position = Vector2(205, 340)
 edited.get_node("Player").move_speed = 255.0
 edited.sight_radius = 180.0
 edited.get_node("NPC").display_name = "검증용 하린"
 var saved := PackedScene.new()
 check("scene_pack", saved.pack(edited) == OK)
 check("scene_save", ResourceSaver.save(saved, "user://mission_roundtrip.tscn") == OK)
 edited.free()
 var restored := (ResourceLoader.load("user://mission_roundtrip.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as DemoWorld
 root.add_child(restored)
 await process_frame
 check("saved_spawn_and_speed", restored.player.position == Vector2(205, 340) and restored.player.move_speed == 255.0)
 check("saved_light_and_npc", restored.sight_radius == 180.0 and restored.npc.display_name == "검증용 하린")
 restored.player.position += Vector2(80, 0)
 restored.reset_world()
 check("restart_uses_saved_spawn", restored.player.position == Vector2(205, 340))
 var passed := true
 for value in checks.values(): passed = passed and value
 var result := {"suite": "mission_v1", "synthetic_test": true, "passed": passed, "check_count": checks.size(), "checks": checks, "jev_live_calls": 0}
 var path := ProjectSettings.globalize_path("res://../evidence/mission_v1").simplify_path()
 DirAccess.make_dir_recursive_absolute(path)
 var file := FileAccess.open(path.path_join("mission_test.json"), FileAccess.WRITE)
 file.store_string(JSON.stringify(result, "  "))
 print("MISSION_TEST ", JSON.stringify(result))
 quit(0 if passed else 1)
