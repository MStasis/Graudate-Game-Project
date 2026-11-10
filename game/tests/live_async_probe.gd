extends "res://tests/harin_live_test.gd"
## 문답 품질 평가와 분리한 실제 비동기·긴급 대응·취소 회귀.
func run() -> void:
 app = load("res://main.tscn").instantiate()
 root.add_child(app)
 app.brain.new_trial(1)
 app.brain.auto_enabled = false
 world = app.world
 world.set_physics_process(false)
 for enemy in world.get_node("Enemies").get_children(): enemy.set_physics_process(false)
 app.brain.measured.connect(func(record): measurements.append(record.duplicate(true)))
 await test_live_emergency()
 await test_live_timeout_and_cancel()
 var directory := ProjectSettings.globalize_path("res://../evidence/story_ui")
 DirAccess.make_dir_recursive_absolute(directory)
 var result := {"passed": not checks.values().has(false), "check_count": checks.size(), "checks": checks, "samples": samples, "measurements": measurements, "actual_model": app.brain.local_dialogue.settings.model, "actual_inference": true, "timeout_injected": true, "human_playtest": false}
 FileAccess.open(directory.path_join("live_async_probe.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
 print("LIVE_ASYNC_PROBE ", JSON.stringify({"passed": result.passed, "check_count": checks.size(), "checks": checks}))
 app.queue_free()
 await process_frame
 quit(0 if result.passed else 1)
