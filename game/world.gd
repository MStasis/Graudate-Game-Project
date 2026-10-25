@tool
class_name DemoWorld
extends Node2D
signal interacted(kind: String)
signal state_changed
signal notice(message: String)
signal game_event(event: Dictionary)
@export_group("맵 설명")
@export var location_name: String = "정전된 연구소"
@export_multiline var objective_text: String = "보관 구역에서 퓨즈를 찾아 연구실 전력을 복구하세요"
@export var room_rect := Rect2(32, 64, 1136, 430):
 set(value):
  room_rect = value
  if is_node_ready(): _sync_room()
@export_range(80.0, 300.0, 5.0) var sight_radius: float = 155.0
@export_group("게임 대상")
@export var player: DemoPlayer
@export var npc: DemoInteractable
@export var fuse: DemoInteractable
@export var generator: DemoInteractable
@export var exit_object: DemoInteractable
@export_group("공통 전투 조건")
@export var max_hp: int = 100
@export var initial_ammo: int = 6
@export var max_ammo: int = 20
@export var bullet_damage: int = 25
@export var npc_move_speed: float = 210.0
@export var heal_amount: int = 35
@export var resupply_amount: int = 10
@export var cover_duration: float = 12.0
@export var initial_medkits: int = 2
@export var initial_supply_packs: int = 2
@export var initial_cover_charges: int = 1
@export var cover_radius: float = 90.0
@export_range(0.0, 1.0, 0.05) var covered_damage_multiplier: float = 0.5
@export var safe_position := Vector2(600, 422)
var fuse_collected := false
var power_restored := false
var finished := false
var defeated := false
var map_id := "lab"
var player_hp := 100
var ammo := 6
var medkits := 2
var supply_packs := 2
var cover_charges := 1
var cache_used := false
var epoch := 0
var active_action := ""
var action_metadata := {}
var action_age := 0.0
var cover_time := 0.0
var guide_time := 0.0
var heal_cd := 0.0
var supply_cd := 0.0
var guide_cd := 0.0
var shoot_cd := 0.0
var recent_events: Array[String] = []
var _spawn_position := Vector2.ZERO
var _npc_spawn := Vector2.ZERO
var _enemy_spawns := {}
var _can_move := true
var can_move: bool:
 get: return _can_move
 set(value):
  _can_move = value
  if player: player.movement_enabled = value and not finished and not defeated

func _ready() -> void:
 _sync_room()
 if Engine.is_editor_hint(): return
 _spawn_position = player.position
 _npc_spawn = npc.position
 for enemy in get_node("Enemies").get_children():
  _enemy_spawns[enemy.name] = enemy.position
  enemy.target = player
  enemy.hit_player.connect(take_damage)
  enemy.defeated.connect(_enemy_defeated)
 reset_world()

func _sync_room() -> void:
 var floor_panel := get_node_or_null("Floor") as Control
 if floor_panel:
  floor_panel.position = room_rect.position
  floor_panel.size = room_rect.size
 for entry in [
  ["North", Vector2(room_rect.get_center().x, room_rect.position.y), Vector2(room_rect.size.x, 6)],
  ["South", Vector2(room_rect.get_center().x, room_rect.end.y), Vector2(room_rect.size.x, 6)],
  ["West", Vector2(room_rect.position.x, room_rect.get_center().y), Vector2(6, room_rect.size.y)],
  ["East", Vector2(room_rect.end.x, room_rect.get_center().y), Vector2(6, room_rect.size.y)]]:
  var shape := get_node_or_null("Walls/" + entry[0]) as CollisionShape2D
  if shape:
   shape.position = entry[1]
   (shape.shape as RectangleShape2D).size = entry[2]

