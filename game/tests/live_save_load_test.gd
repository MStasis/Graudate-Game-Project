extends SceneTree
var checks := {}

func _initialize() -> void:
 call_deferred("run")

func run() -> void:
 var app = load("res://main.tscn").instantiate()
 root.add_child(app)
 await process_frame
 app.brain.auto_enabled = false
 app.world.set_physics_process(false)
 app.world.trigger_blackout()
 app.save_store.directory = "user://live_save_load_test_%d" % OS.get_process_id()
 checks["initial_save"] = app.save_slot(1)
 app._send_question("지금 무엇을 해야 해?")
 await process_frame
 checks["real_http_request_was_pending"] = not app.brain.pending.is_empty() and app.brain.local_dialogue.busy
 var previous_epoch: int = app.world.epoch
 checks["load_during_real_inference"] = app.load_slot(1)
 checks["load_closes_old_stream_and_changes_epoch"] = app.brain.pending.is_empty() and not app.brain.local_dialogue.busy and not app.brain.local_decision.busy and app.world.epoch > previous_epoch
 var new_question := "보관 구역에서 찾아야 할 물건이 뭐야?"
 app._send_question(new_question)
 var elapsed := 0.0
 while not app.brain.pending.is_empty() and elapsed < 85.0:
  await create_timer(0.05).timeout
  elapsed += 0.05
 checks["new_request_completes_after_cancel"] = app.question.editable and app.brain.history.size() == 1 and app.brain.history[0].question == new_question
 checks["new_reply_is_shown_in_bubble"] = app.combat_hud.npc_bubble.full_text == app.answer.text and "퓨즈" in app.answer.text
 await create_timer(0.4).timeout
 checks["old_question_never_enters_restored_history"] = app.brain.history.size() == 1 and app.brain.history[0].question == new_question
 for name in DirAccess.get_files_at(app.save_store.directory): DirAccess.remove_absolute(app.save_store.directory.path_join(name))
 DirAccess.remove_absolute(app.save_store.directory)
 var result := {"suite": "live_save_load", "passed": not checks.values().has(false), "check_count": checks.size(), "checks": checks, "actual_model": app.brain.local_dialogue.settings.model, "http_requests_started": 2, "human_playtest": false, "actual_windows_ime_tested": false}
 var directory := ProjectSettings.globalize_path("res://../evidence/interface_update")
 DirAccess.make_dir_recursive_absolute(directory)
 FileAccess.open(directory.path_join("live_save_load_%d.json" % OS.get_process_id()), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
 print("LIVE_SAVE_LOAD_TEST ", JSON.stringify(result))
 app.queue_free()
 await process_frame
 quit(0 if result.passed else 1)
