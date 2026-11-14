@tool
class_name CooperativeLocker
extends Node2D
## 이후 임무에도 배치할 수 있는 2인 패널/보관함 실행기.
@export var hold_seconds := 1.0
@export var use_radius := 48.0
@export var mission_room := "storage"
@export_enum("locker", "containment") var purpose := "locker"
var world: Node2D
var opened := false
var supply_taken := false
var player_panel := -1
var progress := 0.0
var sequence_elapsed := -1.0
var beep_index := 0
var attempt_started := 0
var hold_started := false
var use_external_cabinet := false
const BEEPS := [0.0, 0.12, 0.36, 0.48, 0.72, 0.84]

func bind(mission: Node2D) -> void:
 world = mission
 if purpose == "containment":
  $PanelA.interaction_id = "containment_panel_a"
  $PanelB.interaction_id = "containment_panel_b"
  $PanelA.display_name = "봉쇄 패널 A · E 유지"
  $PanelB.display_name = "봉쇄 패널 B · E 유지"
 reset()

func reset() -> void:
 opened = false
 supply_taken = false
 player_panel = -1
 progress = 0
 sequence_elapsed = -1
 beep_index = 0
 hold_started = false
 update_visuals()

func panels() -> Array:
 return [$PanelA, $PanelB]

func panel_position(index: int) -> Vector2:
 return position + (panels()[index] as Node2D).position

func partner_position() -> Vector2:
 return panel_position(1 - player_panel) if player_panel >= 0 else position

func needs_assistance() -> bool:
 return player_panel >= 0 and not opened and sequence_elapsed < 0

func begin(index: int) -> String:
 if purpose == "containment" and world.containment.stage != "panel_ready": return "먼저 두 무리의 침식된 선원을 제압하세요."
 if opened: return "보관함이 열렸습니다. 퓨즈와 보급을 챙기세요."
 if sequence_elapsed >= 0: return "잠금 해제 확인 중입니다."
 if world.enemies_remaining() > 0: return "주변 선원을 먼저 제압하세요."
 if world.npc_hp <= 0: return "먼저 미카 가까이에서 E로 치료 키트를 사용해 소생하세요."
 if world.player.position.distance_to(panel_position(index)) > use_radius: return "패널에 더 가까이 다가가세요."
 if player_panel != index:
  cancel("panel_changed")
  player_panel = index
  attempt_started = Time.get_ticks_msec()
  world.epoch += 1
  world._event("panel_requested", {"player_panel": index, "npc_panel": 1 - index})
 update_visuals()
 return "E를 계속 누르세요. 미카가 반대 패널에 도착한 뒤 둘이 %.1f초 유지합니다." % hold_seconds

func cancel(reason: String) -> void:
 if player_panel >= 0 and sequence_elapsed < 0:
  world._event("panel_attempt_cancelled", {"reason": reason, "progress": progress})
  if world.active_action == "assist_panel":
   world._event("support_rejected", {"action": "assist_panel", "reason": reason, "request": world.action_metadata})
   world.active_action = ""
 player_panel = -1
 progress = 0
 hold_started = false
 update_visuals()

func tick(delta: float, holding: bool) -> void:
 if opened: return
 if sequence_elapsed >= 0:
  sequence_elapsed += delta
  while beep_index < BEEPS.size() and sequence_elapsed >= BEEPS[beep_index]:
   world._event("locker_beep", {"index": beep_index})
   beep_index += 1
  if sequence_elapsed >= 1.0:
   opened = true
   player_panel = -1
   world.epoch += 1
   world.active_action = ""
   if purpose == "locker": world._remember("둘이 패널을 유지해 보관함을 열었다")
   world._event("support_completed", {"action": "assist_panel", "request": world.action_metadata})
   world._event("locker_opened" if purpose == "locker" else "containment_panel_completed", {"elapsed_ms": Time.get_ticks_msec() - attempt_started, "hold_seconds": hold_seconds, "source": "common_panel_executor"})
   if purpose == "locker":
    world.say_companion("열렸다! 뭐가 있나 보자.", 30, "assist_panel_done")
    world.notice.emit("보관함 개방 · 퓨즈와 보급 회수 가능")
   else: world.containment.panel_completed()
   world._sync_state()
   world.state_changed.emit()
  update_visuals()
  return
 if player_panel < 0: return
 if not holding or not world.can_move or world.map_id != mission_room or world.player.position.distance_to(panel_position(player_panel)) > use_radius:
  cancel("released_or_left_panel")
  return
 # 가구 발밑 충돌 바깥의 접근점도 플레이어와 같은 사용 반경으로 인정한다.
 var ready: bool = world.active_action == "assist_panel" and world.npc_hp > 0 and world.npc.position.distance_to(partner_position()) <= use_radius
 if ready:
  if not hold_started:
   hold_started = true
   world._event("panel_hold_started", {"player_panel": player_panel, "npc_panel": 1 - player_panel})
  progress = minf(hold_seconds, progress + delta)
  if progress >= hold_seconds:
   sequence_elapsed = 0
   world._event("panel_hold_completed", {"hold_seconds": hold_seconds})
 else:
  progress = 0
  hold_started = false
 update_visuals()

func context() -> Dictionary:
 return {"opened": opened, "player_panel": player_panel, "player_holding": needs_assistance(), "npc_target": [partner_position().x, partner_position().y], "hold_seconds": hold_seconds, "progress": progress, "unlocking": sequence_elapsed >= 0 and not opened}

func snapshot() -> Dictionary:
 return {"opened": opened, "supply_taken": supply_taken, "sequence_elapsed": sequence_elapsed, "beep_index": beep_index}

func restore(data: Dictionary) -> void:
 reset()
 opened = data.opened
 supply_taken = data.supply_taken
 sequence_elapsed = float(data.sequence_elapsed)
 beep_index = int(data.beep_index)
 if sequence_elapsed >= 0: progress = hold_seconds
 update_visuals()

func update_visuals() -> void:
 if not is_node_ready(): return
 $PanelA.set_active(opened or progress > 0 or player_panel == 0)
 $PanelB.set_active(opened or progress > 0 or player_panel == 1)
 $Progress.visible = player_panel >= 0 or (sequence_elapsed >= 0 and not opened)
 $Progress.value = progress / maxf(0.01, hold_seconds) * 100
 $State.text = "보관함 열림 · 물품 회수" if opened else "잠금 해제 중…" if sequence_elapsed >= 0 else "두 패널 유지 %.1f / %.1f초" % [progress, hold_seconds] if progress > 0 else "E 유지 · 미카는 반대 패널로 이동 중" if player_panel >= 0 else "2인 보관함 · 패널 E 유지"
 if purpose == "containment":
  $State.text = "외곽 봉쇄 완료" if opened else "봉쇄 확인 중…" if sequence_elapsed >= 0 else "두 패널 유지 %.1f / %.1f초" % [progress, hold_seconds] if progress > 0 else "E 유지 · 미카는 반대 패널로 이동 중" if player_panel >= 0 else "최종 봉쇄 · 두 무리 제압 후 E 유지"
 queue_redraw()

func _draw() -> void:
 if use_external_cabinet: return
 draw_rect(Rect2(-72, -35, 144, 65), Color("14222a"))
 draw_rect(Rect2(-72, -35, 144, 65), Color("78c8b8") if opened else Color("bd9460"), false, 3)
 draw_line(Vector2(0, -33), Vector2(0, 28), Color("57818a"), 3)
 if opened:
  draw_rect(Rect2(-55, -20, 110, 35), Color("70b799"))
 else: draw_rect(Rect2(-9, -8, 18, 20), Color("d3a66e"))
