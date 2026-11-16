class_name CombatInterface
extends Control
signal npc_line_shown(text: String)
const STATUS := preload("res://scenes/ui/ActorStatus.tscn")
const HUDView := preload("res://scripts/bulkhead_hud.gd")
const DialogueReview := preload("res://scripts/bulkhead_dialogue_review.gd")
var app: Control
var statuses: Array[ActorStatus] = []
var transcript: Array[String] = []
var speech_queue: Array[Dictionary] = []
var speech_priority := 0
var current_speech_guard := ""
var _speech_caption := false
var last_said := {}
var journal := MessageJournal.new()
@onready var hud: HUDView = $HUD
@onready var history: DialogueReview = $HistoryPanel
@onready var minimap: ExplorationMap = hud.minimap
@onready var npc_bubble: SpeechBubble = $NPCSpeech
@onready var player_bubble: SpeechBubble = $PlayerSpeech
@onready var system_notices: SystemNotifications = $SystemNotices

func setup(main: Control) -> void:
 app = main
 hud.bind_minimap(app.world)
 $FullMapPanel/Map.world = app.world
 $FullMapPanel/Map.source = minimap
 $FullMapPanel/Map.full_map = true
 for target in [app.world.npc] + app.world.all_enemies():
  var status := STATUS.instantiate() as ActorStatus
  status.target = target
  status.actor_kind = "npc" if target == app.world.npc else "enemy"
  $ActorLayer.add_child(status)
  statuses.append(status)
  if target is MissionDrone:
   target.show_world_health = false
   target.queue_redraw()
 hud.review_requested.connect(toggle_history)
 history.close_requested.connect(close_modal)
 $FullMapPanel/Close.pressed.connect(toggle_map)
 app.resized.connect(layout)
 layout()

func layout() -> void:
 if not app: return
 size = app.size
 system_notices.position = Vector2(app.size.x - 350, 104)
 system_notices.size.x = 328
 $Pending.position = Vector2(app.size.x - 174, 70)
 $Pending.size = Vector2(152, 24)
 $FullMapPanel.position = Vector2(24, 76)
 $FullMapPanel.size = app.size - Vector2(48, 110)
 $FullMapPanel/Map.position = Vector2(16, 58)
 $FullMapPanel/Map.size = $FullMapPanel.size - Vector2(32, 74)
 $FullMapPanel/Close.position = Vector2($FullMapPanel.size.x - 230, 8)
 $FullMapPanel/Close.size = Vector2(214, 40)

func modal_open() -> bool:
 return history.visible or $FullMapPanel.visible

func toggle_history() -> void:
 if history.visible:
  close_modal()
  return
 if app.world.finished or app.world.transition_active() or get_tree().paused or app.get_node("%DebugPanel").visible: return
 if app.question.has_focus() or app.question.is_composing(): return
 if app.world.use_fleet_demo and app.world.fleet_demo.locks_movement() and not app.world.fleet_demo.voice_active: return
 $FullMapPanel.hide()
 history.open(journal.entries)
 hud.hide()
 get_tree().paused = true
 app._sync_dialogue_presentation()

func toggle_map() -> void:
 if app.world.finished: return
 if app.world.use_fleet_demo and app.world.fleet_demo.locks_movement() and not $FullMapPanel.visible: return
 app.question.finish_editing()
 if history.visible: close_modal()
 $FullMapPanel.visible = not $FullMapPanel.visible
 $FullMapPanel/Map.queue_redraw()
 app._sync_input_mode()

func close_modal() -> void:
 if history.visible:
  history.hide()
  hud.show()
  get_tree().paused = false
 $FullMapPanel.hide()
 app._sync_dialogue_presentation()

func record(who: String, channel: String, message: String, message_id := "") -> bool:
 var added := journal.append(who, channel, message, app.world.map_id, str(app.brain.trial), message_id)
 if added or channel == "system": history.refresh(channel)
 return added

func restore_journal(data: Array) -> void:
 journal.restore(data)

func reset() -> void:
 minimap.explored.clear()
 minimap.known.clear()
 minimap.rooms.clear()
 clear_speech()
 transcript.clear()
 journal.restore([])
 close_modal()

func clear_speech() -> void:
 speech_queue.clear()
 speech_priority = 0
 current_speech_guard = ""
 _speech_caption = false
 last_said.clear()
 system_notices.clear()
 for bubble in [npc_bubble, player_bubble]:
  bubble.remaining = 0
  bubble.hide()
 hud.set_dialogue("", "")

