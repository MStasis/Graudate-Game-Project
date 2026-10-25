@tool
class_name DemoPlayer
extends CharacterBody2D
## World 씬에서 이 노드를 이동하면 해당 위치에서 시작하고 재시작합니다.

@export_group("이동")
@export_range(30.0, 600.0, 5.0) var move_speed: float = 175.0
@export_range(20.0, 180.0, 2.0) var interaction_distance: float = 72.0
@export_group("외형")
@export var body_color: Color = Color("7398f1"):
	set(value):
		body_color = value
		_sync_visual()
@export var character_texture: Texture2D:
	set(value):
		character_texture = value
		_sync_visual()

var movement_enabled := true

func _ready() -> void:
	_sync_visual()

func _sync_visual() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		sprite.self_modulate = body_color
		sprite.texture = character_texture

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	if not movement_enabled:
		velocity = Vector2.ZERO
		return
	velocity = Input.get_vector("move_left", "move_right", "move_up", "move_down") * move_speed
	move_and_slide()

