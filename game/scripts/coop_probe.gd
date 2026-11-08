extends Node2D
## LAN 가능성 검증용 작은 전투실. 입력만 클라이언트에서 받고 물리는 호스트가 계산한다.
const PROTOCOL := 1
const DEFAULT_PORT := 24570
const ARENA := Rect2(40, 180, 1200, 480)
const PLAYER := preload("res://scenes/Player.tscn")
const DRONE := preload("res://scenes/Drone.tscn")
const PROJECTILE := preload("res://scenes/Projectile.tscn")
var players := {}
var enemy: MissionDrone
var active := false
var hosting := false
var connected := false
var tick := 0
var last_tick := -1
var sequence := 0
var send_clock := 0.0
var connect_age := 0.0
var latest_state := {}
var rejected_inputs := 0
var peer_leaves := 0
var peer_joins := 0
var server_lost := false
var test_override := false
var test_move := Vector2.ZERO
var test_fire := false
var test_aim := Vector2(975, 365)
var _queued_fire := false
var _queued_aim := Vector2.ZERO
var _shot_sound := preload("res://assets/temporary/kenney/audio/laserSmall_000.ogg")
@onready var status: Label = $HUD/Panel/Status

func _ready() -> void:
 DisplayServer.window_set_title("LAN 협동 검증 · 접속")
 $HUD/Panel/Host.pressed.connect(func(): host_game(int($HUD/Panel/Port.value)))
 $HUD/Panel/Join.pressed.connect(func(): join_game($HUD/Panel/Address.text, int($HUD/Panel/Port.value)))
 $HUD/Panel/Leave.pressed.connect(func(): leave_game("연결을 종료했습니다. 다시 방을 만들거나 참가할 수 있습니다."))
 $HUD/Panel/Reset.pressed.connect(reset_target)
 multiplayer.peer_disconnected.connect(_peer_left)
 multiplayer.connected_to_server.connect(_connected_to_server)
 multiplayer.connection_failed.connect(func(): leave_game("접속 실패. 호스트 IP와 UDP 포트를 확인하세요."))
 multiplayer.server_disconnected.connect(func():
  server_lost = true
  leave_game("호스트 연결이 종료되었습니다. 다시 참가할 수 있습니다."))
 enemy = DRONE.instantiate()
 enemy.name = "Target"
 enemy.max_hp = 100
 enemy.position = Vector2(975, 365)
 enemy.active = false
 enemy.set_physics_process(false)
 $Enemies.add_child(enemy)
 enemy.reset_enemy()
 _refresh_ui()
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with("--coop-port="): $HUD/Panel/Port.value = int(argument.get_slice("=", 1))
 for argument in OS.get_cmdline_user_args():
  if argument == "--coop-host": host_game(int($HUD/Panel/Port.value))
  elif argument.begins_with("--coop-join="): join_game(argument.get_slice("=", 1), int($HUD/Panel/Port.value))

func host_game(port: int = DEFAULT_PORT) -> int:
 leave_game("")
 var peer := ENetMultiplayerPeer.new()
 var result := peer.create_server(port, 1)
 if result != OK:
  status.text = "방 생성 실패 (%d). 다른 포트를 선택하세요." % result
  return result
 multiplayer.multiplayer_peer = peer
 hosting = true
 DisplayServer.window_set_title("LAN 협동 검증 · 호스트")
 active = true
 connected = true
 _spawn_player(1)
 status.text = "방 생성 완료 · UDP %d · 동료를 기다리는 중" % port
 _refresh_ui()
 return OK

func join_game(address: String, port: int = DEFAULT_PORT) -> int:
 leave_game("")
 var peer := ENetMultiplayerPeer.new()
 var result := peer.create_client(address.strip_edges(), port)
 if result != OK:
  status.text = "접속 시작 실패 (%d). IP와 포트를 확인하세요." % result
  return result
 multiplayer.multiplayer_peer = peer
 active = true
 DisplayServer.window_set_title("LAN 협동 검증 · 동료")
 connect_age = 0
 status.text = "%s:%d 연결 중…" % [address, port]
 _refresh_ui()
 return OK

func leave_game(message: String) -> void:
 active = false
 connected = false
 hosting = false
 if multiplayer.multiplayer_peer: multiplayer.multiplayer_peer.close()
 multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
 for child in $Actors.get_children():
  $Actors.remove_child(child)
  child.queue_free()
 for bullet in $Projectiles.get_children(): bullet.queue_free()
 players.clear()
 latest_state.clear()
 sequence = 0
 last_tick = -1
 tick = 0
 send_clock = 0
 _queued_fire = false
 if is_instance_valid(enemy):
  enemy.reset_enemy()
  enemy.active = false
 if is_instance_valid(status):
  if not message.is_empty(): status.text = message
  _refresh_ui()

func _connected_to_server() -> void:
 _hello.rpc_id(1, PROTOCOL)

