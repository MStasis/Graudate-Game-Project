extends Control
signal title_requested
@onready var world: DemoWorld = %World
@onready var brain: NPCBrain = $NPCBrain
@onready var answer: RichTextLabel = %Answer
@onready var question: ChatInput = %Question
@onready var status: Label = %Status
@onready var state_label: Label = %StateSummary
@onready var metric_label: Label = %Metrics
@onready var send_button: Button = %SendButton
@onready var dialogue_panel: NoncombatDialoguePanel = %RadioPanel
@onready var combat_hud: CombatInterface = $CombatHUD
@onready var pause_menu: MissionPauseMenu = $PauseMenu
var save_store := MissionSaveStore.new()
var world_starts_fleet_demo := false
var _fleet_speaker := ""
var _fleet_line := ""
var _fleet_reaction := false
var _chat_idle := 0.0
var _chat_sent := false
var _camera_zoom := 1.0
var log_dir := ""
var evidence_mode := false
var _health_tween: Tween
var _last_submitted_question := ""
var _radio_error := false
var _lab_dialogue_open := true
var _combat_chat_open := false
var result_screen: Control
var _ending_elapsed := -1.0
const ENDING_SECONDS := 6.0
const UI_TEAL := Color("74c6b6")
const UI_AMBER := Color("d3a66e")
const UI_DANGER := Color("dc8576")

