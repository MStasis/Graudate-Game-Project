class_name MissionProjectile
extends Node2D
signal impacted(target: Object)
var direction := Vector2.RIGHT
var shooter: DemoPlayer
var lifetime := 1.4
var speed := 700.0

func _physics_process(delta: float) -> void:
 lifetime -= delta
 if lifetime <= 0.0: queue_free(); return
 var next := global_position + direction * speed * delta
 var query := PhysicsRayQueryParameters2D.create(global_position, next, 3)
 query.hit_from_inside = true
 if is_instance_valid(shooter): query.exclude = [shooter.get_rid()]
 var hit := get_world_2d().direct_space_state.intersect_ray(query)
 if not hit.is_empty():
  impacted.emit(hit.collider)
  queue_free()
 else: global_position = next

func _draw() -> void:
 draw_circle(Vector2.ZERO, 3, Color("ffe5ac"))
