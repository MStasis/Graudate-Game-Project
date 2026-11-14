class_name SupportSentry
extends SpriteTimeline

signal fired(origin: Vector2, target: Vector2, damage: int)

const RAPID_DAMAGE := 6
const RAIL_DAMAGE := 30
const RAPID_RANGE := 150.0
const RANGE := 330.0
var target: Node2D
var _deployed := false

func _ready() -> void:
 super()
 event_reached.connect(_on_event)
 clip_finished.connect(_on_finished)
 stop_support()

func begin(restored := false) -> void:
 visible = true
 _deployed = restored
 if restored: _hold_state("turret_rapid_ready")
 else: start(data.states.drone_idle.clip, "down")

func stop_support() -> void:
 hide()
 target = null
 _deployed = false
 hold(data.states.drone_idle.clip, "down")

func _physics_process(delta: float) -> void:
 if not visible: return
 if not _deployed:
  advance(delta * 1000.0)
  if clip == data.states.drone_idle.clip and elapsed_ms >= float(durations(clip, facing)[0]):
   start("drone_scan", facing)
  return
 var have_target := is_instance_valid(target)
 var direction := cardinal(global_position.direction_to(target.global_position), facing) if have_target else facing
 var close := have_target and global_position.distance_to(target.global_position) <= RAPID_RANGE
 var transition: Dictionary = data.transitions.extend_rail
 var rail_ready: String = data.states.turret_rail_ready.clip
 if playing and clip == "rapid_fire":
  if not close: _hold_state("turret_rapid_ready")
  elif direction != facing: show_frame(clip, direction, frame_index)
 if not playing:
  if clip == rail_ready:
   if not have_target or close:
    var retract: Dictionary = data.transitions.retract_rail
    start(retract.clip, direction, retract.playback == "reverse")
   else: start(rail_ready, direction)
  elif have_target:
   start(data.states.turret_rapid_ready.clip if close else transition.clip, direction)
 advance(delta * 1000.0)

func _hold_state(state: String) -> void:
 var ready: Dictionary = data.states[state]
 hold(ready.clip, facing, int(ready.get("frame", 0)))

func _on_event(event: Dictionary) -> void:
 if event.name == "deployed":
  _deployed = true
  _hold_state(data.transitions.deploy.to)
 elif event.name == "fire" and is_instance_valid(target):
  if cardinal(global_position.direction_to(target.global_position), facing) != facing: return
  var damage := RAPID_DAMAGE if clip == data.states.turret_rapid_ready.clip else RAIL_DAMAGE
  fired.emit(muzzle(event.muzzle_px_by_direction[facing]), target.global_position, damage)

func _on_finished(animation: String) -> void:
 if animation == "drone_scan": start(data.transitions.deploy.clip, facing)
 elif animation == data.transitions.extend_rail.clip:
  _hold_state(data.transitions.retract_rail.to if frame_index == 0 else data.transitions.extend_rail.to)
