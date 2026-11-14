extends Control

const MISSION := preload("res://main.tscn")
# The launcher can run with a class cache from an earlier editor session.
const MissionScript := preload("res://main.gd")

@onready var _actions: VBoxContainer = %Actions
@onready var _slots: VBoxContainer = %Slots
@onready var _slot_buttons: Array[Button] = [%Slot1, %Slot2, %Slot3]
var _store := MissionSaveStore.new()
var _mission: MissionScript
var _trial := 0
var _request_id := 0

func _ready() -> void:
 %NewGame.pressed.connect(_start_mission, CONNECT_DEFERRED)
 %Continue.pressed.connect(_show_slots)
 %Quit.pressed.connect(func(): get_tree().quit())
 %Back.pressed.connect(_show_actions)
 for index in _slot_buttons.size():
  _slot_buttons[index].pressed.connect(_start_mission.bind(index + 1), CONNECT_DEFERRED)
 _show_actions()
 # Keep the automated mission capture entry point available.
 if "--mission-evidence" in OS.get_cmdline_user_args():
  _start_mission.call_deferred()

func _show_actions() -> void:
 _slots.hide()
 _actions.show()
 %Continue.disabled = not (_store.has_slot(1) or _store.has_slot(2) or _store.has_slot(3))
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
  button.disabled = not _store.has_slot(slot)
  button.text = "슬롯 %d  ·  %s" % [slot, _store.slot_label(slot)]
  button.tooltip_text = button.text
  if not button.disabled and not first_available:
   first_available = button
 if first_available:
  first_available.grab_focus()
 else:
  %Back.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
 if $Menu.visible and _slots.visible and event.is_action_pressed("ui_cancel"):
  _show_actions()
  get_viewport().set_input_as_handled()

func _start_mission(slot := 0) -> void:
 if _mission: return
 _mission = MISSION.instantiate()
 var arguments := OS.get_cmdline_user_args()
 _mission.world_starts_fleet_demo = slot == 0 and "--mission-evidence" not in arguments and "--mission-test" not in arguments
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

func _return_to_title() -> void:
 if not _mission: return
 _discard_mission()
 $Menu.show()
 _show_actions()

func _discard_mission() -> void:
 _trial = _mission.brain.trial
 _request_id = _mission.brain.serial
 remove_child(_mission)
 _mission.queue_free()
 _mission = null
