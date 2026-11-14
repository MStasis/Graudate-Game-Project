@tool
class_name MissionDrone
extends CharacterBody2D

signal hit_player(amount: int)
signal hit_companion(amount: int)
signal defeated
@export var max_hp: int = 50
@export var move_speed: float = 66.0
@export var contact_damage: int = 12
@export var attack_interval: float = 1.0
@export var show_placeholder_body := true
var hp := 50
var active := false
var target: DemoPlayer
var companion: Node2D
var companion_alive := false
var show_world_health := true
var attack_wait := 0.0
var mission: Node2D
var navigate_obstacles := false
var navigation := CompanionNavigation.new()
var _victim: Node2D
var _room_visible := false
var _death_hidden := false
var _melee_until_ms := 0.0
@onready var animation := get_node_or_null("Sprite2D") as SpriteTimeline

func _ready() -> void:
 if animation: animation.event_reached.connect(_on_animation_event)

func reset_enemy() -> void:
 hp = max_hp
 attack_wait = 0.8
 visible = true
 collision_layer = 2
 reset_animation()

func reset_animation() -> void:
 _victim = null
 _death_hidden = false
 _melee_until_ms = 0.0
 if animation: animation.hold("move", "down")

func sync_presence(in_room: bool, can_attack: bool) -> void:
 if _room_visible and not in_room: reset_animation()
 _room_visible = in_room
 var dying := animation and animation.clip == "death" and animation.playing and not _death_hidden
 visible = in_room and (hp > 0 or dying)
 active = in_room and hp > 0 and can_attack
 collision_layer = 2 if in_room and hp > 0 else 0

func take_damage(amount: int, contact := Vector2.INF) -> void:
 if hp <= 0: return
 hp = maxi(0, hp - amount)
 if animation:
  _victim = null
  _melee_until_ms = 0.0
  animation.start("hit" if hp > 0 else "death", animation.facing)
  if contact.is_finite():
   var spark := BulletImpact.new()
   spark.z_index = 2
   # Keep the spark independent of enemy visibility and its subsequent hit animations.
   var effects := mission.get_node("SupportFX") if mission else get_parent()
   spark.position = effects.to_local(contact)
   effects.add_child(spark)
 queue_redraw()
 if hp == 0:
  active = false
  if not animation: visible = false
  collision_layer = 0
  defeated.emit()

func _physics_process(delta: float) -> void:
 if animation and animation.playing and animation.clip == "death":
  animation.advance(delta * 1000.0)
  return
 if not active or hp <= 0 or not is_instance_valid(target):
  velocity = Vector2.ZERO
  return
 attack_wait -= delta
 if animation and animation.playing and animation.clip in ["attack", "hit"]:
  velocity = Vector2.ZERO
  animation.advance(delta * 1000.0)
  if _melee_until_ms > animation.elapsed_ms: _try_melee_hit()
  return
 var victim: Node2D = target
 if companion_alive and is_instance_valid(companion) and position.distance_squared_to(companion.position) < position.distance_squared_to(target.position): victim = companion
 var distance := position.distance_to(victim.position)
 var destination := navigation.waypoint(mission, victim.position, delta, self) if navigate_obstacles and mission else victim.position
 velocity = position.direction_to(destination) * move_speed if distance > 27.0 else Vector2.ZERO
 move_and_slide()
 if animation:
  var direction := SpriteTimeline.cardinal(velocity if velocity.length_squared() > 1.0 else position.direction_to(victim.position), animation.facing)
  if velocity.length_squared() <= 1.0: animation.hold("move", direction)
  else:
   if animation.clip != "move" or not animation.playing or direction != animation.facing: animation.start("move", direction)
   animation.advance(delta * 1000.0)
 var clear := true
 if navigate_obstacles and mission: clear = mission.clear_line(position, victim.position)
 if distance < 39.0 and attack_wait <= 0.0 and clear:
  attack_wait = attack_interval
  if animation:
   _victim = victim
   _melee_until_ms = 0.0
   animation.start("attack", SpriteTimeline.cardinal(position.direction_to(victim.position), animation.facing))
  else: _deal_damage(victim)

func _on_animation_event(event: Dictionary) -> void:
 if event.name == "fully_hidden":
  _death_hidden = true
  visible = false
 elif event.name == "melee_impact":
  _melee_until_ms = float(event.time_ms) + float(event.active_ms)
  _try_melee_hit()

func _try_melee_hit() -> void:
 if not active or not is_instance_valid(_victim): return
 if _victim == companion and not companion_alive: return
 if position.distance_to(_victim.position) < 39.0 and (not mission or mission.clear_line(position, _victim.position)):
  _deal_damage(_victim)
  _victim = null

func _deal_damage(victim: Node2D) -> void:
 if victim == companion: hit_companion.emit(contact_damage)
 else: hit_player.emit(contact_damage)

func _draw() -> void:
 if show_placeholder_body:
  draw_circle(Vector2.ZERO, 20, Color("253543"))
  draw_rect(Rect2(-17, -11, 34, 20), Color("d27366"))
  draw_circle(Vector2(0, -2), 6, Color("ffb46b"))
  draw_line(Vector2(-27, -14), Vector2(27, -14), Color("798d9e"), 4)
  draw_line(Vector2(-27, 14), Vector2(27, 14), Color("798d9e"), 4)
 if show_world_health and max_hp > 0 and hp > 0: draw_rect(Rect2(-20, 26, 40.0 * hp / max_hp, 3), Color("ef8b79"))
