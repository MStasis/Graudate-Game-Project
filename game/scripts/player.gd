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
var facing_direction := Vector2.RIGHT
@onready var animation := $Sprite2D as ArmedSprite

func _ready() -> void:
	_sync_visual()

func _sync_visual() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		sprite.self_modulate = body_color
		if not sprite is ArmedSprite: sprite.texture = character_texture

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	velocity = move_input()
	if movement_enabled:
		if velocity.length_squared() > 1: facing_direction = velocity.normalized()
		move_and_slide()
	if not animation: return
	var mission := get_parent() as DemoWorld
	var aim := facing_direction
	if mission and mission.is_combat_area() and not (mission.use_fleet_demo and mission.fleet_demo.fixed_aim):
		aim = mission.mouse_aim_position() - position
	animation.tick_actor(_delta, velocity, aim, mission != null and mission.is_combat_area())

func move_input() -> Vector2:
	if not movement_enabled: return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_up", "move_down") * move_speed

