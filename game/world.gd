@tool
class_name DemoWorld
extends Node2D
signal interacted(kind: String)
signal state_changed
signal notice(message: String)
signal companion_spoke(message: String)
signal game_event(event: Dictionary)
signal room_changing
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
@export var npc: HarinActor
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
@export var npc_initial_reserve: int = 40
@export var npc_reload_seconds: float = 1.6
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
var npc_reserve := 40
var npc_reload_time := 0.0
var _npc_empty_notified := false
var npc_shoot_cd := 0.0
var recent_events: Array[String] = []
var completed_support := {}
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
var npc_navigation := CompanionNavigation.new()
var _combat_target: MissionDrone
var _target_hold := 0.0
var speech_priority := 30
var speech_guard := ""
var story := StoryProgress.new()
var _sight_frame := -1
var _sight_room := ""
var _sight_rects: Array[Rect2] = []

func obstruction_rects() -> Array[Rect2]:
 if _sight_frame == Engine.get_process_frames() and _sight_room == map_id: return _sight_rects
 _sight_frame = Engine.get_process_frames()
 _sight_room = map_id
 _sight_rects.clear()
 for item in find_children("*", "StaticBody2D", true, false):
  if item is RoundedObstacle and item.is_visible_in_tree():
   var center := to_local(item.global_position)
   _sight_rects.append(Rect2(center - item.footprint * 0.5, item.footprint))
 return _sight_rects

func line_of_sight(point: Vector2) -> bool:
 var start := player.position
 for rect in obstruction_rects():
  # 물체 자체의 표면은 관측할 수 있지만 그 뒤는 가린다.
  if rect.has_point(point) or rect.has_point(start): continue
  var low := 0.0
  var high := 1.0
  var ray := point - start
  var intersects := true
  for axis in range(2):
   if absf(ray[axis]) < 0.001:
    if start[axis] < rect.position[axis] or start[axis] > rect.end[axis]: intersects = false; break
   else:
    var a := (rect.position[axis] - start[axis]) / ray[axis]
    var b := (rect.end[axis] - start[axis]) / ray[axis]
    low = maxf(low, minf(a, b))
    high = minf(high, maxf(a, b))
    if low > high: intersects = false; break
  if intersects and low < 0.999 and high > 0.001: return false
 return true

func map_landmarks() -> Array:
 var result := []
 var targets: Array = [$ToStorage, $Generator, $Exit, $FlashlightPickup] if map_id == "lab" else [$ToLab, $SupplyCache, $Fuse, $LockerSupply] + locker.panels() if map_id == "storage" else [$ToLab, $MainDecor/Console]
 for target in targets:
  if not target.is_visible_in_tree(): continue
  var kind := "door" if target.interaction_id in ["storage_gate", "lab_gate", "exit"] else "objective" if target.interaction_id in ["fuse", "generator", "anomaly_console"] else "supply" if target.interaction_id in ["flashlight", "cache", "locker_supply"] else "device"
  var destination := "storage" if target == $ToStorage else "lab" if target == $ToLab else "main_entry" if target == $Exit else ""
  var active: bool = flashlight_owned if target == $ToStorage else power_restored if target == $Exit else true if target == $ToLab else target.activated
  result.append({"id": str(target.interaction_id), "name": target.display_name, "kind": kind, "position": [target.position.x, target.position.y] if target.get_parent() == self else [to_local(target.global_position).x, to_local(target.global_position).y], "destination": destination, "active": active})
 return result

func story_event(stage: String, event: String) -> void:
 if story.advance(stage, event):
  epoch += 1
  _event("story_event", {"stage": story.stage, "story_event": event})

func trigger_blackout() -> void:
 if "blackout" in story.events: return
 story_event("blackout", "blackout")
 _remember("근무 중 연구 구역의 전등이 갑자기 꺼졌다. 하린이 보안 직원인 플레이어를 불렀다")
 say_companion("어, 불 꺼졌네. 이쪽 좀 와 봐. 전력 장치부터 확인하자.", 60)
 notice.emit("정전 발생 · 하린과 장비를 챙겨 전력 계통 확인")
 _sync_state()
 state_changed.emit()

func trigger_alarm() -> void:
 if not power_restored or "anomaly_alarm" in story.events: return
 story_event("anomaly_alarm", "anomaly_alarm")
 _remember("전력이 돌아오자 침식된 분석 장치가 재가동되고 연구 구역 전체에 경보가 켜졌다")
 say_companion("저 장치 봐. 저거 원래 저렇게 안 돌아가는데… 연구동 쪽도 확인해야겠어.", 80)
 notice.emit("침식 경보 · 튜토리얼의 전력 복구 완료 / 연구동 출발 문에서 E")
 _event("anomaly_alarm", {})
 _sync_state()
 state_changed.emit()

