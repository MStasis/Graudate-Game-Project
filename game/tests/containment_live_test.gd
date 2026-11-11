extends SceneTree
## 실제 HTTP 취소 검사. 봉쇄 완료 직전 상태는 fixture이며 플레이 완주가 아니다.
var checks := {}

func _initialize() -> void:
 call_deferred("run")

func run() -> void:
 var app = load("res://main.tscn").instantiate()
 root.add_child(app)
 await process_frame
 var world: DemoWorld = app.world
 var brain: NPCBrain = app.brain
 brain.auto_enabled = false
 world.set_physics_process(false)
 world.trigger_blackout()
 app._send_question("지금 뭘 해야 해?")
 await process_frame
 checks["new_game_real_request_pending"] = brain.local_dialogue.busy and not brain.dialogue_pending.is_empty()
 app.reset_demo(1)
 checks["new_game_cancels_http_and_memory"] = not brain.local_dialogue.busy and brain.pending.is_empty() and brain.history.is_empty() and world.story.stage == "on_shift"
 world.flashlight_owned = true
 world.fuse_collected = true
 world.power_restored = true
 world.map_id = "main_entry"
 world.story.stage = "containment"
 world.story.tutorial_completed = true
 world.story.events.assign(["blackout", "flashlight_collected", "storage_entered", "fuse_collected", "power_restored", "anomaly_alarm", "main_entered", "anomaly_observed", "containment_briefed", "containment_wave_1", "containment_wave_2", "containment_waves_cleared"])
 world.containment.stage = "panel_ready"
 world.containment.supply_used = true
 world.containment.panel.sequence_elapsed = 0
 world._sync_state()
 app._send_question("이제 봉쇄 패널을 어떻게 작동해?")
 await process_frame
 var pending: Dictionary = brain.pending.duplicate(true)
 checks["ending_real_request_pending"] = brain.local_dialogue.busy and not pending.is_empty()
 world.containment.panel.tick(1.01, false)
 checks["ending_cancels_actual_http_and_queue"] = world.finished and brain.pending.is_empty() and brain.queued_question.is_empty() and not brain.local_dialogue.busy and not brain.local_decision.busy
 var fixed_line: String = app.combat_hud.npc_bubble.full_text
 # 취소된 전송이 뒤늦게 콜백으로 돌아오는 경계도 재현한다.
 if not pending.is_empty():
  brain._local_completed({"request_state": {"_request_id": pending.request_id, "_channel": "dialogue"}, "response": "퓨즈를 다시 찾아야 해.", "actual_model": "synthetic_late_callback"})
 await create_timer(0.4).timeout
 checks["late_callback_never_displays_or_enters_memory"] = app.combat_hud.npc_bubble.full_text == fixed_line and brain.history.is_empty() and "보고서" in fixed_line
 checks["ending_rejects_new_model_requests"] = not brain.request_dialogue("퓨즈가 어디 있어?") and not brain.request_decision()
 await create_timer(6.1).timeout
 checks["ending_result_with_server_present"] = app.result_screen.visible and world.get_node("Projectiles").get_child_count() == 0
 var directory := ProjectSettings.globalize_path("res://../evidence/containment")
 DirAccess.make_dir_recursive_absolute(directory)
 var result := {"passed": not checks.values().has(false), "check_count": checks.size(), "checks": checks, "actual_model": brain.local_dialogue.settings.model, "http_requests_started": 2, "completion_fixture": true, "late_callback_fixture": true, "human_playtest": false, "created_utc": Time.get_datetime_string_from_system(true)}
 FileAccess.open(directory.path_join("live.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
 print("CONTAINMENT_LIVE_RESULT ", JSON.stringify(result))
 app.queue_free()
 await process_frame
 quit(0 if result.passed else 1)
