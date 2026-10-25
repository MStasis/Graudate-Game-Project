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

func _ready() -> void:
 evidence_mode = "--mission-evidence" in OS.get_cmdline_user_args()
 log_dir = ProjectSettings.globalize_path("res://../evidence/mission_v1").simplify_path()
 if "--chat-input-test" in OS.get_cmdline_user_args():
  brain.auto_enabled = false
  brain.run_kind = "chat_input_regression"
  log_dir = ProjectSettings.globalize_path("res://../evidence/chat_input_fix").simplify_path()
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
  answer.text = world.npc.display_name + ": " + text
  _enable_question())
 brain.dialogue_error.connect(func(message):
  answer.text = "[답변 미제공] " + message
  _enable_question())
 brain.status_changed.connect(func(message): status.text = message)
 brain.measured.connect(_measured)
 question.text_submitted.connect(_send_question)
 question.validation_failed.connect(func(message): status.text = message)
 question.focus_entered.connect(func(): world.can_move = false)
 question.focus_exited.connect(func(): world.can_move = true)
 send_button.pressed.connect(ask_npc)
 %RestartButton.pressed.connect(reset_demo)
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

func interact(kind: String) -> void:
 if kind == "npc":
  question.grab_focus()
  return
 status.text = world.apply_interaction(kind)

func reset_demo(mode: int = -1) -> void:
 question.finish_editing()
 brain.new_trial(mode)
 _enable_question()
 answer.text = world.npc.display_name + ": 같이 보관 구역에 가자. 질문이 있으면 편하게 말해."
 %Callout.text = "같은 시작 조건으로 새 회차를 시작했습니다."
 update_state()

func ask_npc() -> void:
 question.request_submit()

func _send_question(message: String) -> void:
 send_button.disabled = true
 question.finish_editing()
 question.editable = false
 answer.text = "[하린의 답변을 기다리는 중 · 게임은 계속 진행됩니다]"
 if not brain.request_dialogue(message): _enable_question()

func _enable_question() -> void:
 send_button.disabled = false
 question.editable = true

func _measured(record: Dictionary) -> void:
 metric_label.text = "%s · %s\n모델 %s / %.1f ms / 실행 수락 %s\n거절 사유: %s\n이 값은 단일 요청 측정이며 논문 비교 결과가 아닙니다." % [record.provider, record.kind, record.get("actual_model", ""), record.elapsed_ms, record.accepted, record.rejected_reason]

func _unhandled_key_input(event: InputEvent) -> void:
 if question.has_focus() or question.is_composing(): return
 if not event is InputEventKey or not event.pressed or event.echo: return
 match event.physical_keycode:
  KEY_F3: %DebugPanel.visible = not %DebugPanel.visible
  KEY_F12: capture_screen("manual")
  KEY_ENTER: question.grab_focus()

func capture_screen(stem: String) -> void:
 await RenderingServer.frame_post_draw
 DirAccess.make_dir_recursive_absolute(log_dir)
 get_viewport().get_texture().get_image().save_png(log_dir.path_join(stem + ".png"))

func _run_evidence() -> void:
 var runner = load("res://scripts/mission_evidence.gd").new()
 await runner.run(self)
