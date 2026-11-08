class_name SpeechBubble
extends Panel
var full_text := ""
var speaker := ""
var remaining := 0.0
var direction := ""

func say(who: String, text: String, duration: float = 8.0) -> void:
 speaker = who
 full_text = text
 remaining = duration
 $Body.text = text
 var lines := clampi($Body.get_line_count(), 1, 3)
 size.y = 44 + lines * 26
 $Body.size.y = size.y - 40
 tooltip_text = who + ": " + text
 show()
 set_direction("")

func set_direction(value: String) -> void:
 direction = value
 $Speaker.text = speaker + ("  " + value if not value.is_empty() else "")
 queue_redraw()

func _draw() -> void:
 if not direction.is_empty(): return
 var center := size.x * 0.5
 draw_colored_polygon(PackedVector2Array([Vector2(center - 8, size.y - 1), Vector2(center + 8, size.y - 1), Vector2(center, size.y + 8)]), Color("95b3a5"))

func tick(delta: float) -> void:
 remaining = maxf(0, remaining - delta)
 visible = remaining > 0
