@tool
class_name DemoWorld
extends Node2D
signal interacted(kind: String)
signal state_changed
signal notice(message: String)
signal companion_spoke(message: String)
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
@export_enum("원거리 엄호", "측면 지원", "근접 선행") var npc_role := 0
@export_group("손전등")
@export var flashlight_range := 390.0
@export_range(15.0, 60.0, 1.0) var flashlight_half_angle := 32.0
@export_group("동료 공통 전투 규칙")
@export var npc_max_hp: int = 100
@export var npc_initial_ammo: int = 20
@export var npc_bullet_damage: int = 25
@export var npc_fire_interval: float = 1.0
@export var npc_fire_range: float = 260.0
@export var npc_combat_enabled := true
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
var npc_hp := 100
var npc_ammo := 20
var npc_shoot_cd := 0.0
var recent_events: Array[String] = []
var _spawn_position := Vector2.ZERO
var _npc_spawn := Vector2.ZERO
var _enemy_spawns := {}
var _can_move := true
var flashlight_owned := false
var flashlight_dropped := false
var flashlight_requested := false
var _aim_screen_position := Vector2.ZERO
var _aim_pointer_seen := false
var _last_flashlight_direction := Vector2.RIGHT
var npc_motion := CompanionMotion.new()
@onready var locker: CooperativeLocker = $Locker
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
 locker.bind(self)
 for enemy in get_node("Enemies").get_children():
  _enemy_spawns[enemy.name] = enemy.position
  enemy.target = player
  enemy.companion = npc
  enemy.hit_player.connect(take_damage)
  enemy.hit_companion.connect(take_npc_damage)
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
 npc_hp = npc_max_hp
 npc_ammo = npc_initial_ammo
 npc_shoot_cd = npc_fire_interval
 flashlight_owned = false
 flashlight_dropped = false
 flashlight_requested = false
 $FlashlightPickup.position = _npc_spawn + Vector2(24, 24)
 player.facing_direction = Vector2.RIGHT
 npc_motion.reset()
 locker.reset()
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
 locker.visible = dark
 locker.update_visuals()
 fuse.visible = dark and locker.opened and not fuse_collected
 $LockerSupply.visible = dark and locker.opened and not locker.supply_taken
 $FlashlightPickup.visible = not dark and flashlight_dropped and not flashlight_owned
 generator.visible = not dark
 exit_object.visible = not dark
 generator.set_active(power_restored)
 exit_object.set_active(power_restored)
 player.movement_enabled = _can_move and not finished and not defeated
 npc.modulate = Color("888888") if npc_hp <= 0 else Color.WHITE
 get_node("Darkness").visible = dark and not power_restored
 get_node("RoomTitle").text = ("전력이 복구된 보관 구역" if power_restored else "어두운 보관 구역") if dark else location_name
 get_node("GoalText").text = current_guidance()
 var ending := get_node("Ending") as Label
 ending.visible = finished or defeated
 ending.text = "전력 복구 · 임무 완료" if finished else "전투 불능 · 다시 시작으로 재도전"
 for enemy in get_node("Enemies").get_children():
  enemy.visible = dark and enemy.hp > 0
  enemy.active = dark and enemy.hp > 0 and not defeated and not finished
  enemy.collision_layer = 2 if enemy.visible else 0
 queue_redraw()

func _input(event: InputEvent) -> void:
 if Engine.is_editor_hint(): return
 if event is InputEventMouseMotion or event is InputEventMouseButton:
  _aim_screen_position = event.position
  _aim_pointer_seen = true

func mouse_aim_position() -> Vector2:
 var screen_point := _aim_screen_position if _aim_pointer_seen else get_viewport().get_mouse_position()
 return get_global_transform_with_canvas().affine_inverse() * screen_point

func flashlight_direction() -> Vector2:
 var offset := mouse_aim_position() - player.position
 if offset.length_squared() > 1.0: _last_flashlight_direction = offset.normalized()
 return _last_flashlight_direction

