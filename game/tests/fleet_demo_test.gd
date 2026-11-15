extends SceneTree
## Plays the title flow using gameplay input. State reads locate targets and verify transitions.
const Fleet := preload("res://scripts/fleet_demo.gd")
const Mission := preload("res://main.gd")
var app: Mission
var world: DemoWorld
var demo: Fleet
var checks := {}
var events: Array[Dictionary]
var evidence: String
var render := false

func _initialize() -> void:
	run.call_deferred()

func check(id: String, result: bool) -> bool:
	checks[id] = result
	if not result: push_error("FLEET_DEMO_FAILED " + id)
	return result

func key(code: Key, down := true, repeat := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	event.echo = repeat
	root.push_input(event, true)

func tap(code: Key) -> void:
	key(code)
	key(code, false)

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

func until(predicate: Callable, limit := 600) -> bool:
	for index in limit:
		await physics_frame
		if predicate.call():
			await process_frame
			return true
	return false

func finish_lines() -> void:
	for i in 24:
		if not demo.voice_active: return
		var remaining := demo._dialogue.size()
		tap(KEY_SPACE)
		await frames(2)
		if remaining == 0: return

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

func capture(stem: String) -> void:
	if not render: return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var center := Vector2i(Vector2(image.get_size()) * 0.5)
	var has_art := image.get_pixel(0, 0) != image.get_pixelv(center)
	check(stem + "_png", has_art and image.save_png(evidence.path_join(stem + ".png")) == OK)

func move(point: Vector2, radius := 12.0, budget := 420, stop_for_dialogue := false) -> bool:
	var previous := []
	for index in budget:
		if stop_for_dialogue and demo.voice_active: break
		var offset := point - world.player.position
		if offset.length() <= radius: break
		var desired := []
		if absf(offset.x) > 6: desired.append("move_right" if offset.x > 0 else "move_left")
		if absf(offset.y) > 6: desired.append("move_down" if offset.y > 0 else "move_up")
		for action in previous:
			if action not in desired: Input.action_release(action)
		for action in desired:
			if action not in previous: Input.action_press(action)
		previous = desired
		await physics_frame
		if world.defeated: break
	for action in previous: Input.action_release(action)
	await frames(2)
	var reached := (stop_for_dialogue and demo.voice_active) or world.player.position.distance_to(point) <= radius + 5
	if not reached: print("MOVE BLOCKED ", world.map_id, " from ", world.player.position, " to ", point, " · step ", demo.step, " · ", app._fleet_line)
	return reached

func enter_door(id: String, destinations: Array[String], waypoints: Array = []) -> bool:
	var origin: String = world.map_id
	var door: Dictionary = demo.room().doors[id]
	for point in waypoints:
		if not await move(point): return check(origin + "_" + id + "_waypoint", false)
	if not await move(Fleet.Room.pixel(door.point_px), 23): return check(origin + "_" + id + "_approach", false)
	tap(KEY_E)
	await frames(2)
	if origin in destinations and not world.transition_active(): return true
	var arrived := await until(func(): return world.map_id in destinations and not world.transition_active(), 180)
	if not arrived: print("DOOR FAILED ", id, " current ", world.map_id, " nearest ", demo.nearest_interaction())
	if arrived:
		var spawn := Fleet.Room.pixel(demo.room().doors[door.target_door].arrival_px)
		check(origin + "_" + id + "_arrival_safe", world.player.position.distance_to(spawn) < 2 and world.room_rect.grow(-14).has_point(world.player.position) and world.player.position.distance_to(world.npc.position) > 20)
	return check(origin + "_" + id + "_entry", arrived)

func click_enemy(enemy: MissionDrone) -> void:
	click(world.get_global_transform_with_canvas() * enemy.aim_position())

func fight(phase: int, frames_limit: int) -> bool:
	for index in frames_limit:
		await physics_frame
		if demo.step != phase or world.defeated: break
		if world.shoot_cd > 0.0: continue
		var targets := world.room_enemies().filter(func(enemy): return enemy.hp > 0 and world.clear_line(world.player.position, enemy.position))
		targets.sort_custom(func(a, b): return world.player.position.distance_squared_to(a.position) < world.player.position.distance_squared_to(b.position))
		if not targets.is_empty(): click_enemy(targets[0])
	if demo.step == phase or world.defeated:
		print("COMBAT STOPPED · HP ", world.player_hp, " / ammo ", world.ammo, " / packs ", world.supply_packs,
			" / enemies ", world.room_enemies().filter(func(enemy): return enemy.hp > 0).map(func(enemy): return [enemy.name, enemy.hp, enemy.position]))
	return not world.defeated and demo.step != phase

func count_event(id: String) -> int:
	return events.filter(func(event): return event.event == id).size()

func waves_match_markers() -> bool:
	var markers := []
	for number in range(1, 4):
		var group := demo.rooms.research_lab_b.get_node("Wave_%d" % number) as Node2D
		for marker: Marker2D in group.get_children(): markers.append(marker.position)
	return demo.unit_pool.slice(1).map(func(enemy): return enemy.get_meta("spawn")) == markers

func has_line(body: String) -> bool:
	return app.combat_hud.journal.entries.any(func(entry): return entry.channel == "dialogue" and entry.body == body)

func run() -> void:
	render = "--render-fleet-demo" in OS.get_cmdline_user_args()
	evidence = ProjectSettings.globalize_path("res://../evidence/fleet_demo")
	DirAccess.make_dir_recursive_absolute(evidence)
	root.size = Vector2i(1280, 800)
	await play()
	var result := {"passed": not checks.values().has(false) and checks.get("result_returns_to_title", false), "check_count": checks.size(),
		"checks": checks, "events": events, "gpu_rendered": render, "created_utc": Time.get_datetime_string_from_system(true)}
	FileAccess.open(evidence.path_join("render.json" if render else "test.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	print("FLEET_DEMO_RESULT ", JSON.stringify({"passed": result.passed, "checks": checks}))
	quit(0 if result.passed else 1)

func play() -> void:
	change_scene_to_file(str(ProjectSettings.get_setting("application/run/main_scene")))
	await frames(3)
	tap(KEY_ENTER)
	await frames(5)
	app = current_scene.get_node_or_null("Main") as Mission
	if not check("title_new_game", app != null): return
	app.save_store.directory = "user://fleet_demo_test_%d" % OS.get_process_id()
	world = app.world
	demo = world.fleet_demo
	world.game_event.connect(func(event): events.append(event))
	if not check("starts_in_dark_left_corridor", world.map_id == "corridor" and world.player.position == Fleet.START and not world.power_restored): return
	if not check("radio_and_input_lock", await until(func(): return demo.voice_active, 150) and not world.can_move): return
	await capture("01_radio")
	app.combat_hud.toggle_history()
	check("scripted_dialogue_cannot_open_history", not app.combat_hud.modal_open())
	await frames(400)
	check("radio_waits_for_input", app._fleet_line == Fleet.Lines.RADIO[0][1] and not world.can_move and not demo._door_arrow.visible)
	key(KEY_SPACE, true, true)
	check("held_space_does_not_advance", app._fleet_line == Fleet.Lines.RADIO[0][1])
	tap(KEY_SPACE)
	check("space_advances_one_line", app._fleet_line == Fleet.Lines.RADIO[1][1] and not world.can_move)
	var ammo_at_radio := world.ammo
	click(Vector2(350, 400))
	await frames(2)
	check("click_ends_radio_without_firing", not demo.voice_active and world.ammo == ammo_at_radio)
	check("move_hint", demo.hint == Fleet.WALK_HINT and world.can_move)
	check("first_door_has_animated_arrow", demo.objective_door() == "to_mika" and demo._door_arrow.visible and is_equal_approx(demo._door_arrow.position.x, 264))
	check("recent_text_does_not_cover_first_door_arrow", not app.combat_hud.get_node("Recent").visible)
	var arrow_frame := demo._door_arrow.frame
	await frames(9)
	check("door_arrow_advances_through_sheet", demo._door_arrow.frame != arrow_frame)
	await capture("02_dark_corridor")
	check("move_subtitle_has_no_chat_overlap", app.get_node("FleetCues/Subtitle").visible and not app.get_node("%TalkPrompt").visible)
	if not await enter_door("to_mika", ["mika_quarters"]): return
	check("movement_hint_removes_on_entry", demo.hint.is_empty() and app.dialogue_panel.visible)
	await finish_lines()
	check("objective_moves_to_supply_door", demo.objective_door() == "to_supply" and demo._door_arrow.visible)
	if not await enter_door("to_supply", ["supply_room"]): return
	check("no_arrow_when_goal_is_in_current_room", demo.objective_door().is_empty() and not demo._door_arrow.visible)
	var supply = demo.room()
	if not await move(supply.approach("crate_side"), 17): return
	tap(KEY_E)
	check("crate_text", app.combat_hud.journal.entries.any(func(entry): return entry.body == "이곳엔 퓨즈가 없다"))
	if not await move(supply.approach("cabinet_reserve")): return
	tap(KEY_E)
	await frames(26)
	check("reserve_cabinet_opens_first", demo.cabinets.get("cabinet_reserve", false) and not world.fuse.visible)
	if not await move(supply.approach("cabinet_fuse")): return
	tap(KEY_E)
	check("fuse_is_not_auto_collected", not world.fuse_collected and demo.cabinets.get("cabinet_fuse", false))
	if not await until(func(): return count_event("fleet_fuse_landed") == 1, 100): return
	check("fuse_uses_breaker_sprite", world.fuse.object_texture == preload("res://resources/FuseWorkingTexture.tres"))
	if not await move(world.fuse.position, 28): return
	check("fuse_prompt_is_anchored", app.get_node("FleetCues/Interaction").visible and not app.get_node("FleetCues/Subtitle").visible
		and demo.nearest_interaction().anchor == world.fuse.position)
	await capture("03_cabinet_fuse_landed")
	if not await move(Vector2(201, 221)): return
	if not await move(Vector2(205, 159)): return
	check("cabinet_footprint_and_depth", world.player.position.y < supply.ground("cabinet_fuse").y and supply.get_node("Objects").y_sort_enabled)
	await capture("03b_cabinet_behind")
	if not await enter_door("to_corridor", ["corridor"]): return
	check("no_ambush_without_pickup", count_event("fleet_corridor_encounter") == 0 and world.enemies_remaining() == 0)
	check("save_after_leaving_uncollected_fuse", app.save_slot(1))
	if not await enter_door("to_supply", ["supply_room"]): return
	check("resume_uncollected_fuse", app.load_slot(1) and world.map_id == "corridor" and not world.fuse_collected)
	if world.map_id != "corridor": return
	if not await enter_door("to_supply", ["supply_room"]): return
	if not await move(world.fuse.position, 18): return
	tap(KEY_E)
	check("pickup_by_e", world.fuse_collected and world.game_state().fuse_in_inventory and count_event("fleet_fuse_landed") == 1)
	check("fuse_pickup_line", app._fleet_line == "찾았구나! 바로 전기실로 가자.")
	await finish_lines()
	check("fuse_changes_objective_to_corridor_door", demo.objective_door() == "to_corridor" and demo._door_arrow.visible)
	if not await enter_door("to_corridor", ["corridor"]): return
	check("hall_crew_waits_during_dialogue", demo.voice_active and world.enemies_remaining() == 1 and not demo.unit_pool[0].active)
	await finish_lines()
	check("ambush_has_no_door_arrow", not demo._door_arrow.visible)
	check("shoot_hint_and_enemy_activated", demo.hint == Fleet.AMBUSH_HINT and demo.unit_pool[0].active)
	await capture("04_shoot_hint")
	var crew := demo.unit_pool[0]
	var torso := crew.aim_position()
	var query := PhysicsRayQueryParameters2D.create(world.to_global(torso - Vector2(30, 0)), world.to_global(torso + Vector2(30, 0)), 8)
	query.collide_with_areas = true
	check("enemy_torso_is_projectile_target", world.get_world_2d().direct_space_state.intersect_ray(query).get("collider") == crew.projectile_body)
	if not check("left_click_kills_corridor_crew", await fight(Fleet.Step.AMBUSH, 540)): return
	check("shoot_hint_clears_on_defeat", demo.hint.is_empty() and count_event("fleet_corridor_encounter") == 1)
	await finish_lines()
	check("post_ambush_arrow_points_to_power", demo.objective_door() == "to_power" and demo._door_arrow.visible)
	if not await enter_door("to_power", ["power_room"]): return
	await finish_lines()
	if not await move(Vector2(144, 221)): return
	if not await move(Vector2(194, 168), 8): return
	if not await move(Vector2(187, 149), 8): return
	check("breaker_footprint_and_depth", world.player.position.y < demo.room().ground("main_fuse_breaker").y)
	await capture("05a_breaker_behind")
	if not await move(Vector2(194, 188), 9): return
	check("breaker_waits_for_handoff", count_event("fleet_breaker_open") == 0 and world.game_state().fuse_in_inventory)
	if not await move(world.npc.position, 35): return
	if not check("mika_has_fuse_handoff_prompt", demo.nearest_interaction().get("id", "") == "give_fuse"):
		print("HANDOFF ", world.player.position.distance_to(world.npc.position), " · ", world.can_move, " · ", demo.step, " · ", world.npc_hp, " · ", demo.fuse_handed)
		return
	tap(KEY_E)
	check("mika_receives_fuse_by_interaction", count_event("fleet_fuse_handed") == 1 and not world.game_state().fuse_in_inventory)
	if not check("breaker_opens_after_one_press", await until(func(): return count_event("fleet_breaker_open") == 1, 450)): return
	if not check("empty_slot_then_inventory_consumption", await until(func(): return count_event("fleet_fuse_inserted") == 1, 220) and count_event("fleet_fuse_removed") == 1 and not world.game_state().fuse_in_inventory and not world.power_restored): return
	await capture("05_inserted_at_breaker")
	if not check("terminal_power_then_alarm", await until(func(): return demo.alarm_active(), 620) and count_event("fleet_terminal_operated") == 1 and count_event("power_restored") == 1): return
	await capture("06_power_reaction")
	if not await until(func(): return demo.voice_active, 150): return
	await finish_lines()
	await until(func(): return world.can_move, 165)
	if not await enter_door("to_corridor", ["corridor"]): return
	await finish_lines()
	check("alarm_loop_and_mika_follow", demo.alarm_active() and world.npc.visible and world.player.position.distance_to(world.npc.position) < 100 and count_event("fleet_corridor_encounter") == 1)
	check("alarm_arrow_points_to_lab", demo.objective_door() == "to_lab" and demo._door_arrow.visible)
	await capture("07_alarm_corridor")
	var audio := world.get_node("MissionAudio")
	var warning_count: int = audio.played_events
	var lights := demo.room()._warning_sprites as Array[AnimatedSprite2D]
	var frame := lights[0].frame
	check("corridor_light_animates", await until(func(): return lights[0].frame != frame, 52))
	check("corridor_warning_repeats", await until(func(): return audio.played_events > warning_count, 155))
	check("corridor_uses_siren_asset", audio.voices.any(func(voice): return voice.stream == audio.FLEET_SIREN))
	if not await move(Fleet.Room.pixel(demo.room().doors.to_lab.point_px), 29): return
	check("lab_door_uses_animated_e_prompt", app.get_node("FleetCues/Interaction").visible and demo.nearest_interaction().name == "연구실 B동 들어가기")
	await capture("07b_lab_door_prompt")
	if not await enter_door("to_lab", ["research_lab_b"]): return
	await finish_lines()
	check("upper_core_closeup", await until(func(): return demo.camera_weight > 0.99, 120) and not world.can_move)
	await capture("08_core_closeup")
	check("lower_core_closeup", await until(func(): return demo.camera_weight > 0.99 and demo.camera_point.y > 700, 240))
	await capture("09_core_closeup")
	await until(func(): return demo.voice_active, 300)
	await finish_lines()
	if not await enter_door("to_corridor", ["corridor"]): return
	if not await enter_door("to_lab", ["research_lab_b"]): return
	check("lab_reentry_preserves_briefing", not demo.voice_active and demo.step == Fleet.Step.CORES and count_event("fleet_wave_started") == 0)
	var lab = demo.room()
	if not await move(lab.approach("lab_ammo_stock"), 23): return
	await capture("09a_ammo_prompt")
	var magazines_before := world.magazines
	var rounds_before := world.ammo
	tap(KEY_E)
	check("lab_ammo_crate_gives_two_magazines", demo.lab_ammo_used and world.magazines == magazines_before + 2 and world.ammo == rounds_before)
	await frames(38)
	check("lab_ammo_crate_opens_and_stays_open", lab._animations.lab_ammo_stock.frame == 4 and not lab._animations.lab_ammo_stock.is_playing())
	await capture("09b_ammo_crate")
	tap(KEY_E)
	check("lab_ammo_crate_is_one_use", count_event("fleet_ammo_collected") == 1 and world.magazines == magazines_before + 2)
	tap(KEY_R)
	check("reload_waits_and_preserves_magazine_during_animation", world.reload_time > 0.0 and world.ammo == rounds_before and world.magazines == magazines_before + 2)
	var reload_saved := app.save_slot(3)
	var timer := world.reload_time
	var reload_restored := app.load_slot(3)
	check("reload_save_roundtrip", reload_saved and reload_restored and is_equal_approx(world.reload_time, timer) and world.magazines == magazines_before + 2 and demo.lab_ammo_used)
	if not check("reload_finishes_and_consumes_one", await until(func(): return world.reload_time == 0.0, 90) and world.ammo == world.max_ammo and world.magazines == magazines_before + 1): return
	if not await move(Vector2(245, 625)): return
	if not await move(lab.approach("normal_sector_crate"), 22): return
	tap(KEY_E)
	check("lab_cache_supplies_two_more_magazines", world.magazines == magazines_before + 3 and demo.lab_supply_used)
	if not await move(Vector2(237, 670)): return
	if not await move(Vector2(294, 592)): return
	if not await move(Vector2(603, 560)): return
	if not await move(Vector2(729, 510), 24, 420, true): return
	check("core_proximity_line", has_line(Fleet.Lines.CORE[0][1]))
	await finish_lines()
	if not await move(Vector2(747, 536)): return
	if not await move(Vector2(747, 626)): return
	if not await move(lab.approach("eroded_stop") + Vector2(0, 28), 15): return
	check("wave_begins_at_lever", demo.step == Fleet.Step.WAVES and demo.wave == 1)
	tap(KEY_E)
	check("lever_locked_during_waves", count_event("fleet_levers_pulled") == 0)
	await capture("10_first_wave")
	if not check("all_waves_killed_with_combat", await fight(Fleet.Step.WAVES, 2200)): return
	var waves := events.filter(func(event): return event.event == "fleet_wave_started")
	check("three_marker_waves", waves_match_markers() and waves.map(func(event): return event.wave) == [1, 2, 3] and waves.map(func(event): return event.count) == [3, 4, 5])
	check("last_enemy_line", has_line(Fleet.Lines.WAVES_CLEAR[0][1]))
	await finish_lines()
	if not await move(lab.approach("eroded_stop") + Vector2(14, 27), 17, 210, true): return
	if not check("countdown_starts_in_range", await until(func(): return demo.voice_active and app._fleet_line == Fleet.Lines.COUNTDOWN[0][1], 480)):
		print("LEVER ", world.player.position, " / ", world.npc.position, " / ", lab.approach("normal_stop"), " / ", world.npc_hp, " / ", app._fleet_line, " / ", demo.step, " / ", world.active_action, " / ", demo.voice_active, " / ", demo.locks_movement(), " / ", demo._near_lever(), " / ", demo._mika_at_lever())
		return
	var position := world.player.position
	Input.action_press("move_down")
	key(KEY_E)
	await frames(12)
	check("early_e_and_movement_blocked", count_event("fleet_levers_pulled") == 0 and world.player.position == position)
	for i in 3: tap(KEY_SPACE)
	check("pull_signal_stays_until_advance", app._fleet_line == Fleet.Lines.COUNTDOWN[-1][1] and not demo.allows_interact())
	tap(KEY_SPACE)
	if not check("signal_arms_lever", demo.allows_interact()): return
	key(KEY_E, true, true)
	await frames(5)
	check("held_or_echoed_e_cannot_pull", count_event("fleet_levers_pulled") == 0 and world.player.position == position)
	Input.action_release("move_down")
	key(KEY_E, false)
	check("armed_save_roundtrip", app.save_slot(2) and app.load_slot(2) and demo.allows_interact())
	await capture("11_lever_signal")
	tap(KEY_E)
	check("fresh_e_pulls_both_levers", count_event("fleet_levers_pulled") == 1)
	if not check("ending_on_corridor_side", await until(func(): return world.map_id == "corridor" and demo.voice_active, 250)
		and world.player.position.distance_to(Fleet.Room.pixel(demo.room().doors.to_lab.arrival_px)) < 2): return
	await capture("12_ending")
	for i in 4:
		tap(KEY_SPACE)
		await frames(2)
	check("last_line_renders_before_result", app.answer.text == Fleet.Lines.ENDING[-1][1] and not app.result_screen.visible)
	await capture("12b_last_line")
	await finish_lines()
	await frames(6)
	check("ending_result", world.finished and app.result_screen.visible and has_line(Fleet.Lines.ENDING[-1][1]))
	await capture("13_result")
	app._return_to_title()
	await frames(4)
	check("result_returns_to_title", current_scene.get_node("Menu").visible and not current_scene.has_node("Main"))
	await test_healer()

func test_healer() -> void:
	current_scene.get_node("%NewGame").pressed.emit()
	await frames(5)
	app = current_scene.get_node_or_null("Main") as Mission
	if not check("healer_fixture_starts", app != null): return
	world = app.world
	demo = world.fleet_demo
	app.brain.auto_enabled = false
	demo.clear_cues()
	world.get_node("RoomFade/Black").color.a = 0.0
	demo.step = Fleet.Step.AMBUSH
	demo.unit_pool[0].reset_enemy()
	world._sync_state()
	world.set_physics_process(false)
	world.player_hp = 50
	world.npc.position = world.safe_position
	world.player.position = world.safe_position + Vector2(50, 20)
	check("healer_player_order_and_decision_metadata", NPCPolicy.requested_action("치료 장비 설치해 줘", true) == "deploy_cover"
		and "초당 최대 5" in NPCPolicy.action_description("deploy_cover", world.game_state()))
	if not check("healer_uses_normal_support_order", world.request_support("deploy_cover")): return
	world._physics_process(1.0 / 60.0)
	check("healer_starts_deploying", world.healer.visible and not world.sentry.visible and world.cover_charges == 0 and world.healer._device.animation == "deploy")
	world._tick_support_device(0.60)
	check("healer_waits_until_deployed", world.player_hp == 50 and not world.healer._range.visible)
	world._tick_support_device(0.045)
	world._tick_support_device(1.0)
	check("healer_restores_five_per_second", world.player_hp == 55 and world.healer._range.visible and world.healer._sparks.visible and world.healer._device.animation == "heal")
	await frames(2)
	await capture("14_healing_station")
	world.ammo = 1
	world.magazines = 1
	world.shoot_cd = 0.0
	var target := demo.unit_pool[0].aim_position()
	check("last_round_starts_automatic_reload", world.shoot(target) and world.ammo == 0 and world.reload_time > 0.0)
	check("cannot_shoot_during_reload", not world.shoot(target))
	world._tick_player_reload(world.RELOAD_SECONDS)
	check("auto_reload_consumes_one_magazine", world.ammo == world.max_ammo and world.magazines == 0 and world.reload_time == 0)
	world.take_damage(8)
	check("healer_does_not_reduce_damage", world.player_hp == 47)
	world.player.position = world.safe_position + Vector2(0, 75)
	world._tick_support_device(1.0)
	check("outside_ellipse_does_not_heal", world.player_hp == 47 and not world.inside_cover() and not world.healer._sparks.visible)
	var save := world.save_snapshot()
	world.restore_snapshot(save)
	check("save_restores_active_device_timer", is_equal_approx(world.cover_time, float(save.cover_time)))
	world.player.position = world.safe_position + Vector2(50, 20)
	world.player_hp = world.max_hp - 2
	world._tick_support_device(1.0)
	check("healer_resume_caps_health", world.player_hp == world.max_hp and world.healer.visible)
	world._tick_support_device(world.cover_time)
	check("healer_expires", not world.healer.visible and world.cover_time == 0.0)
