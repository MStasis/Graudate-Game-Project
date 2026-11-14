@tool
class_name RoundedObstacle
extends StaticBody2D
## 발밑 충돌 전용(레이어 3). 숨겨진 방의 가구는 충돌하지 않는다.
@export var footprint := Vector2(64, 48):
 set(value):
  footprint = value.max(Vector2(2, 2))
  if is_node_ready(): _rebuild()
@export_range(1.0, 32.0, 1.0) var corner_radius := 10.0:
 set(value):
  corner_radius = value
  if is_node_ready(): _rebuild()

func fit_rect(rect: Rect2) -> void:
 position = rect.get_center()
 footprint = rect.size

func _ready() -> void:
 collision_mask = 0
 visibility_changed.connect(_sync_collision)
 _rebuild()
 _sync_collision()

func _sync_collision() -> void:
 # CanvasItem의 숨김만으로 물리 충돌이 사라지지는 않는다.
 collision_layer = 4 if is_visible_in_tree() else 0

func _rebuild() -> void:
 var collider := get_node_or_null("Footprint") as CollisionShape2D
 if not collider:
  collider = CollisionShape2D.new()
  collider.name = "Footprint"
  add_child(collider)
 var half := footprint * 0.5
 # Keep adjacent corner endpoints distinct on narrow objects such as touch panels.
 var radius := minf(corner_radius, minf(half.x, half.y) - 0.25)
 var centers := [Vector2(half.x - radius, half.y - radius), Vector2(-half.x + radius, half.y - radius), Vector2(-half.x + radius, -half.y + radius), Vector2(half.x - radius, -half.y + radius)]
 var points := PackedVector2Array()
 for corner in range(4):
  for step in range(7):
   var angle := (corner + step / 6.0) * PI * 0.5
   points.append(centers[corner] + Vector2.from_angle(angle) * radius)
 var shape := ConvexPolygonShape2D.new()
 shape.points = points
 collider.shape = shape