func _unhandled_input(event: InputEvent) -> void:
 if Engine.is_editor_hint() or not can_move or finished or defeated: return
 if event.is_action_pressed("attack") and not event.is_echo():
  var target_point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position if event is InputEventMouseButton else nearest_enemy_position()
  shoot(target_point)
  get_viewport().set_input_as_handled()
 if not event.is_action_pressed("interact") or event.is_echo(): return
 var closest: DemoInteractable
 var distance := player.interaction_distance
 var targets := [npc, fuse, generator, exit_object, get_node("ToStorage"), get_node("ToLab"), get_node("SupplyCache"), $FlashlightPickup, $LockerSupply]
 if map_id == "storage": targets.append_array(locker.panels())
 for target in targets:
  if not target.is_visible_in_tree(): continue
  var next_distance: float = player.position.distance_to(to_local(target.global_position))
  if next_distance <= player.interaction_distance and (next_distance <= distance or target.interaction_id in ["flashlight", "fuse", "locker_supply"]):
   closest = target
   distance = next_distance
   if target.interaction_id in ["flashlight", "fuse", "locker_supply"]: break
 if closest:
  interacted.emit(closest.interaction_id)
  get_viewport().set_input_as_handled()

func apply_interaction(kind: String) -> String:
 if finished or defeated: return "다시 시작해서 새 회차를 진행하세요."
 var message := ""
 match kind:
  "storage_gate":
   if map_id != "lab": return "연구실에서 이용할 수 있습니다."
   if not flashlight_owned:
    request_flashlight()
    return "하린이 건네는 손전등을 E로 주운 뒤 보관 구역에 들어가세요."
   _change_map("storage", get_node("StorageEntry").position)
   message = "보관 구역 진입. 드론을 제압하고 퓨즈를 찾으세요."
  "lab_gate":
   if map_id != "storage": return "보관 구역에서 이용할 수 있습니다."
   _change_map("lab", get_node("LabReturn").position)
   message = "연구실로 돌아왔습니다."
  "fuse":
   if map_id != "storage": return "퓨즈는 보관 구역에 있습니다."
   if enemies_remaining() > 0: return "주변 드론을 먼저 제압해야 합니다."
   if not locker.opened: return "두 패널을 함께 작동해 보관함을 먼저 여세요."
   if fuse_collected: return "이미 퓨즈를 챙겼습니다."
   fuse_collected = true
   epoch += 1
   message = "퓨즈 획득. 연구실로 돌아가 전력 장치에 장착하세요."
   _remember("전투를 마치고 퓨즈를 찾았다")
  "flashlight":
   if map_id != "lab" or not flashlight_dropped or flashlight_owned: return "지금은 주울 손전등이 없습니다."
   flashlight_owned = true
   flashlight_dropped = false
   flashlight_requested = false
   epoch += 1
   message = "손전등 획득. 마우스 조준 방향으로 먼 곳을 비춥니다. 이제 보관 구역에 들어갈 수 있습니다."
   _event("flashlight_collected", {})
  "panel_a", "panel_b":
   if map_id != "storage": return "패널은 보관 구역에 있습니다."
   message = locker.begin(0 if kind == "panel_a" else 1)
  "locker_supply":
   if map_id != "storage" or not locker.opened or locker.supply_taken: return "아직 회수할 보급이 없습니다."
   if ammo >= max_ammo: return "탄약이 충분합니다. 보급은 남겨두세요."
   ammo = mini(max_ammo, ammo + 10)
   locker.supply_taken = true
   message = "보관함에서 탄약 10발을 회수했습니다."
   _event("locker_supply_collected", {})
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
   _event("power_restored", {"storage_lights_on": true})
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
 locker.cancel("map_changed")
 epoch += 1
 map_id = destination
 player.position = spawn
 npc.position = spawn + Vector2(55, -30)
 npc_motion.reset(player.facing_direction)
 active_action = ""
 cover_time = 0.0
 guide_time = 0.0
 for bullet in get_node("Projectiles").get_children(): bullet.queue_free()
 _sync_state()