func reset_world() -> void:
 epoch += 1
 map_id = "lab"
 fuse_collected = false
 power_restored = false
 finished = false
 defeated = false
 player_hp = max_hp
 ammo = initial_ammo
 medkits = initial_medkits
 supply_packs = initial_supply_packs
 cover_charges = initial_cover_charges
 cache_used = false
 active_action = ""
 action_metadata = {}
 cover_time = 0.0
 guide_time = 0.0
 heal_cd = 0.0
 supply_cd = 0.0
 guide_cd = 0.0
 shoot_cd = 0.0
 recent_events.clear()
 player.position = _spawn_position
 npc.position = _npc_spawn
 player.velocity = Vector2.ZERO
 _can_move = true
 for enemy in get_node("Enemies").get_children():
  enemy.position = _enemy_spawns[enemy.name]
  enemy.reset_enemy()
 for bullet in get_node("Projectiles").get_children(): bullet.queue_free()
 _sync_state()
 _event("trial_reset", {})
 state_changed.emit()

func enemies_remaining() -> int:
 var count := 0
 for enemy in get_node("Enemies").get_children():
  if enemy.hp > 0: count += 1
 return count

func _sync_state() -> void:
 if not is_node_ready(): return
 var dark := map_id == "storage"
 get_node("LabDecor").visible = not dark
 get_node("StorageDecor").visible = dark
 get_node("ToStorage").visible = not dark
 get_node("ToLab").visible = dark
 get_node("SupplyCache").visible = dark and not cache_used
 fuse.visible = dark and not fuse_collected
 generator.visible = not dark
 exit_object.visible = not dark
 generator.set_active(power_restored)
 exit_object.set_active(power_restored)
 player.movement_enabled = _can_move and not finished and not defeated
 get_node("Darkness").visible = dark
 get_node("RoomTitle").text = "어두운 보관 구역" if dark else location_name
 get_node("GoalText").text = current_guidance()
 var ending := get_node("Ending") as Label
 ending.visible = finished or defeated
 ending.text = "전력 복구 · 임무 완료" if finished else "전투 불능 · 다시 시작으로 재도전"
 for enemy in get_node("Enemies").get_children():
  enemy.visible = dark and enemy.hp > 0
  enemy.active = dark and enemy.hp > 0 and not defeated and not finished
  enemy.collision_layer = 2 if enemy.visible else 0
 queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
 if Engine.is_editor_hint() or not can_move or finished or defeated: return
 if event.is_action_pressed("attack") and not event.is_echo():
  shoot(get_local_mouse_position() if event is InputEventMouseButton else nearest_enemy_position())
  get_viewport().set_input_as_handled()
 if not event.is_action_pressed("interact") or event.is_echo(): return
 var closest: DemoInteractable
 var distance := player.interaction_distance
 for target in [npc, fuse, generator, exit_object, get_node("ToStorage"), get_node("ToLab"), get_node("SupplyCache")]:
  if not target.visible: continue
  var next_distance: float = player.position.distance_to(target.position)
  if next_distance <= distance:
   closest = target
   distance = next_distance
 if closest:
  interacted.emit(closest.interaction_id)
  get_viewport().set_input_as_handled()

