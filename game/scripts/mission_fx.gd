extends Node2D
func _process(_delta: float) -> void:
 queue_redraw()
func _draw() -> void:
 var world = get_parent()
 if world.cover_time > 0.0 and world.is_combat_area():
  draw_circle(world.safe_position, world.cover_radius, Color(0.15, 0.8, 0.8, 0.18))
  draw_arc(world.safe_position, world.cover_radius, 0, TAU, 48, Color("6fffe3"), 3)
 if world.guide_time > 0.0 and world.is_combat_area():
  draw_line(world.player.position, world.safe_position, Color("ffdc8b"), 3)