func _physics_process(delta: float) -> void:
 if Engine.is_editor_hint(): return
 update_visibility()
 shoot_cd = maxf(0.0, shoot_cd - delta)
 npc_shoot_cd = maxf(0.0, npc_shoot_cd - delta)
 heal_cd = maxf(0.0, heal_cd - delta)
 supply_cd = maxf(0.0, supply_cd - delta)
 guide_cd = maxf(0.0, guide_cd - delta)
 cover_time = maxf(0.0, cover_time - delta)
 guide_time = maxf(0.0, guide_time - delta)
 if finished or defeated: return
 if map_id == "lab" and not flashlight_owned and not flashlight_dropped and player.position.distance_to($ToStorage.position) < 150:
  request_flashlight()
 for enemy in get_node("Enemies").get_children():
  enemy.companion_alive = npc_combat_enabled and npc_hp > 0
 if npc_combat_enabled and npc_hp > 0: _npc_fire()
 if npc_hp <= 0:
  npc_motion.velocity = Vector2.ZERO
  locker.tick(delta, false)
  queue_redraw()
  return
 var target := npc_motion.formation_target(self, delta)
 var scripted := not active_action.is_empty() or flashlight_requested
 var arrival := 8.0
 if active_action == "deploy_cover": target = safe_position
 if active_action in ["heal", "resupply"]:
  target = player.position
  arrival = 38
 if active_action == "assist_panel": target = locker.partner_position()
 if flashlight_requested:
  target = player.position
  arrival = 50
 npc_motion.move_to(self, target, delta, arrival, scripted)
 if flashlight_requested and npc.position.distance_to(player.position) <= 90: _drop_flashlight()
 if not active_action.is_empty():
  action_age += delta
  if active_action == "assist_panel":
   if not locker.needs_assistance() and locker.sequence_elapsed < 0: active_action = ""
  elif action_age > 5.0:
   _event("support_rejected", {"action": active_action, "reason": "approach_timeout", "request": action_metadata})
   active_action = ""
  elif npc.position.distance_to(target) <= 50.0: _finish_support()
 locker.tick(delta, Input.is_action_pressed("interact"))
 queue_redraw()

func update_visibility() -> void:
 var darkness := get_node("Darkness") as ColorRect
 (darkness.material as ShaderMaterial).set_shader_parameter("player_position", player.position)
 (darkness.material as ShaderMaterial).set_shader_parameter("sight_radius", sight_radius)
 (darkness.material as ShaderMaterial).set_shader_parameter("flashlight_enabled", flashlight_owned)
 (darkness.material as ShaderMaterial).set_shader_parameter("flashlight_direction", flashlight_direction())
 (darkness.material as ShaderMaterial).set_shader_parameter("flashlight_range", flashlight_range)
 (darkness.material as ShaderMaterial).set_shader_parameter("cone_half_angle", deg_to_rad(flashlight_half_angle))

func request_flashlight() -> void:
 if flashlight_owned or flashlight_dropped or npc_hp <= 0: return
 if not flashlight_requested:
  flashlight_requested = true
  companion_spoke.emit("앞이 꽤 어둡네. 잠깐, 손전등 줄게.")
  _event("flashlight_requested", {})
 if npc.position.distance_to(player.position) <= 90: _drop_flashlight()

func _drop_flashlight() -> void:
 flashlight_requested = false
 flashlight_dropped = true
 $FlashlightPickup.position = (npc.position + npc.position.direction_to(player.position) * 30).clamp(room_rect.position + Vector2(28, 28), room_rect.end - Vector2(28, 28))
 npc_motion.velocity = Vector2.ZERO
 _event("flashlight_dropped", {"position": [$FlashlightPickup.position.x, $FlashlightPickup.position.y]})
 companion_spoke.emit("여기 놨어. 챙겨 가.")
 notice.emit("손전등 · 가까이에서 E로 줍기")
 _sync_state()
 state_changed.emit()

func visibility_at(point: Vector2) -> float:
 if map_id != "storage" or power_restored: return 1.0
 var offset := point - player.position
 var distance := offset.length()
 var local_light := 1.0 - smoothstep(sight_radius * 0.7, sight_radius, distance)
 if not flashlight_owned or distance < 0.01: return local_light
 var angle := deg_to_rad(flashlight_half_angle)
 var angular := smoothstep(cos(angle), cos(angle * 0.75), offset.normalized().dot(flashlight_direction()))
 var beam := angular * (1.0 - smoothstep(sight_radius * 0.5, flashlight_range, distance))
 return maxf(local_light, beam)

