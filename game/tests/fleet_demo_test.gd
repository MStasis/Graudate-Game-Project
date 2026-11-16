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
	var hud: CombatInterface = app.combat_hud
	check("opening_radio_uses_single_bottom_caption", hud.hud.get_node("%Line").text == app._fleet_line and hud.hud.get_node("%Dialogue").visible and not app.dialogue_panel.visible and not hud.npc_bubble.visible)
	await capture("01_radio")
	var radio_line := app._fleet_line
	var radio_ammo := world.ammo
	click(hud.hud.get_node("%Review").get_global_rect().get_center())
	await frames(2)
	check("review_button_opens_during_radio_without_advancing", hud.history.visible and paused and app._fleet_line == radio_line)
	tap(KEY_SPACE)
	click(Vector2(260, 420))
	await frames(2)
	check("review_consumes_radio_and_attack_input", hud.history.visible and app._fleet_line == radio_line and world.ammo == radio_ammo and not world.can_move)
	await capture("01b_review")
	tap(KEY_L)
	check("l_closes_review_at_same_radio_line", not paused and not hud.modal_open() and app._fleet_line == radio_line and not world.can_move)
	await frames(400)
	check("radio_waits_for_input", app._fleet_line == Fleet.Lines.RADIO[0][1] and not world.can_move and not demo._door_arrow.visible)
	key(KEY_SPACE, true, true)
	check("held_space_does_not_advance", app._fleet_line == Fleet.Lines.RADIO[0][1])
	tap(KEY_SPACE)
	check("space_advances_one_line", app._fleet_line == Fleet.Lines.RADIO[1][1] and not world.can_move)
	for index in range(2, Fleet.Lines.RADIO.size()):
		tap(KEY_SPACE)
	var ammo_at_radio := world.ammo
	click(Vector2(350, 400))
	await frames(2)
	check("click_ends_radio_without_firing", not demo.voice_active and world.ammo == ammo_at_radio)
	check("move_hint", demo.hint == Fleet.WALK_HINT and world.can_move)
	check("first_door_has_animated_arrow", demo.objective_door() == "to_mika" and demo._door_arrow.visible and is_equal_approx(demo._door_arrow.position.x, 264))
	check("no_recent_dialogue_strip_over_first_door_arrow", not hud.has_node("Recent") and not hud.hud.get_node("%Dialogue").visible)
	var arrow_frame := demo._door_arrow.frame
	await frames(9)
	check("door_arrow_advances_through_sheet", demo._door_arrow.frame != arrow_frame)
	await capture("02_dark_corridor")
	check("move_hint_is_in_objective_without_chat_overlap", Fleet.WALK_HINT in hud.hud.get_node("%Objective").text and not app.get_node("%TalkPrompt").visible)
	if not await enter_door("to_mika", ["mika_quarters"]): return
	check("movement_hint_removes_on_entry", demo.hint.is_empty() and hud.hud.get_node("%Dialogue").visible and not app.dialogue_panel.visible)
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
	check("fuse_prompt_is_anchored", app.get_node("FleetCues/Interaction").visible and not hud.hud.get_node("%Dialogue").visible
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
	if not await move(Vector2(170, 265)): return
	if not await move(Vector2(120, 333), 8): return
	await until(func(): return demo.nearest_interaction().get("id", "") == "give_fuse", 120)
	if not check("mika_has_fuse_handoff_prompt", demo.nearest_interaction().get("id", "") == "give_fuse"):
		print("HANDOFF ", world.player.position.distance_to(world.npc.position), " · ", world.can_move, " · ", demo.step, " · ", world.npc_hp, " · ", demo.fuse_handed)
		return
	var blocked_terminal_position := world.player.position
	tap(KEY_E)
	check("mika_receives_fuse_by_interaction", count_event("fleet_fuse_handed") == 1 and not world.game_state().fuse_in_inventory)
	await frames(12)
	var repair_stand: Vector2 = demo.room().get_node("PlayerRepairStand").position
	var walked := world.player.position.distance_to(blocked_terminal_position)
	check("terminal_blocker_walks_at_cutscene_speed", walked > 6 and walked < 19 and not world.can_move)
	await capture("04b_clear_terminal")
	if not check("breaker_opens_after_one_press", await until(func(): return count_event("fleet_breaker_open") == 1, 450)): return
	check("player_clears_terminal_before_mika_works", world.player.position.distance_to(repair_stand) <= 2.1)
	if not check("empty_slot_then_inventory_consumption", await until(func(): return count_event("fleet_fuse_inserted") == 1, 220) and count_event("fleet_fuse_removed") == 1 and not world.game_state().fuse_in_inventory and not world.power_restored): return
	await capture("05_inserted_at_breaker")
	if not check("terminal_power_then_line", await until(func(): return demo.voice_active, 620)
		and world.power_restored and app._fleet_line == Fleet.Lines.BREAKER_FIXED[0][1]
		and count_event("fleet_terminal_operated") == 1 and count_event("power_restored") == 1
		and count_event("anomaly_alarm") == 0 and not app._fleet_reaction): return
	await finish_lines()
	if not check("alarm_begins_before_reaction", demo.alarm_active() and count_event("anomaly_alarm") == 1 and not app._fleet_reaction): return
	if not check("reaction_follows_alarm", await until(func(): return app._fleet_reaction, 90)): return
	await capture("06_power_reaction")
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
	var warning_frames := ceili((audio.FLEET_SIREN.get_length() + 0.30) * 60.0) + 10
	check("corridor_warning_repeats", await until(func(): return audio.played_events > warning_count, warning_frames))
	check("corridor_uses_siren_asset", audio.voices.any(func(voice): return voice.stream == audio.FLEET_SIREN))
	if not await move(Fleet.Room.pixel(demo.room().doors.to_lab.point_px), 29): return
	check("lab_door_uses_animated_e_prompt", app.get_node("FleetCues/Interaction").visible and demo.nearest_interaction().name == "연구실 B동 들어가기")
	await capture("07b_lab_door_prompt")
	if not await enter_door("to_lab", ["research_lab_b"]): return
	check("lab_entry_mutes_corridor_siren", demo.alarm_active() and is_zero_approx(audio._warning_left)
		and not audio.voices.any(func(voice): return voice.stream == audio.FLEET_SIREN))
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
	await frames(2)
	check("hud_shows_loaded_rounds_and_reserve_magazines", hud.hud.get_node("%Rounds").text == "%02d" % world.ammo and hud.hud.get_node("%Magazines").text == str(world.magazines) and (hud.hud.get_node("%Reserve/Magazine").texture as AtlasTexture).region == Rect2(5, 4, 13, 17))
	await frames(38)
	check("lab_ammo_crate_opens_and_stays_open", lab._animations.lab_ammo_stock.frame == 4 and not lab._animations.lab_ammo_stock.is_playing())
	await capture("09b_ammo_crate")
	tap(KEY_E)
	check("lab_ammo_crate_is_one_use", count_event("fleet_ammo_collected") == 1 and world.magazines == magazines_before + 2)
	tap(KEY_R)
	check("reload_waits_and_preserves_magazine_during_animation", world.reload_time > 0.0 and world.ammo == rounds_before and world.magazines == magazines_before + 2)
	var reload_bar := world.player.get_node("ReloadProgress") as ProgressBar
	check("reload_starts_rifle_foley_and_shows_bar", reload_bar.visible
		and audio.voices.any(func(voice): return voice.stream == audio.RELOAD))
	await frames(19)
	check("reload_bar_advances_above_player", reload_bar.visible and reload_bar.value > 0.2 and reload_bar.value < 0.8 and reload_bar.position.y < -60)
	await capture("09c_reload")
	var reload_saved := app.save_slot(3)
	var timer := world.reload_time
	var previous_save := app.save_store.read_slot(3)
	var previous_config := world.log_configuration()
	previous_config.fleet_demo.erase("sentry_attack")
	previous_save.scenario = JSON.stringify(previous_config).sha256_text()
	check("bolt_only_sentry_save_still_loads", app.save_store.write_slot(3, previous_save) and app.load_slot(3))
	previous_config.fleet_demo.erase("rift_sentry")
	previous_save.scenario = JSON.stringify(previous_config).sha256_text()
	check("previous_fleet_hash_fixture", app.save_store.write_slot(3, previous_save))
	var reload_restored := app.load_slot(3)
	check("reload_save_roundtrip", reload_saved and reload_restored and is_equal_approx(world.reload_time, timer) and world.magazines == magazines_before + 2 and demo.lab_ammo_used)
	if not check("reload_finishes_and_consumes_one", await until(func(): return world.reload_time == 0.0, 90) and world.ammo == world.max_ammo and world.magazines == magazines_before + 1): return
	await frames(2)
	check("reload_bar_hides_when_ready", not reload_bar.visible)
	check("hud_tracks_completed_reload", hud.hud.get_node("%Rounds").text == "%02d" % world.max_ammo and hud.hud.get_node("%Magazines").text == str(magazines_before + 1))
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
	if not await move(lab.approach("eroded_stop") + Vector2(0, 28), 15, 420, true): return
	check("wave_begins_at_lever", demo.step == Fleet.Step.WAVES and demo.wave == 1)
	check("first_wave_line_with_visible_inactive_enemies", app._fleet_line == Fleet.Lines.WAVE_START[0][1]
		and world.enemies_remaining() == 3
		and world.room_enemies().all(func(enemy): return enemy.hp <= 0 or (enemy.visible and not enemy.active)))
	tap(KEY_E)
	check("lever_locked_during_waves", count_event("fleet_levers_pulled") == 0)
	await capture("10_first_wave")
	await finish_lines()
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
	check("lever_objects_show_lowered_frames", (lab.get_node("Objects/normal_stop/Sprite") as Sprite2D).texture == lab.LEVER_LOWERED.normal_stop
		and (lab.get_node("Objects/eroded_stop/Sprite") as Sprite2D).texture == lab.LEVER_LOWERED.eroded_stop)
	await capture("11b_lowered_levers")
	if not check("ending_on_corridor_side", await until(func(): return world.map_id == "corridor" and demo.voice_active, 250)
		and world.player.position.distance_to(Fleet.Room.pixel(demo.room().doors.to_lab.arrival_px)) < 2): return
	await capture("12_ending")
	for i in range(1, Fleet.Lines.ENDING.size()):
		tap(KEY_SPACE)
		await frames(2)
	check("last_line_renders_before_result", hud.hud.get_node("%Dialogue").visible and hud.hud.get_node("%Line").text == Fleet.Lines.ENDING[-1][1] and not app.result_screen.visible)
	await capture("12b_last_line")
	await finish_lines()
	await frames(6)
	check("ending_result", world.finished and app.result_screen.visible and has_line(Fleet.Lines.ENDING[-1][1]))
	await capture("13_result")
	app._return_to_title()
	await frames(4)
	check("result_returns_to_title", current_scene.get_node("Menu").visible and not current_scene.has_node("Main"))
	await test_healer()
	await test_sentry_and_dash()

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

func test_sentry_and_dash() -> void:
	var sentry := demo.unit_pool.filter(func(enemy): return enemy.name == Fleet.SENTRY_SPAWN)[0] as Fleet.Sentry
	var starting_position := Vector2(648, 568)
	world._change_map("research_lab_b", starting_position)
	demo.step = Fleet.Step.WAVES
	demo.wave = 2
	demo.hint = ""
	world.power_restored = true
	sentry.reset_enemy()
	sentry.attack_wait = 0.0
	world.player_hp = world.max_hp
	world._sync_state()
	world.game_event.connect(func(event): events.append(event))
	var audio := world.get_node("MissionAudio")
	var charges := count_event("fleet_sentry_charged")
	var fires := count_event("fleet_sentry_fired")
	var beams := count_event("fleet_sentry_laser_fired")
	if not check("sentry_winds_up_before_fire", await until(func(): return count_event("fleet_sentry_charged") == charges + 1, 30)
		and count_event("fleet_sentry_fired") == fires): return
	world.player.position = starting_position + Vector2(0, 66)
	if not check("sentry_fires_after_aim_changes", await until(func(): return count_event("fleet_sentry_fired") == fires + 1, 40)): return
	var bolt := world.get_node("Projectiles").get_child(0) as MissionProjectile
	var expected_direction := sentry.position.direction_to(world.player.position)
	check("bolt_uses_latest_aim_and_supplied_sprite", bolt.shooter == sentry and bolt.get_child(0) is AnimatedSprite2D
		and bolt.direction.is_equal_approx(expected_direction))
	check("sentry_bolt_routes_heavy_sound", audio.voices.any(func(voice): return voice.stream == audio.SENTRY_BOLT))
	world.player.position += expected_direction * 100.0
	if not check("retreating_along_bolt_line_still_takes_damage", await until(func(): return world.player_hp < world.max_hp, 45)
		and world.player_hp == world.max_hp - sentry.contact_damage): return
	var hp := world.player_hp
	var ammo := world.ammo
	world.player.position = starting_position
	sentry.attack_wait = 0.0
	if not check("sentry_fires_second_bolt_before_laser", await until(func(): return count_event("fleet_sentry_fired") == fires + 2, 110)
		and count_event("fleet_sentry_laser_fired") == beams): return
	Input.action_press("move_up")
	tap(KEY_SPACE)
	Input.action_release("move_up")
	check("space_starts_dash_without_firing", world.player.dash_remaining > 0.0 and world.ammo == ammo)
	var dash_voices: Array = audio.voices.filter(func(voice): return voice.stream == audio.DASH)
	check("dash_sound_matches_invulnerability_duration", dash_voices.size() == 1
		and is_equal_approx(audio.DASH.get_length() / dash_voices[0].pitch_scale, world.player.DASH_DURATION))
	tap(KEY_SPACE)
	check("dash_cooldown_blocks_repeat", count_event("fleet_dash_started") == 1)
	await frames(8)
	check("dash_leaves_sprite_afterimages", get_nodes_in_group("dash_afterimage").size() > 2)
	await capture("16_dash_afterimages")
	await frames(45)
	check("dash_moves_out_of_sentry_lane", world.player.position.y < starting_position.y - 100 and world.player_hp == hp)
	check("afterimages_expire", get_nodes_in_group("dash_afterimage").is_empty())
	check("dash_sound_ends_with_invulnerability", world.player.dash_remaining == 0.0
		and not audio.voices.any(func(voice): return voice.stream == audio.DASH))
	if not check("two_bolts_are_followed_by_laser_charge", count_event("fleet_sentry_laser_charged") > 0
		and sentry._laser_left > 0.0 and sentry.bolts_fired == sentry.BOLTS_PER_LASER): return
	var cycle: Dictionary = demo.snapshot()
	check("pending_laser_is_preserved_in_save", cycle.enemies[Fleet.SENTRY_SPAWN].bolts_fired == sentry.BOLTS_PER_LASER)
	if not check("laser_warnings_finish_before_beam", await until(func(): return sentry._laser_left > 0.0 and sentry._laser_left < 0.14, 60)): return
	await capture("17_sentry_laser_warning")
	if not check("laser_damages_once_along_the_warning", await until(func(): return count_event("fleet_sentry_laser_fired") == beams + 1, 15)
		and world.player_hp == hp - sentry.LASER_DAMAGE): return
	check("laser_routes_own_heavy_sound", audio.voices.any(func(voice): return voice.stream == audio.SENTRY_LASER))
	await capture("18_sentry_laser_beam")
	await frames(20)
	check("laser_flash_does_not_repeat_damage", world.player_hp == hp - sentry.LASER_DAMAGE and sentry.bolts_fired == 0)
	demo.restore(cycle)
	world._sync_state()
	check("laser_cycle_resumes_after_restore", sentry.bolts_fired == sentry.BOLTS_PER_LASER)
	world.player.position = starting_position
	sentry.attack_wait = 0.0
	if not check("next_laser_warns_before_dash", await until(func(): return sentry._laser_left > 0.0 and sentry._laser_left < 0.11, 90)): return
	var evades := count_event("fleet_damage_evaded")
	hp = world.player_hp
	Input.action_press("move_left")
	tap(KEY_SPACE)
	Input.action_release("move_left")
	check("dash_invulnerability_can_cross_firing_laser", await until(func(): return count_event("fleet_sentry_laser_fired") == beams + 2, 16)
		and count_event("fleet_damage_evaded") == evades + 1 and world.player_hp == hp)
	await frames(25)
	world.player.position = starting_position
	sentry.bolts_fired = sentry.BOLTS_PER_LASER
	sentry.attack_wait = 0.0
	if not check("laser_locks_a_lane_before_firing", await until(func(): return sentry._laser_left > 0.0 and sentry._laser_left < 0.42, 80)): return
	var locked_end: Vector2 = sentry._laser_end
	world.player.position = Vector2(735, 568)
	check("laser_warning_stops_at_solid_lever", locked_end.length() < sentry.position.distance_to(world.player.position))
	check("laser_does_not_damage_through_cover", await until(func(): return count_event("fleet_sentry_laser_fired") == beams + 3, 36)
		and world.player_hp == hp and locked_end.is_equal_approx(sentry._laser_end)
		and count_event("fleet_damage_evaded") == evades + 1)
	await frames(25)
	world.player.position = starting_position
	world.player_hp = 1
	sentry.bolts_fired = sentry.BOLTS_PER_LASER
	sentry.attack_wait = 0.0
	check("lethal_laser_still_renders_its_flash", await until(func(): return world.defeated, 75)
		and sentry._beam_left > 0.0 and not sentry.active)
	await frames(25)
	check("lethal_laser_ends_without_a_followup_attack", sentry._beam_left == 0.0
		and count_event("fleet_sentry_laser_fired") == beams + 4)
