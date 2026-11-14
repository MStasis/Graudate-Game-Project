@tool
class_name ContainmentMission
extends Node2D
## 연구동 외곽 봉쇄. 튜토리얼 보관함/적과 수명 및 저장을 공유하지 않는다.
const STAGES := ["unobserved", "ready", "wave_one", "wave_two", "panel_ready", "complete"]
const DRONE := preload("res://scenes/RiftCrew.tscn")
@export_range(1, 6, 1) var first_wave_count := 2
@export_range(1, 6, 1) var second_wave_count := 3
var world: Node2D
var stage := "unobserved"
var supply_used := false
@onready var panel: CooperativeLocker = $Panel

func bind(mission: Node2D) -> void:
 world = mission
 panel.bind(world)
 for wave in [1, 2]:
  for index in first_wave_count if wave == 1 else second_wave_count:
   var drone := DRONE.instantiate() as MissionDrone
   drone.name = "Wave%dDrone%d" % [wave, index + 1]
   drone.set_meta("wave", wave)
   drone.mission = world
   drone.navigate_obstacles = true
   drone.navigation.clearance = 22.0
   drone.collision_mask = 5
   drone.target = world.player
   drone.companion = world.npc
   drone.hit_player.connect(world.take_damage)
   drone.hit_companion.connect(world.take_npc_damage)
   drone.defeated.connect(_drone_defeated)
   $Enemies.add_child(drone)
 reset()

func reset() -> void:
 stage = "unobserved"
 supply_used = false
 panel.reset()
 for drone in enemies():
  drone.hp = 0
  drone.active = false
  drone.visible = false
  drone.position = Vector2(1000, 400)
  drone.velocity = Vector2.ZERO
  drone.collision_layer = 0
  drone.navigation.reset()
  drone.reset_animation()

func enemies() -> Array:
 return $Enemies.get_children()

func fighting() -> bool:
 return stage in ["wave_one", "wave_two"]

func remaining() -> int:
 return enemies().filter(func(enemy): return enemy.hp > 0).size()

func observe() -> String:
 if stage != "unobserved": return guidance()
 stage = "ready"
 world.story_event("containment", "anomaly_observed")
 world.story_event("containment", "containment_briefed")
 world._remember("관측 단말에서 외곽 침식 확산과 임시 봉쇄 장치를 확인했다")
 world.say_companion("침식이 외곽으로 번지고 있어. 저 봉쇄 장치를 켜자. 선원부터 정리하고, 마지막 패널은 둘이 같이 누르는 거야.", 80)
 world.notice.emit("외곽 임시 봉쇄 · 일회용 보급함 확인 → 봉쇄 장치 E → 침식된 선원 두 무리 → 2인 패널")
 return "관측 완료 · 목표: 봉쇄 장치 가동. 연구소 전체 해결이 아닌 외곽 확산의 임시 차단입니다."

func interact(kind: String) -> String:
 if kind == "containment_supply":
  if supply_used: return "봉쇄 보급함은 이미 사용했습니다."
  supply_used = true
  return replenish()
 if kind == "containment_device":
  if stage == "unobserved": return "먼저 관측 단말을 E로 조사하세요."
  if stage != "ready": return guidance()
  if world.npc_hp <= 0: return "미카 가까이에서 E로 소생한 뒤 장치를 켜세요."
  if world.npc_motion.mode == "wait": return "미카가 대기 중입니다. Enter로 ‘따라와’를 전송한 뒤 장치를 켜세요."
  if not supply_used: return "전투 준비 · 왼쪽 봉쇄 보급함에서 E로 양쪽 탄약과 치료 키트를 먼저 챙기세요."
  _spawn_wave(1)
  return "봉쇄 장치 가동 · 첫 무리 제압. 안전 격리 때문에 전투 중 연구실 복귀문은 잠깁니다."
 if kind in ["containment_panel_a", "containment_panel_b"]:
  if stage != "panel_ready": return "두 차례 선원을 모두 제압해야 최종 봉쇄 패널을 사용할 수 있습니다."
  if world.npc_motion.mode == "wait": return "미카가 대기 중입니다. Enter로 ‘따라와’를 전송한 뒤 함께 패널을 누르세요."
  var message := panel.begin(0 if kind.ends_with("_a") else 1)
  ensure_panel_assistance()
  return message
 return ""

func replenish() -> String:
 world.ammo = world.max_ammo
 world.npc_ammo = world.npc_initial_ammo
 world.npc_reserve = world.npc_initial_reserve
 world.npc_reload_time = 0
 world.medkits = world.initial_medkits
 world.supply_packs = world.initial_supply_packs
 world.cover_charges = world.initial_cover_charges
 world._event("containment_supply_collected", {"source": "fixed_supply", "one_use": true})
 world.notice.emit("봉쇄 보급함 회수 · 양쪽 탄약/미카 예비탄/공용 치료·보급·보호 재고 보충 (최대치)")
 return "일회용 보급 완료 · 미카 다운 시 가까이에서 E로 키트를 사용하세요."

func ensure_panel_assistance() -> void:
 # 먼저 수행 중인 치료/보급이 끝난 경우에도 모델 판단을 기다리지 않고 이어 간다.
 if world.map_id == "main_entry" and stage == "panel_ready" and panel.needs_assistance() and world.npc_hp > 0 and world.npc_motion.mode != "wait" and world.active_action.is_empty():
  world.request_support("assist_panel", {"source": "fixed_mission_panel"})

