class_name CompanionMotion
extends RefCounted
## 공통 이동 실행기. 모델은 매 프레임 위치를 만들지 않는다.
var velocity := Vector2.ZERO
var heading := Vector2.RIGHT
var elapsed := 0.0
var pattern := "동행"
var mode := "follow"
var wait_position := Vector2.ZERO
var side := -1.0
var held_target := Vector2.INF
var target_hold := 0.0
var arrived := false
var last_move_target := Vector2.INF

func reset(direction := Vector2.RIGHT) -> void:
 velocity = Vector2.ZERO
 heading = direction
 elapsed = 0
 mode = "follow"
 side = -1.0
 held_target = Vector2.INF
 target_hold = 0
 arrived = false
 last_move_target = Vector2.INF

func order(value: String, position: Vector2) -> void:
 mode = value
 wait_position = position
 held_target = Vector2.INF
 arrived = false
 velocity = Vector2.ZERO

func formation_target(world: Node2D, delta: float) -> Vector2:
 elapsed += delta
 if mode == "wait":
  pattern = "지정 위치 경계 · 따라와 명령까지"
  return wait_position
 var forward: Vector2 = world.player.facing_direction
 heading = heading.slerp(forward, 1.0 - exp(-5.0 * delta)).normalized()
 var lateral := heading.orthogonal()
 var target: Vector2 = world.player.position - heading * 105 + lateral * side * 62
 pattern = "사선 후방 동행"
 var nearest: Node2D = world.combat_target()
 if nearest:
  var combat_forward: Vector2 = world.player.position.direction_to(nearest.position)
  lateral = combat_forward.orthogonal()
  target = world.player.position - combat_forward * 95 + lateral * side * 88
  pattern = "좌우 사선 엄호"
  if world.npc_role == 1:
   target = world.player.position - combat_forward * 50 + lateral * side * 110
   pattern = "측면 지원"
  elif world.npc_role == 2:
   target = world.player.position + combat_forward * 95 + lateral * side * 56
   pattern = "선행 경계"
  var away: Vector2 = world.npc.position - nearest.position
  if away.length() < 85:
   target += away.normalized() * 100
   pattern = "위협에서 간격 벌리기"
 elif world.npc_role == 2:
  target = world.player.position + heading * 100 + lateral * side * 60
  pattern = "선행 이동"
 var separation: Vector2 = world.npc.position - world.player.position
 if separation.length() < 58:
  target += (separation.normalized() if separation.length() > 1 else lateral) * 75
  pattern = "플레이어 길 비켜주기"
 if world.npc.position.distance_to(world.player.position) > 260: pattern = "따라잡기"
 target = target.clamp(world.room_rect.position + Vector2(32, 32), world.room_rect.end - Vector2(32, 32))
 target_hold = maxf(0, target_hold - delta)
 # 작은 변화는 무시하고 큰 이동/위협 회피는 즉시 반영한다.
 if not held_target.is_finite() or target.distance_to(held_target) > 100 or (target_hold <= 0 and target.distance_to(held_target) > 36):
  held_target = target
  target_hold = 0.8
 return held_target

func move_to(world: Node2D, target: Vector2, delta: float, arrival_radius := 8.0, scripted := false) -> void:
 var offset: Vector2 = target - world.npc.position
 if not last_move_target.is_finite() or last_move_target.distance_to(target) > 30:
  arrived = false
 last_move_target = target
 if offset.length() <= arrival_radius + 3: arrived = true
 elif offset.length() > arrival_radius + 24: arrived = false
 var speed: float = world.npc_move_speed
 if not scripted and world.npc.position.distance_to(world.player.position) > 260: speed *= 1.25
 var waypoint: Vector2 = world.npc_navigation.waypoint(world, target, delta)
 var steering: Vector2 = waypoint - world.npc.position
 var desired := steering.normalized() * minf(speed, maxf(0, offset.length() - arrival_radius) * 5)
 if arrived: desired = Vector2.ZERO
 velocity = velocity.move_toward(desired, 720 * delta)
 if offset.length() < arrival_radius and velocity.length() < 8: velocity = Vector2.ZERO
 world.npc.velocity = velocity
 world.npc.move_and_slide()
 velocity = world.npc.velocity
