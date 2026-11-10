@tool
class_name HarinActor
extends CharacterBody2D
## 본체는 공통 충돌 이동, 자식 Interaction은 기존 E 상호작용 영역.
@export var interaction_id := "npc"
@export var display_name := "정비사 하린"
@export var location_hint := "연구소"
@export_multiline var description := "연구소의 정비사. 플레이어와 서로 믿는 친한 동료다."
@export var base_color := Color.WHITE
@export var object_texture: Texture2D
var activated := false
var pose := "idle"
var pose_phase := 0.0

func set_active(value: bool) -> void:
 activated = value

func show_pose(value: String, aim: Vector2) -> void:
 pose = value
 set_meta("visual_aim", position + Vector2.DOWN * 80 if pose in ["support", "reload"] else aim)
 var sprite := $Sprite2D as Sprite2D
 sprite.self_modulate = Color("9de5c0") if pose == "support" else Color("8b929d") if pose == "down" else Color.WHITE
 sprite.scale = Vector2(1.0, 0.55) if pose == "down" else Vector2(0.92, 1.04) if pose == "support" else Vector2.ONE
 var labels := {"idle": "동행 대기", "move": "동행 이동", "aim": "표적 경계", "support": "지원 중", "wait": "위치 경계", "down": "전투 불능", "reload": "탄약 장전"}
 $NameLabel.text = display_name + " · " + str(labels.get(pose, pose))
 queue_redraw()

func _process(delta: float) -> void:
 if Engine.is_editor_hint(): return
 pose_phase += delta
 $Sprite2D.position.y = 10 + sin(pose_phase * 13) * 1.4 if pose == "move" else 10
 if pose == "move": queue_redraw()

func _draw() -> void:
 if pose == "support":
  draw_arc(Vector2.ZERO, 22, 0, TAU, 24, Color("94ebbd"), 2)
  draw_line(Vector2(-5, -22), Vector2(5, -22), Color("94ebbd"), 3)
 elif pose == "wait": draw_arc(Vector2.ZERO, 22, 0, TAU, 24, Color("e0c383"), 2)
 elif pose == "reload": draw_arc(Vector2.ZERO, 22, 0, PI * 1.5, 24, Color("a2d0ef"), 3)
 elif pose == "move":
  var step := sin(pose_phase * 13) * 3
  draw_line(Vector2(-7, 16 + step), Vector2(-7, 23 + step), Color("94b1c3"), 2)
  draw_line(Vector2(7, 16 - step), Vector2(7, 23 - step), Color("94b1c3"), 2)
 elif pose == "aim":
  var direction := position.direction_to(get_meta("visual_aim", position + Vector2.RIGHT))
  draw_arc(Vector2.ZERO, 24, direction.angle() - 0.22, direction.angle() + 0.22, 8, Color("e2ba78"), 2)
