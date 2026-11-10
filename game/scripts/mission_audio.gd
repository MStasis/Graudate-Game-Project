extends Node
## 게임 규칙을 바꾸지 않고 공통 임무 상태/이벤트를 재생한다.
const SHOT := preload("res://assets/temporary/kenney/audio/laserSmall_000.ogg")
const NPC_SHOT := preload("res://assets/temporary/kenney/audio/laserSmall_001.ogg")
const HIT := preload("res://assets/temporary/kenney/audio/impactMetal_000.ogg")
const DOWN := preload("res://assets/temporary/kenney/audio/explosionCrunch_000.ogg")
const DOOR := preload("res://assets/temporary/kenney/audio/doorOpen_000.ogg")
const COMPLETE := preload("res://assets/temporary/kenney/audio/forceField_000.ogg")
const PANEL_BEEP := preload("res://assets/audio/panel_beep.wav")
var world: DemoWorld
var last_ammo := 0
var voices: Array[AudioStreamPlayer] = []
var next_voice := 0
var played_events := 0

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

func _state_changed() -> void:
 if world.ammo < last_ammo and world.shoot_cd > 0.27: play(SHOT)
 last_ammo = world.ammo

func _world_event(event: Dictionary) -> void:
 match str(event.get("event", "")):
  "locker_beep": play(PANEL_BEEP)
  "anomaly_alarm": play(PANEL_BEEP)
  "locker_opened", "power_restored": play(DOOR)
  "npc_shot": play(NPC_SHOT)
  "player_damage", "npc_damage": play(HIT)
  "enemy_defeated": play(DOWN)
  "trial_reset": last_ammo = world.ammo
  "interaction":
   var kind := str(event.get("kind", ""))
   if kind in ["storage_gate", "lab_gate"]: play(DOOR)
   elif kind == "exit" and world.finished: play(COMPLETE)

func play(stream: AudioStream) -> void:
 if voices.is_empty(): return
 var voice := voices[next_voice]
 next_voice = (next_voice + 1) % voices.size()
 voice.volume_db = -12 if stream == PANEL_BEEP else -20
 voice.stream = stream
 # 헤드리스 검사는 이벤트와 리소스만 확인하고 오디오 장치를 사용하지 않는다.
 if DisplayServer.get_name() != "headless": voice.play()
 played_events += 1

func _exit_tree() -> void:
 stop_all()

func stop_all() -> void:
 for voice in voices:
  if is_instance_valid(voice):
   voice.stop()
   voice.stream = null
 voices.clear()
