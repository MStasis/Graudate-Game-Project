@tool
class_name IndustrialUIFrame
extends Control
## 개별 Control의 배경 장식. 글자·상태·입력은 부모의 표준 UI 노드가 담당한다.
@export_enum("dialogue", "field", "button", "objective", "prompt") var frame_kind := "dialogue"
@export var fill_top := Color("161c1f")
@export var fill_bottom := Color("090e11")
@export var rim_color := Color("65716b")
@export var accent_color := Color("cda66c")
var _button_state := ""

func _ready() -> void:
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 resized.connect(queue_redraw)
 var button := get_parent() as BaseButton
 set_process(button != null)
 if button:
  button.mouse_entered.connect(queue_redraw)
  button.mouse_exited.connect(queue_redraw)
  button.focus_entered.connect(queue_redraw)
  button.focus_exited.connect(queue_redraw)
  button.button_down.connect(queue_redraw)
  button.button_up.connect(queue_redraw)

func _process(_delta: float) -> void:
 var button := get_parent() as BaseButton
 if not button: return
 var state := str([button.disabled, button.is_pressed(), button.is_hovered(), button.has_focus()])
 if state != _button_state:
  _button_state = state
  queue_redraw()

func frame_geometry() -> Dictionary:
 var cut := 14.0 if frame_kind == "dialogue" else 7.0
 var w := maxf(size.x, cut * 2)
 var h := maxf(size.y, cut * 2)
 var points := PackedVector2Array([Vector2(cut, 0), Vector2(w - cut, 0), Vector2(w, cut), Vector2(w, h - cut), Vector2(w - cut, h), Vector2(cut, h), Vector2(0, h - cut), Vector2(0, cut)])
 var highlight := accent_color
 var top := fill_top
 var button := get_parent() as BaseButton
 if button:
  if button.disabled:
   highlight = Color("5c6158")
   top = Color("101517")
  elif button.is_pressed(): top = Color("34342a")
  elif button.is_hovered() or button.has_focus(): top = Color("29302d")
 var serial_points := []
 for point in points: serial_points.append([point.x, point.y])
 return {"points": serial_points, "top": top.to_html(), "bottom": fill_bottom.to_html(), "rim": rim_color.to_html(), "accent": highlight.to_html(), "kind": frame_kind}

func _draw() -> void:
 var data := frame_geometry()
 var points := PackedVector2Array()
 for point in data.points: points.append(Vector2(point[0], point[1]))
 var top := Color(data.top)
 var bottom := Color(data.bottom)
 var colors := PackedColorArray([top, top, top, bottom, bottom, bottom, bottom, top])
 draw_polygon(points, colors)
 var closed := points.duplicate()
 closed.append(points[0])
 draw_polyline(closed, rim_color, 2.0, false)
 var accent := Color(data.accent)
 draw_line(Vector2(14, 3), Vector2(size.x - 18, 3), Color(accent, 0.48), 1)
 draw_line(Vector2(14, size.y - 4), Vector2(size.x - 18, size.y - 4), Color(rim_color, 0.55), 1)
 if frame_kind == "dialogue":
  draw_line(Vector2(18, size.y - 1), Vector2(122, size.y - 1), accent, 2)
  draw_line(Vector2(size.x - 190, 1), Vector2(size.x - 112, 1), Color(accent, 0.75), 1)
  for p in [Vector2(12, 18), Vector2(size.x - 12, 18), Vector2(12, size.y - 18), Vector2(size.x - 12, size.y - 18)]:
   draw_circle(p, 3, Color("080c0e"))
   draw_arc(p, 2, 0, TAU, 8, rim_color, 1)
 elif frame_kind == "button":
  draw_line(Vector2(5, 11), Vector2(5, size.y - 11), Color(accent, 0.6), 2)
 elif frame_kind == "objective":
  var center := Vector2(24, size.y * 0.5)
  draw_polyline(PackedVector2Array([center + Vector2(0, -8), center + Vector2(8, 0), center + Vector2(0, 8), center + Vector2(-8, 0), center + Vector2(0, -8)]), accent, 2)