func speak(who: String, message: String, priority := 60, guard := "", caption := false) -> bool:
 if who not in ["미카", "플레이어"]:
  notify(message)
  return false
 if who == "미카":
  var now := Time.get_ticks_msec()
  if last_said.size() > 64:
   for old in last_said.keys():
    if now - int(last_said[old]) > 12000: last_said.erase(old)
  if priority < 60 and now - int(last_said.get(message, -20000)) < 12000: return false
  var finishes_current := current_speech_guard.ends_with("_started") and guard == current_speech_guard.replace("_started", "_done")
  if npc_bubble.remaining > 0 and priority < speech_priority and not finishes_current:
   if speech_queue.any(func(entry): return entry.text == message): return false
   if speech_queue.size() >= 4: speech_queue.pop_front()
   speech_queue.append({"text": message, "priority": priority, "guard": guard, "caption": caption, "grounding": app.brain.dialogue_grounding.duplicate(true) if guard == "answer" else {}, "epoch": app.world.epoch, "expires": now + 10000})
   return false
  speech_priority = priority
  current_speech_guard = guard
  _speech_caption = caption or guard == "answer"
  last_said[message] = now
 var bubble := player_bubble if who == "플레이어" else npc_bubble
 bubble.say(who, message)
 transcript.append(who + ": " + message)
 if transcript.size() > 30: transcript.pop_front()
 record(who, "dialogue", message)
 if who == "미카":
  if _speech_caption: bubble.hide()
  refresh_caption()
  npc_line_shown.emit(message)
 return true

func speech_valid(entry: Dictionary) -> bool:
 var world: DemoWorld = app.world
 if entry.epoch != world.epoch or Time.get_ticks_msec() > int(entry.expires): return false
 match entry.guard:
  "answer":
   var grounding: Dictionary = entry.get("grounding", {})
   if grounding.has("action"):
    if not grounding.get("action_accepted", false): return true
    if grounding.action in ["follow", "wait"]: return world.npc_motion.mode == grounding.action
    return world.active_action == grounding.action
   if grounding.get("topic", "unknown") in ["mission", "support"]:
    return grounding.get("facts") == MikaDialogue.grounding_facts(world.game_state(), grounding.get("question", ""), grounding.topic)
   return not world.defeated and not world.finished
  "heal_started": return world.active_action == "heal"
  "resupply_started": return world.active_action == "resupply"
  "deploy_cover_started": return world.active_action == "deploy_cover"
  "assist_panel_started": return world.active_action == "assist_panel" and world.current_panel().needs_assistance()
  "panel": return world.active_action == "assist_panel" and world.current_panel().needs_assistance()
  "clear": return world.map_id == "storage" and world.enemies_remaining() == 0 and not world.defeated
  "flashlight": return world.flashlight_dropped and not world.flashlight_owned
 return not world.defeated and not world.finished

func notify(message: String) -> void:
 system_notices.post(message)
 record("시스템", "system", message)

func screen_point(target: Node2D) -> Vector2:
 return app.get_global_transform_with_canvas().affine_inverse() * target.get_global_transform_with_canvas().origin

func refresh_caption() -> void:
 if modal_open() or app.dialogue_panel.visible:
  hud.set_dialogue("", "")
 elif not app._fleet_line.is_empty():
  hud.set_dialogue(app._fleet_speaker, app._fleet_line, true)
 elif _speech_caption and npc_bubble.remaining > 0:
  hud.set_dialogue(npc_bubble.speaker, npc_bubble.full_text)
 else:
  hud.set_dialogue("", "")

