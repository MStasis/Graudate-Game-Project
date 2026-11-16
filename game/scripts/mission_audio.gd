extends Node
## 게임 규칙을 바꾸지 않고 공통 임무 상태/이벤트를 재생한다.
const SHOT := preload("res://assets/audio/rifle_shot.wav")
const RELOAD := preload("res://assets/audio/rifle_reload.wav")
const DASH := preload("res://assets/audio/dash_phase.wav")
const SENTRY_BOLT := preload("res://assets/audio/rift_sentry_bolt.wav")
const SENTRY_LASER := preload("res://assets/audio/rift_sentry_laser.wav")
const HIT := preload("res://assets/temporary/kenney/audio/impactMetal_000.ogg")
const DOWN := preload("res://assets/temporary/kenney/audio/explosionCrunch_000.ogg")
const DOOR := preload("res://assets/temporary/kenney/audio/doorOpen_000.ogg")
const COMPLETE := preload("res://assets/temporary/kenney/audio/forceField_000.ogg")
const PANEL_BEEP := preload("res://assets/audio/panel_beep.wav")
const FLEET_SIREN := preload("res://assets/audio/fleet_warning_wail.wav")
var world: DemoWorld
var last_ammo := 0
var voices: Array[AudioStreamPlayer] = []
var next_voice := 0
var played_events := 0
var _warning_left := 0.0

func _ready() -> void:
 world = get_parent() as DemoWorld
 last_ammo = world.ammo
 for index in range(6):
  var voice := AudioStreamPlayer.new()
  voice.volume_db = -20
  add_child(voice)
  voices.append(voice)
 world.state_changed.connect(_state_changed)
 world.game_event.connect(_world_event)
 world.player.dash_finished.connect(_stop_stream.bind(DASH))
 world.room_changing.connect(_stop_sentry_sounds)

func _state_changed() -> void:
 if not world.use_fleet_demo and world.ammo < last_ammo and world.shoot_cd > 0.27: play(SHOT)
 last_ammo = world.ammo

func _world_event(event: Dictionary) -> void:
 match str(event.get("event", "")):
  "locker_beep": play(PANEL_BEEP)
  "anomaly_alarm":
   if world.use_fleet_demo: _play_warning()
   else: play(PANEL_BEEP)
  "fleet_radio": play(PANEL_BEEP)
  "fleet_levers_pulled":
   _stop_stream(FLEET_SIREN)
   play(COMPLETE)
  "locker_opened", "power_restored", "fleet_door_open": play(DOOR)
  "player_shot_fired", "npc_shot": play(SHOT)
  "player_reload_started": play(RELOAD)
  "fleet_dash_started": play(DASH, 0.0, DASH.get_length() / DemoPlayer.DASH_DURATION)
  "fleet_sentry_fired": play(SENTRY_BOLT)
  "fleet_sentry_laser_fired": play(SENTRY_LASER)
  "player_damage", "npc_damage": play(HIT)
  "enemy_defeated": play(DOWN)
  "trial_reset":
   last_ammo = world.ammo
   _stop_stream(FLEET_SIREN)
   _stop_stream(RELOAD)
   _stop_sentry_sounds()
   _warning_left = 0.0
  "save_loaded":
   last_ammo = world.ammo
   _stop_stream(FLEET_SIREN)
   _stop_stream(RELOAD)
   _stop_sentry_sounds()
   _warning_left = 0.0
   if world.reload_time > 0.0: play(RELOAD, world.RELOAD_SECONDS - world.reload_time)
  "mission_failed": _stop_stream(RELOAD)
  "mission_completed":
   for voice in voices: voice.stop()
   play(COMPLETE)
  "interaction":
   var kind := str(event.get("kind", ""))
   if kind in ["storage_gate", "lab_gate"]: play(DOOR)
   elif kind == "exit" and world.finished: play(COMPLETE)

func _process(delta: float) -> void:
 var warning := world.use_fleet_demo and not world.defeated and not world.finished and world.fleet_demo.alarm_active()
 warning = warning and world.map_id in ["power_room", "corridor"]
 if not warning:
  if _warning_left > 0.0: _stop_stream(FLEET_SIREN)
  _warning_left = 0.0
  return
 _warning_left -= delta
 if _warning_left <= 0.0: _play_warning()

func _play_warning() -> void:
 play(FLEET_SIREN)
 _warning_left = FLEET_SIREN.get_length() + 0.30

func _stop_stream(stream: AudioStream) -> void:
 for voice in voices:
  if voice.stream == stream:
   voice.stop()
   voice.stream = null

func _stop_sentry_sounds() -> void:
 _stop_stream(SENTRY_BOLT)
 _stop_stream(SENTRY_LASER)

func play(stream: AudioStream, from := 0.0, pitch := 1.0) -> void:
 if voices.is_empty() or from >= stream.get_length(): return
 var voice := voices[next_voice]
 next_voice = (next_voice + 1) % voices.size()
 voice.volume_db = -17 if stream == FLEET_SIREN else -12 if stream == PANEL_BEEP else -20
 if stream == SHOT: voice.volume_db = -11
 if stream == RELOAD: voice.volume_db = -15
 if stream == DASH: voice.volume_db = -14
 if stream == SENTRY_BOLT or stream == SENTRY_LASER: voice.volume_db = -12
 voice.pitch_scale = pitch
 voice.stream = stream
 # 헤드리스 검사는 이벤트와 리소스만 확인하고 오디오 장치를 사용하지 않는다.
 if DisplayServer.get_name() != "headless" and AudioServer.get_driver_name() != "Dummy": voice.play(from)
 played_events += 1

func _exit_tree() -> void:
 stop_all()

func stop_all() -> void:
 for voice in voices:
  if is_instance_valid(voice):
   voice.stop()
   voice.stream = null
 voices.clear()