func nearest_enemy_position() -> Vector2:
 var nearest := Vector2.INF
 var best := INF
 for enemy in get_node("Enemies").get_children():
  if enemy.hp > 0 and enemy.visible:
   var distance: float = player.position.distance_to(enemy.position)
   if distance < best and visibility_at(enemy.position) > 0.12:
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
 if npc_hp <= 0: return ["wait"]
 if defeated or finished or not active_action.is_empty(): return result
 if map_id == "storage" and locker.needs_assistance(): result.append("assist_panel")
 if player_hp < max_hp and medkits > 0 and heal_cd <= 0: result.append("heal")
 if ammo < max_ammo and supply_packs > 0 and supply_cd <= 0: result.append("resupply")
 if map_id == "storage" and enemies_remaining() > 0:
  if cover_charges > 0 and cover_time <= 0: result.append("deploy_cover")
  if cover_time > 0 and not inside_cover() and guide_cd <= 0: result.append("guide_to_cover")
 return result

func request_support(action: String, metadata: Dictionary = {}) -> bool:
 if action not in valid_actions() or defeated or finished or npc_hp <= 0: return false
 if action in ["follow", "wait"]: return true
 if action == "assist_panel":
  active_action = action
  action_metadata = metadata.duplicate(true)
  action_age = 0
  npc_motion.pattern = "반대 패널 지원"
  companion_spoke.emit("내가 반대편 누를게!")
  _event("support_started", {"action": action, "request": action_metadata})
  return true
 if action == "guide_to_cover":
  guide_time = 4.0
  guide_cd = 4.0
  var offset := safe_position - player.position
  var direction := ("오른쪽" if offset.x > 0 else "왼쪽") if absf(offset.x) > absf(offset.y) else ("아래쪽" if offset.y > 0 else "위쪽")
  var text := direction + "이야! 이리로 와!"
  notice.emit("보호 장비 · " + direction + " 원 안으로 이동")
  companion_spoke.emit(text)
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
   text = "됐어. 이제 좀 괜찮아?"
   notice.emit("치료 완료 · 체력 +%d" % effect)
  "resupply":
   effect = mini(resupply_amount, max_ammo - ammo)
   ammo += effect
   supply_packs -= 1
   supply_cd = 8.0
   text = "탄약 여기 있어. 챙겨!"
   notice.emit("보급 완료 · 탄약 +%d" % effect)
  "deploy_cover":
   cover_charges -= 1
   cover_time = cover_duration
   text = "이쪽이야. 내 옆으로 와!"
   notice.emit("보호 장비 설치 · 원 안에서 피해 50% 감소")
 companion_spoke.emit(text)
 _remember(text)
 _event("support_completed", {"action": action, "effect": effect, "request": action_metadata})
 state_changed.emit()

func _enemy_defeated() -> void:
 if enemies_remaining() == 0:
  companion_spoke.emit("다 정리됐네. 같이 열어 보자.")
  _remember("함께 보관 구역의 드론을 제압했다")
 _event("enemy_defeated", {"remaining": enemies_remaining()})
 _sync_state()
 state_changed.emit()

func current_guidance() -> String:
 if defeated: return "전투 불능입니다. 새 회차로 다시 시작하세요."
 if finished: return "임무를 완료했습니다."
 if power_restored: return "연구실 출구를 이용하세요."
 if fuse_collected: return "연구실로 돌아가 전력 장치에 퓨즈를 장착하세요." if map_id == "storage" else "전력 장치에 퓨즈를 장착하세요."
 if map_id == "lab":
  if flashlight_dropped: return "바닥의 손전등을 E로 주운 뒤 오른쪽 보관 구역으로 가세요."
  return "오른쪽 통로에서 하린에게 손전등을 받으세요." if not flashlight_owned else "오른쪽 통로로 보관 구역에 가서 퓨즈를 찾으세요."
 if enemies_remaining() > 0: return "드론 %d기를 제압한 뒤 북동쪽 2인 패널 보관함에서 퓨즈를 찾으세요." % enemies_remaining()
 if npc_hp <= 0 and not locker.opened: return "하린 전투 불능 · 2인 패널 이용 불가. 이전 저장을 불러오거나 새 회차를 시작하세요."
 if not locker.opened:
  if locker.sequence_elapsed >= 0: return "비프음 확인 중 · 보관함 잠금이 해제됩니다."
  if locker.player_panel >= 0: return "E 유지 · 하린과 양쪽 패널을 %.1f / %.1f초 함께 작동" % [locker.progress, locker.hold_seconds]
  return "보관함 양쪽 패널 중 하나에서 E 유지 · 하린에게 반대 패널 지원 요청"
 return "열린 보관함의 퓨즈·보급을 챙기고 왼쪽 통로로 연구실에 돌아가세요."