func _spawn_wave(wave: int) -> void:
 stage = "wave_one" if wave == 1 else "wave_two"
 world.story_event("containment", "containment_wave_%d" % wave)
 var placed: Array[Vector2] = []
 for drone in enemies():
  if drone.get_meta("wave") != wave: continue
  drone.position = _spawn_point(placed)
  placed.append(drone.position)
  drone.reset_enemy()
  drone.navigation.reset()
  drone.attack_wait = 1.5
 world._event("containment_wave_started", {"wave": wave, "count": placed.size(), "source": "fixed_mission"})
 world.say_companion("장치가 켜졌어. 오는 선원부터 막자!" if wave == 1 else "한 무리 더 온다. 이것만 정리하면 패널을 쓸 수 있어!", 80)
 world.notice.emit("봉쇄 전투 %d / 2 · 침식된 선원 %d명" % [wave, placed.size()])
 world._sync_state()

func _spawn_point(placed: Array[Vector2]) -> Vector2:
 # 정해진 이동 가능 격자에서 두 캐릭터/가구/다른 출현점과 떨어진 점을 선택한다.
 var best := Vector2.ZERO
 var score := -1.0
 for x in range(100, 1120, 60):
  for y in range(110, 470, 60):
   var point := Vector2(x, y)
   var blocked := false
   for rect in world.obstruction_rects():
    if rect.grow(32).has_point(point): blocked = true; break
   if blocked: continue
   var distance := minf(point.distance_to(world.player.position), point.distance_to(world.npc.position))
   for other in placed: distance = minf(distance, point.distance_to(other))
   if distance > score: best = point; score = distance
 return best

func _drone_defeated() -> void:
 world._event("enemy_defeated", {"mission": "containment", "remaining": remaining()})
 if not world.finished and not world.defeated and remaining() == 0:
  if stage == "wave_one": _spawn_wave(2)
  elif stage == "wave_two":
   stage = "panel_ready"
   world.story_event("containment", "containment_waves_cleared")
   world.clear_projectiles()
   world._remember("외곽 봉쇄를 방해하던 두 무리의 침식된 선원을 모두 제압했다")
   world.say_companion("다 정리됐어. 이제 저쪽 패널 같이 누르자. 한쪽에서 E를 계속 누르고 있어.", 80)
   world.notice.emit("최종 봉쇄 패널 해제 · 양쪽 패널 1초 동시 유지 후 비프 확인")
 world._sync_state()
 world.state_changed.emit()

func panel_completed() -> void:
 if stage != "panel_ready" or remaining() != 0: return
 stage = "complete"
 world.complete_demo()

func sync() -> void:
 visible = world.map_id == "main_entry"
 $Supply.visible = not supply_used
 $Device.set_active(stage not in ["unobserved", "ready"])
 panel.update_visuals()
 for drone in enemies():
  drone.sync_presence(visible, fighting() and not world.finished and not world.defeated)

func guidance() -> String:
 match stage:
  "unobserved": return "관측 단말을 E로 조사하세요 · 연구동 외곽 침식 확인"
  "ready": return "봉쇄 보급함을 회수한 뒤 중앙 봉쇄 장치에서 E · 봉쇄 장치 가동"
  "wave_one", "wave_two": return "봉쇄 전투 %d / 2 · 이번 무리 침식된 선원 %d명 제압" % [1 if stage == "wave_one" else 2, remaining()]
  "panel_ready":
   if world.npc_motion.mode == "wait": return "미카 대기 중 · Enter로 ‘따라와’ 전송 후 최종 봉쇄 패널 E 유지"
   return "최종 봉쇄 패널 · E 유지, 미카와 양쪽 1초 동시 작동 → 비프 확인"
 return "연구동 외곽 구역 봉쇄 성공"

func snapshot() -> Dictionary:
 var saved := {}
 for drone in enemies():
  saved[str(drone.name)] = {"hp": drone.hp, "position": [drone.position.x, drone.position.y], "attack_wait": drone.attack_wait}
 return {"stage": stage, "supply_used": supply_used, "panel": panel.snapshot(), "enemies": saved}

func initial_snapshot() -> Dictionary:
 var saved := {}
 for drone in enemies():
  saved[str(drone.name)] = {"hp": 0, "position": [1000, 400], "attack_wait": 0.0}
 return {"stage": "unobserved", "supply_used": false, "panel": {"opened": false, "supply_taken": false, "sequence_elapsed": -1.0, "beep_index": 0}, "enemies": saved}

func restore(data: Dictionary) -> void:
 reset()
 stage = data.stage
 supply_used = data.supply_used
 panel.restore(data.panel)
 for drone in enemies():
  var saved: Dictionary = data.enemies[str(drone.name)]
  drone.hp = int(saved.hp)
  drone.position = Vector2(saved.position[0], saved.position[1])
  drone.attack_wait = float(saved.attack_wait)

func configuration() -> Dictionary:
 return {"version": 1, "waves": [first_wave_count, second_wave_count], "panel_hold_seconds": panel.hold_seconds, "supply": "one_use_refill_initial_caps", "terrain": "drone_astar20_mask5_projectile7"}
