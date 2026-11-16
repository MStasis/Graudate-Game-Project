@tool
class_name DemoPlayer
extends CharacterBody2D
## World 씬에서 이 노드를 이동하면 해당 위치에서 시작하고 재시작합니다.

signal dash_finished

const SCRIPTED_WALK_SPEED := 72.0
const DASH_SPEED := 610.0
const DASH_DURATION := 0.22
const DASH_COOLDOWN := 1.1
const DASH_TRAIL_INTERVAL := 0.032
const DASH_TRAIL_LIFETIME := 0.30
const DASH_AFTERIMAGE := preload("res://assets/fleet_sprites/dash_afterimage.gdshader")

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
var scripted_target := Vector2.INF
var dash_remaining := 0.0
var dash_cooldown := 0.0
var _walk_navigation := CompanionNavigation.new()
var _dash_direction := Vector2.ZERO
var _trail_wait := 0.0
var _afterimage_material := ShaderMaterial.new()
@onready var animation := $Sprite2D as ArmedSprite

func _ready() -> void:
	_sync_visual()
	_afterimage_material.shader = DASH_AFTERIMAGE

func _sync_visual() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		sprite.self_modulate = body_color
		if not sprite is ArmedSprite: sprite.texture = character_texture

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	var mission := get_parent() as DemoWorld
	velocity = move_input()
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	if scripted_target.is_finite():
		velocity = _scripted_motion(mission, delta)
	elif movement_enabled and dash_remaining > 0.0:
		velocity = _dash_direction * DASH_SPEED
	if movement_enabled or scripted_target.is_finite():
		if velocity.length_squared() > 1: facing_direction = velocity.normalized()
		move_and_slide()
	if dash_remaining > 0.0:
		if not movement_enabled or dash_remaining <= delta:
			_end_dash()
		else:
			dash_remaining -= delta
			_trail_wait -= delta
			if _trail_wait <= 0.0:
				_leave_afterimage()
				_trail_wait += DASH_TRAIL_INTERVAL
	if not animation: return
	var aim := facing_direction
	if mission and mission.is_combat_area() and not (mission.use_fleet_demo and mission.fleet_demo.fixed_aim):
		aim = mission.mouse_aim_position() - position
	animation.tick_actor(delta, velocity, aim, mission != null and mission.is_combat_area())

func move_input() -> Vector2:
	if not movement_enabled: return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_up", "move_down") * move_speed

func walk_to(target: Vector2) -> void:
	_walk_navigation.reset()
	scripted_target = target
	_end_dash()

func _scripted_motion(mission: DemoWorld, delta: float) -> Vector2:
	var offset := scripted_target - position
	if offset.length() <= 2.0:
		scripted_target = Vector2.INF
		return Vector2.ZERO
	if test_move(global_transform, offset):
		offset = _walk_navigation.waypoint(mission, scripted_target, delta, self) - position
	return (offset / delta).limit_length(SCRIPTED_WALK_SPEED)

func start_dash() -> bool:
	if not movement_enabled or dash_cooldown > 0.0: return false
	var movement := move_input()
	_dash_direction = movement.normalized() if not movement.is_zero_approx() else facing_direction
	dash_remaining = DASH_DURATION
	dash_cooldown = DASH_COOLDOWN
	_trail_wait = DASH_TRAIL_INTERVAL
	_leave_afterimage()
	return true

func _leave_afterimage() -> void:
	var ghost := Sprite2D.new()
	ghost.texture = animation.texture
	ghost.region_enabled = true
	ghost.region_filter_clip_enabled = true
	ghost.region_rect = animation.region_rect
	ghost.centered = animation.centered
	ghost.offset = animation.offset
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ghost.material = _afterimage_material
	ghost.self_modulate = Color(0.27, 0.93, 1.0, 0.66) if get_child_count() % 2 == 0 else Color(0.71, 0.43, 1.0, 0.58)
	ghost.show_behind_parent = true
	ghost.top_level = true
	add_child(ghost)
	ghost.global_transform = animation.global_transform
	ghost.add_to_group("dash_afterimage")
	var fade := ghost.create_tween()
	fade.tween_property(ghost, "self_modulate:a", 0.0, DASH_TRAIL_LIFETIME).set_trans(Tween.TRANS_QUAD)
	fade.tween_callback(ghost.queue_free)

func reset_dash() -> void:
	_end_dash()
	dash_cooldown = 0.0
	for child in get_children():
		if child.is_in_group("dash_afterimage"):
			child.hide()
			child.queue_free()

func _end_dash() -> void:
	if dash_remaining <= 0.0: return
	dash_remaining = 0.0
	dash_finished.emit()

func show_reload(progress: float) -> void:
	$ReloadProgress.visible = progress >= 0.0
	$ReloadProgress.value = progress

