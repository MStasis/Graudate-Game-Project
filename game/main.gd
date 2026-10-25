extends Control
@onready var world: DemoWorld = %World
@onready var brain: NPCBrain = $NPCBrain
@onready var answer: RichTextLabel = %Answer
@onready var question: ChatInput = %Question
@onready var status: Label = %Status
@onready var state_label: Label = %StateSummary
@onready var metric_label: Label = %Metrics
@onready var send_button: Button = %SendButton
var log_dir := ""
var evidence_mode := false
var _health_tween: Tween
var _last_submitted_question := ""
var _radio_error := false
const UI_TEAL := Color("74c6b6")
const UI_AMBER := Color("d3a66e")
const UI_DANGER := Color("dc8576")

func _ready() -> void:
 evidence_mode = "--mission-evidence" in OS.get_cmdline_user_args()
 log_dir = ProjectSettings.globalize_path("res://../evidence/mission_v1").simplify_path()
 if "--chat-input-test" in OS.get_cmdline_user_args():
  brain.auto_enabled = false
  brain.run_kind = "chat_input_regression"
  log_dir = ProjectSettings.globalize_path("res://../evidence/chat_input_fix").simplify_path()
 if "--ui-layout-test" in OS.get_cmdline_user_args():
  brain.auto_enabled = false
  brain.run_kind = "ui_redesign_regression"
  log_dir = ProjectSettings.globalize_path("res://../evidence/ui_redesign").simplify_path()
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
 world.notice.connect(func(text): %Callout.text = text)
 brain.dialogue_ready.connect(func(text):
  _radio_error = false
  answer.text = text
  _enable_question())
 brain.dialogue_error.connect(func(message):
  _radio_error = true
  answer.text = "[답변 미제공] " + message
  _enable_question())
 brain.status_changed.connect(_show_status)
 brain.measured.connect(_measured)
 question.text_submitted.connect(_send_question)
 question.validation_failed.connect(_show_status)
 question.focus_entered.connect(_sync_input_mode)
 question.focus_exited.connect(_sync_input_mode)
 send_button.pressed.connect(ask_npc)
 %RestartButton.pressed.connect(reset_demo)
 %SettingsButton.pressed.connect(toggle_settings)
 %CloseSettings.pressed.connect(toggle_settings)
 %MissionPrompt.pressed.connect(func(): prepare_question("지금 뭘 해야 해?"))
 %SupportPrompt.pressed.connect(func(): prepare_question("지금 어떻게 도와줄 수 있어?"))
 %EverydayPrompt.pressed.connect(func(): prepare_question("오늘 기분은 어때?"))
 for label_name in ["RoomTitle", "GoalText", "ControlsHint"]:
  world.get_node(label_name).hide()
 brain.setup(world, log_dir)
 %Provider.select(brain.provider)
 %Provider.item_selected.connect(func(index): reset_demo(index))
 update_state()
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
 %Location.text = "보관 구역" if world.map_id == "storage" else "연구실"
 var step := 1
 if world.map_id == "storage": step = 2
 if world.fuse_collected: step = 3
 if world.power_restored: step = 4
 %MissionStep.text = "%02d / 04  ·  목표" % step
 if world.finished: %MissionStep.text = "04 / 04  ·  완료"
 if world.defeated: %MissionStep.text = "임무 중단"
 var provider_names := ["규칙 기반", "로컬 LLM", "Jev"]
 %ProviderBadge.text = "판단 방식 · " + provider_names[brain.provider]

func interact(kind: String) -> void:
 if kind == "npc":
  question.grab_focus()
  return
 _show_status(world.apply_interaction(kind))

func reset_demo(mode: int = -1) -> void:
 question.finish_editing()
 brain.new_trial(mode)
 %Provider.select(brain.provider)
 _radio_error = false
 _last_submitted_question = ""
 _enable_question()
 answer.text = "같이 보관 구역에 가자. 질문이 있으면 편하게 말해."
 %Callout.text = "같은 시작 조건으로 새 회차를 시작했습니다."
 update_state()
 _sync_input_mode()

func ask_npc() -> void:
 question.request_submit()

func _send_question(message: String) -> void:
 _radio_error = false
 _last_submitted_question = message
 send_button.disabled = true
 question.finish_editing()
 question.editable = false
 _set_prompts_enabled(false)
 _update_radio_state("응답 중", UI_AMBER)
 answer.text = "하린의 답변을 기다리는 중…"
 _show_status("응답 대기 중에도 이동할 수 있습니다. 전투는 계속됩니다.")
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
 world.can_move = not question.has_focus() and not %DebugPanel.visible
 if not question.editable: _update_radio_state("응답 중", UI_AMBER)
 elif _radio_error: _update_radio_state("응답 오류", UI_DANGER)
 elif question.has_focus(): _update_radio_state("입력 중", UI_AMBER)
 else: _update_radio_state("대기", UI_TEAL)

func _show_status(message: String) -> void:
 status.text = message
 status.tooltip_text = message

func prepare_question(text: String) -> void:
 if not question.editable or question.is_composing(): return
 if not question.text.strip_edges().is_empty() and question.text != _last_submitted_question:
  _show_status("작성 중인 대화를 먼저 전송하거나 지워 주세요.")
  question.grab_focus()
  return
 question.text = text
 question.set_caret_line(0)
 question.set_caret_column(text.length())
 question.grab_focus()

func toggle_settings() -> void:
 question.finish_editing()
 %DebugPanel.visible = not %DebugPanel.visible
 if not %DebugPanel.visible:
  for control in [%SettingsButton, %CloseSettings, %Provider, %RestartButton]:
   control.release_focus()
 _sync_input_mode()

func _measured(record: Dictionary) -> void:
 metric_label.text = "%s · %s\n모델 %s / %.1f ms / 실행 수락 %s\n거절 사유: %s\n이 값은 단일 요청 측정이며 논문 비교 결과가 아닙니다." % [record.provider, record.kind, record.get("actual_model", ""), record.elapsed_ms, record.accepted, record.rejected_reason]

func _unhandled_key_input(event: InputEvent) -> void:
 if not event is InputEventKey or not event.pressed or event.echo: return
 if event.physical_keycode == KEY_F3:
  toggle_settings()
  get_viewport().set_input_as_handled()
  return
 if %DebugPanel.visible:
  if event.physical_keycode == KEY_ESCAPE: toggle_settings()
  get_viewport().set_input_as_handled()
  return
 if question.has_focus() or question.is_composing(): return
 match event.physical_keycode:
  KEY_F12: capture_screen("manual")
  KEY_ENTER: question.grab_focus()

func capture_screen(stem: String) -> void:
 await RenderingServer.frame_post_draw
 DirAccess.make_dir_recursive_absolute(log_dir)
 get_viewport().get_texture().get_image().save_png(log_dir.path_join(stem + ".png"))

func _run_evidence() -> void:
 var runner = load("res://scripts/mission_evidence.gd").new()
 await runner.run(self)
