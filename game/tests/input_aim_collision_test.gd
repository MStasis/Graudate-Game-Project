extends SceneTree
var checks := {}
var app: Control
var world: DemoWorld
var rendered := false
var directory := ""

func _initialize() -> void:
 rendered = "--render-input-collision" in OS.get_cmdline_user_args()
 call_deferred("run")

func check(label: String, result: bool) -> void:
 checks[label] = result
 if not result: push_error("INPUT_COLLISION_FAILED " + label)

func frames(count := 4) -> void:
 for index in range(count):
  await process_frame
  await physics_frame

func key(code: int) -> void:
 var event := InputEventKey.new()
 event.keycode = code
 # 실제 OS 주입에서 관찰한 일반/물리 키코드 불일치도 검사한다.
 event.physical_keycode = KEY_PAUSE
 event.pressed = true
 root.push_input(event, true)
 await frames()

func aim_at(point: Vector2) -> void:
 app._update_world_view()
 var event := InputEventMouseMotion.new()
 event.position = world.get_global_transform_with_canvas() * point
 root.push_input(event, true)
 await frames()

func capture(stem: String) -> void:
 if not rendered: return
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(directory.path_join(stem + ".png"))

func run() -> void:
 directory = ProjectSettings.globalize_path("res://../evidence/input_aim_collision")
 DirAccess.make_dir_recursive_absolute(directory)
 app = load("res://main.tscn").instantiate()
 root.add_child(app)
 world = app.world
 app.brain.auto_enabled = false
 world.npc_combat_enabled = false
 world.set_physics_process(false)
 for enemy in world.get_node("Enemies").get_children(): enemy.set_physics_process(false)
 await frames()
 await test_chat()
 await test_aim()
 await test_obstacles()
 var passed := checks.values().all(func(value): return value)
 var result := {"suite": "input_aim_collision", "passed": passed, "check_count": checks.size(), "checks": checks, "gpu_rendered": rendered, "synthetic_input_events": true, "actual_microsoft_ime_tested": false, "human_playtest": false}
 var file := FileAccess.open(directory.path_join("render.json" if rendered else "test.json"), FileAccess.WRITE)
 file.store_string(JSON.stringify(result, "  "))
 file.close()
 print("INPUT_COLLISION_RESULT " + JSON.stringify(result))
 app.queue_free()
 await frames()
 quit(0 if passed else 1)

func test_chat() -> void:
 var field: ChatInput = app.question
 field.text = ""
 await key(KEY_ENTER)
 check("empty_enter_closes_unfocused_lab_dialogue", not app.dialogue_panel.visible and world.can_move and app.brain.history.is_empty())
 await key(KEY_ENTER)
 check("enter_opens_chat_and_blocks_movement", field.has_focus() and not world.can_move)
 field.text = "   "
 await key(KEY_KP_ENTER)
 check("whitespace_keypad_enter_closes_without_send", not app.dialogue_panel.visible and not field.has_focus() and world.can_move and app.brain.history.is_empty())
 var before := world.player.position
 Input.action_press("move_right")
 await frames(10)
 Input.action_release("move_right")
 check("movement_resumes_after_empty_enter", world.player.position.x > before.x + 10)
 await key(KEY_ENTER)
 field.text = "남겨 둔 초안"
 await key(KEY_ESCAPE)
 check("escape_closes_and_preserves_draft", not app.dialogue_panel.visible and field.text == "남겨 둔 초안" and world.can_move and not app.pause_menu.visible)
 await key(KEY_ENTER)
 field.text = "안녕"
 await key(KEY_ENTER)
 check("nonempty_enter_sends_once_then_closes", not app.dialogue_panel.visible and world.can_move and app.brain.history.size() == 1)
 app.brain.pending = {"kind": "decision"}
 app._send_question("응답 대기 검사")
 app.open_dialogue()
 await key(KEY_ENTER)
 check("readonly_pending_enter_closes_without_cancelling_request", not app.dialogue_panel.visible and world.can_move and not app.brain.pending.is_empty())
 app.open_dialogue()
 await key(KEY_ESCAPE)
 check("readonly_pending_escape_closes_before_pause", not app.dialogue_panel.visible and not app.pause_menu.visible and not app.brain.pending.is_empty())
 app.brain.pending = {}
 app.brain.queued_question = ""
 app._enable_question()
 world.flashlight_owned = true
 world.apply_interaction("storage_gate")
 field.text = ""
 await key(KEY_ENTER)
 await key(KEY_ENTER)
 check("empty_enter_closes_storage_chat", not app.dialogue_panel.visible and not field.has_focus() and world.can_move)
 await key(KEY_ESCAPE)
 check("closed_chat_escape_opens_pause_normally", app.pause_menu.visible and paused)
 await key(KEY_ESCAPE)
 check("pause_escape_restores_movement", not app.pause_menu.visible and world.can_move)

