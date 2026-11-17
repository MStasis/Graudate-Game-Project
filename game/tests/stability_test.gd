extends SceneTree

const Mission := preload("res://main.gd")
const Fleet := preload("res://scripts/fleet_demo.gd")

var app: Mission
var checks := {}

func _initialize() -> void:
 run.call_deferred()

func check(label: String, passed: bool) -> bool:
 checks[label] = passed
 if not passed: push_error("STABILITY_CHECK_FAILED " + label)
 return passed

func run() -> void:
 app = (load("res://main.tscn") as PackedScene).instantiate() as Mission
 app.world_starts_fleet_demo = true
 root.add_child(app)
 app.brain.auto_enabled = false
 app.save_store.directory = "user://stability_test_%d" % OS.get_process_id()
 app.world.fleet_demo.clear_cues()

 check("normal_play_does_not_log_raw_dialogue", app.brain.log_dir.is_empty() and app.brain.local_dialogue.log_dir.is_empty())
 check("explicit_capture_is_available", app._configure_launch(PackedStringArray(["--record-dialogue"])) and app.log_dir.begins_with(ProjectSettings.globalize_path("user://")))
 test_save()
 test_transport()
 test_decision()
 await test_repair_recovery()
 print("STABILITY_RESULT ", JSON.stringify({"check_count": checks.size(), "checks": checks, "passed": not checks.values().has(false)}))
 quit(1 if checks.values().has(false) else 0)

func test_save() -> void:
 var world := app.world
 var store := app.save_store
 # Use the same journal path as the HUD, with long UTF-8 text.
 for index in MessageJournal.LIMIT:
  app.combat_hud.journal.append("미카", "dialogue", str(index) + "한".repeat(2000), world.map_id, "1")
 var journal := app.combat_hud.journal.entries
 check("large_journal_fits_without_altering_live_journal", app.save_slot(1) and journal.size() == MessageJournal.LIMIT)
 var data := store.read_slot(1)
 if not check("large_journal_loads", not data.is_empty() and app.load_slot(1)): return
 check("newest_entries_preserved", data.journal.size() < MessageJournal.LIMIT and data.journal.back().sequence == MessageJournal.LIMIT)
 var before := FileAccess.get_sha256(store.path_for(1))
 var oversized := data.duplicate(true)
 oversized["extra"] = "한".repeat(MissionSaveStore.MAX_SAVE_BYTES)
 check("oversized_payload_keeps_previous_save", not store.write_slot(1, oversized) and before == FileAccess.get_sha256(store.path_for(1)))

 var malformed := data.duplicate(true)
 malformed.world.reload_time = 0.5
 malformed.world.ammo = "bad"
 check("invalid_ammo_has_clear_error", not store.validate(malformed, world) and not store.last_error.is_empty())
 malformed = data.duplicate(true)
 malformed.world.erase("flashlight_position")
 check("invalid_inactive_field_rejected_before_restore", not store.validate(malformed, world) and not store.last_error.is_empty())
 var config := world.log_configuration()
 var stable_hash := MissionSaveStore.compatibility_hash(config)
 data.scenario = JSON.stringify(config).sha256_text()
 check("existing_fleet_save_hash_still_valid", store.validate(data, world))
 config.companion_rules.prompt_version = "new_prompt_revision"
 check("prompt_version_is_not_save_compatibility", stable_hash == MissionSaveStore.compatibility_hash(config))
 config.bullet_damage += 1
 check("combat_changes_still_change_save_compatibility", stable_hash != MissionSaveStore.compatibility_hash(config))