func _ready() -> void:
 process_mode = Node.PROCESS_MODE_ALWAYS
 $WorldCanvas.process_mode = Node.PROCESS_MODE_PAUSABLE
 brain.process_mode = Node.PROCESS_MODE_PAUSABLE
 dialogue_panel.process_mode = Node.PROCESS_MODE_PAUSABLE
 combat_hud.process_mode = Node.PROCESS_MODE_PAUSABLE
 combat_hud.setup(self)
 result_screen = preload("res://scenes/ui/DemoResult.tscn").instantiate()
 add_child(result_screen)
 result_screen.get_node("Center/Card/Margin/Content/Buttons/Restart").pressed.connect(reset_demo)
 result_screen.get_node("Center/Card/Margin/Content/Buttons/ReturnToTitle").pressed.connect(_return_to_title)
 result_screen.get_node("Center/Card/Margin/Content/Buttons/Quit").pressed.connect(func(): get_tree().quit())
 pause_menu.store = save_store
 pause_menu.close_requested.connect(toggle_pause)
 pause_menu.title_requested.connect(_return_to_title)
 pause_menu.save_selected.connect(save_slot)
 pause_menu.load_selected.connect(load_slot)
 evidence_mode = "--mission-evidence" in OS.get_cmdline_user_args()
 var evidence_root := "user://evidence" if OS.has_feature("template") else "res://../evidence"
 log_dir = ProjectSettings.globalize_path(evidence_root.path_join("mission_v1")).simplify_path()
 if "--chat-input-test" in OS.get_cmdline_user_args():
  brain.auto_enabled = false
  brain.run_kind = "chat_input_regression"
  log_dir = ProjectSettings.globalize_path("res://../evidence/chat_input_fix").simplify_path()
 if "--ui-layout-test" in OS.get_cmdline_user_args():
  brain.auto_enabled = false
  brain.run_kind = "ui_redesign_regression"
  log_dir = ProjectSettings.globalize_path("res://../evidence/ui_redesign").simplify_path()
 if "--noncombat-ui-test" in OS.get_cmdline_user_args():
  brain.auto_enabled = false
  brain.run_kind = "noncombat_ui_regression"
  log_dir = ProjectSettings.globalize_path("res://../evidence/noncombat_ui").simplify_path()
 if "--interface-test" in OS.get_cmdline_user_args():
  brain.auto_enabled = false
  brain.run_kind = "interface_update_regression"
  log_dir = ProjectSettings.globalize_path("res://../evidence/interface_update").simplify_path()
 if "--provider-probe" in OS.get_cmdline_user_args():
  brain.auto_enabled = false
  brain.run_kind = "fixed_snapshot_live_probe"
  log_dir = log_dir.path_join("provider_probe")
 if "--local-integration" in OS.get_cmdline_user_args():
  brain.auto_enabled = false
  brain.run_kind = "live_integration_controlled_inputs"
  log_dir = log_dir.path_join("local_integration")
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with("--provider="):
   var selected := NPCBrain.PROVIDERS.find(argument.trim_prefix("--provider="))
   if selected >= 0: brain.settings.provider = selected
  if argument.begins_with("--local-model="):
   for client in [brain.local_dialogue, brain.local_decision]:
    client.settings = client.settings.duplicate(true)
    client.settings.model = argument.trim_prefix("--local-model=")
 world.interacted.connect(interact)
 world.state_changed.connect(update_state)
 world.game_event.connect(func(event):
  if event.event == "mission_completed": _begin_ending())
 world.room_changing.connect(combat_hud.clear_speech)
 world.notice.connect(_show_status)
 world.fleet_demo.line_changed.connect(_show_fleet_line)
 world.fleet_demo.showing_reaction.connect(func(active): _fleet_reaction = active)
 combat_hud.npc_line_shown.connect(func(text):
  if _fleet_line.is_empty(): answer.text = text)
 world.companion_spoke.connect(func(text): _companion_says(text, world.speech_priority, world.speech_guard))
 brain.dialogue_ready.connect(func(text):
  _radio_error = false
  var grounding: Dictionary = brain.dialogue_grounding
  var guard := "answer"
  if grounding.get("action_accepted", false) and grounding.get("action", "") in ["heal", "resupply", "deploy_cover", "assist_panel"]:
   guard = str(grounding.action) + "_started"
  _companion_says(text, 60, guard)
  _enable_question())
 brain.dialogue_error.connect(func(message):
  _radio_error = true
  _show_status("대화 응답 오류 · " + message)
  _enable_question())
 brain.status_changed.connect(func(message):
  # 자동 판단/모델 준비 같은 개발 상태를 캐릭터 대사나 반복 알림으로 내보내지 않는다.
  status.text = message
  status.tooltip_text = message)
 brain.measured.connect(_measured)
 question.text_submitted.connect(_send_question)
 question.validation_failed.connect(_show_status)
 question.editing_closed.connect(close_dialogue)
 question.focus_entered.connect(_sync_input_mode)
 question.focus_exited.connect(_sync_input_mode)
 send_button.pressed.connect(ask_npc)
 %RestartButton.pressed.connect(reset_demo)
 %SettingsButton.pressed.connect(toggle_settings)
 %CloseSettings.pressed.connect(toggle_settings)
 %CloseDialogue.pressed.connect(close_dialogue)
 %TalkPrompt.pressed.connect(open_dialogue)
 %MissionPrompt.pressed.connect(func(): prepare_question("지금 뭘 해야 해?"))
 %SupportPrompt.pressed.connect(func(): prepare_question("지금 어떻게 도와줄 수 있어?"))
 %EverydayPrompt.pressed.connect(func(): prepare_question("오늘 기분은 어때?"))
 for label_name in ["RoomTitle", "GoalText", "ControlsHint"]:
  world.get_node(label_name).hide()
 world.use_fleet_demo = world_starts_fleet_demo
 if world.use_fleet_demo: _lab_dialogue_open = false
 brain.setup(world, log_dir)
 %Provider.select(brain.provider)
 %Provider.item_selected.connect(func(index): reset_demo(index))
 update_state()
 answer.text = NPCPolicy.opening_line(world.game_state())
 if evidence_mode:
  brain.auto_enabled = false
  call_deferred("_run_evidence")

func game_state() -> Dictionary:
 return world.game_state()