func game_state() -> Dictionary:
 return {"epoch": epoch, "map_id": map_id, "objective": objective_text, "location": ("전력이 복구된 보관 구역" if power_restored else "어두운 보관 구역") if map_id == "storage" else location_name,
 "fuse_collected": fuse_collected, "fuse_in_inventory": fuse_collected and not power_restored, "power_restored": power_restored, "escaped": finished, "defeated": defeated,
 "player_hp": player_hp, "max_hp": max_hp, "ammo": ammo, "max_ammo": max_ammo, "enemy_count": enemies_remaining() if map_id == "storage" else 0,
 "npc_hp": npc_hp, "npc_max_hp": npc_max_hp, "npc_ammo": npc_ammo, "npc_max_ammo": npc_initial_ammo, "npc_downed": npc_hp <= 0,
 "medkits": medkits, "supply_packs": supply_packs, "cover_charges": cover_charges, "cover_active": cover_time > 0.0, "inside_cover": inside_cover(),
 "active_action": active_action, "current_guidance": current_guidance(), "relationship": "서로 믿는 친한 동료",
 "player_position": [player.position.x, player.position.y], "npc_position": [npc.position.x, npc.position.y], "cover_position": [safe_position.x, safe_position.y],
 "recent_shared_events": recent_events.duplicate(), "valid_actions": valid_actions(),
  "flashlight_owned": flashlight_owned, "flashlight_dropped": flashlight_dropped, "flashlight_requested": flashlight_requested, "storage_lit": power_restored, "locker": locker.context(), "npc_movement_pattern": npc_motion.pattern,
 "scenario_config": scenario_configuration()}

func scenario_configuration() -> Dictionary:
 var enemies := []
 for enemy in get_node("Enemies").get_children():
  enemies.append({"name": enemy.name, "spawn": _enemy_spawns.get(enemy.name), "hp": enemy.max_hp, "speed": enemy.move_speed, "damage": enemy.contact_damage, "attack_interval": enemy.attack_interval})
 var configuration := {"max_hp": max_hp, "initial_ammo": initial_ammo, "max_ammo": max_ammo, "bullet_damage": bullet_damage, "npc_max_hp": npc_max_hp, "npc_initial_ammo": npc_initial_ammo, "npc_bullet_damage": npc_bullet_damage, "npc_fire_interval": npc_fire_interval, "npc_combat_enabled": npc_combat_enabled, "heal_amount": heal_amount, "resupply_amount": resupply_amount, "cover_duration": cover_duration, "cover_radius": cover_radius, "damage_multiplier": covered_damage_multiplier, "medkits": initial_medkits, "supply_packs": initial_supply_packs, "cover_charges": initial_cover_charges, "player_speed": player.move_speed, "sight_radius": sight_radius, "room_rect": str(room_rect), "safe_position": [safe_position.x, safe_position.y], "enemies": enemies}

 configuration["mechanics"] = {"version": 2, "npc_role": npc_role, "npc_fire_range": npc_fire_range, "panel_hold_seconds": locker.hold_seconds, "flashlight_range": flashlight_range, "flashlight_half_angle": flashlight_half_angle}
 return configuration

func _npc_fire() -> void:
 if not npc_combat_enabled or npc_hp <= 0 or defeated or finished or map_id != "storage" or npc_ammo <= 0 or npc_shoot_cd > 0.0 or not active_action.is_empty(): return
 var closest: MissionDrone
 var distance := npc_fire_range
 for enemy in get_node("Enemies").get_children():
  if enemy.hp > 0 and enemy.visible and npc.position.distance_to(enemy.position) < distance:
   closest = enemy
   distance = npc.position.distance_to(enemy.position)
 if not closest: return
 npc_shoot_cd = npc_fire_interval
 npc_ammo -= 1
 var bullet := (load("res://scenes/Projectile.tscn") as PackedScene).instantiate() as MissionProjectile
 bullet.shooter = npc
 bullet.position = npc.position
 bullet.direction = npc.position.direction_to(closest.position)
 bullet.impacted.connect(func(collider):
  if collider is MissionDrone: collider.take_damage(npc_bullet_damage))
 get_node("Projectiles").add_child(bullet)
 _event("npc_shot", {"ammo": npc_ammo, "target": closest.name})
 state_changed.emit()

