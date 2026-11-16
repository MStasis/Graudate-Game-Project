extends MissionDrone
## The sentry alternates two tracking bolts with a charged laser.

const BOLT_SHEET := preload("res://assets/fleet_sprites/devices/rift_turret/rift_turret_projectile.png")
const BOLT_SCENE := preload("res://scenes/Projectile.tscn")
const RANGE := 560.0
const BOLT_SPEED := 720.0
const BOLTS_PER_LASER := 2
const PRE_LASER_PAUSE := 0.54
const LASER_CHARGE := 0.92
const LASER_TRACK_SECONDS := 0.32
const LASER_FLASH := 0.22
const LASER_RECOVERY := 1.20
const LASER_WIDTH := 28.0
const LASER_DAMAGE := 32
const WORLD_HIT_MASK := 5

var bolts_fired := 0
var _tracking_bolt := false
var _laser_left := 0.0
var _beam_left := 0.0
var _aim_direction := Vector2.RIGHT
var _laser_end := Vector2.ZERO
var _bolt_frames := SpriteFrames.new()
@onready var _visual: SpriteTimeline = $Visual

func _ready() -> void:
 super()
 _visual.event_reached.connect(_on_fire)
 _visual.clip_finished.connect(func(_clip): _visual.hold("idle", _visual.facing))
 var data: Dictionary = _visual.data.projectile
 var cell := SpriteTimeline.pixel(data.cell_px)
 var times: Array = data.frame_durations_ms
 for row in data.direction_rows.size():
  var direction: String = data.direction_rows[row]
  _bolt_frames.add_animation(direction)
  _bolt_frames.set_animation_speed(direction, 1000.0 / float(times[0]))
  _bolt_frames.set_animation_loop(direction, data.loop)
  for column in int(data.frame_count):
   var frame_texture := AtlasTexture.new()
   frame_texture.atlas = BOLT_SHEET
   frame_texture.region = Rect2(Vector2(column, row) * cell, cell)
   _bolt_frames.add_frame(direction, frame_texture, float(times[column]) / float(times[0]))

func reset_animation() -> void:
 super()
 bolts_fired = 0
 _clear_attack("down")

func face_spawn(direction: String) -> void:
 _visual.hold("idle", direction)

func sync_presence(in_room: bool, can_attack: bool) -> void:
 var was_active := active
 super(in_room, can_attack)
 if was_active and not active and (not in_room or _beam_left == 0.0):
  _clear_attack(_visual.facing)

func _clear_attack(facing: String) -> void:
 _tracking_bolt = false
 _laser_left = 0.0
 _beam_left = 0.0
 if is_instance_valid(_visual): _visual.hold("idle", facing)
 queue_redraw()

func _physics_process(delta: float) -> void:
 if Engine.is_editor_hint(): return
 if active: attack_wait = maxf(0.0, attack_wait - delta)
 if _beam_left > 0.0:
  _beam_left = maxf(0.0, _beam_left - delta)
  if _beam_left == 0.0: _visual.hold("idle", _visual.facing)
  queue_redraw()
  return
 if not active or not is_instance_valid(target): return
 if _laser_left > 0.0:
  _tick_charge(delta)
  return
 var direction := global_position.direction_to(target.global_position)
 var facing := SpriteTimeline.cardinal(direction, _visual.facing)
 if _visual.playing:
  if _tracking_bolt and facing != _visual.facing:
   _visual.show_frame("shoot", facing, _visual.frame_index)
  _visual.advance(delta * 1000.0)
  return
 if facing != _visual.facing: _visual.hold("idle", facing)
 if attack_wait > 0.0 or position.distance_to(target.position) > RANGE: return
 if not mission.clear_line(position, target.position): return
 if bolts_fired >= BOLTS_PER_LASER:
  _laser_left = LASER_CHARGE
  _aim_laser()
  _visual.hold("shoot", facing)
  mission._event("fleet_sentry_laser_charged", {"id": name})
  queue_redraw()
  return
 attack_wait = attack_interval
 _tracking_bolt = true
 _visual.start("shoot", facing)
 mission._event("fleet_sentry_charged", {"id": name})