func test_aim() -> void:
 # 시야 픽셀 표본을 대화/알림 UI가 가리지 않도록 이 검사만의 준비 상태를 만든다.
 app.combat_hud.clear_speech()
 world.player.position = Vector2(410, 318)
 world.player.facing_direction = Vector2.DOWN
 await aim_at(world.player.position + Vector2(300, 0))
 check("mouse_aim_overrides_movement_facing", world.flashlight_direction().dot(Vector2.RIGHT) > 0.999 and world.player.facing_direction == Vector2.DOWN)
 check("cpu_visibility_uses_mouse_beam", world.visibility_at(world.player.position + Vector2(240, 0)) > 0.2 and world.visibility_at(world.player.position + Vector2(0, 240)) < 0.01)
 await aim_at(world.player.position - Vector2(300, 0))
 world.update_visibility()
 var shader_direction: Vector2 = world.get_node("Darkness").material.get_shader_parameter("flashlight_direction")
 check("shader_and_hud_share_mouse_direction", shader_direction.dot(Vector2.LEFT) > 0.999 and world.visibility_at(world.player.position - Vector2(240, 0)) > 0.2)
 await capture("mouse_flashlight")
 if rendered:
  var picture := root.get_texture().get_image()
  var transform := world.get_global_transform_with_canvas()
  var lit := picture.get_pixelv(Vector2i(transform * (world.player.position - Vector2(220, 0))))
  var dark := picture.get_pixelv(Vector2i(transform * (world.player.position + Vector2(220, 0))))
  check("gpu_beam_rotates_to_mouse", lit.r + lit.g + lit.b > dark.r + dark.g + dark.b + 0.015)
 await aim_at(world.player.position + Vector2(250, -80))
 Input.action_press("move_right")
 await frames(16)
 Input.action_release("move_right")
 check("stationary_mouse_recomputes_aim_after_player_and_camera_move", world.flashlight_direction().dot(world.player.position.direction_to(world.mouse_aim_position())) > 0.999)
 var previous_direction := world.flashlight_direction()
 await aim_at(world.player.position)
 check("mouse_on_player_keeps_finite_last_direction", world.flashlight_direction().is_finite() and world.flashlight_direction().dot(previous_direction) > 0.999)
 world.apply_interaction("lab_gate")
 app.close_dialogue()
 world.player.position = Vector2(700, 350)
 await aim_at(world.player.position + Vector2(-140, -90))
 check("zoomed_lab_uses_canvas_inverse_for_mouse", world.flashlight_direction().dot(Vector2(-140, -90).normalized()) > 0.999)

func move_player(direction: Vector2, count: int) -> Dictionary:
 var touched := false
 var largest_step := 0.0
 for index in range(count):
  await physics_frame
  var before := world.player.position
  world.player.velocity = direction.normalized() * world.player.move_speed
  world.player.move_and_slide()
  touched = touched or world.player.get_slide_collision_count() > 0
  largest_step = maxf(largest_step, world.player.position.distance_to(before))
 world.player.velocity = Vector2.ZERO
 return {"touched": touched, "largest_step": largest_step}

func test_obstacles() -> void:
 world.player.set_physics_process(false)
 for room in ["lab", "storage", "quarters"]:
  world._change_map(room, Vector2(300, 350))
  await frames()
  var obstacles: Array = world.fleet_rooms[room].find_children("*", "StaticBody2D", true, false)
  var tested := 0
  for obstacle: RoundedObstacle in obstacles:
   var half: Vector2 = obstacle.footprint * 0.5
   var start: Vector2 = obstacle.global_position + Vector2(0, half.y + 22)
   if not world.room_rect.grow(-14).has_point(start) or world.obstruction_rects().any(func(rect): return rect.grow(13).has_point(start)): continue
   world.player.position = start
   await frames()
   var movement := await move_player(Vector2.UP, 16)
   tested += 1
   check("solid_%s_%d" % [room, tested], movement.touched and world.player.position.y >= obstacle.global_position.y + half.y - 3)
  check("fixture_reaches_multiple_objects_" + room, tested >= 3)
  for hidden in world.fleet_rooms:
   if hidden == room: continue
   var hidden_obstacles: Array = world.fleet_rooms[hidden].find_children("*", "StaticBody2D", true, false)
   check("inactive_room_%s_has_no_collision_in_%s" % [hidden, room], hidden_obstacles.all(func(item): return item.collision_layer == 0))
 world._change_map("lab", Vector2(300, 350))
 await frames()
 check("research_core_collision_matches_visible_base", Rect2(248, 344, 93, 35) in world.obstruction_rects())
 world.player.position = Vector2(210, 405)
 var cross := await move_player(Vector2.RIGHT, 52)
 check("empty_floor_in_front_of_core_is_walkable", not cross.touched and world.player.position.x > 345)
 world.player.position = Vector2(204, 395)
 var start := world.player.position
 var slide := await move_player(Vector2(1, -0.2), 100)
 check("rounded_corner_allows_continuous_slide", slide.touched and world.player.position.x - start.x > 200)
 check("sliding_has_no_position_jump", slide.largest_step < 4.5)
 await capture("lab_solid_props")
 world._change_map("storage", Vector2(300, 350))
 await frames()
 check("coop_panel_collision_matches_visible_base", world.locker.get_node("PanelA/Solid").position == Vector2(0, -6) and world.locker.get_node("PanelA/Solid").footprint == Vector2(42, 12))
 var hidden_obstacle := Vector2(285, 342)
 world.player.position = hidden_obstacle + Vector2(0, 45)
 var through_hidden := await move_player(Vector2.UP, 22)
 check("hidden_lab_core_does_not_block_storage", not through_hidden.touched and world.player.position.y < hidden_obstacle.y)
 var panel: Node2D = world.locker.get_node("PanelA/Solid")
 world.player.global_position = panel.global_position + Vector2(0, 50)
 await move_player(Vector2.UP, 24)
 world.can_move = true
 var event := InputEventAction.new()
 event.action = "interact"
 event.pressed = true
 for enemy in world.get_node("Enemies").get_children(): enemy.take_damage(enemy.hp)
 root.push_input(event, true)
 await frames()
 check("panel_interaction_reachable_outside_collider", world.locker.needs_assistance() and world.player.position.distance_to(world.locker.panel_position(0)) <= world.locker.use_radius)