func update_state() -> void:
 state_label.text = "체력 %d/%d  ·  탄약 %d  ·  치료 %d / 보급 %d / 보호 %d" % [world.player_hp, world.max_hp, world.ammo, world.medkits, world.supply_packs, world.cover_charges]
 var danger := world.player_hp <= 35
 %HealthValue.text = "%d / %d%s" % [world.player_hp, world.max_hp, " · 위험" if danger else ""]
 %HealthValue.modulate = UI_DANGER if danger else Color.WHITE
 %HealthBar.max_value = world.max_hp
 var fill := %HealthBar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
 fill.bg_color = UI_DANGER if danger else UI_TEAL
 %HealthBar.add_theme_stylebox_override("fill", fill)
 if _health_tween: _health_tween.kill()
 _health_tween = create_tween()
 _health_tween.tween_property(%HealthBar, "value", float(world.player_hp), 0.18)
 %AmmoValue.text = "%02d / %02d" % [world.ammo, world.max_ammo]
 %AmmoValue.add_theme_color_override("font_color", UI_AMBER if world.ammo <= 4 else UI_TEAL)
 %SupportValue.text = "치료 %02d   보급 %02d   보호 %02d" % [world.medkits, world.supply_packs, world.cover_charges]
 %Objective.text = world.current_guidance()
 %Location.text = world.room_name() if world.use_fleet_demo else ExplorationMap.ROOM_NAMES.get(world.map_id, world.map_id)
 var step := 1
 if world.map_id == "storage": step = 2
 if world.fuse_collected: step = 3
 if world.power_restored: step = 4
 %MissionStep.text = "%02d / 04  ·  목표" % step
 if world.story.tutorial_completed: %MissionStep.text = "외곽 봉쇄 · " + world.containment.guidance()
 if world.defeated: %MissionStep.text = "임무 중단"
 var provider_names := ["규칙 기반", "로컬 LLM", "Jev"]
 %ProviderBadge.text = "판단 방식 · " + provider_names[brain.provider]
 %LabModeBadge.text = provider_names[brain.provider] + " · F3 실험 설정"
 _sync_dialogue_presentation()

func interact(kind: String) -> void:
 if kind == "npc":
  if world.npc_hp <= 0:
   _show_status(world.apply_interaction("revive_npc"))
   return
  if is_noncombat(): open_dialogue()
  else: _show_status("Enter를 눌러 미카에게 짧은 메시지를 보낼 수 있습니다.")
  return
 var message := world.apply_interaction(kind, true)
 if not message.is_empty(): _show_status(message)

func _companion_says(message: String, priority := 60, guard := "") -> void:
 combat_hud.speak("미카", message, priority, guard)

func reset_demo(mode: int = -1) -> void:
 _ending_elapsed = -1
 result_screen.hide()
 if pause_menu.visible: toggle_pause()
 combat_hud.reset()
 _chat_idle = 0
 _chat_sent = false
 question.finish_editing()
 question.text = ""
 _lab_dialogue_open = not world.use_fleet_demo
 _combat_chat_open = false
 brain.new_trial(mode)
 %Provider.select(brain.provider)
 _radio_error = false
 _last_submitted_question = ""
 _enable_question()
 answer.text = NPCPolicy.opening_line(world.game_state())
 %Callout.text = "같은 시작 조건으로 새 회차를 시작했습니다."
 update_state()
 _sync_input_mode()

func ask_npc() -> void:
 question.request_submit()

func _send_question(message: String) -> void:
 if pause_menu.visible or world.finished or world.defeated: return
 combat_hud.speak("플레이어", message)
 _chat_idle = 0
 _chat_sent = true
 _radio_error = false
 _last_submitted_question = message
 send_button.disabled = true
 question.finish_editing()
 question.editable = false
 question.text = ""
 close_dialogue()
 _set_prompts_enabled(false)
 _update_radio_state("응답 중", UI_AMBER)
 status.text = "미카의 답변을 기다리는 중…" # 개발/대기 상태는 사용자 통합 기록을 채우지 않는다.
 combat_hud.get_node("Pending").show()
 if not brain.request_dialogue(message): _enable_question()

func _enable_question() -> void:
 send_button.disabled = false
 question.editable = true
 _set_prompts_enabled(true)
 _sync_input_mode()

func _set_prompts_enabled(enabled: bool) -> void:
 for button in [%MissionPrompt, %SupportPrompt, %EverydayPrompt]:
  button.disabled = not enabled

func _update_radio_state(label_text: String, color: Color) -> void:
 %RadioState.text = "● " + label_text
 %RadioState.modulate = color

