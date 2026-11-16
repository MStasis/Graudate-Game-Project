extends Control

const MISSION := preload("res://main.tscn")
# The launcher can run with a class cache from an earlier editor session.
const MissionScript := preload("res://main.gd")
const MasterVolume := preload("res://scripts/master_volume.gd")

@onready var _actions: VBoxContainer = %Actions
@onready var _slots: VBoxContainer = %Slots
@onready var _settings: VBoxContainer = %SettingsPanel
@onready var _master_volume: MasterVolume = %MasterVolume
@onready var _slot_buttons: Array[Button] = [%Slot1, %Slot2, %Slot3]
@onready var _entry_fade: ColorRect = $TransitionLayer/EntryFade
var _store := MissionSaveStore.new()
var _mission: MissionScript
var _trial := 0
var _request_id := 0
var _fade_tween: Tween
var _fleet_saves_only := true

func _ready() -> void:
 var arguments := OS.get_cmdline_user_args()
 _fleet_saves_only = "--mission-evidence" not in arguments and "--mission-test" not in arguments
 get_window().title = "BEYOND THE BULKHEAD"
 %NewGame.pressed.connect(_start_mission, CONNECT_DEFERRED)
 %Continue.pressed.connect(_show_slots)
 %Settings.pressed.connect(_show_settings)
 %Quit.pressed.connect(func(): get_tree().quit())
 %Back.pressed.connect(_show_actions)
 %SettingsBack.pressed.connect(_close_settings)
 for index in _slot_buttons.size():
  _slot_buttons[index].pressed.connect(_start_mission.bind(index + 1), CONNECT_DEFERRED)
 _show_actions()
 # Keep the automated mission capture entry point available.
 if "--mission-evidence" in OS.get_cmdline_user_args():
  _start_mission.call_deferred()

func _show_actions() -> void:
 _slots.hide()
 _settings.hide()
 _actions.show()
 %Continue.disabled = not [1, 2, 3].any(func(slot): return _store.has_slot(slot, _fleet_saves_only))
 %Continue.tooltip_text = "저장된 슬롯이 없습니다." if %Continue.disabled else ""
 if %Continue.disabled:
  %NewGame.grab_focus()
 else:
  %Continue.grab_focus()

func _show_slots() -> void:
 _actions.hide()
 _slots.show()
 %SlotMessage.text = "불러올 저장 슬롯을 선택하세요."
 var first_available: Button
 for index in _slot_buttons.size():
  var slot := index + 1
  var button := _slot_buttons[index]
  button.disabled = not _store.has_slot(slot, _fleet_saves_only)
  button.text = "슬롯 %d  ·  %s" % [slot, _store.slot_label(slot, _fleet_saves_only)]
  button.tooltip_text = button.text
  if not button.disabled and not first_available:
   first_available = button
 if first_available:
  first_available.grab_focus()
 else:
  %Back.grab_focus()

func _show_settings() -> void:
 _actions.hide()
 _master_volume.load_setting()
 _settings.show()
 _master_volume.grab_focus()

func _close_settings() -> void:
 _master_volume.save_setting()
 _show_actions()
 %Settings.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
 if not $Menu.visible or not event.is_action_pressed("ui_cancel"): return
 if _settings.visible:
  _close_settings()
  get_viewport().set_input_as_handled()
 elif _slots.visible:
  _show_actions()
  get_viewport().set_input_as_handled()

func _start_mission(slot := 0) -> void:
 if _mission: return
 _mission = MISSION.instantiate()
 _mission.world_starts_fleet_demo = slot == 0 and _fleet_saves_only
 _mission.fleet_saves_only = _fleet_saves_only
 _mission.save_store = _store
 # Keep trial and request IDs distinct within the same process.
 var brain := _mission.get_node("NPCBrain") as NPCBrain
 brain.trial = _trial
 brain.serial = _request_id
 _mission.title_requested.connect(_return_to_title, CONNECT_DEFERRED)
 add_child(_mission)
 if slot != 0 and not _mission.load_slot(slot):
  var error := _store.last_error
  _discard_mission()
  _show_slots()
  %SlotMessage.text = "슬롯 %d · %s" % [slot, error]
  return
 $Menu.hide()
 if slot == 0:
  _entry_fade.modulate.a = 1.0
  _entry_fade.show()
  _fade_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
  _fade_tween.tween_property(_entry_fade, "modulate:a", 0.0, 0.32)
  _fade_tween.tween_callback(_entry_fade.hide)

func _return_to_title() -> void:
 if not _mission: return
 if _fade_tween: _fade_tween.kill()
 _entry_fade.hide()
 _discard_mission()
 $Menu.show()
 _show_actions()

func _discard_mission() -> void:
 _trial = _mission.brain.trial
 _request_id = _mission.brain.serial
 remove_child(_mission)
 _mission.queue_free()
 _mission = null