func say_companion(text: String, priority := 30, guard := "") -> void:
 speech_priority = priority
 speech_guard = guard
 companion_spoke.emit(text)

func combat_target() -> MissionDrone:
 if map_id != "storage":
  _combat_target = null
  return null
 var current: MissionDrone = _combat_target if is_instance_valid(_combat_target) and _combat_target.hp > 0 and _combat_target.visible and npc.position.distance_to(_combat_target.position) <= npc_fire_range + 140 else null
 if current and _target_hold > 0: return current
 var candidate: MissionDrone
 var best := npc_fire_range + 140
 for enemy in get_node("Enemies").get_children():
  var distance: float = npc.position.distance_to(enemy.position)
  if enemy.hp > 0 and enemy.visible and distance < best:
   candidate = enemy
   best = distance
 if current and (not candidate or candidate == current or best > 100 or best > npc.position.distance_to(current.position) * 0.6): return current
 _combat_target = candidate
 _target_hold = 1.0
 return _combat_target
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
 story = StoryProgress.new()
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
 npc_reserve = npc_initial_reserve
 npc_reload_time = 0
 _npc_empty_notified = false
 npc_shoot_cd = npc_fire_interval
 flashlight_owned = false
 flashlight_dropped = false
 flashlight_requested = false
 $FlashlightPickup.position = _npc_spawn + Vector2(24, 24)
 player.facing_direction = Vector2.RIGHT
 npc_motion.reset()
 npc_navigation.reset()
 _combat_target = null
 locker.reset()
 recent_events.clear()
 completed_support.clear()
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
 get_node("LabDecor").visible = map_id == "lab"
 $MainDecor.visible = map_id == "main_entry"
 $MainDecor/Console.set_active("anomaly_observed" in story.events)
 get_node("StorageDecor").visible = dark
 get_node("ToStorage").visible = map_id == "lab"
 get_node("ToLab").visible = map_id != "lab"
 get_node("SupplyCache").visible = dark and not cache_used
 locker.visible = dark
 locker.update_visuals()
 fuse.visible = dark and locker.opened and not fuse_collected
 $LockerSupply.visible = dark and locker.opened and not locker.supply_taken
 $FlashlightPickup.visible = map_id == "lab" and flashlight_dropped and not flashlight_owned
 generator.visible = map_id == "lab"
 exit_object.visible = map_id == "lab"
 exit_object.display_name = "연구동 출발 · E" if power_restored else "연구동 출발 · 전력 필요"
 generator.set_active(power_restored)
 exit_object.set_active(power_restored)
 player.movement_enabled = _can_move and not finished and not defeated
 npc.modulate = Color("888888") if npc_hp <= 0 else Color.WHITE
 if npc_hp <= 0: npc.show_pose("down", npc.position + Vector2.RIGHT)
 elif npc.pose == "down": npc.show_pose("wait" if npc_motion.mode == "wait" else "idle", npc.position + player.facing_direction * 80)
 # 전력 조명과 시야 가림은 별개다. 밝아진 뒤에도 가구 뒤를 투시하지 않는다.
 get_node("Darkness").visible = true
 (get_node("Darkness").material as ShaderMaterial).set_shader_parameter("ambient_enabled", power_restored or story.stage == "on_shift")
 $Alarm.visible = "anomaly_alarm" in story.events
 $LabDecor/Desk.modulate = Color("ff7777") if power_restored else Color.WHITE
 get_node("RoomTitle").text = "연구동 진입실" if map_id == "main_entry" else ("전력이 복구된 보관 구역" if power_restored else "어두운 보관 구역") if dark else location_name
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
 var closest: Node2D
 var distance := player.interaction_distance
 var targets := [npc, fuse, generator, exit_object, get_node("ToStorage"), get_node("ToLab"), get_node("SupplyCache"), $FlashlightPickup, $LockerSupply]
 if map_id == "main_entry": targets.append($MainDecor/Console)
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
   trigger_blackout()
   if not flashlight_owned:
    request_flashlight()
    if npc_motion.mode == "wait": return "하린이 대기 중입니다. 따라와 명령으로 동행을 재개한 뒤 손전등을 받으세요."
    return "하린이 건네는 손전등을 E로 주운 뒤 보관 구역에 들어가세요."
   _change_map("storage", get_node("StorageEntry").position)
   story_event("fuse_search", "storage_entered")
   message = "보관 구역 진입. 드론을 제압하고 퓨즈를 찾으세요."
  "lab_gate":
   if map_id not in ["storage", "main_entry"]: return "이 방에서는 돌아갈 수 없습니다."
   _change_map("lab", get_node("LabReturn").position)
   message = "연구실로 돌아왔습니다."
  "fuse":
   if map_id != "storage": return "퓨즈는 보관 구역에 있습니다."
   if enemies_remaining() > 0: return "주변 드론을 먼저 제압해야 합니다."
   if not locker.opened: return "두 패널을 함께 작동해 보관함을 먼저 여세요."
   if fuse_collected: return "이미 퓨즈를 챙겼습니다."
   fuse_collected = true
   story_event("fuse_return", "fuse_collected")
   epoch += 1
   message = "퓨즈 획득. 연구실로 돌아가 전력 장치에 장착하세요."
   _remember("전투를 마치고 퓨즈를 찾았다")
  "flashlight":
   if map_id != "lab" or not flashlight_dropped or flashlight_owned: return "지금은 주울 손전등이 없습니다."
   flashlight_owned = true
   story_event("equipment", "flashlight_collected")
   flashlight_dropped = false
   flashlight_requested = false
   epoch += 1
   message = "손전등 획득. 마우스 조준 방향으로 먼 곳을 비춥니다. 이제 보관 구역에 들어갈 수 있습니다."
   _event("flashlight_collected", {})
   _remember("플레이어가 하린이 놓은 손전등을 주웠다")
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
   if ammo >= max_ammo and npc_reserve >= npc_initial_reserve: return "둘 다 탄약이 충분합니다."
   cache_used = true
   ammo = mini(max_ammo, ammo + 10)
   npc_reserve = mini(npc_initial_reserve, npc_reserve + 20)
   message = "비상 탄약 회수 · 플레이어 +10 / 하린 예비탄 +20 (최대치 제한)"
   _event("cache_recovered", {"npc_reserve": npc_reserve, "player_ammo": ammo})
  "revive_npc":
   if npc_hp > 0: return "하린은 움직일 수 있습니다."
   if player.position.distance_to(npc.position) > player.interaction_distance: return "하린 가까이에서 E로 소생하세요."
   if medkits <= 0:
    fail_mission("소생할 치료 키트가 없습니다.")
    return "하린 소생 불가 · 새 회차로 재도전하세요."
   medkits -= 1
   npc_hp = mini(35, npc_max_hp)
   npc_shoot_cd = npc_fire_interval
   npc_reload_time = 0
   npc_motion.order("follow", npc.position)
   epoch += 1
   message = "하린 소생 · 치료 키트 1개 사용 (체력 35)"
   _remember("플레이어가 치료 키트로 하린을 소생시켰다")
   _event("npc_revived", {"hp": npc_hp, "medkits": medkits})
   say_companion("고마워. 이제 움직일 수 있어.", 30)
  "generator":
   if map_id != "lab": return "전력 장치는 연구실에 있습니다."
   if power_restored: return "이미 전력을 복구했습니다."
   if not fuse_collected: return "보관 구역에서 퓨즈를 가져와야 합니다."
   power_restored = true
   story_event("power_restored", "power_restored")
   epoch += 1
   _remember("연구실로 돌아와 함께 전력을 복구했다")
   message = "전력 복구 · 장치 재가동 중…"
   _event("power_restored", {"storage_lights_on": true})
  "exit":
   if map_id != "lab" or not power_restored: return "연구실 전력을 먼저 복구해야 합니다."
   trigger_alarm()
   story.tutorial_completed = true
   story_event("main_entry", "main_entered")
   _change_map("main_entry", Vector2(130, 405))
   message = "연구동 진입 · 관측 단말을 확인하세요. 이상현상 봉쇄 임무는 계속됩니다."
   say_companion("여기부터는 내가 아는 고장 수준이 아니네. 저 단말부터 보자.", 60)
  "anomaly_console":
   if map_id != "main_entry": return "연구동 진입실의 관측 단말입니다."
   story_event("main_entry", "anomaly_observed")
   _remember("연구동 관측 단말에서 침식이 내부 구역으로 이어짐을 확인했다")
   message = "관측 완료 · 내부 봉쇄 경로 조사 필요 (후속 전투·구역은 아직 미구현)"
 _sync_state()
 _event("interaction", {"kind": kind, "message": message})
 state_changed.emit()
 return message

