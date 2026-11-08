class_name CompanionMotion
extends RefCounted
## 공통 이동 실행기. 모델은 매 프레임 위치를 만들지 않는다.
var velocity := Vector2.ZERO
var heading := Vector2.RIGHT
var elapsed := 0.0
var pattern := "동행"

func reset(direction := Vector2.RIGHT) -> void:
 velocity = Vector2.ZERO
 heading = direction
 elapsed = 0

func formation_target(world: Node2D, delta: float) -> Vector2:
 elapsed += delta
 var forward: Vector2 = world.player.facing_direction
 heading = heading.slerp(forward, 1.0 - exp(-5.0 * delta)).normalized()
 var lateral := heading.orthogonal()
 # 회차마다 같은 주기로 좌우/넓은 간격을 전환해 비교 조건을 유지한다.
 var phase := int(elapsed / 5.0) % 4
 var side := -1.0 if phase in [0, 3] else 1.0
 var target: Vector2 = world.player.position - heading * 105 + lateral * side * (85 if phase in [2, 3] else 62)
 pattern = "사선 후방 동행"
 var nearest: Node2D
 var best := INF
 if world.map_id == "storage":
  for enemy in world.get_node("Enemies").get_children():
   var distance: float = world.player.position.distance_squared_to(enemy.position)
   if enemy.hp > 0 and enemy.visible and distance < best:
    nearest = enemy
    best = distance
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
 return target.clamp(world.room_rect.position + Vector2(32, 32), world.room_rect.end - Vector2(32, 32))

func move_to(world: Node2D, target: Vector2, delta: float, arrival_radius := 8.0, scripted := false) -> void:
 var offset: Vector2 = target - world.npc.position
 var speed: float = world.npc_move_speed
 if not scripted and world.npc.position.distance_to(world.player.position) > 260: speed *= 1.25
 var desired := offset.normalized() * minf(speed, maxf(0, offset.length() - arrival_radius) * 5)
 velocity = velocity.move_toward(desired, 720 * delta)
 if offset.length() < arrival_radius and velocity.length() < 8: velocity = Vector2.ZERO
 world.npc.position += velocity * delta
 world.npc.position = world.npc.position.clamp(world.room_rect.position + Vector2(28, 28), world.room_rect.end - Vector2(28, 28))