func apply_interaction(kind: String) -> String:
 if finished or defeated: return "다시 시작해서 새 회차를 진행하세요."
 var message := ""
 match kind:
  "storage_gate":
   if map_id != "lab": return "연구실에서 이용할 수 있습니다."
   _change_map("storage", get_node("StorageEntry").position)
   message = "보관 구역 진입. 드론을 제압하고 퓨즈를 찾으세요."
  "lab_gate":
   if map_id != "storage": return "보관 구역에서 이용할 수 있습니다."
   _change_map("lab", get_node("LabReturn").position)
   message = "연구실로 돌아왔습니다."
  "fuse":
   if map_id != "storage": return "퓨즈는 보관 구역에 있습니다."
   if enemies_remaining() > 0: return "주변 드론을 먼저 제압해야 합니다."
   if fuse_collected: return "이미 퓨즈를 챙겼습니다."
   fuse_collected = true
   epoch += 1
   message = "퓨즈 획득. 연구실로 돌아가 전력 장치에 장착하세요."
   _remember("전투를 마치고 퓨즈를 찾았다")
  "cache":
   if map_id != "storage" or cache_used: return "지금은 비상 탄약함을 이용할 수 없습니다."
   if ammo >= max_ammo: return "탄약이 충분합니다."
   cache_used = true
   ammo = mini(max_ammo, ammo + 10)
   message = "비상 탄약 10발을 챙겼습니다."
  "generator":
   if map_id != "lab": return "전력 장치는 연구실에 있습니다."
   if power_restored: return "이미 전력을 복구했습니다."
   if not fuse_collected: return "보관 구역에서 퓨즈를 가져와야 합니다."
   power_restored = true
   epoch += 1
   _remember("연구실로 돌아와 함께 전력을 복구했다")
   message = "전력 복구 완료. 출구를 이용하세요."
  "exit":
   if map_id != "lab" or not power_restored: return "연구실 전력을 먼저 복구해야 합니다."
   finished = true
   epoch += 1
   message = "하린과 함께 임무를 마쳤습니다."
 _sync_state()
 _event("interaction", {"kind": kind, "message": message})
 state_changed.emit()
 return message

func _change_map(destination: String, spawn: Vector2) -> void:
 epoch += 1
 map_id = destination
 player.position = spawn
 npc.position = spawn + Vector2(55, -30)
 active_action = ""
 cover_time = 0.0
 guide_time = 0.0
 for bullet in get_node("Projectiles").get_children(): bullet.queue_free()
 _sync_state()

func _physics_process(delta: float) -> void:
 if Engine.is_editor_hint(): return
 shoot_cd = maxf(0.0, shoot_cd - delta)
 heal_cd = maxf(0.0, heal_cd - delta)
 supply_cd = maxf(0.0, supply_cd - delta)
 guide_cd = maxf(0.0, guide_cd - delta)
 cover_time = maxf(0.0, cover_time - delta)
 guide_time = maxf(0.0, guide_time - delta)
 if finished or defeated: return
 var target := player.position + Vector2(-65, -12)
 if active_action == "deploy_cover": target = safe_position
 if active_action in ["heal", "resupply"]: target = player.position
 var distance := npc.position.distance_to(target)
 if distance > (42.0 if not active_action.is_empty() else 25.0):
  npc.position = npc.position.move_toward(target, npc_move_speed * delta)
 npc.position = npc.position.clamp(room_rect.position + Vector2(28, 28), room_rect.end - Vector2(28, 28))
 if not active_action.is_empty():
  action_age += delta
  if action_age > 5.0:
   _event("support_rejected", {"action": active_action, "reason": "approach_timeout", "request": action_metadata})
   active_action = ""
  elif npc.position.distance_to(target) <= 50.0: _finish_support()
 var darkness := get_node("Darkness") as ColorRect
 (darkness.material as ShaderMaterial).set_shader_parameter("player_position", player.position)
 (darkness.material as ShaderMaterial).set_shader_parameter("sight_radius", sight_radius)
 queue_redraw()

func nearest_enemy_position() -> Vector2:
 var nearest := Vector2.INF
 var best := INF
 for enemy in get_node("Enemies").get_children():
  if enemy.hp > 0 and enemy.visible:
   var distance: float = player.position.distance_to(enemy.position)
   if distance < best and distance <= sight_radius:
    best = distance
    nearest = enemy.position
 return nearest

func shoot(target: Vector2) -> bool:
 if not target.is_finite(): return false
 if map_id != "storage" or finished or defeated or shoot_cd > 0.0 or ammo <= 0: return false
 var direction := player.position.direction_to(target)
 if direction.is_zero_approx(): return false
 shoot_cd = 0.28
 ammo -= 1
 var bullet := (load("res://scenes/Projectile.tscn") as PackedScene).instantiate() as MissionProjectile
 bullet.direction = direction
 bullet.shooter = player
 bullet.position = player.position
 bullet.impacted.connect(func(collider):
  if collider is MissionDrone: collider.take_damage(bullet_damage))
 get_node("Projectiles").add_child(bullet)
 state_changed.emit()
 return true

