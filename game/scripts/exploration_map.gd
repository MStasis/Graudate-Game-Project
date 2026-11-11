class_name ExplorationMap
extends Control
const COLUMNS := 32
const ROWS := 12
const ROOM_NAMES := {"lab": "연구실", "storage": "보관 구역", "main_entry": "연구동 진입실"}
var world: DemoWorld
var explored := {}
var known := {}
var rooms := {}
var source: ExplorationMap
var full_map := false

func restore_exploration(data: Dictionary) -> void:
 explored.clear()
 for room in data:
  var cells := []
  for value in data[room]:
   var index := int(value)
   if index >= 0 and index < COLUMNS * ROWS and index not in cells: cells.append(index)
  explored[room] = cells
 queue_redraw()

func restore_atlas(data: Dictionary) -> void:
 known = data.get("known", {}).duplicate(true)
 rooms = data.get("rooms", {}).duplicate(true)
 queue_redraw()

func snapshot() -> Dictionary:
 return {"known": known.duplicate(true), "rooms": rooms.duplicate(true)}

func remember_position() -> void:
 if not world: return
 var room := world.map_id
 if not explored.has(room): explored[room] = []
 if not known.has(room): known[room] = {}
 var bounds := world.room_rect
 var geometry := []
 for rect in world.obstruction_rects(): geometry.append([rect.position.x, rect.position.y, rect.size.x, rect.size.y])
 rooms[room] = {"bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y], "obstacles": geometry}
 var cells: Array = explored[room]
 var cell_size := bounds.size / Vector2(COLUMNS, ROWS)
 for y in range(ROWS):
  for x in range(COLUMNS):
   var index := y * COLUMNS + x
   var center := bounds.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * cell_size
   if index not in cells and world.visibility_at(center) > 0.12: cells.append(index)
 var current := {}
 for item in world.map_landmarks():
  current[item.id] = item
  var point := Vector2(item.position[0], item.position[1])
  if world.visibility_at(point) > 0.12: known[room][item.id] = item.duplicate(true)
 for id in known[room].keys():
  if not current.has(id): known[room].erase(id)
  elif id in ["generator", "anomaly_console", "exit", "storage_gate", "lab_gate", "containment_device", "containment_panel_a", "containment_panel_b"]: known[room][id]["active"] = current[id].active
 queue_redraw()

func mini_bounds() -> Rect2:
 var width := minf(720, world.room_rect.size.x)
 var extent := Vector2(width, minf(world.room_rect.size.y, width * (size.y - 42) / maxf(1, size.x - 20)))
 return Rect2((world.player.position - extent * 0.5).clamp(world.room_rect.position, world.room_rect.end - extent), extent)

func map_point(point: Vector2) -> Vector2:
 var bounds := mini_bounds()
 return project(point, bounds, terrain_area(bounds, Rect2(Vector2(10, 32), size - Vector2(20, 42))))

func terrain_area(bounds: Rect2, available: Rect2) -> Rect2:
 var scale_factor := minf(available.size.x / bounds.size.x, available.size.y / bounds.size.y)
 var extent := bounds.size * scale_factor
 return Rect2(available.position + (available.size - extent) * 0.5, extent)

func project(point: Vector2, bounds: Rect2, area: Rect2) -> Vector2:
 return area.position + (point - bounds.position) / bounds.size * area.size

func visible_companion(room: String) -> Vector2:
 if room == world.map_id and world.visibility_at(world.npc.position) > 0.12: return world.npc.position
 return Vector2.INF

func icon(point: Vector2, kind: String, active := false) -> void:
 var color := Color("92a9b0") if active else Color("e3b86d")
 match kind:
  "door": draw_rect(Rect2(point - Vector2(4, 5), Vector2(8, 10)), Color("87bfe4") if active else Color("7e8990"), false, 2)
  "objective": draw_colored_polygon(PackedVector2Array([point + Vector2(0, -5), point + Vector2(5, 0), point + Vector2(0, 5), point + Vector2(-5, 0)]), color)
  "supply":
   draw_line(point - Vector2(4, 0), point + Vector2(4, 0), Color("8cdda2"), 3)
   draw_line(point - Vector2(0, 4), point + Vector2(0, 4), Color("8cdda2"), 3)
  _: draw_rect(Rect2(point - Vector2(3, 3), Vector2(6, 6)), Color("d0a3dc"))

func draw_room(room: String, area: Rect2, bounds: Rect2) -> void:
 var data: Dictionary = rooms.get(room, {})
 if data.is_empty(): return
 area = terrain_area(bounds, area)
 var real_bounds := Rect2(data.bounds[0], data.bounds[1], data.bounds[2], data.bounds[3])
 var cell_size := real_bounds.size / Vector2(COLUMNS, ROWS)
 draw_rect(area, Color("101a23"))
 for value in explored.get(room, []):
  var cell := Rect2(real_bounds.position + Vector2(int(value) % COLUMNS, int(int(value) / COLUMNS)) * cell_size, cell_size)
  var clipped := cell.intersection(bounds)
  if not clipped.has_area(): continue
  var tile := Rect2(project(clipped.position, bounds, area), clipped.size / bounds.size * area.size)
  draw_rect(tile, Color("425e61"))
  for entry in data.obstacles:
   var obstacle := Rect2(entry[0], entry[1], entry[2], entry[3]).intersection(clipped)
   if obstacle.has_area(): draw_rect(Rect2(project(obstacle.position, bounds, area), obstacle.size / bounds.size * area.size), Color("9aabb1"))
  if int(value) / COLUMNS < 1: draw_line(tile.position, Vector2(tile.end.x, tile.position.y), Color("c1cbd0"), 2)
  if int(value) / COLUMNS >= ROWS - 1: draw_line(Vector2(tile.position.x, tile.end.y), tile.end, Color("c1cbd0"), 2)
  if int(value) % COLUMNS == 0: draw_line(tile.position, Vector2(tile.position.x, tile.end.y), Color("c1cbd0"), 2)
  if int(value) % COLUMNS == COLUMNS - 1: draw_line(Vector2(tile.end.x, tile.position.y), tile.end, Color("c1cbd0"), 2)
 for item in known.get(room, {}).values():
  var point := Vector2(item.position[0], item.position[1])
  if bounds.grow(-8).has_point(point): icon(project(point, bounds, area), item.kind, item.get("active", false))
 if room == world.map_id:
  if bounds.has_point(world.player.position):
   var p := project(world.player.position, bounds, area)
   draw_circle(p, 4, Color("ffe1a0"))
   draw_line(p, p + world.flashlight_direction() * 11, Color("ffe1a0"), 2)
  var companion := visible_companion(room)
  if companion.is_finite() and bounds.has_point(companion): draw_circle(project(companion, bounds, area), 4, Color("6ce3d6"))

func _draw() -> void:
 if source:
  explored = source.explored
  known = source.known
  rooms = source.rooms
 draw_style_box(get_theme_stylebox("panel", "Panel"), Rect2(Vector2.ZERO, size))
 if not world: return
 var font := get_theme_default_font()
 if not full_map:
  draw_string(font, Vector2(10, 22), ROOM_NAMES.get(world.map_id, world.map_id) + " · M 지도", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("c2d5d0"))
  draw_room(world.map_id, Rect2(Vector2(10, 32), size - Vector2(20, 42)), mini_bounds())
  return
 draw_string(font, Vector2(12, 22), "발견 지도 · 위치 미확인 목표는 좌표를 표시하지 않음", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("d0e3dd"))
 var found := []
 for room in ["lab", "storage", "main_entry"]:
  if rooms.has(room): found.append(room)
 var height := minf(180, (size.y - 100) / maxf(1, found.size()))
 var centers := {}
 for index in range(found.size()):
  var room: String = found[index]
  var data: Dictionary = rooms[room]
  var bounds := Rect2(data.bounds[0], data.bounds[1], data.bounds[2], data.bounds[3])
  var area := Rect2(20, 48 + index * height, size.x - 220, height - 28)
  draw_string(font, Vector2(area.end.x + 12, area.position.y + 20), ROOM_NAMES[room], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("c2d5d0"))
  var route_line := 0
  for item in known.get(room, {}).values():
   if item.kind != "door": continue
   var destination: String = item.get("destination", "")
   if destination.is_empty(): continue
   var route: String = "→ " + str(ROOM_NAMES.get(destination, destination) if rooms.has(destination) else "미탐색 통로")
   route += " · 통행" if item.active else " · 잠김"
   draw_string(font, Vector2(area.end.x + 12, area.position.y + 42 + route_line * 18), route, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("87bfe4") if item.active else Color("7e8990"))
   route_line += 1
  draw_room(room, area, bounds)
  centers[room] = Vector2(size.x - 38, area.get_center().y)
 for room in found:
  for item in known.get(room, {}).values():
   var destination: String = item.get("destination", "")
   if centers.has(destination): draw_line(centers[room], centers[destination], Color("87bfe4") if item.active else Color("7e8990"), 2)
 draw_string(font, Vector2(12, size.y - 48), "● 플레이어(노랑) / 하린(청록·현재 시야)   □ 문   ◆ 목표   + 물자   ■ 장치", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("d0e3dd"))
 draw_string(font, Vector2(12, size.y - 22), world.current_guidance().left(68), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("e3b86d"))