func _on_fire(event: Dictionary) -> void:
 if event.name != "fire" or not _tracking_bolt or not active: return
 _tracking_bolt = false
 var shot_direction := global_position.direction_to(target.global_position)
 if shot_direction.is_zero_approx(): shot_direction = Vector2.RIGHT
 bolts_fired += 1
 if bolts_fired == BOLTS_PER_LASER: attack_wait = PRE_LASER_PAUSE
 var shot := BOLT_SCENE.instantiate() as MissionProjectile
 var projectiles: Node2D = mission.get_node("Projectiles")
 shot.position = projectiles.to_local(global_position)
 shot.direction = shot_direction
 shot.hit_mask = WORLD_HIT_MASK
 shot.shooter = self
 shot.speed = BOLT_SPEED
 shot.lifetime = _room_span() / BOLT_SPEED
 var sprite := AnimatedSprite2D.new()
 sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
 sprite.sprite_frames = _bolt_frames
 var muzzle: Array = _visual.data.animations.shoot.muzzle_px_by_direction_and_frame[_visual.facing][int(event.frame)]
 sprite.position = _visual.muzzle(muzzle) - global_position
 sprite.play(_visual.facing)
 shot.add_child(sprite)
 shot.impacted.connect(func(collider):
  if collider == target: hit_player.emit(contact_damage))
 projectiles.add_child(shot)
 shot.create_tween().tween_property(sprite, "position", Vector2(0, -14), 0.12)
 mission._event("fleet_sentry_fired", {"id": name})

func _room_span() -> float:
 var bounds: Rect2 = mission.room_rect
 return bounds.size.length() + 16.0

func _aim_laser() -> void:
 var direction := global_position.direction_to(target.global_position)
 if not direction.is_zero_approx(): _aim_direction = direction
 _laser_end = _laser_wall_end()

func _laser_wall_end() -> Vector2:
 var end := global_position + _aim_direction * _room_span()
 var hit := _cover_between(global_position, end)
 return to_local(hit.get("position", end))

func _cover_between(start: Vector2, end: Vector2) -> Dictionary:
 var query := PhysicsRayQueryParameters2D.create(start, end, WORLD_HIT_MASK, [target.get_rid()])
 query.hit_from_inside = true
 return get_world_2d().direct_space_state.intersect_ray(query)

func _tick_charge(delta: float) -> void:
 if _laser_left > LASER_CHARGE - LASER_TRACK_SECONDS: _aim_laser()
 _laser_left = maxf(0.0, _laser_left - delta)
 if _laser_left == 0.0:
  _fire_laser()
 else:
  var progress := 1.0 - _laser_left / LASER_CHARGE
  _visual.hold("shoot", SpriteTimeline.cardinal(_aim_direction), mini(2, int(progress * 3.0)))
 queue_redraw()

func _fire_laser() -> void:
 _laser_end = _laser_wall_end()
 bolts_fired = 0
 attack_wait = LASER_RECOVERY
 _beam_left = LASER_FLASH
 _visual.hold("shoot", SpriteTimeline.cardinal(_aim_direction), 3)
 mission._event("fleet_sentry_laser_fired", {"id": name})
 var player_offset := to_local(target.global_position)
 var distance_along := player_offset.dot(_aim_direction)
 if distance_along < 0.0 or distance_along > _laser_end.length(): return
 var player_shape := target.get_node("CollisionShape2D").shape as CircleShape2D
 var reach := LASER_WIDTH * 0.5 + player_shape.radius
 if absf(player_offset.cross(_aim_direction)) > reach: return
 if _cover_between(global_position, target.global_position).is_empty(): hit_player.emit(LASER_DAMAGE)

func _draw() -> void:
 super()
 if active and _laser_left > 0.0:
  var progress := 1.0 - _laser_left / LASER_CHARGE
  var edge := Color(1.0, 0.53, 0.32, 0.38).lerp(Color(1.0, 0.07, 0.14, 0.94), progress)
  draw_line(Vector2.ZERO, _laser_end, Color(edge, 0.13 + 0.21 * progress), LASER_WIDTH, true)
  var side := _aim_direction.orthogonal() * LASER_WIDTH * 0.5
  draw_line(side, _laser_end + side, edge, 2.0, true)
  draw_line(-side, _laser_end - side, edge, 2.0, true)
  draw_dashed_line(Vector2.ZERO, _laser_end, edge, 1.5, 12.0)
 elif _beam_left > 0.0:
  var fade := _beam_left / LASER_FLASH
  draw_line(Vector2.ZERO, _laser_end, Color(1.0, 0.04, 0.15, 0.40 * fade), LASER_WIDTH + 16.0, true)
  draw_line(Vector2.ZERO, _laser_end, Color(1.0, 0.08, 0.19, fade), LASER_WIDTH, true)
  draw_line(Vector2.ZERO, _laser_end, Color(1.0, 0.89, 0.83, fade), 8.0 * fade, true)
