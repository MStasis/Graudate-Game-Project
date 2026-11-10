extends SceneTree
var checks := {}
var measurements: Array[Dictionary] = []
var app: Control
var world: DemoWorld

func _initialize() -> void:
 call_deferred("run")

func check(label: String, condition: bool) -> void:
 checks[label] = condition
 if not condition: push_error("MECHANICS_LLM_FAILED " + label)

func wait_for(condition: Callable, seconds := 85.0) -> bool:
 var deadline := Time.get_ticks_msec() + int(seconds * 1000)
 while not condition.call() and Time.get_ticks_msec() < deadline:
  await create_timer(0.025).timeout
 return condition.call()

func panel_fixture() -> void:
 app.brain.new_trial(1)
 app.brain.auto_enabled = false
 world.flashlight_owned = true
 world.apply_interaction("storage_gate")
 for enemy in world.get_node("Enemies").get_children():
  enemy.hp = 0
  enemy.active = false
 world.ammo = 20
 world._sync_state()
 world.player.position = world.locker.panel_position(0) + Vector2(0, 35)
 world.npc.position = world.locker.partner_position() - Vector2(130, 0)
 world.npc_motion.reset()
 Input.action_press("interact")
 world.apply_interaction("panel_a")

func run() -> void:
 app = load("res://main.tscn").instantiate()
 root.add_child(app)
 world = app.world
 app.brain.measured.connect(func(record): measurements.append(record.duplicate(true)))
 panel_fixture()
 var initial := world.npc.position
 app.brain.request_decision()
 check("real_model_returns_panel_decision", await wait_for(func(): return not measurements.is_empty()))
 if not measurements.is_empty():
  check("qwen_selected_valid_panel_action", measurements.back().get("actual_model") == app.brain.local_decision.settings.model and measurements.back().selected == "assist_panel" and measurements.back().accepted)
 check("real_model_choice_completes_locker", await wait_for(func(): return world.locker.opened, 12))
 check("shared_motion_approaches_panel", world.npc.position.distance_to(initial) > 10 and world.npc.position.distance_to(world.locker.panel_position(1)) < 35)
 Input.action_release("interact")
 panel_fixture()
 var old_count := measurements.size()
 app.brain.request_decision()
 Input.action_release("interact")
 check("cancelled_panel_request_returns", await wait_for(func(): return measurements.size() > old_count))
 check("released_panel_prevents_late_execution", not world.locker.opened and world.active_action.is_empty() and not measurements.back().accepted and measurements.back().get("rejected_reason") in ["no_longer_valid", "stale_epoch"])
 app.brain.request_dialogue("퓨즈 보관함은 어떻게 열어?")
 check("mechanic_dialogue_finishes", await wait_for(func(): return app.brain.pending.is_empty()))
 check("mechanic_dialogue_mentions_cooperation", "패널" in app.answer.text and ("같" in app.answer.text or "반대" in app.answer.text or "둘" in app.answer.text or "동시" in app.answer.text))
 check("local_response_never_opens_portrait", not app.dialogue_panel.visible and not app.get_node("RadioPanel/LabPortrait").is_visible_in_tree())
 var mechanic_dialogue: String = app.answer.text
 app.brain.request_dialogue("손전등은 어느 방향을 비춰?")
 check("flashlight_dialogue_finishes", await wait_for(func(): return app.brain.pending.is_empty()))
 check("flashlight_dialogue_explains_mouse_aim", "마우스" in app.answer.text or "조준" in app.answer.text)
 var directory := ProjectSettings.globalize_path("res://../evidence/mission_mechanics")
 DirAccess.make_dir_recursive_absolute(directory)
 var result := {"suite": "mechanics_live_qwen3", "actual_inference": true, "controlled_inputs": true, "passed": not checks.values().has(false), "check_count": checks.size(), "checks": checks, "measurements": measurements, "dialogue": mechanic_dialogue, "flashlight_dialogue": app.answer.text, "human_playtest": false}
 FileAccess.open(directory.path_join("local_ai_%d.json" % OS.get_process_id()), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
 print("MECHANICS_LLM_RESULT ", JSON.stringify({"passed": result.passed, "check_count": checks.size(), "checks": checks, "dialogue": mechanic_dialogue, "flashlight_dialogue": app.answer.text}))
 app.queue_free()
 await process_frame
 quit(0 if result.passed else 1)
