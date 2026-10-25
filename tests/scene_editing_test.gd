extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var checks := {}
	var scene := load("res://scenes/World.tscn") as PackedScene
	var edited := scene.instantiate() as DemoWorld
	edited.get_node("Player").position = Vector2(205, 340)
	edited.get_node("Player").move_speed = 255.0
	edited.get_node("NPC").display_name = "검증용 정비사"
	edited.get_node("Fuse").display_name = "검증용 전지"
	edited.find_item_guidance = "편집한 안내: {item_name}를 찾으세요."
	var saved := PackedScene.new()
	checks["pack_scene"] = saved.pack(edited) == OK
	checks["save_scene"] = ResourceSaver.save(saved, "user://scene_edit_roundtrip.tscn") == OK
	edited.free()
	var restored := (ResourceLoader.load("user://scene_edit_roundtrip.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as DemoWorld
	root.add_child(restored)
	await process_frame
	checks["saved_spawn_position"] = restored.player.position.is_equal_approx(Vector2(205, 340))
	checks["saved_speed"] = is_equal_approx(restored.player.move_speed, 255.0)
	checks["saved_npc_name"] = restored.npc.display_name == "검증용 정비사"
	checks["saved_item_name"] = restored.fuse.display_name == "검증용 전지"
	checks["saved_guidance_template"] = restored.find_item_guidance == "편집한 안내: {item_name}를 찾으세요."
	checks["ai_uses_scene_names"] = restored.npc_context().npc_name == "검증용 정비사" and restored.npc_context().item_name == "검증용 전지"
	checks["editor_label_sync"] = restored.npc.get_node("NameLabel").text == "검증용 정비사"
	restored.player.position += Vector2(35, 0)
	restored.reset_world()
	checks["restart_uses_saved_spawn"] = restored.player.position.is_equal_approx(Vector2(205, 340))
	var start := restored.player.position
	Input.action_press("move_right")
	for index in range(5): await physics_frame
	Input.action_release("move_right")
	await physics_frame
	checks["input_map_moves_character"] = restored.player.position.x > start.x + 5
	restored.can_move = false
	var stopped := restored.player.position
	Input.action_press("move_right")
	for index in range(4): await physics_frame
	Input.action_release("move_right")
	await physics_frame
	checks["dialogue_focus_can_block_movement"] = restored.player.position.is_equal_approx(stopped)
	restored.can_move = true
	restored.player.position = Vector2(restored.room_rect.end.x - 20, restored.room_rect.get_center().y)
	Input.action_press("move_right")
	for index in range(20): await physics_frame
	Input.action_release("move_right")
	await physics_frame
	checks["native_wall_collision"] = restored.player.position.x < restored.room_rect.end.x - 8
	var received: Array[String] = []
	restored.interacted.connect(func(kind: String): received.append(kind))
	restored.player.position = restored.fuse.position + Vector2(0, 35)
	var interaction := InputEventAction.new()
	interaction.action = "interact"
	interaction.pressed = true
	root.push_input(interaction, true)
	await process_frame
	checks["input_map_nearby_interaction"] = received.has("fuse")
	checks["guidance_uses_edited_item_name"] = restored.current_guidance().contains("검증용 전지")
	restored.apply_interaction("fuse")
	checks["guidance_changes_when_carrying_item"] = restored.current_guidance().contains(restored.generator.display_name) and restored.current_guidance().contains("검증용 전지")
	restored.apply_interaction("generator")
	checks["guidance_changes_when_powered"] = restored.current_guidance().contains(restored.exit_object.display_name)
	var settings := (load("res://resources/NPCSettings.tres") as LocalNPCSettings).duplicate(true) as LocalNPCSettings
	settings.model = "roundtrip-test:model"
	settings.temperature = 0.65
	checks["save_ai_resource"] = ResourceSaver.save(settings, "user://ai_settings_roundtrip.tres") == OK
	var restored_settings := ResourceLoader.load("user://ai_settings_roundtrip.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as LocalNPCSettings
	checks["ai_settings_roundtrip"] = restored_settings.model == "roundtrip-test:model" and is_equal_approx(restored_settings.temperature, 0.65)
	var app := (load("res://main.tscn") as PackedScene).instantiate()
	checks["ui_exists_before_runtime"] = app.get_node_or_null("Margin/Layout/Content/Dialogue/Question") != null and app.get_node_or_null("Margin/Layout/TestControls/RestartButton") != null
	checks["world_is_saved_scene_instance"] = app.get_node("Margin/Layout/Content/WorldFrame/World").scene_file_path == "res://scenes/World.tscn"
	app.free()
	var passed := true
	for value in checks.values(): passed = passed and value
	var result := {"suite": "scene_editor_roundtrip", "synthetic_test": true, "passed": passed, "checks": checks}
	var path := ProjectSettings.globalize_path("res://../evidence/scene_refactor").simplify_path()
	DirAccess.make_dir_recursive_absolute(path)
	var file := FileAccess.open(path.path_join("scene_editing_test.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	print("SCENE_EDITING_TEST ", JSON.stringify(result))
	quit(0 if passed else 1)
