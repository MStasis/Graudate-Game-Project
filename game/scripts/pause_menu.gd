class_name MissionPauseMenu
extends Control
const MasterVolume := preload("res://scripts/master_volume.gd")
signal save_selected(slot: int)
signal load_selected(slot: int)
signal close_requested
signal title_requested
var choosing_load := false
var can_save := true
var fleet_saves_only := false
var overwrite_slot := 0
var store: MissionSaveStore
@onready var _master_volume: MasterVolume = $Window/AudioSettings/MasterVolume

func _ready() -> void:
 process_mode = Node.PROCESS_MODE_ALWAYS
 hide()
 $Window/Save.pressed.connect(func(): show_slots(false))
 $Window/Load.pressed.connect(func(): show_slots(true))
 $Window/Settings.pressed.connect(_open_settings)
 $Window/AudioSettings/Back.pressed.connect(close_settings)
 $Window/Close.pressed.connect(func(): close_requested.emit())
 $Window/ReturnToTitle.pressed.connect(func(): title_requested.emit())
 $Window/Slots/Back.pressed.connect(_show_actions)
 for index in range(1, 4):
  var slot := index
  get_node("Window/Slots/Slot%d" % slot).pressed.connect(func(): choose_slot(slot))
 get_parent().resized.connect(layout)
 layout()

func layout() -> void:
 var canvas: Vector2 = get_parent().size
 size = canvas
 $Shade.size = canvas
 $Window.position = (canvas - $Window.size) * 0.5

func open_menu(allowed: bool, fleet_only := false) -> void:
 can_save = allowed
 fleet_saves_only = fleet_only
 $Window/Save.disabled = not can_save
 _show_actions()
 layout()
 show()

func _show_actions() -> void:
 overwrite_slot = 0
 $Window/Slots.hide()
 $Window/AudioSettings.hide()
 $Window/Close.text = "계속하기  Esc"
 _set_actions_visible(true)
 $Window/Message.text = "" if can_save else "현재 상태에서는 저장할 수 없습니다."

func _set_actions_visible(active: bool) -> void:
 $Window/Save.visible = active
 $Window/Load.visible = active
 $Window/Settings.visible = active
 $Window/ReturnToTitle.visible = active

func _open_settings() -> void:
 _set_actions_visible(false)
 $Window/Message.text = ""
 $Window/Close.text = "계속하기"
 _master_volume.load_setting()
 $Window/AudioSettings.show()
 _master_volume.grab_focus()

func close_settings() -> bool:
 if not $Window/AudioSettings.visible: return false
 _master_volume.save_setting()
 _show_actions()
 $Window/Settings.grab_focus()
 return true

func show_slots(load_mode: bool) -> void:
 choosing_load = load_mode
 overwrite_slot = 0
 _set_actions_visible(false)
 $Window/Slots.show()
 $Window/Slots/Title.text = "불러올 저장 선택" if load_mode else "저장할 슬롯 선택"
 var filter_legacy := load_mode and fleet_saves_only
 var available := false
 for slot in range(1, 4):
  var button := get_node("Window/Slots/Slot%d" % slot) as Button
  button.text = "슬롯 %d  ·  %s" % [slot, store.slot_label(slot, filter_legacy)]
  button.disabled = not store.has_slot(slot, filter_legacy) if load_mode else not can_save
  available = available or not button.disabled
 $Window/Message.text = ("" if available else "불러올 수 있는 저장이 없습니다.") if load_mode else "기존 슬롯은 한 번 더 눌러 덮어씁니다."

func choose_slot(slot: int) -> void:
 if choosing_load:
  load_selected.emit(slot)
  return
 if not can_save: return
 if store.has_slot(slot) and overwrite_slot != slot:
  overwrite_slot = slot
  $Window/Message.text = "슬롯 %d를 덮어쓰려면 같은 슬롯을 한 번 더 눌러 주세요." % slot
  return
 overwrite_slot = 0
 save_selected.emit(slot)

func show_result(message: String) -> void:
 $Window/Message.text = message