@rpc("any_peer", "call_remote", "reliable", 0)
func _hello(version: int) -> void:
 if not hosting: return
 var sender := multiplayer.get_remote_sender_id()
 if version != PROTOCOL or sender == 1 or players.has(sender) or players.size() >= 2: return
 _spawn_player(sender)
 peer_joins += 1
 status.text = "2인 접속 완료 · 호스트가 이동·탄약·피해를 계산합니다."
 _welcome.rpc_id(sender, PROTOCOL, snapshot())
 _refresh_ui()

@rpc("authority", "call_remote", "reliable", 0)
func _welcome(version: int, state: Dictionary) -> void:
 if hosting or version != PROTOCOL: return
 connected = true
 status.text = "접속 완료 · 내 캐릭터만 조작할 수 있습니다."
 _apply_state(state)
 _refresh_ui()

func _spawn_player(id: int) -> void:
 var actor: DemoPlayer = PLAYER.instantiate()
 actor.name = "Player_%d" % id
 actor.position = Vector2(230, 335 if id == 1 else 510)
 actor.movement_enabled = false
 actor.set_physics_process(false)
 $Actors.add_child(actor)
 actor.get_node("Sprite2D").self_modulate = Color.WHITE if id == 1 else Color("82dfdd")
 var label := Label.new()
 label.name = "PeerLabel"
 label.text = "P1 · 호스트" if id == 1 else "P2 · 동료"
 label.position = Vector2(-45, 42)
 label.add_theme_font_size_override("font_size", 15)
 actor.add_child(label)
 players[id] = {"actor": actor, "move": Vector2.ZERO, "aim": enemy.position, "fire": false, "seq": -1, "last_input": Time.get_ticks_msec(), "ammo": 20, "cooldown": 0.0, "shots": 0, "hits": 0}

func _peer_left(id: int) -> void:
 if not hosting or not players.has(id): return
 players[id].actor.queue_free()
 players.erase(id)
 peer_leaves += 1
 status.text = "동료 연결이 종료되었습니다. 새 동료가 다시 참가할 수 있습니다."
 _refresh_ui()

func _physics_process(delta: float) -> void:
 if not active: return
 if not connected:
  connect_age += delta
  if connect_age > 6.0: leave_game("접속 시간이 초과되었습니다. 호스트 IP와 UDP 포트를 확인하세요.")
  return
 send_clock += delta
 if send_clock >= 0.05 or (not test_override and _queued_fire):
  send_clock = 0
  var movement := test_move if test_override else Input.get_vector("move_left", "move_right", "move_up", "move_down")
  var aim := test_aim if test_override else get_global_mouse_position()
  if not test_override and _queued_fire: aim = _queued_aim
  var focus := get_viewport().gui_get_focus_owner()
  var firing := test_fire if test_override else (Input.is_physical_key_pressed(KEY_SPACE) or (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and ARENA.has_point(aim)))
  if not test_override: firing = firing or _queued_fire
  if not test_override and (focus is LineEdit or focus is SpinBox): movement = Vector2.ZERO; firing = false
  if not test_override and Input.is_physical_key_pressed(KEY_SPACE): aim = enemy.position
  sequence += 1
  if hosting: _accept_input(1, sequence, movement, aim, firing)
  else: _submit_input.rpc_id(1, sequence, movement, aim, firing)
  _queued_fire = false
  if hosting:
   tick += 1
   latest_state = snapshot()
   if players.size() > 1: _sync_state.rpc(latest_state)
   _refresh_ui()
 if not hosting: return
 for id in players:
  var state: Dictionary = players[id]
  var actor: DemoPlayer = state.actor
  if Time.get_ticks_msec() - int(state.last_input) > 350: state.move = Vector2.ZERO; state.fire = false
  actor.velocity = state.move * actor.move_speed
  actor.move_and_slide()
  actor.position = actor.position.clamp(ARENA.position + Vector2(24, 24), ARENA.end - Vector2(24, 30))
  actor.set_meta("visual_aim", state.aim)
  actor.get_node("Sprite2D").rotation = actor.position.angle_to_point(state.aim)
  state.cooldown = maxf(0, state.cooldown - delta)
  if state.fire: _shoot(id)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _submit_input(seq: int, movement: Vector2, aim: Vector2, firing: bool) -> void:
 if hosting: _accept_input(multiplayer.get_remote_sender_id(), seq, movement, aim, firing)

func _accept_input(id: int, seq: int, movement: Vector2, aim: Vector2, firing: bool) -> bool:
 if not players.has(id) or seq <= int(players[id].seq) or not movement.is_finite() or not aim.is_finite() or not Rect2(-10000, -10000, 20000, 20000).has_point(aim):
  rejected_inputs += 1
  return false
 players[id].seq = seq
 players[id].move = movement.limit_length(1)
 players[id].aim = aim
 players[id].fire = firing
 players[id].last_input = Time.get_ticks_msec()
 return true

