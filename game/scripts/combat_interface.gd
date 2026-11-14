class_name CombatInterface
extends Control
signal npc_line_shown(text: String)
const STATUS := preload("res://scenes/ui/ActorStatus.tscn")
var app: Control
var statuses: Array[ActorStatus] = []
var transcript: Array[String] = []
var speech_queue: Array[Dictionary] = []
var speech_priority := 0
var current_speech_guard := ""
var last_said := {}
var journal := MessageJournal.new()
var _journal_refresh := false
var _follow_journal := true
var _journal_scroll := 0.0
@onready var minimap: ExplorationMap = $Minimap
@onready var npc_bubble: SpeechBubble = $NPCSpeech
@onready var player_bubble: SpeechBubble = $PlayerSpeech
@onready var system_notices: SystemNotifications = $SystemNotices

func setup(main: Control) -> void:
 app = main
 minimap.world = app.world
 $FullMapPanel/Map.world = app.world
 $FullMapPanel/Map.source = minimap
 $FullMapPanel/Map.full_map = true
 var recent_style := StyleBoxFlat.new()
 recent_style.bg_color = Color(0.035, 0.055, 0.075, 0.94)
 for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: recent_style.set_content_margin(side, 6)
 $Recent.add_theme_stylebox_override("normal", recent_style)
 for target in [app.world.player, app.world.npc] + app.world.all_enemies():
  var hud := STATUS.instantiate() as ActorStatus
  hud.target = target
  hud.actor_kind = "player" if target == app.world.player else "npc" if target == app.world.npc else "enemy"
  $ActorLayer.add_child(hud)
  statuses.append(hud)
  if target is MissionDrone:
   target.show_world_health = false
   target.queue_redraw()
 $HistoryButton.pressed.connect(toggle_history)
 $HistoryPanel/Close.pressed.connect(toggle_history)
 $HistoryPanel/NewMessages.pressed.connect(scroll_to_latest)
 $FullMapPanel/Close.pressed.connect(toggle_map)
 app.resized.connect(layout)
 layout()

func layout() -> void:
 if not app: return
 size = app.size
 minimap.position = Vector2(20, 20)
 minimap.size = Vector2(242, 134)
 $Objective.position = Vector2(282, 20)
 $Objective.size = Vector2(maxf(250, app.size.x - 450), 52)
 $HistoryButton.position = Vector2(app.size.x - 150, 20)
 $HistoryPanel.position = Vector2(app.size.x - 470, 76)
 app.get_node("LabObjective").set_anchors_preset(Control.PRESET_TOP_LEFT)
 app.get_node("LabObjective").position = Vector2(282, 20)
 app.get_node("LabObjective").size = Vector2(maxf(250, app.size.x - 450), 52)
 app.get_node("LabModeBadge").position = Vector2(20, 164)
 app.get_node("LabModeBadge").size = Vector2(242, 22)
 $HistoryPanel.size = Vector2(440, minf(420, app.size.y - 160))
 $HistoryPanel/Content.size = $HistoryPanel.size - Vector2(32, 80)
 system_notices.position = Vector2(282, 84)
 system_notices.size.x = minf(360, app.size.x - 460)
 $Recent.position = Vector2(282, 76)
 $Recent.size = Vector2(maxf(220, app.size.x - 470), 64)
 $Pending.position = Vector2(app.size.x - 154, 70)
 $Pending.size = Vector2(140, 24)
 # 최근 메시지와 페이드 알림은 같은 고정 영역의 서로 다른 행을 쓴다.
 system_notices.position.y = 146
 $FullMapPanel.position = Vector2(24, 76)
 $FullMapPanel.size = app.size - Vector2(48, 110)
 $FullMapPanel/Map.position = Vector2(16, 58)
 $FullMapPanel/Map.size = $FullMapPanel.size - Vector2(32, 74)
 $FullMapPanel/Close.position = Vector2($FullMapPanel.size.x - 230, 8)
 $FullMapPanel/Close.size = Vector2(214, 40)

func modal_open() -> bool:
 return $HistoryPanel.visible or $FullMapPanel.visible

func toggle_history() -> void:
 if app.world.finished: return
 if app.world.use_fleet_demo and app.world.fleet_demo.locks_movement() and not $HistoryPanel.visible: return
 app.question.finish_editing()
 $FullMapPanel.hide()
 $HistoryPanel.visible = not $HistoryPanel.visible
 if $HistoryPanel.visible: scroll_to_latest()
 app._sync_input_mode()

func toggle_map() -> void:
 if app.world.finished: return
 if app.world.use_fleet_demo and app.world.fleet_demo.locks_movement() and not $FullMapPanel.visible: return
 app.question.finish_editing()
 $HistoryPanel.hide()
 $FullMapPanel.visible = not $FullMapPanel.visible
 $FullMapPanel/Map.queue_redraw()
 app._sync_input_mode()

func close_modal() -> void:
 $HistoryPanel.hide()
 $FullMapPanel.hide()
 app._sync_input_mode()

func scroll_to_latest() -> void:
 var bar: VScrollBar = $HistoryPanel/Content.get_v_scroll_bar()
 bar.value = bar.max_value
 $HistoryPanel/NewMessages.hide()