func update_view(delta: float) -> void:
 if not app: return
 $Pending.visible = not app.brain.dialogue_pending.is_empty()
 if npc_bubble.remaining <= 0 and not speech_queue.is_empty():
  speech_queue.sort_custom(func(a, b): return a.priority > b.priority)
  var next: Dictionary = speech_queue.pop_front()
  if speech_valid(next):
   speech_priority = 0
   # 표시한 적 없는 큐 항목이므로 중복 억제 대상이 아니다.
   speak("미카", next.text, next.priority, next.guard, next.get("caption", false))
  else: app.brain._log({"event": "speech_discarded", "reason": "stale_display_context", "text": next.text})
 var world: DemoWorld = app.world
 minimap.remember_position()
 var combat: bool = not app.is_noncombat()
 var objective := world.current_guidance(true)
 if world.use_fleet_demo and not world.fleet_demo.hint.is_empty() and not world.fleet_demo.locks_movement() and not world.finished and not world.defeated:
  objective += "\n" + world.fleet_demo.hint
 hud.set_objective(objective)
 hud.set_vitals(world.player_hp, world.max_hp, world.ammo, world.max_ammo, world.magazines if world.use_fleet_demo else -1, world.reload_time > 0.0)
 var review_button: Button = hud.get_node("%Review")
 review_button.visible = not world.finished
 var caption: Control = hud.get_node("%Dialogue")
 var occupied: Array[Rect2] = [hud.get_node("Navigation").get_rect(), hud.get_node("Vitals").get_rect(), review_button.get_rect()]
 if app.dialogue_panel.visible: occupied.append(app.dialogue_panel.get_rect())
 for status in statuses:
  var target := status.target
  var point := screen_point(target)
  var bounds: Rect2 = app.play_rect()
  status.visible = combat and target.visible and bounds.has_point(point)
  if status.actor_kind == "npc": status.show_state(world.npc_hp, world.npc_max_hp, world.npc_ammo, world.npc_initial_ammo)
  else:
   status.show_state(target.hp, target.max_hp)
   status.visible = status.visible and target.hp > 0
  if not status.visible: continue
  # 상태바는 월드 기준 고정 오프셋이다. 주변 물체/말풍선 점유 영역으로 옮기지 않는다.
  status.position = point + (Vector2(-60, -102) if status.actor_kind == "npc" else Vector2(-60, 27))
  status.visible = bounds.encloses(status.get_rect()) and world.visibility_at(target.position) > 0.12
  if status.visible: occupied.append(status.get_rect())
 system_notices.tick(delta)
 if system_notices.visible:
  # 알림은 layout에서만 화면 고정 배치한다.
  occupied.append(system_notices.get_rect())
 player_bubble.tick(delta)
 npc_bubble.tick(delta)
 refresh_caption()
 if caption.visible: occupied.append(caption.get_rect())
 for pair in [[player_bubble, world.player], [npc_bubble, world.npc]]:
  var bubble: SpeechBubble = pair[0]
  if bubble.remaining <= 0: continue
  if caption.visible or modal_open() or (bubble == npc_bubble and _speech_caption) or (world.use_fleet_demo and world.fleet_demo.locks_movement()):
   bubble.hide()
   continue
  var bounds: Rect2 = app.play_rect().grow(-12)
  var point := screen_point(pair[1])
  var onscreen := bounds.has_point(point)
  var origin := point + Vector2(-150, -bubble.size.y - 48)
  if not onscreen:
   var ray := point - bounds.get_center()
   var factor := minf((bounds.size.x * 0.5) / maxf(absf(ray.x), 0.001), (bounds.size.y * 0.5) / maxf(absf(ray.y), 0.001))
   origin = bounds.get_center() + ray * factor - bubble.size * 0.5
  bubble.set_direction("" if onscreen else direction_text(point - bounds.get_center()))
  bubble.position = fit(Rect2(origin, bubble.size), bounds, occupied)
  occupied.append(bubble.get_rect())
 queue_redraw()
 if $FullMapPanel.visible: $FullMapPanel/Map.queue_redraw()

func _draw() -> void:
 if not app: return
 for pair in [[player_bubble, app.world.player], [npc_bubble, app.world.npc]]:
  var bubble: SpeechBubble = pair[0]
  if not bubble.visible or not bubble.direction.is_empty(): continue
  var start := bubble.position + Vector2(bubble.size.x * 0.5, bubble.size.y + 6)
  var end := screen_point(pair[1]) + Vector2(0, -38)
  draw_line(start, end, Color(0.58, 0.70, 0.65, 0.7), 1.0, true)

func direction_text(ray: Vector2) -> String:
 if absf(ray.x) > absf(ray.y): return "오른쪽 ▶" if ray.x > 0 else "◀ 왼쪽"
 return "아래 ▼" if ray.y > 0 else "▲ 위"

func fit(rect: Rect2, bounds: Rect2, occupied: Array[Rect2]) -> Vector2:
 var start := rect.position.clamp(bounds.position, bounds.end - rect.size)
 # 플레이어부터 배치하고 겹치는 후순위 표시를 가까운 빈 위치로 옮긴다.
 for shift in [Vector2.ZERO, Vector2(128, 0), Vector2(-128, 0), Vector2(0, 60), Vector2(0, -60), Vector2(128, 60), Vector2(-128, 60), Vector2(0, -140), Vector2(310, 0), Vector2(-310, 0)]:
  var candidate := Rect2((start + shift).clamp(bounds.position, bounds.end - rect.size), rect.size)
  var overlaps := false
  for other in occupied:
   if candidate.grow(3).intersects(other): overlaps = true; break
  if not overlaps: return candidate.position
 return start