func _shoot(id: int) -> void:
 var state: Dictionary = players[id]
 if state.cooldown > 0 or state.ammo <= 0: return
 var actor: DemoPlayer = state.actor
 var direction := actor.position.direction_to(state.aim)
 if direction.is_zero_approx(): return
 state.ammo -= 1
 state.shots += 1
 state.cooldown = 0.28
 var bullet: MissionProjectile = PROJECTILE.instantiate()
 bullet.position = actor.position
 bullet.direction = direction
 bullet.shooter = actor
 bullet.impacted.connect(func(collider):
  if collider == enemy and enemy.hp > 0:
   state.hits += 1
   enemy.take_damage(25))
 $Projectiles.add_child(bullet)
 _play_shot(actor.position, direction)
 if players.size() > 1: _shot_visual.rpc(actor.position, direction)

@rpc("authority", "call_remote", "reliable", 0)
func _shot_visual(origin: Vector2, direction: Vector2) -> void:
 _play_shot(origin, direction)
 var visual := Line2D.new()
 visual.width = 3
 visual.default_color = Color("91ece8")
 visual.points = PackedVector2Array([Vector2.ZERO, direction * 18])
 visual.position = origin
 $Projectiles.add_child(visual)
 var tween := visual.create_tween()
 tween.tween_property(visual, "position", origin + direction * 700 * 0.7, 0.7)
 tween.tween_callback(visual.queue_free)

func _play_shot(_origin: Vector2, _direction: Vector2) -> void:
 if DisplayServer.get_name() == "headless": return
 var sound := AudioStreamPlayer.new()
 sound.stream = _shot_sound
 sound.volume_db = -20
 add_child(sound)
 sound.finished.connect(sound.queue_free)
 sound.play()

func snapshot() -> Dictionary:
 var actors := {}
 for id in players:
  var state: Dictionary = players[id]
  actors[id] = {"position": state.actor.position, "aim": state.aim, "ammo": state.ammo, "shots": state.shots, "hits": state.hits}
 return {"tick": tick, "players": actors, "enemy_hp": enemy.hp, "enemy_max_hp": enemy.max_hp, "rejected_inputs": rejected_inputs}

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _sync_state(state: Dictionary) -> void:
 if connected and not hosting: _apply_state(state)

func _apply_state(state: Dictionary) -> void:
 if int(state.tick) < last_tick: return
 last_tick = int(state.tick)
 latest_state = state
 for id in state.players:
  if not players.has(id): _spawn_player(id)
  var actor: DemoPlayer = players[id].actor
  var data: Dictionary = state.players[id]
  actor.position = data.position
  actor.set_meta("visual_aim", data.aim)
  actor.get_node("Sprite2D").rotation = actor.position.angle_to_point(data.aim)
  players[id].ammo = data.ammo
  players[id].shots = data.shots
  players[id].hits = data.hits
 for id in players.keys():
  if not state.players.has(id): players[id].actor.queue_free(); players.erase(id)
 enemy.hp = int(state.enemy_hp)
 enemy.visible = enemy.hp > 0
 enemy.collision_layer = 0 # 클라이언트는 적중이나 피해를 계산하지 않는다.
 enemy.queue_redraw()
 _refresh_ui()

func reset_target() -> void:
 if not hosting: return
 enemy.reset_enemy()
 enemy.active = false
 for id in players:
  players[id].ammo = 20
  players[id].shots = 0
  players[id].hits = 0
 for bullet in $Projectiles.get_children(): bullet.queue_free()
 _refresh_ui()

func _refresh_ui() -> void:
 $HUD/Panel/Host.disabled = active
 $HUD/Panel/Join.disabled = active
 $HUD/Panel/Leave.disabled = not active
 $HUD/Panel/Reset.disabled = not hosting
 var lines := ["표적 체력  %d / %d" % [enemy.hp, enemy.max_hp] if is_instance_valid(enemy) else "표적 준비 중"]
 for id in players:
  var state: Dictionary = players[id]
  lines.append("%s%s  탄약 %d · 발사 %d · 적중 %d" % ["P1" if id == 1 else "P2", " (나)" if id == multiplayer.get_unique_id() else "", state.ammo, state.shots, state.hits])
 $HUD/Results.text = "\n".join(lines)
 queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
 if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
  leave_game("연결을 종료했습니다.")

func _unhandled_input(event: InputEvent) -> void:
 if not active or not connected or test_override: return
 if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
  var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
  if not ARENA.has_point(point): return
  _queued_aim = point
 elif event is InputEventKey and event.physical_keycode == KEY_SPACE and event.pressed and not event.echo:
  _queued_aim = enemy.position
 else: return
 # press/release가 같은 전송 간격 안에 들어와도 한 발의 입력은 보존한다.
 _queued_fire = true
 get_viewport().set_input_as_handled()

func _exit_tree() -> void:
 if multiplayer.multiplayer_peer: multiplayer.multiplayer_peer.close()

func _draw() -> void:
 draw_rect(ARENA, Color("18252e"))
 for x in range(40, 1240, 48): draw_line(Vector2(x, 180), Vector2(x, 660), Color("263a44"))
 for y in range(180, 660, 48): draw_line(Vector2(40, y), Vector2(1240, y), Color("263a44"))
 draw_rect(ARENA, Color("5a888d"), false, 3)
 draw_circle(Vector2(975, 365), 58, Color(0.7, 0.35, 0.22, 0.15))