func _sync_input_mode() -> void:
 world.can_move = not world.finished and not world.defeated and not question.has_focus() and not %DebugPanel.visible and not pause_menu.visible and not combat_hud.modal_open()
 if question.has_focus():
  _chat_idle = 0
  dialogue_panel.modulate.a = 1
 if not question.editable: _update_radio_state("응답 중", UI_AMBER)
 elif _radio_error: _update_radio_state("응답 오류", UI_DANGER)
 elif question.has_focus(): _update_radio_state("입력 중", UI_AMBER)
 else: _update_radio_state("대기", UI_TEAL)

func _show_status(message: String) -> void:
 status.text = message
 status.tooltip_text = message
 combat_hud.notify(message)

func is_noncombat() -> bool:
 if world.use_fleet_demo: return not world.is_combat_area()
 return world.map_id in ["lab", "quarters"]

func _show_fleet_line(speaker: String, body: String) -> void:
 var starting := _fleet_line.is_empty() and not body.is_empty()
 _fleet_speaker = speaker
 _fleet_line = body
 if starting:
  brain.cancel_pending("scripted_dialogue")
  question.finish_editing()
  _lab_dialogue_open = false
  _combat_chat_open = false
  combat_hud.clear_speech()
  combat_hud.close_modal()
 if not body.is_empty(): combat_hud.record(speaker, "dialogue", body)
 _sync_dialogue_presentation()

func _sync_dialogue_presentation() -> void:
 var lab := is_noncombat()
 var scripted := not _fleet_line.is_empty()
 if dialogue_panel.noncombat_mode != (lab or scripted):
  question.finish_editing()
  _combat_chat_open = false
  dialogue_panel.set_noncombat(lab or scripted)
 dialogue_panel.set_scripted(scripted)
 for path in ["Header", "Frame", "MissionBar", "NoticeStrip", "Footer"]:
  get_node(path).visible = false
 $Footer.visible = not lab
 %LabObjective.visible = lab
 %LabModeBadge.visible = lab
 dialogue_panel.visible = scripted or (not (world.use_fleet_demo and world.fleet_demo.locks_movement()) and (_lab_dialogue_open if lab else _combat_chat_open))
 %TalkPrompt.visible = lab and not _lab_dialogue_open and not scripted and not (world.use_fleet_demo and world.fleet_demo.locks_movement())
 var short_name := world.npc.display_name.trim_prefix("정비사 ")
 $RadioPanel/CompanionName.text = _fleet_speaker if scripted else short_name
 if scripted:
  answer.text = _fleet_line
  $RadioPanel/LabPortrait.visible = world.fleet_demo.show_mika_portrait
 %TalkPrompt.text = "Enter를 눌러 %s에게 말하기" % short_name
 world.npc.get_node("NameLabel").visible = false
 var goal := "비품실에서 퓨즈 찾기"
 if world.map_id == "storage": goal = "퓨즈를 챙겨 연구실로 복귀"
 if world.fuse_collected: goal = "전력 장치에 퓨즈 장착"
 if world.power_restored: goal = "침식 경보 · 연구동으로 출발"
 if world.map_id == "main_entry": goal = world.containment.guidance()
 if world.finished: goal = "연구동 외곽 구역 봉쇄 성공"
 if world.defeated: goal = "전투 불능 · 새 회차 필요"
 if world.use_fleet_demo: goal = world.current_guidance()
 %LabObjectiveText.text = goal
 %LabObjective.tooltip_text = world.current_guidance()
 _sync_input_mode()
 _update_world_view()
 _update_speaker_bubble()

func open_dialogue() -> void:
 if pause_menu.visible or combat_hud.modal_open() or world.finished or world.defeated: return
 if world.use_fleet_demo and world.fleet_demo.locks_movement(): return
 if is_noncombat():
  _lab_dialogue_open = true
  dialogue_panel.show()
  %TalkPrompt.hide()
 else:
  _combat_chat_open = true
  dialogue_panel.show()
 if question.editable: question.grab_focus()
 _sync_input_mode()

func close_dialogue() -> void:
 question.finish_editing()
 if is_noncombat(): _lab_dialogue_open = false
 else: _combat_chat_open = false
 dialogue_panel.hide()
 %TalkPrompt.visible = is_noncombat()
 _sync_input_mode()

