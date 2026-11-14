class_name MissionPauseMenu
extends Control
signal save_selected(slot: int)
signal load_selected(slot: int)
signal close_requested
signal title_requested
var choosing_load := false
var can_save := true
var overwrite_slot := 0
var store: MissionSaveStore

func _ready() -> void:
 process_mode = Node.PROCESS_MODE_ALWAYS
 hide()
 $Window/Save.pressed.connect(func(): show_slots(false))
 $Window/Load.pressed.connect(func(): show_slots(true))
 $Window/Close.pressed.connect(func(): close_requested.emit())
 $Window/ReturnToTitle.pressed.connect(func(): title_requested.emit())
 $Window/Slots/Back.pressed.connect(func():
  $Window/Slots.hide()
  overwrite_slot = 0)
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

func open_menu(allowed: bool) -> void:
 can_save = allowed
 overwrite_slot = 0
 $Window/Save.disabled = not can_save
 $Window/Slots.hide()
 $Window/Message.text = "게임이 일시정지되었습니다." if can_save else "현재 상태에서는 저장할 수 없습니다."
 layout()
 show()

func show_slots(load_mode: bool) -> void:
 choosing_load = load_mode
 overwrite_slot = 0
 $Window/Slots.show()
 $Window/Slots/Title.text = "불러올 저장 선택" if load_mode else "저장할 슬롯 선택"
 for slot in range(1, 4):
  var button := get_node("Window/Slots/Slot%d" % slot) as Button
  button.text = "슬롯 %d  ·  %s" % [slot, store.slot_label(slot)]
  button.disabled = not store.has_slot(slot) if load_mode else not can_save
 $Window/Message.text = "저장된 슬롯이 없으면 먼저 저장해 주세요." if load_mode else "기존 슬롯은 한 번 더 눌러 덮어씁니다."

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
