@tool
class_name MissionDrone
extends CharacterBody2D

signal hit_player(amount: int)
signal defeated
@export var max_hp: int = 50
@export var move_speed: float = 66.0
@export var contact_damage: int = 12
@export var attack_interval: float = 1.0
var hp := 50
var active := false
var target: DemoPlayer
var attack_wait := 0.0

func reset_enemy() -> void:
 hp = max_hp
 attack_wait = 0.8
 visible = true
 collision_layer = 2

func take_damage(amount: int) -> void:
 if hp <= 0: return
 hp = maxi(0, hp - amount)
 queue_redraw()
 if hp == 0:
  active = false
  visible = false
  collision_layer = 0
  defeated.emit()

func _physics_process(delta: float) -> void:
 if not active or hp <= 0 or not is_instance_valid(target):
  velocity = Vector2.ZERO
  return
 var distance := position.distance_to(target.position)
 velocity = position.direction_to(target.position) * move_speed if distance > 27.0 else Vector2.ZERO
 move_and_slide()
 attack_wait -= delta
 if distance < 39.0 and attack_wait <= 0.0:
  attack_wait = attack_interval
  hit_player.emit(contact_damage)

func _draw() -> void:
 draw_circle(Vector2.ZERO, 20, Color("253543"))
 draw_rect(Rect2(-17, -11, 34, 20), Color("d27366"))
 draw_circle(Vector2(0, -2), 6, Color("ffb46b"))
 draw_line(Vector2(-27, -14), Vector2(27, -14), Color("798d9e"), 4)
 draw_line(Vector2(-27, 14), Vector2(27, 14), Color("798d9e"), 4)
 if max_hp > 0: draw_rect(Rect2(-20, -28, 40.0 * hp / max_hp, 3), Color("ef8b79"))
