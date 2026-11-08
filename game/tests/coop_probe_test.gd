extends SceneTree
var app: Node2D
var checks := {}
var role := "host"
var port := 24571
var directory := ""

func _initialize() -> void:
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with("--test-role="): role = argument.get_slice("=", 1)
  if argument.begins_with("--test-port="): port = int(argument.get_slice("=", 1))
 call_deferred("run")

func check(label: String, condition: bool) -> void:
 checks[label] = condition
 if not condition: push_error("COOP_CHECK_FAILED " + role + ": " + label)

func until(condition: Callable, seconds: float = 8) -> bool:
 var deadline := Time.get_ticks_msec() + int(seconds * 1000)
 while not condition.call() and Time.get_ticks_msec() < deadline:
  await create_timer(0.025).timeout
 return bool(condition.call())

func delay(seconds: float) -> void:
 await create_timer(seconds).timeout

func capture(stem: String) -> void:
 if DisplayServer.get_name() == "headless": return
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(directory.path_join(stem + ".png"))

func rejection_received(seq: int, movement: Vector2, aim: Vector2) -> bool:
 var previous := int(app.latest_state.get("rejected_inputs", 0))
 # 이 채널은 UDP다. 전송 손실을 입력 검증 실패로 오인하지 않고 응답까지 재전송한다.
 for attempt in range(6):
  app._submit_input.rpc_id(1, seq, movement, aim, true)
  if await until(func(): return int(app.latest_state.get("rejected_inputs", 0)) > previous, 0.15): return true
 return false

func run() -> void:
 directory = ProjectSettings.globalize_path("res://../evidence/coop_probe")
 DirAccess.make_dir_recursive_absolute(directory)
 app = load("res://scenes/CoopProbe.tscn").instantiate()
 root.add_child(app)
 app.test_override = true
 if role == "host": await run_host()
 else: await run_client()
 var result := {"role": role, "passed": not checks.values().has(false), "check_count": checks.size(), "checks": checks, "real_enet_two_processes": true, "same_machine_loopback": true, "two_pc_lan_tested": false, "gpu_rendered": DisplayServer.get_name() != "headless"}
 FileAccess.open(directory.path_join(role + ".json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
 print("COOP_PROBE_RESULT ", JSON.stringify(result))
 app.leave_game("검사 종료")
 app.queue_free()
 await process_frame
 quit(0 if result.passed else 1)

func run_host() -> void:
 check("enet_server_created", app.host_game(port) == OK)
 if not await until(func(): return app.players.size() == 2):
  check("client_connected", false)
  return
 check("one_remote_player", app.players.size() == 2 and app.peer_joins == 1)
 var remote: int = app.players.keys().filter(func(id): return id != 1)[0]
 await delay(0.2)
 app.test_move = Vector2.DOWN
 await delay(0.35)
 app.test_move = Vector2.ZERO
 await delay(0.7)
 check("host_moves_own_actor", app.players[1].actor.position.y > 370)
 check("remote_input_moves_only_remote_actor", app.players[remote].actor.position.y < 475 and app.players[1].actor.position.y > 370)
 app.test_fire = true
 check("host_fires_two_real_projectiles", await until(func(): return app.players[1].shots >= 2, 3))
 app.test_fire = false
 check("both_players_clear_same_target", await until(func(): return app.enemy.hp == 0, 5))
 check("host_ammo_consumed_once", app.players[1].ammo == 18 and app.players[1].shots == 2)
 check("remote_ammo_consumed_once", app.players[remote].ammo == 18 and app.players[remote].shots == 2)
 check("both_players_dealt_actual_damage", app.players[1].hits == 2 and app.players[remote].hits == 2)
 check("replayed_and_nonfinite_input_rejected", await until(func(): return app.rejected_inputs >= 3, 5))
 check("remote_disconnect_removes_actor", await until(func(): return app.peer_leaves == 1 and app.players.size() == 1, 5))
 check("reconnect_has_exactly_two_actors", await until(func(): return app.peer_joins == 2 and app.players.size() == 2, 5))
 check("reconnect_does_not_respawn_target", app.enemy.hp == 0)
 await delay(0.6)
 app.reset_target()
 await delay(0.4)
 check("host_reset_restores_resources", app.enemy.hp == 100 and app.players.values().all(func(state): return state.ammo == 20))
 await capture("host_reconnected")
 app.leave_game("호스트 종료 검사")
 await delay(0.5)

func run_client() -> void:
 check("enet_client_created", app.join_game("127.0.0.1", port) == OK)
 if not await until(func(): return app.connected and app.players.size() == 2):
  check("welcome_snapshot_received", false)
  return
 check("welcome_has_two_actors", app.players.size() == 2)
 var own_id := app.multiplayer.get_unique_id()
 await delay(0.2)
 app.test_move = Vector2.UP
 await delay(0.35)
 app.test_move = Vector2.ZERO
 await delay(0.7)
 check("own_input_replicated_by_server", app.players[own_id].actor.position.y < 475)
 check("host_movement_replicated", app.players[1].actor.position.y > 370)
 await capture("two_players_before_fire")
 app.test_fire = true
 check("own_shots_acknowledged", await until(func(): return app.players[own_id].shots >= 2, 3))
 app.test_fire = false
 check("same_target_death_replicated", await until(func(): return app.enemy.hp == 0, 5))
 check("both_ammo_values_match_authority", app.players[1].ammo == 18 and app.players[own_id].ammo == 18)
 check("both_hit_counts_match_authority", app.players[1].hits == 2 and app.players[own_id].hits == 2)
 # 정상 20Hz 입력이 진단 패킷을 앞질러 버리지 않게 입력 송신만 잠시 중단한다.
 app.set_physics_process(false)
 check("replayed_sequence_rejected", await rejection_received(-1, Vector2.RIGHT, Vector2(975, 365)))
 check("nonfinite_movement_rejected", await rejection_received(app.sequence + 1000, Vector2(NAN, 0), Vector2(975, 365)))
 check("server_reports_rejected_inputs", await rejection_received(app.sequence + 1001, Vector2.ZERO, Vector2(INF, 0)))
 app.set_physics_process(true)
 check("invalid_inputs_do_not_consume_ammo", app.players[own_id].ammo == 18)
 app.leave_game("재접속 검사")
 await delay(0.5)
 app.join_game("127.0.0.1", port)
 check("reconnected_to_existing_host", await until(func(): return app.connected and app.players.size() == 2, 5))
 if not app.connected: return
 check("old_actor_not_duplicated", app.players.size() == 2 and app.multiplayer.get_unique_id() != own_id and not app.players.has(own_id))
 check("dead_target_persists_on_reconnect", app.enemy.hp == 0)
 check("host_reset_replicated", await until(func(): return app.enemy.hp == 100 and app.players.values().all(func(state): return state.ammo == 20), 3))
 await capture("client_reconnected")
 check("host_disconnect_returns_to_menu", await until(func(): return app.server_lost and not app.active and app.players.is_empty(), 5))
 check("rejoin_controls_enabled_after_disconnect", not app.get_node("HUD/Panel/Join").disabled and "호스트" in app.status.text)
 await capture("host_disconnected")
