class_name MissionProjectile
extends Node2D
signal impacted(target: Object)
var direction := Vector2.RIGHT
var shooter: CollisionObject2D
var lifetime := 1.4
var speed := 700.0
var hit_mask := 3
var contact_point := Vector2.ZERO

func _physics_process(delta: float) -> void:
 lifetime -= delta
 if lifetime <= 0.0: queue_free(); return
 var next := global_position + direction * speed * delta
 var query := PhysicsRayQueryParameters2D.create(global_position, next, hit_mask)
 query.hit_from_inside = true
 query.collide_with_areas = true
 if is_instance_valid(shooter): query.exclude = [shooter.get_rid()]
 var hit := get_world_2d().direct_space_state.intersect_ray(query)
 if not hit.is_empty():
  contact_point = hit.position
  impacted.emit(hit.collider)
  queue_free()
 else: global_position = next

func _draw() -> void:
 if get_child_count() == 0: draw_circle(Vector2.ZERO, 3, Color("ffe5ac"))
