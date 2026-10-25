extends Node2D
func _process(_delta: float) -> void:
 queue_redraw()
func _draw() -> void:
 var world = get_parent()
 if world.cover_time > 0.0 and world.map_id == "storage":
  draw_circle(world.safe_position, world.cover_radius, Color(0.15, 0.8, 0.8, 0.18))
  draw_arc(world.safe_position, world.cover_radius, 0, TAU, 48, Color("6fffe3"), 3)
  draw_rect(Rect2(world.safe_position - Vector2(12, 12), Vector2(24, 24)), Color("6fbfb7"))
 if world.guide_time > 0.0 and world.map_id == "storage":
  draw_line(world.player.position, world.safe_position, Color("ffdc8b"), 3)
