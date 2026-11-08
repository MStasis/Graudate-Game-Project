@tool
extends Control
var spinning := false
var completed_turns := 0

func _ready() -> void:
 pivot_offset = size * 0.5
 mouse_entered.connect(spin)

func spin() -> void:
 if spinning or Engine.is_editor_hint(): return
 spinning = true
 rotation = 0
 var tween := create_tween()
 tween.tween_property(self, "rotation", TAU, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
 tween.tween_callback(func():
  rotation = 0
  spinning = false
  completed_turns += 1)

func _draw() -> void:
 var center := size * 0.5
 var points := PackedVector2Array()
 for index in range(48):
  var angle := TAU * index / 48.0
  var radius := 41.0 if index % 4 in [1, 2] else 33.0
  points.append(center + Vector2.from_angle(angle) * radius)
 draw_colored_polygon(points, Color("c3a56e"))
 draw_circle(center, 23, Color("283738"))
 draw_arc(center, 22, 0, TAU, 40, Color("738c85"), 3)
 draw_circle(center, 10, Color("111d21"))