func record(who: String, channel: String, message: String, message_id := "") -> bool:
 var bar: VScrollBar = $HistoryPanel/Content.get_v_scroll_bar()
 if not _journal_refresh:
  _follow_journal = not $HistoryPanel.visible or bar.value >= bar.max_value - bar.page - 4
  _journal_scroll = bar.value
  _journal_refresh = true
  call_deferred("_settle_journal")
 var added := journal.append(who, channel, message, app.world.map_id, str(app.brain.trial), message_id)
 $HistoryPanel/Content.text = journal.display_text()
 var recent := PackedStringArray()
 for item in journal.entries.slice(-2): recent.append("[%s] %s" % [item.sender, item.body.replace("\n", " ").left(110)])
 $Recent.text = "\n".join(recent)
 if added and not _follow_journal: $HistoryPanel/NewMessages.show()
 return added

func _settle_journal() -> void:
 await get_tree().process_frame
 if _follow_journal: scroll_to_latest()
 else: $HistoryPanel/Content.get_v_scroll_bar().value = _journal_scroll
 _journal_refresh = false

func restore_journal(data: Array) -> void:
 journal.restore(data)
 $HistoryPanel/Content.text = journal.display_text()
 $Recent.text = ""
 scroll_to_latest()

func reset() -> void:
 minimap.explored.clear()
 minimap.known.clear()
 minimap.rooms.clear()
 clear_speech()
 transcript.clear()
 journal.restore([])
 $Recent.text = ""
 $HistoryPanel/Content.text = ""
 $HistoryPanel.hide()
 $FullMapPanel.hide()

func clear_speech() -> void:
 speech_queue.clear()
 speech_priority = 0
 current_speech_guard = ""
 last_said.clear()
 system_notices.clear()
 for bubble in [npc_bubble, player_bubble]:
  bubble.remaining = 0
  bubble.hide()

func speak(who: String, message: String, priority := 60, guard := "") -> bool:
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
   speech_queue.append({"text": message, "priority": priority, "guard": guard, "grounding": app.brain.dialogue_grounding.duplicate(true) if guard == "answer" else {}, "epoch": app.world.epoch, "expires": now + 10000})
   return false
  speech_priority = priority
  current_speech_guard = guard
  last_said[message] = now
 var bubble := player_bubble if who == "플레이어" else npc_bubble
 bubble.say(who, message)
 transcript.append(who + ": " + message)
 if transcript.size() > 30: transcript.pop_front()
 record(who, "dialogue", message)
 if who == "미카": npc_line_shown.emit(message)
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
    return grounding.get("facts") == MikaDialogue.facts(world.game_state(), grounding.get("question", ""), grounding.topic)
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

func update_view(delta: float) -> void:
 if not app: return
 $Pending.visible = not app.brain.dialogue_pending.is_empty()
 if npc_bubble.remaining <= 0 and not speech_queue.is_empty():
  speech_queue.sort_custom(func(a, b): return a.priority > b.priority)
  var next: Dictionary = speech_queue.pop_front()
  if speech_valid(next):
   speech_priority = 0
   # 표시한 적 없는 큐 항목이므로 중복 억제 대상이 아니다.
   speak("미카", next.text, next.priority, next.guard)
  else: app.brain._log({"event": "speech_discarded", "reason": "stale_display_context", "text": next.text})
 minimap.remember_position()
 var combat: bool = not app.is_noncombat()
 minimap.visible = true
 $Objective.visible = combat
 $Objective.text = app.world.current_guidance()
 $HistoryButton.visible = not app.world.finished
 var occupied: Array[Rect2] = []
 if combat:
  occupied.append(minimap.get_rect())
  occupied.append($Objective.get_rect())
  occupied.append($HistoryButton.get_rect())
 else:
  occupied.append(app.get_node("LabObjective").get_rect())
  occupied.append(app.get_node("LabModeBadge").get_rect())
  if app.dialogue_panel.visible: occupied.append(app.get_node("RadioPanel/LabPortrait").get_global_rect())
 for hud in statuses:
  var target := hud.target
  var point := screen_point(target)
  var bounds: Rect2 = app.play_rect()
  hud.visible = combat and target.visible and bounds.has_point(point)
  if hud.actor_kind == "player": hud.show_state(app.world.player_hp, app.world.max_hp, app.world.ammo, app.world.max_ammo)
  elif hud.actor_kind == "npc": hud.show_state(app.world.npc_hp, app.world.npc_max_hp, app.world.npc_ammo, app.world.npc_initial_ammo)
  else:
   hud.show_state(target.hp, target.max_hp)
   hud.visible = hud.visible and target.hp > 0 and app.world.visibility_at(target.position) > 0.12
  if not hud.visible: continue
  if hud.actor_kind == "npc": hud.visible = app.world.visibility_at(target.position) > 0.12
  # 상태바는 월드 기준 고정 오프셋이다. 주변 물체/말풍선 점유 영역으로 옮기지 않는다.
  var offset := Vector2(-60, 38) if hud.actor_kind == "player" else Vector2(-60, -102) if hud.actor_kind == "npc" else Vector2(-60, 27)
  hud.position = point + offset
  hud.visible = hud.visible and bounds.encloses(hud.get_rect())
  occupied.append(hud.get_rect())
 system_notices.tick(delta)
 if system_notices.visible:
  # 알림은 layout에서만 화면 고정 배치한다.
  occupied.append(system_notices.get_rect())
 for pair in [[player_bubble, app.world.player], [npc_bubble, app.world.npc]]:
  var bubble: SpeechBubble = pair[0]
  bubble.tick(delta)
  if bubble.remaining <= 0: continue
  if app.world.use_fleet_demo and app.world.fleet_demo.locks_movement():
   bubble.hide()
   continue
  # 비전투에서는 큰 본문과 NPC 말풍선을 중복 표시하지 않는다.
  if not combat and bubble == npc_bubble and app.dialogue_panel.visible and bubble.full_text == app.answer.text:
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
