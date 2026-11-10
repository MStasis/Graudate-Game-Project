class_name CompanionNavigation
extends RefCounted
## 현재 방의 실제 발밑 충돌을 확장한 A* 격자. 물리 이동은 CharacterBody2D가 최종 제한한다.
const CELL := 20.0
const CLEARANCE := 14.0
var grid := AStarGrid2D.new()
var path := PackedVector2Array()
var destination := Vector2.INF
var map_key := ""
var repath_time := 0.0
var blocked_time := 0.0
var previous := Vector2.INF
var reachable := false
var replans := 0

func reset() -> void:
 map_key = ""
 path.clear()
 destination = Vector2.INF
 previous = Vector2.INF
 blocked_time = 0
 repath_time = 0

func rebuild(world: Node2D) -> void:
 grid.region = Rect2i(Vector2i.ZERO, Vector2i(world.room_rect.size / CELL))
 grid.cell_size = Vector2(CELL, CELL)
 grid.offset = world.room_rect.position + Vector2(CELL * 0.5, CELL * 0.5)
 grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
 grid.update()
 var obstacles := []
 for node in world.find_children("*", "StaticBody2D", true, false):
  if node is RoundedObstacle and node.is_visible_in_tree() and node.collision_layer != 0:
   var center: Vector2 = world.to_local(node.global_position)
   obstacles.append(Rect2(center - node.footprint * 0.5, node.footprint).grow(CLEARANCE))
 for x in grid.region.size.x:
  for y in grid.region.size.y:
   var id := Vector2i(x, y)
   var point := grid.get_point_position(id)
   var solid: bool = not world.room_rect.grow(-CLEARANCE).has_point(point)
   for rect: Rect2 in obstacles:
    if rect.has_point(point): solid = true; break
   grid.set_point_solid(id, solid)
 map_key = world.map_id

func cell(point: Vector2) -> Vector2i:
 return Vector2i((point - grid.offset) / CELL + Vector2(0.5, 0.5)).clamp(Vector2i.ZERO, grid.region.size - Vector2i.ONE)

func free_near(point: Vector2) -> Vector2i:
 var start := cell(point)
 if not grid.is_point_solid(start): return start
 var best := Vector2i(-1, -1)
 var distance := INF
 for x in grid.region.size.x:
  for y in grid.region.size.y:
   var id := Vector2i(x, y)
   if grid.is_point_solid(id): continue
   var next := point.distance_squared_to(grid.get_point_position(id))
   if next < distance: best = id; distance = next
 return best

func plan(world: Node2D, target: Vector2) -> void:
 if map_key != world.map_id: rebuild(world)
 destination = target
 var start := free_near(world.npc.position)
 var goal := free_near(target)
 path.clear()
 if start.x >= 0 and goal.x >= 0: path = grid.get_point_path(start, goal)
 reachable = not path.is_empty()
 if path.size() > 1: path.remove_at(0)
 repath_time = 0.7
 blocked_time = 0
 replans += 1

func waypoint(world: Node2D, target: Vector2, delta: float) -> Vector2:
 repath_time -= delta
 if previous.is_finite() and world.npc.position.distance_to(previous) < 0.2 and not path.is_empty(): blocked_time += delta
 else: blocked_time = 0
 previous = world.npc.position
 if map_key != world.map_id or not destination.is_finite() or destination.distance_to(target) > 34 or repath_time <= 0 or blocked_time > 0.35:
  # 막히면 실제 가구 위치/표시 상태를 다시 읽는다.
  if blocked_time > 0.35 or repath_time <= 0: map_key = ""
  plan(world, target)
 while path.size() > 1 and world.npc.position.distance_to(path[0]) < 9: path.remove_at(0)
 if path.is_empty(): return world.npc.position
 return path[0]
