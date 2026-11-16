extends Control

signal close_requested

@onready var _dialogue_tab: Button = %DialogueTab
@onready var _system_tab: Button = %SystemTab
@onready var _scroll: ScrollContainer = %Scroll
@onready var _entries_box: VBoxContainer = %Entries
@onready var _empty: Label = %Empty
@onready var _new_messages: Button = %NewMessages
var _entries: Array[Dictionary] = []
var _render_revision := 0
var _channel := "dialogue"
var _refresh_queued := false

func _ready() -> void:
 %Close.pressed.connect(close_requested.emit)
 _dialogue_tab.pressed.connect(_show_channel.bind("dialogue"))
 _system_tab.pressed.connect(_show_channel.bind("system"))
 _new_messages.pressed.connect(scroll_to_latest)

func open(entries: Array[Dictionary]) -> void:
 _entries = entries
 show()
 _show_channel("dialogue")
 %Close.grab_focus()

func _show_channel(channel: String) -> void:
 _channel = channel
 _dialogue_tab.set_pressed_no_signal(channel == "dialogue")
 _system_tab.set_pressed_no_signal(channel == "system")
 _new_messages.hide()
 _render_entries()

func refresh(channel: String) -> void:
 if not visible or channel != _channel or _refresh_queued: return
 _refresh_queued = true
 _refresh_entries.call_deferred(channel)

func _refresh_entries(channel: String) -> void:
 _refresh_queued = false
 if not visible or channel != _channel: return
 var bar := _scroll.get_v_scroll_bar()
 var reading_earlier := bar.value < bar.max_value - bar.page - 4
 _new_messages.visible = reading_earlier
 _render_entries(_scroll.scroll_vertical if reading_earlier else -1)

func scroll_to_latest() -> void:
 _scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
 _new_messages.hide()

func _render_entries(saved_scroll := -1) -> void:
 for child in _entries_box.get_children():
  _entries_box.remove_child(child)
  child.queue_free()
 for entry in _entries:
  if entry.get("channel") == _channel:
   if _entries_box.get_child_count() > 0: _entries_box.add_child(HSeparator.new())
   _add_line(str(entry.get("sender", "")), str(entry.get("body", "")), int(entry.get("repeat", 1)))
 _empty.visible = _entries_box.get_child_count() == 0
 _empty.text = "아직 기록된 대사가 없습니다." if _channel == "dialogue" else "아직 기록된 시스템 알림이 없습니다."
 _render_revision += 1
 var revision := _render_revision
 await get_tree().process_frame
 if revision == _render_revision and is_visible_in_tree():
  if saved_scroll < 0: scroll_to_latest()
  else: _scroll.scroll_vertical = saved_scroll

func _add_line(speaker: String, body: String, repeat: int) -> void:
 var row := HBoxContainer.new()
 row.add_theme_constant_override("separation", 16)
 _entries_box.add_child(row)

 var name_label := Label.new()
 name_label.custom_minimum_size.x = 100
 name_label.theme_type_variation = &"HUDAccent" if speaker == "미카" else &"HUDSecondary"
 name_label.text = speaker
 row.add_child(name_label)

 var body_label := Label.new()
 body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 body_label.text = body + (" ×%d" % repeat if repeat > 1 else "")
 row.add_child(body_label)