func take_npc_damage(amount: int) -> void:
 if not npc_combat_enabled or npc_hp <= 0 or map_id != "storage" or defeated or finished: return
 var protected := cover_time > 0.0 and npc.position.distance_to(safe_position) <= cover_radius
 var actual := maxi(1, ceili(amount * (covered_damage_multiplier if protected else 1.0)))
 npc_hp = maxi(0, npc_hp - actual)
 _event("npc_damage", {"damage": actual, "hp": npc_hp})
 if npc_hp <= 0:
  active_action = ""
  epoch += 1
  companion_spoke.emit("미안… 더는 못 움직이겠어.")
  notice.emit("하린 전투 불능 · 패널 지원 불가. 이전 저장 또는 새 회차를 이용하세요.")
  for enemy in get_node("Enemies").get_children(): enemy.companion_alive = false
 _sync_state()
 state_changed.emit()

func save_snapshot() -> Dictionary:
 var data := {"map_id": map_id, "player_position": [player.position.x, player.position.y], "npc_position": [npc.position.x, npc.position.y], "enemies": {}, "recent_events": recent_events.duplicate()}
 data.merge({"flashlight_owned": flashlight_owned, "flashlight_dropped": flashlight_dropped, "flashlight_position": [$FlashlightPickup.position.x, $FlashlightPickup.position.y], "facing": [player.facing_direction.x, player.facing_direction.y], "locker": locker.snapshot()})
 for key in ["fuse_collected", "power_restored", "finished", "defeated", "cache_used", "player_hp", "ammo", "medkits", "supply_packs", "cover_charges", "npc_hp", "npc_ammo", "cover_time", "guide_time", "heal_cd", "supply_cd", "guide_cd", "shoot_cd", "npc_shoot_cd"]: data[key] = get(key)
 for enemy in get_node("Enemies").get_children():
  data.enemies[str(enemy.name)] = {"hp": enemy.hp, "position": [enemy.position.x, enemy.position.y], "attack_wait": enemy.attack_wait}
 return data

func restore_snapshot(data: Dictionary) -> void:
 epoch += 1
 active_action = ""
 action_metadata = {}
 action_age = 0.0
 for key in ["map_id", "fuse_collected", "power_restored", "finished", "defeated", "cache_used", "player_hp", "ammo", "medkits", "supply_packs", "cover_charges", "npc_hp", "npc_ammo", "cover_time", "guide_time", "heal_cd", "supply_cd", "guide_cd", "shoot_cd", "npc_shoot_cd"]: set(key, data[key])
 action_metadata = {}
 flashlight_requested = false
 flashlight_owned = data.flashlight_owned
 flashlight_dropped = data.flashlight_dropped
 $FlashlightPickup.position = Vector2(data.flashlight_position[0], data.flashlight_position[1])
 player.facing_direction = Vector2(data.facing[0], data.facing[1])
 npc_motion.reset(player.facing_direction)
 locker.restore(data.locker)
 player.position = Vector2(data.player_position[0], data.player_position[1])
 npc.position = Vector2(data.npc_position[0], data.npc_position[1])
 player.velocity = Vector2.ZERO
 recent_events.assign(data.recent_events)
 for enemy in get_node("Enemies").get_children():
  var state: Dictionary = data.enemies[str(enemy.name)]
  enemy.hp = int(state.hp)
  enemy.position = Vector2(state.position[0], state.position[1])
  enemy.velocity = Vector2.ZERO
  enemy.attack_wait = float(state.attack_wait)
  enemy.companion_alive = npc_combat_enabled and npc_hp > 0
  enemy.queue_redraw()
 for bullet in get_node("Projectiles").get_children():
  bullet.set_physics_process(false)
  bullet.queue_free()
 _sync_state()
 _event("save_loaded", {})
 state_changed.emit()

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