func test_transport() -> void:
 var brain := app.brain
 var client := brain.local_dialogue
 var errors: Array[String] = []
 client.failed.connect(func(message): errors.append(message))
 brain.provider = 1
 var question := "오늘 기분은 어때?"
 prepare_local_reply(question, 10)
 client._consume_chunk('{"message":[],"done":true}\n'.to_utf8_buffer())
 check("malformed_message_releases_request", errors.size() == 1 and not client.busy and brain.pending.is_empty() and app.question.editable)

 prepare_local_reply(question, 11)
 client._consume_chunk('{"message":{"content":24},"done":true}\n'.to_utf8_buffer())
 check("malformed_token_releases_request", errors.size() == 2 and not client.busy and brain.pending.is_empty())

 prepare_local_reply(question, 12)
 var huge_line := PackedByteArray()
 huge_line.resize(LocalAIClient.MAX_EVENT_BYTES + 1)
 client._consume_chunk(huge_line)
 check("single_line_limit_releases_request", errors.size() == 3 and not client.busy and brain.pending.is_empty())

 prepare_local_reply(question, 13)
 client.response_bytes = LocalAIClient.MAX_RESPONSE_BYTES
 client._consume_chunk(PackedByteArray([10]))
 check("aggregate_byte_limit_releases_request", errors.size() == 4 and not client.busy and brain.pending.is_empty())

 prepare_local_reply(question, 14)
 var content := {"message": {"content": "한".repeat(MikaDialogue.ANSWER_LIMIT + 1)}, "done": false}
 var bytes := (JSON.stringify(content) + "\n").to_utf8_buffer()
 var half := bytes.size() / 2
 client._consume_chunk(bytes.slice(0, half))
 client._consume_chunk(bytes.slice(half))
 client._consume_chunk('{"message":{"content":""},"done":true,"model":"test-fixture"}'.to_utf8_buffer())
 client._finish_stream("연결 종료")
 check("valid_chunked_reply_can_be_saved", not client.busy and brain.pending.is_empty() and not brain.history.is_empty() and brain.history.back().answer.length() == MikaDialogue.ANSWER_LIMIT and app.save_slot(2))

func prepare_local_reply(question: String, request_id: int) -> void:
 var brain := app.brain
 var client := brain.local_dialogue
 var snapshot := app.world.game_state()
 brain.pending = {"kind": "dialogue", "question": question, "snapshot": snapshot, "snapshot_hash": "fixture", "request_id": request_id, "started_usec": Time.get_ticks_usec(), "epoch": app.world.epoch, "allowed": []}
 client.request_state = {"_channel": "dialogue", "_request_id": request_id}
 client.busy = true
 client.generated = ""
 client.buffer = PackedByteArray()
 client.response_bytes = 0
 client.started_usec = Time.get_ticks_usec()
 client.first_usec = 0
 app.question.editable = false

func test_decision() -> void:
 var world := app.world
 var brain := app.brain
 brain.provider = 0
 check("empty_tactical_candidates_do_not_start_request", world.valid_actions().is_empty() and not brain.request_decision() and brain.pending.is_empty())
 world._change_map("mika_quarters", world.bounds_for("mika_quarters").get_center())
 world.fleet_demo.step = Fleet.Step.FIND_FUSE
 world._sync_state()
 world.npc_motion.order("wait", world.npc.position)
 var records: Array[Dictionary] = []
 brain.measured.connect(func(record): records.append(record))
 var snapshot := world.game_state()
 brain.pending = {"kind": "decision", "question": "", "snapshot": snapshot, "snapshot_hash": "fixture", "request_id": 15, "started_usec": Time.get_ticks_usec(), "epoch": world.epoch, "allowed": snapshot.valid_actions}
 brain._resolve("follow", {})
 check("automatic_no_change_is_reported_without_execution", not records.is_empty() and records.back().action_outcome == "no_change" and not records.back().accepted and world.npc_motion.mode == "wait")

func test_repair_recovery() -> void:
 var world := app.world
 var demo := world.fleet_demo
 demo.step = Fleet.Step.REPAIR
 world.fuse_collected = true
 var starting_point := Fleet.HANDOFF_POSITION + Vector2(31, 0)
 world._change_map("power_room", starting_point)
 world.npc.position = Fleet.HANDOFF_POSITION
 var stand := demo.rooms.power_room.get_node("PlayerRepairStand") as Marker2D
 var safe_stand := stand.position
 stand.position = Vector2(-300, -300)
 world.apply_interaction("give_fuse")
 check("blocked_repair_starts_locked", demo.fuse_handed and demo.locks_movement())
 for i in ceili(Fleet.REPAIR_MOVE_TIMEOUT * 60) + 10:
  await physics_frame
  if demo.npc_task.is_empty(): break
 check("blocked_repair_returns_fuse_and_unlocks", demo.npc_task.is_empty() and not demo.locks_movement() and world.can_move and world.fuse_collected and not demo.fuse_handed and not demo.inserted and not world.player.scripted_target.is_finite())
 stand.position = safe_stand
 world.apply_interaction("give_fuse")
 for i in 560:
  await physics_frame
  if world.power_restored: break
 check("repair_can_be_retried_to_completion", world.power_restored and demo.inserted)
