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