func _change_map(destination: String, spawn: Vector2) -> void:
 room_changing.emit()
 locker.cancel("map_changed")
 epoch += 1
 map_id = destination
 player.position = spawn
 npc.position = spawn + Vector2(55, -30)
 npc_motion.reset(player.facing_direction)
 npc_navigation.reset()
 _combat_target = null
 active_action = ""
 cover_time = 0.0
 guide_time = 0.0
 for bullet in get_node("Projectiles").get_children(): bullet.queue_free()
 _sync_state()

func _physics_process(delta: float) -> void:
 if Engine.is_editor_hint(): return
 story.elapsed += delta
 if story.stage == "on_shift" and story.elapsed > 0.7: trigger_blackout()
 if story.stage == "power_restored" and story.elapsed > 0.9: trigger_alarm()
 if $Alarm.visible: $Alarm.modulate.a = 0.18 + 0.13 * sin(Time.get_ticks_msec() * 0.005)
 update_visibility()
 shoot_cd = maxf(0.0, shoot_cd - delta)
 npc_shoot_cd = maxf(0.0, npc_shoot_cd - delta)
 _target_hold = maxf(0.0, _target_hold - delta)
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
 if npc_hp > 0: _npc_reload(delta)
 if map_id == "storage" and enemies_remaining() > 0 and ammo <= 0 and npc_ammo + npc_reserve <= 0 and supply_packs <= 0 and cache_used and not (locker.opened and not locker.supply_taken):
  fail_mission("전투에 필요한 탄약과 보급을 모두 소진했습니다.")
  return
 if npc_hp <= 0:
  npc_motion.velocity = Vector2.ZERO
  npc.show_pose("down", npc.position + Vector2.RIGHT)
  locker.tick(delta, false)
  if medkits <= 0: fail_mission("하린을 소생할 치료 키트가 없습니다.")
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
 var aim_target := combat_target()
 var pose := "aim" if aim_target else "wait" if npc_motion.mode == "wait" else "move" if npc_motion.velocity.length() > 10 else "idle"
 var aim: Vector2 = aim_target.position if aim_target else npc.position + npc_motion.heading * 80
 if scripted:
  pose = "support"
  aim = target
 elif npc_reload_time > 0:
  pose = "reload"
  aim = npc.position + npc_motion.heading * 60
 npc.show_pose(pose, aim)
 if flashlight_requested and npc.position.distance_to(player.position) <= 90: _drop_flashlight()
 if not active_action.is_empty():
  action_age += delta
  if active_action == "assist_panel":
   if not locker.needs_assistance() and locker.sequence_elapsed < 0: active_action = ""
   elif action_age > 10 and locker.progress <= 0 and locker.sequence_elapsed < 0:
    locker.cancel("approach_timeout")
    say_companion("반대편으로 가는 길이 막혔어. 잠깐 놓고 다시 해 보자.", 30, "assist_panel_done")
  elif action_age > 5.0:
   _event("support_rejected", {"action": active_action, "reason": "approach_timeout", "request": action_metadata})
   say_companion("길이 막혀서 못 가겠어. 가까이 와 줄래?", 30, active_action + "_done")
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
 var occluders := PackedVector4Array()
 for rect in obstruction_rects(): occluders.append(Vector4(rect.position.x, rect.position.y, rect.end.x, rect.end.y))
 var count := mini(occluders.size(), 32)
 occluders.resize(32)
 (darkness.material as ShaderMaterial).set_shader_parameter("obstacles", occluders)
 (darkness.material as ShaderMaterial).set_shader_parameter("obstacle_count", count)

