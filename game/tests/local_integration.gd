extends SceneTree
var checks := {}
var measurements: Array[Dictionary] = []
func _initialize() -> void:
 call_deferred("run")
func settle(brain: NPCBrain, world: DemoWorld) -> void:
 var elapsed := 0.0
 while (not brain.pending.is_empty() or not world.active_action.is_empty()) and elapsed < 15.0:
  await create_timer(0.05).timeout
  elapsed += 0.05
func run() -> void:
 var app = load("res://main.tscn").instantiate()
 root.add_child(app)
 await process_frame
 var world: DemoWorld = app.world
 var brain: NPCBrain = app.brain
 brain.auto_enabled = false
 brain.measured.connect(func(record): measurements.append(record))
 brain.new_trial(1)
 world.apply_interaction("storage_gate")
 world.player_hp = 40
 world.ammo = 20
 world.npc.position = world.player.position + Vector2(60, 0)
 var start := world.player.position
 brain.request_decision()
 Input.action_press("move_right")
 await create_timer(0.2).timeout
 Input.action_release("move_right")
 await settle(brain, world)
 checks["real_llm_heal_applies"] = world.player_hp == 75 and world.medkits == 1
 checks["movement_continues_during_inference"] = world.player.position.x > start.x + 8
 if DisplayServer.get_name() != "headless": await app.capture_screen("01_llm_heal")
 world.ammo = 0
 brain.request_decision()
 await settle(brain, world)
 checks["real_llm_resupply_applies"] = world.ammo == 10 and world.supply_packs == 1
 if DisplayServer.get_name() != "headless": await app.capture_screen("02_llm_resupply")
 # 실제로 요청한 뒤 맵을 바꾸어 이전 판단이 실행되지 않는지 검사한다.
 brain.new_trial(1)
 world.apply_interaction("storage_gate")
 world.player_hp = 40
 world.ammo = 20
 brain.request_decision()
 world.apply_interaction("lab_gate")
 await settle(brain, world)
 checks["real_late_reply_dropped_after_map_change"] = world.medkits == 2 and world.player_hp == 40 and measurements.back().rejected_reason == "stale_epoch"
 brain.new_trial(1)
 brain.request_dialogue("지금 무엇을 해야 해?")
 await settle(brain, world)
 checks["real_mission_dialogue_has_route"] = app.answer.text.contains("보관") and app.answer.text.contains("퓨즈")
 if DisplayServer.get_name() != "headless": await app.capture_screen("03_llm_mission_dialogue")
 var passed := true
 for value in checks.values(): passed = passed and value
 var output := {"phase": "live_integration_controlled_inputs", "actual_inference": true, "input_states_controlled": true, "display_server": DisplayServer.get_name(), "human_playtest": false, "benchmark_complete": false, "passed": passed, "checks": checks, "measurements": measurements}
 var file := FileAccess.open(app.log_dir.path_join("live_integration_" + str(OS.get_process_id()) + ".json"), FileAccess.WRITE)
 file.store_string(JSON.stringify(output, "  "))
 print("LIVE_INTEGRATION ", JSON.stringify({"passed": passed, "checks": checks, "requests": measurements.size()}))
 quit(0 if passed else 1)