func _process(delta: float) -> void:
 if not is_node_ready() or get_tree().paused: return
 if _ending_elapsed >= 0:
  _ending_elapsed += delta
  if _ending_elapsed >= ENDING_SECONDS and not result_screen.visible:
   result_screen.show()
   result_screen.get_node("Center/Card/Margin/Content/Buttons/Restart").grab_focus()
 _update_world_view()
 _update_speaker_bubble()
 combat_hud.update_view(delta)
 $FleetCues.visible = world.use_fleet_demo
 if world.use_fleet_demo: _update_fleet_cues()
 dialogue_panel.modulate.a = 1

func play_rect() -> Rect2:
 return Rect2(0, 0, size.x, size.y - (240 if dialogue_panel.noncombat_mode and dialogue_panel.visible else 40))

func _update_world_view() -> void:
 # CanvasLayer만 변환하므로 캐릭터의 속도·충돌 형태·게임 좌표는 바뀌지 않는다.
 var area := play_rect()
 _camera_zoom = 1.35 if is_noncombat() else 1.0
 var focus := world.player.position
 if world.use_fleet_demo:
  _camera_zoom = 1.1 if world.map_id == "corridor" or world.map_id == "research_lab_b" else 1.35
  var weight := world.fleet_demo.camera_weight
  if weight > 0:
   _camera_zoom = lerpf(_camera_zoom, 2.3, weight)
   focus = focus.lerp(world.fleet_demo.camera_point, weight)
 var extent := world.map_extent() * _camera_zoom
 var offset := area.get_center() - focus * _camera_zoom
 for axis in range(2):
  if extent[axis] <= area.size[axis]: offset[axis] = area.position[axis] + (area.size[axis] - extent[axis]) * 0.5
  else: offset[axis] = clampf(offset[axis], area.end[axis] - extent[axis], area.position[axis])
 $WorldCanvas.scale = Vector2.ONE * _camera_zoom
 $WorldCanvas.offset = offset
 world.update_visibility()

func _update_speaker_bubble() -> void:
 var sprite := world.npc.animation
 var sprite_to_ui := get_global_transform_with_canvas().affine_inverse() * sprite.get_global_transform_with_canvas()
 var art_bounds := sprite_to_ui * sprite.get_rect()
 var bubble := %SpeakerBubble as Control
 var origin := Vector2(art_bounds.get_center().x - bubble.size.x * 0.5, art_bounds.position.y - bubble.size.y - 8.0)
 var nearby := world.player.position.distance_to(world.npc.position) <= world.player.interaction_distance
 var onscreen := play_rect().encloses(Rect2(origin, bubble.size))
 bubble.visible = world.npc.visible and is_noncombat() and onscreen and not combat_hud.npc_bubble.visible and not world.finished and not world.defeated and (_lab_dialogue_open or nearby) and not (world.use_fleet_demo and world.fleet_demo.locks_movement())
 bubble.position = origin
 bubble.tooltip_text = "답변을 기다리는 중" if not question.editable else "미카와 대화 가능"

func prepare_question(text: String) -> void:
 if not question.editable or question.is_composing(): return
 if not question.text.strip_edges().is_empty() and question.text != _last_submitted_question:
  _show_status("작성 중인 대화를 먼저 전송하거나 지워 주세요.")
  question.grab_focus()
  return
 question.text = text
 question.set_caret_line(0)
 question.set_caret_column(text.length())
 open_dialogue()

func toggle_settings() -> void:
 if pause_menu.visible or world.finished: return
 question.finish_editing()
 %DebugPanel.visible = not %DebugPanel.visible
 if not %DebugPanel.visible:
  for control in [%SettingsButton, %CloseSettings, %Provider, %RestartButton]:
   control.release_focus()
 _sync_input_mode()

func _measured(record: Dictionary) -> void:
 metric_label.text = "%s · %s\n모델 %s / %.1f ms / 실행 수락 %s\n거절 사유: %s\n이 값은 단일 요청 측정이며 논문 비교 결과가 아닙니다." % [record.provider, record.kind, record.get("actual_model", ""), record.elapsed_ms, record.accepted, record.rejected_reason]