func request_flashlight() -> void:
 if flashlight_owned or flashlight_dropped or npc_hp <= 0: return
 if npc_motion.mode == "wait": return
 if not flashlight_requested:
  flashlight_requested = true
  say_companion("앞이 꽤 어둡네. 잠깐, 손전등 줄게.", 30)
  _event("flashlight_requested", {})
 if npc.position.distance_to(player.position) <= 90: _drop_flashlight()

func _drop_flashlight() -> void:
 flashlight_requested = false
 flashlight_dropped = true
 $FlashlightPickup.position = (npc.position + npc.position.direction_to(player.position) * 30).clamp(room_rect.position + Vector2(28, 28), room_rect.end - Vector2(28, 28))
 npc_motion.velocity = Vector2.ZERO
 _event("flashlight_dropped", {"position": [$FlashlightPickup.position.x, $FlashlightPickup.position.y]})
 say_companion("여기 놨어. 챙겨 가.", 30, "flashlight")
 notice.emit("손전등 · 가까이에서 E로 줍기")
 _sync_state()
 state_changed.emit()

func visibility_at(point: Vector2) -> float:
 if not room_rect.has_point(point) or not line_of_sight(point): return 0.0
 if power_restored or story.stage == "on_shift": return 1.0 if player.position.distance_to(point) < 550 else 0.0
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
 if action in ["follow", "wait"]:
  # 자동 판단은 플레이어의 명시적인 대기 지시를 해제하지 않는다.
  if metadata.has("provider"): return true
  npc_motion.order(action, npc.position)
  if action == "wait":
   flashlight_requested = false
  _event("companion_order", {"mode": action, "release": "follow_or_map_or_trial", "request": metadata})
  return true
 if action == "assist_panel":
  active_action = action
  action_metadata = metadata.duplicate(true)
  action_age = 0
  npc_motion.pattern = "반대 패널 지원"
  if metadata.get("source") != "player_order": say_companion("내가 반대편 누를게!", 30, "panel")
  _event("support_started", {"action": action, "request": action_metadata})
  return true
 if action == "guide_to_cover":
  guide_time = 4.0
  guide_cd = 4.0
  var offset := safe_position - player.position
  var direction := ("오른쪽" if offset.x > 0 else "왼쪽") if absf(offset.x) > absf(offset.y) else ("아래쪽" if offset.y > 0 else "위쪽")
  var text := direction + "이야! 이리로 와!"
  notice.emit("보호 장비 · " + direction + " 원 안으로 이동")
  say_companion(text)
  _event("support_completed", {"action": action, "callout": text, "target": [safe_position.x, safe_position.y], "request": metadata})
  return true
 active_action = action
 action_metadata = metadata.duplicate(true)
 action_age = 0.0
 _event("support_started", {"action": action, "request": action_metadata})
 return true

