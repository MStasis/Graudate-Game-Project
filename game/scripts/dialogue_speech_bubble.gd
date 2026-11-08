@tool
extends Control
@export var fill_color := Color("ddd8c5")
@export var border_color := Color("262c29")

func _ready() -> void:
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 resized.connect(queue_redraw)

func _draw() -> void:
 var body := Rect2(0, 0, size.x, size.y - 8)
 draw_rect(body, border_color)
 draw_rect(body.grow(-2), fill_color)
 draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.42 - 2, size.y - 10), Vector2(size.x * 0.42 - 2, size.y), Vector2(size.x * 0.42 + 10, size.y - 10)]), border_color)
 draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.42, size.y - 10), Vector2(size.x * 0.42, size.y - 4), Vector2(size.x * 0.42 + 6, size.y - 10)]), fill_color)

