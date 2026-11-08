extends SceneTree
var checks := {}
func _initialize() -> void:
 call_deferred("run")
func check(label: String, condition: bool) -> void:
 checks[label] = condition
 if not condition: push_error("COOP_INPUT_FAILED " + label)
func click(point: Vector2) -> void:
 var event := InputEventMouseButton.new()
 event.button_index = MOUSE_BUTTON_LEFT
 event.position = point
 event.pressed = true
 root.push_input(event, true)
 event = event.duplicate()
 event.pressed = false
 root.push_input(event, true)
func run() -> void:
 var app = load("res://scenes/CoopProbe.tscn").instantiate()
 root.add_child(app)
 check("host_ready", app.host_game(24573) == OK)
 await process_frame
 click(app.enemy.position)
 await create_timer(1.3).timeout
 check("single_frame_click_fires_exactly_once", app.players[1].shots == 1 and app.players[1].ammo == 19)
 check("single_frame_click_deals_real_damage", app.enemy.hp == 75)
 click(Vector2(60, 35))
 await create_timer(0.1).timeout
 check("hud_click_does_not_fire", app.players[1].shots == 1 and app.players[1].ammo == 19)
 var key := InputEventKey.new()
 key.physical_keycode = KEY_SPACE
 key.pressed = true
 root.push_input(key, true)
 key = key.duplicate()
 key.pressed = false
 root.push_input(key, true)
 await create_timer(1.3).timeout
 check("single_frame_space_fires_exactly_once", app.players[1].shots == 2 and app.players[1].ammo == 18 and app.enemy.hp == 50)
 click(Vector2(1100, 84)) # 초기화 버튼을 누른 뒤 Space가 버튼을 다시 누르지 않아야 한다.
 await process_frame
 key.pressed = true
 root.push_input(key, true)
 key = key.duplicate()
 key.pressed = false
 root.push_input(key, true)
 await create_timer(1.3).timeout
 check("reset_button_does_not_capture_space", app.players[1].shots == 1 and app.players[1].ammo == 19 and app.enemy.hp == 75)
 app.leave_game("접속 실패 검사")
 app.join_game("127.0.0.1", 24574)
 await create_timer(6.5).timeout
 check("unavailable_host_returns_to_menu", not app.active and not app.get_node("HUD/Panel/Join").disabled)
 app.leave_game("검사 종료")
 app.queue_free()
 await process_frame
 var main = load("res://main.tscn").instantiate()
 root.add_child(main)
 main.brain.auto_enabled = false
 var world: DemoWorld = main.world
 var audio = world.get_node("MissionAudio")
 var initial: int = audio.played_events
 world.flashlight_owned = true # Fixture: 기존 회귀의 전투/입력 조건. 지급 흐름은 mission_mechanics_test에서 별도 검증.
 world.apply_interaction("storage_gate")
 check("room_transition_routes_audio", audio.played_events > initial)
 world.ammo = 20
 world.state_changed.emit()
 var before: int = audio.played_events
 world.shoot(Vector2(600, 405))
 check("player_shot_routes_audio", audio.played_events == before + 1)
 before = audio.played_events
 world.take_damage(5)
 check("damage_routes_audio", audio.played_events == before + 1)
 check("audio_stream_has_decodable_duration", audio.voices[0].stream != null and audio.voices[0].stream.get_length() > 0)
 var directory := ProjectSettings.globalize_path("res://../evidence/coop_probe")
 DirAccess.make_dir_recursive_absolute(directory)
 var result := {"suite": "coop_input_and_presentation", "passed": not checks.values().has(false), "check_count": checks.size(), "checks": checks, "synthetic_input_events": true, "human_audio_listening": false}
 FileAccess.open(directory.path_join("input.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
 print("COOP_INPUT_RESULT ", JSON.stringify(result))
 main.queue_free()
 await process_frame
 # 오디오 믹서가 중단한 OGG 디코더를 회수할 실제 시간을 둔다.
 await create_timer(0.15).timeout
 quit(0 if result.passed else 1)