func request_player_order(action: String) -> Dictionary:
 var text := ""
 var reason := ""
 if action == "clarify": return {"accepted": false, "status": "clarification", "text": "치료가 필요해, 아니면 탄약이 필요해?"}
 if action == "unsupported": return {"accepted": false, "status": "unsupported", "text": "그 행동은 지금 내가 할 수 없어. 동행이나 치료, 탄약 지원은 할 수 있어."}
 if npc_hp <= 0: reason = "지금은 움직이거나 지원할 수 없어."
 elif finished or defeated: reason = "이번 임무는 끝났어."
 elif action == "heal" and medkits <= 0: reason = "치료 키트가 다 떨어졌어."
 elif action == "resupply" and supply_packs <= 0: reason = "탄약 보급품이 다 떨어졌어."
 elif action == "heal" and player_hp >= max_hp: reason = "지금은 다친 데가 없어 보여."
 elif action == "resupply" and ammo >= max_ammo: reason = "지금은 탄약이 충분해."
 elif action == "assist_panel" and not locker.needs_assistance(): reason = "먼저 한쪽 패널을 잡아 줘. 같이 유지해야 해."
 elif action not in ["follow", "wait"] and not active_action.is_empty(): reason = "지금 하던 지원을 마친 뒤에 할 수 있어."
 elif action not in valid_actions(): reason = "지금은 그 지원을 할 수 없어."
 if not reason.is_empty():
  _event("player_order_rejected", {"action": action, "reason": reason})
  return {"accepted": false, "status": "rejected", "text": reason}
 if action in ["follow", "wait"] and not active_action.is_empty():
  _event("support_rejected", {"action": active_action, "reason": "player_order", "request": action_metadata})
  if active_action == "assist_panel": locker.cancel("player_order")
  active_action = ""
 var accepted := request_support(action, {"source": "player_order"})
 match action:
  "heal": text = "잠깐만, 내가 갈게."
  "resupply": text = "탄약 가져갈게. 잠깐만."
  "follow": text = "응, 네 뒤로 붙을게."
  "wait": text = "여기서 경계할게. 다시 따라오라고 하면 움직일게."
  "assist_panel": text = "반대편으로 갈게. 한쪽을 계속 잡아 줘."
  "deploy_cover": text = "보호 장비 설치하러 갈게."
 return {"accepted": accepted, "status": "started" if accepted else "rejected", "text": text if accepted else "지금은 그 지원을 할 수 없어."}

