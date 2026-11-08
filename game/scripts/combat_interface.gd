class_name CombatInterface
extends Control
const STATUS := preload("res://scenes/ui/ActorStatus.tscn")
var app: Control
var statuses: Array[ActorStatus] = []
var transcript: Array[String] = []
@onready var minimap: ExplorationMap = $Minimap
@onready var npc_bubble: SpeechBubble = $NPCSpeech
@onready var player_bubble: SpeechBubble = $PlayerSpeech
@onready var system_notices: SystemNotifications = $SystemNotices

func setup(main: Control) -> void:
 app = main
 minimap.world = app.world
 for target in [app.world.player, app.world.npc] + app.world.get_node("Enemies").get_children():
  var hud := STATUS.instantiate() as ActorStatus
  hud.target = target
  hud.actor_kind = "player" if target == app.world.player else "npc" if target == app.world.npc else "enemy"
  $ActorLayer.add_child(hud)
  statuses.append(hud)
  if target is MissionDrone:
   target.show_world_health = false
   target.queue_redraw()
 $HistoryButton.pressed.connect(func():
  $HistoryPanel.visible = not $HistoryPanel.visible)
 $HistoryPanel/Close.pressed.connect(func(): $HistoryPanel.hide())
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

func reset() -> void:
 minimap.explored.clear()
 clear_speech()
 transcript.clear()
 $HistoryPanel/Content.text = ""
 $HistoryPanel.hide()

func clear_speech() -> void:
 system_notices.clear()
 for bubble in [npc_bubble, player_bubble]:
  bubble.remaining = 0
  bubble.hide()

func speak(who: String, message: String) -> void:
 if who not in ["하린", "플레이어"]:
  notify(message)
  return
 var bubble := player_bubble if who == "플레이어" else npc_bubble
 bubble.say(who, message)
 transcript.append(who + ": " + message)
 if transcript.size() > 30: transcript.pop_front()
 $HistoryPanel/Content.text = "\n\n".join(transcript)

func notify(message: String) -> void:
 system_notices.post(message)

func screen_point(target: Node2D) -> Vector2:
 return app.get_global_transform_with_canvas().affine_inverse() * target.get_global_transform_with_canvas().origin

func update_view(delta: float) -> void:
 if not app: return
 minimap.remember_position()
 var combat: bool = not app.is_noncombat()
 minimap.visible = combat
 $Objective.visible = combat
 $Objective.text = app.world.current_guidance()
 $HistoryButton.visible = combat
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
  var rect := Rect2(point + Vector2(-60, 38 if hud.actor_kind != "enemy" else 27), hud.size)
  hud.position = fit(rect, bounds, occupied)
  occupied.append(hud.get_rect())
 system_notices.tick(delta)
 if system_notices.visible:
  var bounds: Rect2 = app.play_rect().grow(-12)
  var origin := screen_point(app.world.player) + Vector2(42, -18)
  system_notices.position = fit(Rect2(origin, system_notices.size), bounds, occupied)
  occupied.append(system_notices.get_rect())
 for pair in [[player_bubble, app.world.player], [npc_bubble, app.world.npc]]:
  var bubble: SpeechBubble = pair[0]
  bubble.tick(delta)
  if bubble.remaining <= 0: continue
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
