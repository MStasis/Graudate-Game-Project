extends SceneTree
var results: Array[Dictionary] = []
var latest := {}
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var app = load("res://main.tscn").instantiate()
 root.add_child(app)
 await process_frame
 var brain: NPCBrain = app.brain
 var world: DemoWorld = app.world
 brain.auto_enabled = false
 world.set_physics_process(false)
 world.player.set_physics_process(false)
 for enemy in world.get_node("Enemies").get_children(): enemy.set_physics_process(false)
 brain.measured.connect(func(record): latest = record)
 var cases := [
 {"id": "low_health", "kind": "decision", "hp": 40, "ammo": 20, "expected": ["heal"]},
 {"id": "empty_ammo", "kind": "decision", "hp": 100, "ammo": 0, "expected": ["resupply"]},
 {"id": "combat_cover", "kind": "decision", "hp": 100, "ammo": 20, "expected": ["deploy_cover"]},
 {"id": "mission_question", "kind": "dialogue", "question": "지금 무엇을 해야 해?"},
 {"id": "friend_relationship", "kind": "dialogue", "question": "하린, 우린 어떤 사이야?"},
 {"id": "everyday_chat", "kind": "dialogue", "question": "오늘 좀 긴장돼. 너는 괜찮아?"}
 ]
 var mode := brain.provider
 for scenario in cases:
  brain.new_trial(mode)
  latest = {}
  if scenario.kind == "decision":
   world.apply_interaction("storage_gate")
   world.player_hp = scenario.hp
   world.ammo = scenario.ammo
   brain.request_decision()
  else:
   brain.request_dialogue(scenario.question)
  var elapsed := 0.0
  while not brain.pending.is_empty() and elapsed < 100.0:
   await create_timer(0.05).timeout
   elapsed += 0.05
  var record := latest.duplicate(true)
  record["case_id"] = scenario.id
  record["request_observed"] = not latest.is_empty()
  record["expected_actions"] = scenario.get("expected", [])
  if scenario.kind == "decision": record["initial_reference_match"] = record.get("selected", "") in scenario.expected
  results.append(record)
 var passed := true
 for result in results:
  passed = passed and result.request_observed
 var output := {"provider": NPCBrain.PROVIDERS[mode], "phase": "fixed_snapshot_live_probe", "benchmark_complete": false, "passed_transport_for_all_cases": passed, "results": results, "jev_live_calls": brain.jev_calls}
 var file := FileAccess.open(app.log_dir.path_join(NPCBrain.PROVIDERS[mode] + "_probe_" + str(OS.get_process_id()) + ".json"), FileAccess.WRITE)
 file.store_string(JSON.stringify(output, "  "))
 for result in results:
  print("PROVIDER_PROBE ", JSON.stringify({"case_id": result.case_id, "observed": result.request_observed, "selected": result.get("selected"), "elapsed_ms": result.get("elapsed_ms"), "accepted": result.get("accepted"), "reference_match": result.get("initial_reference_match"), "rejection": result.get("rejected_reason")}))
 quit(0 if passed else 1)