func emergency_support() -> String:
 if npc_hp <= 0 or finished or defeated: return ""
 var action := ""
 if player_hp <= 30 and medkits > 0 and heal_cd <= 0: action = "heal"
 elif ammo == 0 and supply_packs > 0 and supply_cd <= 0: action = "resupply"
 if action.is_empty() or active_action == action or active_action in ["heal", "resupply"]: return ""
 if not active_action.is_empty():
  _event("support_rejected", {"action": active_action, "reason": "emergency_preempted", "request": action_metadata})
  if active_action == "assist_panel": locker.cancel("emergency_preempted")
  active_action = ""
 if request_support(action, {"source": "common_emergency", "version": 2}):
  say_companion("잠깐만, 내가 갈게." if action == "heal" else "탄약 가져갈게. 잠깐만.", 100, action + "_started")
  return action
 return ""

func _finish_support() -> void:
 var action := active_action
 active_action = ""
 if action not in valid_actions():
  _event("support_rejected", {"action": action, "reason": "no_longer_valid", "request": action_metadata})
  say_companion("상황이 바뀌어서 지금은 그 지원을 할 수 없어.", 30, action + "_done")
  return
 var effect := 0
 var text := ""
 match action:
  "heal":
   effect = mini(heal_amount, max_hp - player_hp)
   player_hp += effect
   medkits -= 1
   heal_cd = 8.0
   text = "됐어. 움직일 수 있겠어?"
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
 say_companion(text, 30, action + "_done")
 _remember({"heal": "하린이 플레이어를 치료하고 키트를 사용했다", "resupply": "하린이 플레이어에게 탄약을 보급했다", "deploy_cover": "하린이 보호 장비를 설치했다"}.get(action, text))
 _event("support_completed", {"action": action, "effect": effect, "request": action_metadata})
 completed_support[action] = int(completed_support.get(action, 0)) + 1
 state_changed.emit()

func _enemy_defeated() -> void:
 if enemies_remaining() == 0:
  say_companion("다 정리됐네. 같이 열어 보자.", 10, "clear")
  _remember("함께 보관 구역의 드론을 제압했다")
 _event("enemy_defeated", {"remaining": enemies_remaining()})
 _sync_state()
 state_changed.emit()

func current_guidance() -> String:
 if defeated: return "전투 불능입니다. 새 회차로 다시 시작하세요."
 if finished: return "임무를 완료했습니다."
 if npc_hp <= 0: return "하린 다운 · 가까이에서 E로 치료 키트 1개를 사용해 소생하세요."
 if story.stage == "on_shift": return "근무 중 · 연구 구역의 전등 상태를 확인하세요."
 if map_id == "main_entry": return "관측 단말을 확인하세요 · 이후 내부 봉쇄 경로는 개발 중" if "anomaly_observed" not in story.events else "침식 내부 구역으로 이어지는 봉쇄 경로 조사 · 후속 구역 개발 중"
 if power_restored: return "침식 경보 · 연구실 출발 출입문에서 E로 연구동 진입" if "anomaly_alarm" in story.events else "전력 복구 · 장치 재가동을 확인하세요"
 if fuse_collected: return "연구실로 돌아가 전력 장치에 퓨즈를 장착하세요." if map_id == "storage" else "전력 장치에 퓨즈를 장착하세요."
 if map_id == "lab":
  if flashlight_dropped: return "바닥의 손전등을 E로 주운 뒤 오른쪽 보관 구역으로 가세요."
  return "오른쪽 통로에서 하린에게 손전등을 받으세요." if not flashlight_owned else "오른쪽 통로로 보관 구역에 가서 퓨즈를 찾으세요."
 if enemies_remaining() > 0: return "드론 %d기를 제압한 뒤 북동쪽 2인 패널 보관함에서 퓨즈를 찾으세요." % enemies_remaining()
 if not locker.opened:
  if locker.sequence_elapsed >= 0: return "비프음 확인 중 · 보관함 잠금이 해제됩니다."
  if locker.player_panel >= 0: return "E 유지 · 하린과 양쪽 패널을 %.1f / %.1f초 함께 작동" % [locker.progress, locker.hold_seconds]
  return "보관함 양쪽 패널 중 하나에서 E 유지 · 하린에게 반대 패널 지원 요청"
 return "열린 보관함의 퓨즈·보급을 챙기고 왼쪽 통로로 연구실에 돌아가세요."