func take_damage(amount: int) -> void:
 if map_id != "storage" or defeated or finished: return
 var protected := inside_cover()
 var actual := maxi(1, ceili(amount * (covered_damage_multiplier if protected else 1.0)))
 player_hp = maxi(0, player_hp - actual)
 if player_hp == 0:
  defeated = true
  epoch += 1
  active_action = ""
 _event("player_damage", {"damage": actual, "protected": protected, "hp": player_hp})
 _sync_state()
 state_changed.emit()

func inside_cover() -> bool:
 return cover_time > 0.0 and map_id == "storage" and player.position.distance_to(safe_position) <= cover_radius

func valid_actions() -> Array:
 var result := ["follow", "wait"]
 if defeated or finished or not active_action.is_empty(): return result
 if player_hp < max_hp and medkits > 0 and heal_cd <= 0: result.append("heal")
 if ammo < max_ammo and supply_packs > 0 and supply_cd <= 0: result.append("resupply")
 if map_id == "storage" and enemies_remaining() > 0:
  if cover_charges > 0 and cover_time <= 0: result.append("deploy_cover")
  if cover_time > 0 and not inside_cover() and guide_cd <= 0: result.append("guide_to_cover")
 return result

func request_support(action: String, metadata: Dictionary = {}) -> bool:
 if action not in valid_actions() or defeated or finished: return false
 if action in ["follow", "wait"]: return true
 if action == "guide_to_cover":
  guide_time = 4.0
  guide_cd = 4.0
  var offset := safe_position - player.position
  var direction := ("오른쪽" if offset.x > 0 else "왼쪽") if absf(offset.x) > absf(offset.y) else ("아래쪽" if offset.y > 0 else "위쪽")
  var text := direction + "으로 와! 보호 장비 안으로 들어와!"
  notice.emit("하린: " + text)
  _event("support_completed", {"action": action, "callout": text, "target": [safe_position.x, safe_position.y], "request": metadata})
  return true
 active_action = action
 action_metadata = metadata.duplicate(true)
 action_age = 0.0
 _event("support_started", {"action": action, "request": action_metadata})
 return true

func _finish_support() -> void:
 var action := active_action
 active_action = ""
 if action not in valid_actions():
  _event("support_rejected", {"action": action, "reason": "no_longer_valid", "request": action_metadata})
  return
 var effect := 0
 var text := ""
 match action:
  "heal":
   effect = mini(heal_amount, max_hp - player_hp)
   player_hp += effect
   medkits -= 1
   heal_cd = 8.0
   text = "내가 치료할게. 체력 %d 회복!" % effect
  "resupply":
   effect = mini(resupply_amount, max_ammo - ammo)
   ammo += effect
   supply_packs -= 1
   supply_cd = 8.0
   text = "탄약 여기 있어. %d발 챙겨!" % effect
  "deploy_cover":
   cover_charges -= 1
   cover_time = cover_duration
   text = "보호 장비 설치했어. 표시된 원 안으로 와!"
 notice.emit("하린: " + text)
 _remember(text)
 _event("support_completed", {"action": action, "effect": effect, "request": action_metadata})
 state_changed.emit()

func _enemy_defeated() -> void:
 if enemies_remaining() == 0:
  notice.emit("하린: 드론은 정리됐어. 이제 퓨즈를 챙기자.")
  _remember("함께 보관 구역의 드론을 제압했다")
 _event("enemy_defeated", {"remaining": enemies_remaining()})
 _sync_state()
 state_changed.emit()

