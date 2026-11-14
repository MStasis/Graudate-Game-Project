extends SceneTree

var checks: Dictionary
var app: Control
var world: DemoWorld
var render := "--render-fleet" in OS.get_cmdline_user_args()
var directory := ProjectSettings.globalize_path("res://../evidence/fleet_sprites")

func _initialize() -> void:
 call_deferred("run")

func check(label: String, result: bool) -> void:
 checks[label] = result
 if not result: push_error("FLEET_CHECK_FAILED " + label)

func frames(count: int) -> void:
 for index in count: await physics_frame

func press_interact() -> void:
 var event := InputEventAction.new()
 event.action = "interact"
 event.pressed = true
 root.push_input(event, true)
 event = InputEventAction.new()
 event.action = "interact"
 root.push_input(event, true)

func capture(name: String) -> void:
 if not render: return
 await process_frame
 await RenderingServer.frame_post_draw
 var screenshot := root.get_texture().get_image()
 check("capture_" + name, not screenshot.is_empty() and not screenshot.is_invisible() and screenshot.save_png(directory.path_join(name + ".png")) == OK)

func run() -> void:
 DirAccess.make_dir_recursive_absolute(directory)
 app = load("res://main.tscn").instantiate()
 root.add_child(app)
 await frames(2)
 world = app.world
 app.brain.auto_enabled = false
 world.npc_combat_enabled = false
 app.question.release_focus()
 check("mika_name_and_portrait", world.npc.display_name == "정비사 미카" and app.get_node("RadioPanel/LabPortrait").texture is AtlasTexture)
 check("mika_model_identity", "미카" in MikaDialogue.build(world.game_state(), "안녕", [], "", "").prompt)
 check("room_spawn_matches_manifest", world.player.position == world.fleet_rooms.lab.cell(world.fleet_rooms.lab.layout.spawn_cell))
 verify_armed()
 await verify_rooms()
 verify_legacy_save()
 await verify_crew()
 await verify_sentry()
 var result := {"passed": not checks.values().has(false), "check_count": checks.size(), "checks": checks, "gpu_rendered": render}
 FileAccess.open(directory.path_join("render.json" if render else "test.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
 print("FLEET_RESULT ", JSON.stringify(result))
 app.queue_free()
 await process_frame
 quit(0 if result.passed else 1)

func verify_armed() -> void:
 for actor in [world.player, world.npc]:
  var sprite: ArmedSprite = actor.animation
  var direction: Array = sprite.data.direction_rows
  var shot: Dictionary = sprite.data.animations.shoot
  var fired := []
  var callback := func(origin, target): fired.append([origin, target])
  sprite.fired.connect(callback)
  check(sprite.data.character + "_nearest_and_pivot", sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and sprite.offset == -SpriteTimeline.pixel(sprite.data.ground_pivot_px))
  var vectors := [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]
  for index in direction.size():
   var row: String = direction[index]
   var target: Vector2 = actor.global_position + vectors[index] * 180
   sprite.reset_animation()
   fired.clear()
   sprite.request_shot(target, Vector2.ZERO)
   var fire_time := float(shot.events[0].time_ms)
   sprite.advance(fire_time - 1)
   check(sprite.data.character + "_waits_for_" + row, fired.is_empty() and sprite.frame_index == 0)
   sprite.advance(1)
   check(sprite.data.character + "_muzzle_" + row, fired.size() == 1 and fired[0][0] == sprite.muzzle(shot.muzzle_px_by_direction[row]) and sprite.frame_index == int(shot.events[0].frame))
   sprite.advance(1000)
   check(sprite.data.character + "_once_" + row, fired.size() == 1 and not sprite.playing)
  sprite.reset_animation()
  fired.clear()
  var moving: Dictionary = sprite.data.moving_fire
  sprite.tick_actor(float(moving.gait_ms_by_direction.left[0] + 1) / 1000.0, Vector2.LEFT * 150, Vector2.UP, true)
  sprite.request_shot(actor.global_position + Vector2.UP * 200, Vector2.LEFT * 150)
  check(sprite.data.character + "_moving_fire_keeps_column", sprite.clip == "move_fire" and sprite.facing == "left" and sprite.frame_index == 1 and fired[0][0] == sprite.muzzle(moving.muzzle_px_by_direction_and_column.left[1]))
  sprite.tick_actor((float(moving.fire_pose_ms) + 1.0) / 1000.0, Vector2.LEFT * 150, Vector2.UP, true)
  check(sprite.data.character + "_moving_recoil_keeps_gait", sprite.clip == "move_recoil" and sprite.frame_index == 1)
  sprite.fired.disconnect(callback)
  sprite.reset_animation()

func verify_rooms() -> void:
 var lab: FleetRoom = world.fleet_rooms.lab
 var storage: FleetRoom = world.fleet_rooms.storage
 var quarters: FleetRoom = world.fleet_rooms.quarters
 world.player.position = lab.cell([10, 6])
 world.npc.position = world.player.position + Vector2(70, 12)
 app.combat_hud.clear_speech()
 await capture("01_research_lab")
 world.player.position = lab.cell(lab.exit_data("s").approach_cells[0])
 press_interact()
 check("south_exit_remains_locked", world.map_id == "lab" and not world.transition_active())
 world.player.position = lab.cell([21, 8])
 press_interact()
 check("wall_beside_east_door_does_not_open_it", not world.transition_active())
 world.player.position = lab.cell(lab.exit_data("e").approach_cells[1])
 Input.action_press("move_right")
 await frames(30)
 Input.action_release("move_right")
 check("walks_up_to_east_door", world.player.position.x > lab.cell([21, 10]).x)
 press_interact()
 check("east_exit_locks_controls_during_fade", world.transition_active() and not world.player.movement_enabled and world.map_id == "lab")
 await frames(24)
 check("quarters_arrival_matches_json", world.map_id == "quarters" and world.player.position == quarters.cell(quarters.exit_data("w").arrival_cell) and not world.transition_active())
 app.save_store.directory = "user://fleet_sprites_test"
 var saved: bool = app.save_slot(1)
 world.player.position = quarters.cell([8, 5])
 await capture("02_gunsmith_quarters")
 check("quarters_save_and_load", saved and app.load_slot(1) and world.player.position == quarters.cell(quarters.exit_data("w").arrival_cell))
 world.player.position = quarters.cabinet_cells[0]
 press_interact()
 await frames(28)
 check("cabinet_opens_to_last_manifest_frame", quarters.cabinets[0].animation == "open" and quarters.cabinets[0].frame == 4)
 press_interact()
 await frames(28)
 check("cabinet_closes_in_reverse_order", quarters.cabinets[0].animation == "close" and quarters.cabinets[0].frame == 4)
 world.player.position = quarters.cell(quarters.exit_data("w").approach_cells[0])
 Input.action_press("move_left")
 await frames(30)
 Input.action_release("move_left")
 check("walks_up_to_quarters_return_door", world.player.position.x < quarters.cell([0, 7]).x)
 press_interact()
 await frames(24)
 check("quarters_return_matches_json", world.map_id == "lab" and world.player.position == lab.cell(lab.exit_data("e").arrival_cell))
 world.player.position = lab.cell(lab.exit_data("w").approach_cells[0])
 press_interact()
 check("flashlight_gate_still_blocks_supply_room", world.map_id == "lab" and not world.transition_active())
 world.flashlight_owned = true
 press_interact()
 await frames(24)
 check("supply_arrival_matches_json", world.map_id == "storage" and world.player.position == storage.cell(storage.exit_data("e").arrival_cell))
 world.player.position = storage.cell([8, 6])
 await capture("03_supply_room")
 world.player.position = storage.cell(storage.exit_data("e").approach_cells[0])
 press_interact()
 await frames(24)
 check("supply_return_matches_json", world.map_id == "lab" and world.player.position == lab.cell(lab.exit_data("w").arrival_cell))
 world.fuse_collected = true
 world.apply_interaction("generator")
 world.player.position = lab.cell(lab.exit_data("n").approach_cells[0])
 press_interact()
 await frames(12)
 check("north_door_finishes_before_swapping", world.map_id == "lab" and world.transition_active())
 await frames(22)
 check("north_door_links_containment", world.map_id == "main_entry" and world.story.tutorial_completed and not world.transition_active())
 world.apply_interaction("lab_gate", true)
 await frames(24)
 check("north_arrival_locks_through_close", world.map_id == "lab" and world.transition_active() and world.player.position == lab.cell(lab.exit_data("n").arrival_cell))
 await frames(22)
 check("north_arrival_unlocks_after_close", not world.transition_active())

func verify_legacy_save() -> void:
 var old: Dictionary = app.save_store.read_slot(1)
 var old_config := world.scenario_configuration(true)
 old.scenario = JSON.stringify(old_config).sha256_text()
 old.world.map_id = "lab"
 old.world.player_position = [223, 350]
 old.world.npc_position = [365, 245]
 old.world.wait_position = [365, 245]
 old.world.flashlight_position = [390, 270]
 for enemy in old_config.enemies:
  old.world.enemies[str(enemy.name)].position = [enemy.spawn.x, enemy.spawn.y]
 old.exploration = {"lab": [1, 2, 3]}
 old.atlas = {}
 old.journal = [{"id": "legacy-1", "sequence": 1, "sender": "하린", "body": "하린이 먼저 갈게.", "room": "lab", "trial": "legacy", "time": "0", "channel": "dialogue", "repeat": 1}]
 old.history = [{"question": "같이 가?", "answer": "하린이 먼저 갈게."}]
 var path: String = app.save_store.path_for(2)
 FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(old))
 var original := FileAccess.get_sha256(path)
 var loaded: bool = app.load_slot(2)
 check("legacy_layout_loads_without_rewriting_slot", loaded and world.room_rect.has_point(world.player.position) and world.player.position != Vector2(223, 350) and FileAccess.get_sha256(path) == original)
 check("legacy_dialogue_uses_mika", loaded and app.combat_hud.journal.entries[0].sender == "미카" and "미카가" in app.brain.history[0].answer)

func verify_crew() -> void:
 world.reset_world()
 world.npc_combat_enabled = false
 world.flashlight_owned = true
 world.apply_interaction("storage_gate")
 for other in world.room_enemies(): other.set_physics_process(false)
 var crew: MissionDrone = world.room_enemies()[0]
 crew.set_physics_process(true)
 world.player.position = world.fleet_rooms.storage.cell([8, 7])
 world.npc.position = world.player.position + Vector2(120, 40)
 crew.position = world.player.position + Vector2(24, 0)
 crew.attack_wait = 0
 await frames(3)
 check("crew_windup_before_damage", crew.animation.clip == "attack" and world.player_hp == world.max_hp)
 await frames(20)
 check("crew_no_damage_before_430ms", world.player_hp == world.max_hp)
 await frames(8)
 check("crew_damage_at_melee_event", world.player_hp == world.max_hp - crew.contact_damage)
 crew.take_damage(1, crew.global_position)
 crew.animation.advance(45)
 crew.take_damage(1, crew.global_position + Vector2(6, 0))
 var sparks := world.get_node("SupportFX").get_children().filter(func(node): return node is BulletImpact)
 check("crew_restarts_hit_and_each_contact_has_spark", crew.animation.frame_index == 0 and sparks.size() == 2 and sparks[1].global_position == crew.global_position + Vector2(6, 0))
 crew.take_damage(crew.hp)
 check("crew_death_removes_collision_but_keeps_animation", crew.visible and crew.collision_layer == 0 and crew.animation.clip == "death")
 crew.animation.advance(899)
 check("crew_visible_until_metadata_death_event", crew.visible)
 crew.animation.advance(1)
 check("crew_hidden_at_900ms", not crew.visible)

func verify_sentry() -> void:
 world.reset_world()
 world.npc_combat_enabled = false
 world.flashlight_owned = true
 world.apply_interaction("storage_gate")
 var enemy: MissionDrone = world.room_enemies()[0]
 var other: MissionDrone = world.room_enemies()[1]
 world.room_enemies()[2].take_damage(999)
 for target in world.room_enemies(): target.set_physics_process(false)
 var center := world.safe_position
 world.player.position = center + Vector2(0, 105)
 world.npc.position = center
 enemy.position = center + Vector2(105, 0)
 other.position = center + Vector2(0, -210)
 var shots := []
 var callback := func(origin, target, damage): shots.append({"origin": origin, "target": target, "damage": damage})
 world.sentry.fired.connect(callback)
 check("sentry_uses_existing_cover_order", world.request_support("deploy_cover"))
 await frames(5)
 check("sentry_starts_hover_and_preserves_cover", world.sentry.visible and world.sentry.clip == "drone_hover" and world.cover_charges == 0)
 await frames(108)
 check("rapid_event_uses_muzzle_and_damages_enemy", shots.any(func(shot): return shot.damage == SupportSentry.RAPID_DAMAGE and shot.origin == world.sentry.muzzle([98, 62])) and enemy.hp < enemy.max_hp)
 if render:
  app.combat_hud.clear_speech()
  world.power_restored = true
  world._sync_state()
  world.player.position = center + Vector2(-70, 35)
  await capture("04_support_sentry")
 enemy.take_damage(999)
 await frames(104)
 check("rail_event_uses_muzzle_and_damages_enemy", shots.any(func(shot): return shot.damage == SupportSentry.RAIL_DAMAGE and shot.origin == world.sentry.muzzle([64, 16])) and other.hp < other.max_hp)
 world.sentry.fired.disconnect(callback)
 world.apply_interaction("lab_gate")
 check("room_swap_stops_support_and_clears_shots", not world.sentry.visible and world.cover_time == 0 and world.get_node("Projectiles").get_child_count() == 0)