func game_state() -> Dictionary:
 return {"epoch": epoch, "map_id": map_id, "story": story.snapshot(), "objective": current_guidance(), "location": "연구동 진입실" if map_id == "main_entry" else ("전력이 복구된 보관 구역" if power_restored else "어두운 보관 구역") if map_id == "storage" else location_name,
 "fuse_collected": fuse_collected, "fuse_in_inventory": fuse_collected and not power_restored, "power_restored": power_restored, "escaped": finished, "defeated": defeated,
 "player_hp": player_hp, "max_hp": max_hp, "ammo": ammo, "max_ammo": max_ammo, "enemy_count": enemies_remaining() if map_id == "storage" else 0,
 "npc_hp": npc_hp, "npc_max_hp": npc_max_hp, "npc_ammo": npc_ammo, "npc_max_ammo": npc_initial_ammo, "npc_reserve": npc_reserve, "npc_reload_time": npc_reload_time, "npc_downed": npc_hp <= 0,
 "medkits": medkits, "supply_packs": supply_packs, "cover_charges": cover_charges, "cover_active": cover_time > 0.0, "inside_cover": inside_cover(),
 "active_action": active_action, "current_guidance": current_guidance(), "relationship": "서로 믿는 친한 동료",
 "player_position": [player.position.x, player.position.y], "npc_position": [npc.position.x, npc.position.y], "cover_position": [safe_position.x, safe_position.y],
 "recent_shared_events": recent_events.duplicate(), "completed_support": completed_support.duplicate(), "valid_actions": valid_actions(),
  "flashlight_owned": flashlight_owned, "flashlight_dropped": flashlight_dropped, "flashlight_requested": flashlight_requested, "storage_lit": power_restored, "locker": locker.context(), "npc_movement_pattern": npc_motion.pattern, "companion_mode": npc_motion.mode,
 "scenario_config": scenario_configuration()}

func scenario_configuration() -> Dictionary:
 var enemies := []
 for enemy in get_node("Enemies").get_children():
  enemies.append({"name": enemy.name, "spawn": _enemy_spawns.get(enemy.name), "hp": enemy.max_hp, "speed": enemy.move_speed, "damage": enemy.contact_damage, "attack_interval": enemy.attack_interval})
 var configuration := {"max_hp": max_hp, "initial_ammo": initial_ammo, "max_ammo": max_ammo, "bullet_damage": bullet_damage, "npc_max_hp": npc_max_hp, "npc_initial_ammo": npc_initial_ammo, "npc_bullet_damage": npc_bullet_damage, "npc_fire_interval": npc_fire_interval, "npc_combat_enabled": npc_combat_enabled, "heal_amount": heal_amount, "resupply_amount": resupply_amount, "cover_duration": cover_duration, "cover_radius": cover_radius, "damage_multiplier": covered_damage_multiplier, "medkits": initial_medkits, "supply_packs": initial_supply_packs, "cover_charges": initial_cover_charges, "player_speed": player.move_speed, "sight_radius": sight_radius, "room_rect": str(room_rect), "safe_position": [safe_position.x, safe_position.y], "enemies": enemies}

 configuration["mechanics"] = {"version": 2, "npc_role": npc_role, "npc_fire_range": npc_fire_range, "panel_hold_seconds": locker.hold_seconds, "flashlight_range": flashlight_range, "flashlight_half_angle": flashlight_half_angle}
 configuration["companion_rules"] = {"version": 2, "reserve_ammo": npc_initial_reserve, "reload_seconds": npc_reload_seconds, "emergency_hp": 30, "emergency_ammo": 0, "motion": "stable_formation_astar20_collision12", "revive_cost": 1, "revive_hp": 35, "cache_npc_reserve": 20, "prompt_version": NPCPolicy.PROMPT_VERSION}
 return configuration

func _npc_fire() -> void:
 if not npc_combat_enabled or npc_hp <= 0 or defeated or finished or map_id != "storage" or npc_ammo <= 0 or npc_reload_time > 0 or npc_shoot_cd > 0.0 or not active_action.is_empty(): return
 var closest := combat_target()
 if not closest or npc.position.distance_to(closest.position) > npc_fire_range: return
 npc.set_meta("visual_aim", closest.position)
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
  say_companion("미안… 더는 못 움직이겠어.", 100)
  locker.cancel("npc_downed")
  npc_reload_time = 0
  notice.emit("하린 다운 · 가까이에서 E로 치료 키트 1개를 사용해 소생")
  if medkits <= 0: fail_mission("하린을 소생할 치료 키트가 없습니다.")
  for enemy in get_node("Enemies").get_children(): enemy.companion_alive = false
 _sync_state()
 state_changed.emit()

func fail_mission(reason: String) -> void:
 if finished or defeated: return
 defeated = true
 epoch += 1
 active_action = ""
 locker.cancel("mission_failed")
 notice.emit(reason + " 새 회차로 재도전하세요.")
 _event("mission_failed", {"reason": reason})
 _sync_state()
 state_changed.emit()