func current_guidance() -> String:
 if defeated: return "전투 불능입니다. 새 회차로 다시 시작하세요."
 if finished: return "임무를 완료했습니다."
 if power_restored: return "연구실 출구를 이용하세요."
 if fuse_collected: return "연구실로 돌아가 전력 장치에 퓨즈를 장착하세요." if map_id == "storage" else "전력 장치에 퓨즈를 장착하세요."
 if map_id == "lab": return "오른쪽 통로로 보관 구역에 가서 퓨즈를 찾으세요."
 if enemies_remaining() > 0: return "드론 %d기를 제압한 뒤 북동쪽 보관함의 퓨즈를 챙기세요." % enemies_remaining()
 return "북동쪽 보관함에서 퓨즈를 챙기고 왼쪽 통로로 연구실에 돌아가세요."

func game_state() -> Dictionary:
 return {"epoch": epoch, "map_id": map_id, "objective": objective_text, "location": "어두운 보관 구역" if map_id == "storage" else location_name,
 "fuse_collected": fuse_collected, "fuse_in_inventory": fuse_collected and not power_restored, "power_restored": power_restored, "escaped": finished, "defeated": defeated,
 "player_hp": player_hp, "max_hp": max_hp, "ammo": ammo, "max_ammo": max_ammo, "enemy_count": enemies_remaining() if map_id == "storage" else 0,
 "medkits": medkits, "supply_packs": supply_packs, "cover_charges": cover_charges, "cover_active": cover_time > 0.0, "inside_cover": inside_cover(),
 "active_action": active_action, "current_guidance": current_guidance(), "relationship": "서로 믿는 친한 동료",
 "player_position": [player.position.x, player.position.y], "npc_position": [npc.position.x, npc.position.y], "cover_position": [safe_position.x, safe_position.y],
 "recent_shared_events": recent_events.duplicate(), "valid_actions": valid_actions(),
 "scenario_config": scenario_configuration()}

func scenario_configuration() -> Dictionary:
 var enemies := []
 for enemy in get_node("Enemies").get_children():
  enemies.append({"name": enemy.name, "spawn": _enemy_spawns.get(enemy.name), "hp": enemy.max_hp, "speed": enemy.move_speed, "damage": enemy.contact_damage, "attack_interval": enemy.attack_interval})
 return {"max_hp": max_hp, "initial_ammo": initial_ammo, "max_ammo": max_ammo, "bullet_damage": bullet_damage, "heal_amount": heal_amount, "resupply_amount": resupply_amount, "cover_duration": cover_duration, "cover_radius": cover_radius, "damage_multiplier": covered_damage_multiplier, "medkits": initial_medkits, "supply_packs": initial_supply_packs, "cover_charges": initial_cover_charges, "player_speed": player.move_speed, "sight_radius": sight_radius, "room_rect": str(room_rect), "safe_position": [safe_position.x, safe_position.y], "enemies": enemies}

func npc_context() -> Dictionary:
 return {"npc_name": npc.display_name, "npc_role": npc.description, "relationship": "친한 동료", "location": game_state().location, "current_guidance": current_guidance()}

func _remember(text: String) -> void:
 recent_events.append(text)
 if recent_events.size() > 6: recent_events.pop_front()

func _event(kind: String, details: Dictionary) -> void:
 var event := details.duplicate(true)
 event["event"] = kind
 event["epoch"] = epoch
 event["map_id"] = map_id
 event["time_msec"] = Time.get_ticks_msec()
 game_event.emit(event)

func _draw() -> void:
 if Engine.is_editor_hint(): return
 if cover_time > 0.0 and map_id == "storage":
  draw_circle(safe_position, 90, Color(0.15, 0.8, 0.8, 0.16))
  draw_arc(safe_position, 90, 0, TAU, 48, Color("6fffe3"), 3)
  draw_rect(Rect2(safe_position - Vector2(12, 12), Vector2(24, 24)), Color("6fbfb7"))
 if guide_time > 0.0 and map_id == "storage":
  draw_line(player.position, safe_position, Color("ffdc8b"), 3)
