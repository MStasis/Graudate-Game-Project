class_name ExplorationMap
extends Control
const COLUMNS := 32
const ROWS := 12
var world: DemoWorld
var explored := {}

func restore_exploration(data: Dictionary) -> void:
 explored.clear()
 for room in data:
  var cells := []
  for value in data[room]:
   var index := int(value)
   if index not in cells: cells.append(index)
  explored[room] = cells
 queue_redraw()

func remember_position() -> void:
 if not world: return
 if not explored.has(world.map_id): explored[world.map_id] = []
 var cells: Array = explored[world.map_id]
 var cell_size := world.room_rect.size / Vector2(COLUMNS, ROWS)
 for y in range(ROWS):
  for x in range(COLUMNS):
   var center := world.room_rect.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * cell_size
   var index := y * COLUMNS + x
   if world.visibility_at(center) > 0.12 and index not in cells: cells.append(index)
 queue_redraw()

func map_point(point: Vector2) -> Vector2:
 return Vector2(10, 32) + (point - world.room_rect.position) / world.room_rect.size * (size - Vector2(20, 42))

func _draw() -> void:
 draw_style_box(get_theme_stylebox("panel", "Panel"), Rect2(Vector2.ZERO, size))
 if not world: return
 var font := get_theme_default_font()
 draw_string(font, Vector2(10, 22), "보관 구역 · 탐색 기록" if world.map_id == "storage" else "연구실 · 탐색 기록", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("b4c9c4"))
 var cells: Array = explored.get(world.map_id, [])
 var cell_size := (size - Vector2(20, 42)) / Vector2(COLUMNS, ROWS)
 for y in range(ROWS):
  for x in range(COLUMNS):
   var visited := y * COLUMNS + x in cells
   var p := Vector2(10, 32) + Vector2(x, y) * cell_size
   draw_rect(Rect2(p, cell_size - Vector2(0.5, 0.5)), Color("4d726b") if visited else Color("111d25"))
 draw_circle(map_point(world.player.position), 4, Color("ffe1a0"))