func _npc_reload(delta: float) -> void:
 if npc_reload_time > 0:
  npc_reload_time = maxf(0, npc_reload_time - delta)
  if npc_reload_time <= 0:
   var amount := mini(npc_initial_ammo - npc_ammo, npc_reserve)
   npc_ammo += amount
   npc_reserve -= amount
   _event("npc_reload_completed", {"ammo": npc_ammo, "reserve": npc_reserve, "loaded": amount})
   state_changed.emit()
  return
 if npc_ammo > 0: _npc_empty_notified = false; return
 if npc_reserve <= 0 and supply_packs > 0 and active_action != "resupply" and ammo > 0:
  supply_packs -= 1
  npc_reserve += resupply_amount
  _event("npc_resupply_completed", {"amount": resupply_amount, "supply_packs": supply_packs, "source": "shared_pack"})
 if npc_reserve > 0:
  npc_reload_time = npc_reload_seconds
  _event("npc_reload_started", {"seconds": npc_reload_seconds, "reserve": npc_reserve})
  state_changed.emit()
 elif not _npc_empty_notified:
  _npc_empty_notified = true
  say_companion("내 탄약도 다 떨어졌어. 사격 지원은 어려워." if cache_used else "내 탄약도 다 떨어졌어. 비상 탄약함을 찾아야 해.", 30)
  notice.emit("하린 탄약 소진 · 남은 보급 확인" if cache_used else "하린 탄약 소진 · 비상 탄약함 E로 예비탄 회수")

func save_snapshot() -> Dictionary:
 var data := {"map_id": map_id, "player_position": [player.position.x, player.position.y], "npc_position": [npc.position.x, npc.position.y], "enemies": {}, "recent_events": recent_events.duplicate()}
 data["story"] = story.snapshot()
 data.merge({"flashlight_owned": flashlight_owned, "flashlight_dropped": flashlight_dropped, "flashlight_position": [$FlashlightPickup.position.x, $FlashlightPickup.position.y], "facing": [player.facing_direction.x, player.facing_direction.y], "locker": locker.snapshot()})
 data.merge({"npc_reserve": npc_reserve, "npc_reload_time": npc_reload_time, "companion_mode": npc_motion.mode, "wait_position": [npc_motion.wait_position.x, npc_motion.wait_position.y] if npc_motion.mode == "wait" else [npc.position.x, npc.position.y]})
 data["completed_support"] = completed_support.duplicate()
 for key in ["fuse_collected", "power_restored", "finished", "defeated", "cache_used", "player_hp", "ammo", "medkits", "supply_packs", "cover_charges", "npc_hp", "npc_ammo", "cover_time", "guide_time", "heal_cd", "supply_cd", "guide_cd", "shoot_cd", "npc_shoot_cd"]: data[key] = get(key)
 for enemy in get_node("Enemies").get_children():
  data.enemies[str(enemy.name)] = {"hp": enemy.hp, "position": [enemy.position.x, enemy.position.y], "attack_wait": enemy.attack_wait}
 return data

func restore_snapshot(data: Dictionary) -> void:
 epoch += 1
 active_action = ""
 action_metadata = {}
 action_age = 0.0
 story.restore(data.get("story", StoryProgress.legacy(data)))
 for key in ["map_id", "fuse_collected", "power_restored", "finished", "defeated", "cache_used", "player_hp", "ammo", "medkits", "supply_packs", "cover_charges", "npc_hp", "npc_ammo", "cover_time", "guide_time", "heal_cd", "supply_cd", "guide_cd", "shoot_cd", "npc_shoot_cd"]: set(key, data[key])
 action_metadata = {}
 flashlight_requested = false
 flashlight_owned = data.flashlight_owned
 flashlight_dropped = data.flashlight_dropped
 $FlashlightPickup.position = Vector2(data.flashlight_position[0], data.flashlight_position[1])
 player.facing_direction = Vector2(data.facing[0], data.facing[1])
 npc_motion.reset(player.facing_direction)
 npc_navigation.reset()
 _combat_target = null
 locker.restore(data.locker)
 player.position = Vector2(data.player_position[0], data.player_position[1])
 npc.position = Vector2(data.npc_position[0], data.npc_position[1])
 npc_reserve = int(data.get("npc_reserve", npc_initial_reserve))
 npc_reload_time = float(data.get("npc_reload_time", 0))
 _npc_empty_notified = false
 if data.get("companion_mode", "follow") == "wait":
  npc_motion.order("wait", Vector2(data.wait_position[0], data.wait_position[1]))
 player.velocity = Vector2.ZERO
 recent_events.assign(data.recent_events)
 completed_support = data.get("completed_support", {}).duplicate()
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
