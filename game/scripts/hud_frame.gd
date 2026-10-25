@tool
extends Control
## 게임 입력을 가로채지 않는 편집 가능한 프레임 장식.
@export var playfield_rect := Rect2(64, 114, 1152, 446):
 set(value):
  playfield_rect = value
  queue_redraw()
@export var line_color := Color("36504f")
@export var accent_color := Color("74c6b6")

func _draw() -> void:
 draw_line(Vector2(28, 69), Vector2(1252, 69), line_color, 1)
 var r := playfield_rect
 for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
  var sx := 1.0 if corner.x == r.position.x else -1.0
  var sy := 1.0 if corner.y == r.position.y else -1.0
  draw_line(corner, corner + Vector2(sx * 22, 0), accent_color, 2)
  draw_line(corner, corner + Vector2(0, sy * 14), accent_color, 2)
 for x in range(72, 284, 9):
  draw_line(Vector2(x, 600), Vector2(x + 4, 596), line_color, 1)
 draw_line(Vector2(306, 598), Vector2(1240, 598), Color(line_color, 0.4), 1)
