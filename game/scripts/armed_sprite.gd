@tool
class_name ArmedSprite
extends SpriteTimeline

signal fired(origin: Vector2, target: Vector2)

var _gait_ms := 0.0
var _shot_pose_ms := 0.0
var _shot_target := Vector2.ZERO
var _shot_pending := false
var _moving_shot := false
var _hit_after_shot := false

func _ready() -> void:
 super()
 event_reached.connect(_on_event)

func reset_animation() -> void:
 _gait_ms = 0.0
 _shot_pose_ms = 0.0
 _shot_pending = false
 _moving_shot = false
 _hit_after_shot = false
 hold("idle", "down")

func play_hit() -> void:
 if _shot_pending:
  _hit_after_shot = true
  return
 _moving_shot = false
 start("hit", facing)

func request_shot(target: Vector2, motion: Vector2) -> bool:
 if _shot_pending: return false
 _shot_target = target
 _shot_pending = true
 _moving_shot = not motion.is_zero_approx()
 if _moving_shot:
  var direction := cardinal(motion, facing)
  var moving: Dictionary = data.moving_fire
  var column := _gait_frame(direction)
  _shot_pose_ms = 0.0
  hold(moving.animation_names.fire, direction, column)
  _emit_shot(moving.muzzle_px_by_direction_and_column[direction][column])
 else:
  start("shoot", cardinal(target - global_position, facing))
 return true

func tick_actor(delta: float, motion: Vector2, aim: Vector2, aiming: bool) -> void:
 var milliseconds := delta * 1000.0
 var moving := motion.length_squared() > 1.0
 if moving: _gait_ms += milliseconds
 else: _gait_ms = 0.0
 if playing and clip in ["shoot", "hit"]:
  advance(milliseconds)
  if _hit_after_shot and not _shot_pending and frame_index > int(data.animations.shoot.events[0].frame):
   _hit_after_shot = false
   play_hit()
  if playing: return
 var direction := cardinal(motion if moving else aim, facing)
 var move_fire: Dictionary = data.moving_fire
 if _moving_shot:
  _shot_pose_ms += milliseconds
  var fire_ms := float(move_fire.fire_pose_ms)
  if _shot_pose_ms < fire_ms + float(move_fire.recoil_pose_ms):
   var animation: String = move_fire.animation_names.fire if _shot_pose_ms < fire_ms else move_fire.animation_names.recoil
   hold(animation, direction if moving else facing, _gait_frame(direction) if moving else frame_index)
   return
  _moving_shot = false
 if moving:
  hold(move_fire.animation_names.aim if aiming else "move", direction, _gait_frame(direction))
  return
 if clip != "idle" or not playing or facing != direction: start("idle", direction)
 advance(milliseconds)

func _gait_frame(direction: String) -> int:
 var times: Array = data.moving_fire.gait_ms_by_direction[direction]
 var cycle := 0.0
 for time in times: cycle += float(time)
 var phase := fposmod(_gait_ms, cycle)
 for index in times.size():
  phase -= float(times[index])
  if phase < 0: return index
 return times.size() - 1

func _on_event(event: Dictionary) -> void:
 if event.name == "fire" and _shot_pending:
  _emit_shot(data.animations.shoot.muzzle_px_by_direction[facing])

func _emit_shot(point: Array) -> void:
 _shot_pending = false
 fired.emit(muzzle(point), _shot_target)
