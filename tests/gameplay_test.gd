extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var checks := {}
	app.interact("generator")
	checks["power_requires_fuse"] = not app.world.power_restored
	app.interact("exit")
	checks["exit_requires_power"] = not app.world.finished
	app.interact("fuse")
	checks["fuse_is_inventory_item"] = app.game_state().fuse_in_inventory
	app.interact("generator")
	checks["restoring_power_consumes_inventory_fuse"] = app.world.power_restored and not app.game_state().fuse_in_inventory
	app.interact("exit")
	checks["powered_exit_completes_game"] = app.world.finished
	app.reset_demo()
	checks["restart_clears_state"] = not app.world.finished and not app.world.power_restored and not app.world.fuse_collected
	app.busy = true
	app.interact("fuse")
	checks["pending_response_preserves_state"] = not app.world.fuse_collected
	app.busy = false
	var passed := true
	for value in checks.values(): passed = passed and value
	var result := {"suite": "gameplay_state_rules", "synthetic_test": true, "passed": passed, "checks": checks}
	var file := FileAccess.open(app.log_dir.path_join("gameplay_test.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	print("GAMEPLAY_TEST ", JSON.stringify(result))
	quit(0 if passed else 1)