func _input(event: InputEvent) -> void:
 if not is_node_ready() or not event is InputEventKey or not event.pressed or event.echo: return
 if world.transition_active():
  get_viewport().set_input_as_handled()
  return
 if world.finished: return
 var code: int = event.keycode if event.keycode != 0 else event.physical_keycode
 if world.use_fleet_demo and not pause_menu.visible and world.fleet_demo.locks_movement():
  if code in [KEY_ENTER, KEY_KP_ENTER] and world.fleet_demo.voice_active:
   world.fleet_demo.advance_dialogue()
  elif code == KEY_ESCAPE:
   toggle_pause()
  elif event.is_action_pressed("interact") and world.fleet_demo.allows_interact():
   return
  get_viewport().set_input_as_handled()
  return
 if combat_hud.modal_open():
  if code == KEY_ESCAPE: combat_hud.close_modal()
  elif code == KEY_M: combat_hud.toggle_map()
  elif code == KEY_H: combat_hud.toggle_history()
  get_viewport().set_input_as_handled()
 elif code in [KEY_M, KEY_H] and not question.has_focus() and not question.is_composing() and not pause_menu.visible and not %DebugPanel.visible:
  question.finish_editing()
  if code == KEY_M: combat_hud.toggle_map()
  else: combat_hud.toggle_history()
  get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
 if world.finished: return
 if not event is InputEventKey or not event.pressed or event.echo: return
 var code: int = event.keycode if event.keycode != 0 else event.physical_keycode
 if code == KEY_F3:
  toggle_settings()
  get_viewport().set_input_as_handled()
  return
 if %DebugPanel.visible:
  if code == KEY_ESCAPE: toggle_settings()
  get_viewport().set_input_as_handled()
  return
 if code == KEY_ESCAPE:
  if dialogue_panel.visible: close_dialogue()
  else: toggle_pause()
  get_viewport().set_input_as_handled()
  return
 if question.has_focus() or question.is_composing(): return
 match code:
  KEY_F12: capture_screen("manual")
  KEY_ENTER, KEY_KP_ENTER:
   if dialogue_panel.visible: question.request_submit()
   else: open_dialogue()
   get_viewport().set_input_as_handled()
func toggle_pause() -> void:
 if world.finished: return
 if pause_menu.visible:
  pause_menu.hide()
  get_tree().paused = false
 else:
  question.finish_editing()
  %DebugPanel.hide()
  combat_hud.get_node("HistoryPanel").hide()
  pause_menu.open_menu(not world.defeated and not world.finished and (not world.use_fleet_demo or world.fleet_demo.can_save()))
  get_tree().paused = true
 _sync_input_mode()

func save_slot(slot: int) -> bool:
 if world.transition_active(): return false
 if world.use_fleet_demo and not world.fleet_demo.can_save():
  pause_menu.show_result("연출이 끝난 뒤 저장할 수 있습니다.")
  return false
 if world.finished or world.defeated:
  pause_menu.show_result("사망·완료 후에는 저장할 수 없습니다.")
  return false
 var configuration := world.log_configuration()
 var data := {"version": MissionSaveStore.VERSION, "scenario": JSON.stringify(configuration).sha256_text(), "saved_at": Time.get_datetime_string_from_system(false, true), "provider": brain.provider, "world": world.save_snapshot(), "exploration": combat_hud.minimap.explored.duplicate(true), "atlas": combat_hud.minimap.snapshot(), "journal": combat_hud.journal.entries.duplicate(true), "history": brain.history.duplicate(true)}
 if not save_store.validate(data, world) or not save_store.write_slot(slot, data):
  pause_menu.show_result(save_store.last_error)
  return false
 pause_menu.show_result("슬롯 %d 저장 완료. 진행 중 지원은 불러올 때 취소됩니다." % slot)
 return true

func load_slot(slot: int) -> bool:
 if world.finished: return false
 var data := save_store.read_slot(slot)
 if data.is_empty() or not save_store.validate(data, world):
  pause_menu.show_result(save_store.last_error)
  return false
 # 이전 요청·질문·탄환·화면 발화를 버린 뒤 새 epoch의 상태를 복원한다.
 brain.cancel_pending("save_loaded")
 brain.queued_question = ""
 brain.clock = 0.0
 brain.provider = int(data.provider)
 brain.jev_disabled = ""
 brain.history.assign(data.history)
 _combat_chat_open = false
 world.restore_snapshot(data.world)
 _lab_dialogue_open = not world.use_fleet_demo
 combat_hud.clear_speech()
 combat_hud.transcript.clear()
 combat_hud.restore_journal(data.get("journal", []))
 combat_hud.minimap.restore_exploration(data.exploration)
 combat_hud.minimap.restore_atlas(data.get("atlas", {}))
 _radio_error = false
 _last_submitted_question = ""
 _chat_sent = false
 _chat_idle = 0
 question.finish_editing()
 question.text = ""
 _enable_question()
 answer.text = NPCPolicy.opening_line(world.game_state())
 %Provider.select(brain.provider)
 update_state()
 combat_hud.update_view(0)
 if pause_menu.visible: toggle_pause()
 _show_status(("슬롯 %d 불러오기 완료 · 이전 저장의 손전등을 복원했습니다." if data.get("migrated_from") == 1 else "슬롯 %d 불러오기 완료") % slot)
 return true

func _exit_tree() -> void:
 if get_tree(): get_tree().paused = false

func _return_to_title() -> void:
 brain.cancel_pending("title_return")
 if title_requested.has_connections():
  title_requested.emit()
 else:
  get_tree().change_scene_to_file("res://scenes/ui/TitleMenu.tscn")

func _begin_ending() -> void:
 brain.cancel_pending("demo_ending")
 combat_hud.clear_speech()
 combat_hud.close_modal()
 question.finish_editing()
 question.text = ""
 dialogue_panel.hide()
 _combat_chat_open = false
 %DebugPanel.hide()
 pause_menu.hide()
 get_tree().paused = false
 var content := result_screen.get_node("Center/Card/Margin/Content")
 content.get_node("Objective").text = "연구실 B동 임시 격리 완료" if world.use_fleet_demo else "연구동 외곽 구역 봉쇄 성공"
 content.get_node("Afterword").text = "두 코어의 레버로 임시 격벽을 설치했습니다.\n후속 대응은 지원부서가 맡습니다." if world.use_fleet_demo else "외곽의 침식 확산을 일시적으로 차단했습니다.\n연구동 내부의 이상현상은 후속 조사가 필요합니다."
 _ending_elapsed = ENDING_SECONDS if world.use_fleet_demo else 0.0
 _sync_input_mode()

func _update_fleet_cues() -> void:
 var cues := $FleetCues
 var demo := world.fleet_demo
 var item := demo.nearest_interaction() if not world.finished and not world.defeated and not dialogue_panel.visible and not combat_hud.modal_open() else {}
 if item.get("id", "") == "eroded_stop" and not demo.allows_interact(): item = {}
 var text: String = demo.hint
 if not item.is_empty():
  text += ("\n" if not text.is_empty() else "") + "[E]  " + str(item.name)
 cues.get_node("Subtitle/Text").text = text
 var shown := not text.is_empty() and not dialogue_panel.visible and not combat_hud.modal_open() and not world.transition_active() and not world.finished
 cues.get_node("Subtitle").visible = shown
 if shown or not world.npc.visible: %TalkPrompt.hide()
 elif is_noncombat() and not dialogue_panel.visible and not demo.locks_movement(): %TalkPrompt.show()
 for pair in [["PlayerReaction", world.player], ["MikaReaction", world.npc]]:
  var marker := cues.get_node(pair[0]) as Label
  marker.visible = _fleet_reaction
  if _fleet_reaction:
   var actor: Node2D = pair[1]
   var art := actor.get_node("Sprite2D") as Sprite2D
   var point := combat_hud.screen_point(actor)
   var art_top := point.y + art.get_rect().position.y * _camera_zoom
   marker.position = Vector2(point.x - marker.size.x * 0.5, art_top - marker.size.y - 4)

func capture_screen(stem: String) -> void:
 await RenderingServer.frame_post_draw
 DirAccess.make_dir_recursive_absolute(log_dir)
 get_viewport().get_texture().get_image().save_png(log_dir.path_join(stem + ".png"))

func _run_evidence() -> void:
 var runner = load("res://scripts/mission_evidence.gd").new()
 await runner.run(self)
