class_name ChatInput
extends TextEdit
## TextEdit는 조합 표시를 담당하고 Windows 확정 문자는 전용 연결 모듈로 받습니다.
signal text_submitted(value: String)
signal validation_failed(message: String)
@export_range(1, 300, 1) var message_limit: int = 300
var _submit_queued := false
var _native_bridge: Node
var _native_commit_characters := 0
var _reported_first_commit := false

func _ready() -> void:
 if OS.get_name() != "Windows" or DisplayServer.get_name() == "headless" or Engine.is_editor_hint(): return
 if not ClassDB.class_exists("WindowsIMEBridge"):
  GDExtensionManager.load_extension("res://native/windows_ime/windows_ime.gdextension")
 if not ClassDB.class_exists("WindowsIMEBridge"):
  push_warning("Windows IME bridge is unavailable; using the engine input path.")
  _write_native_status("module_unavailable")
  return
 _native_bridge = ClassDB.instantiate("WindowsIMEBridge") as Node
 add_child(_native_bridge)
 var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, get_window().get_window_id())
 if not _native_bridge.call("attach", handle):
  push_warning("Windows IME bridge attach failed: %s" % _native_bridge.call("get_last_error"))
  _native_bridge.queue_free()
  _native_bridge = null
  _write_native_status("attach_failed")
  return
 focus_entered.connect(func(): _native_bridge.call("set_active", editable))
 focus_exited.connect(func():
  _flush_native_commits()
  _native_bridge.call("set_active", false))
 if has_focus(): _native_bridge.call("set_active", editable)
 _write_native_status("attached")

func _process(_delta: float) -> void:
 _flush_native_commits()

func _input(event: InputEvent) -> void:
 if not _native_bridge or not has_focus() or not editable: return
 _flush_native_commits()
 # TextEdit의 포커스 해제 처리보다 먼저 Windows 조합을 확정합니다.
 if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
  commit_composition()
 elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
  if not get_global_rect().has_point(get_global_mouse_position()): commit_composition()

func _flush_native_commits() -> void:
 if not is_instance_valid(_native_bridge): return
 var committed := str(_native_bridge.call("drain_commits"))
 if not committed.is_empty() and editable:
  insert_text_at_caret(committed)
  _native_commit_characters += committed.length()
  if not _reported_first_commit:
   _reported_first_commit = true
   _write_native_status("first_commit")

func _write_native_status(phase: String) -> void:
 if DisplayServer.get_name() == "headless": return
 var attached := is_instance_valid(_native_bridge) and bool(_native_bridge.call("is_attached"))
 var record := {"phase": phase, "backend": "windows_native_commit_bridge_v1", "run_id": OS.get_process_id(), "attached": attached, "inserted_characters": _native_commit_characters, "screen_automation_used": false}
 if attached:
  record["ime_result_events"] = _native_bridge.call("get_capture_count")
  record["suppressed_duplicates"] = _native_bridge.call("get_suppressed_count")
 var directory := ProjectSettings.globalize_path("res://../evidence/native_ime_fix").simplify_path()
 DirAccess.make_dir_recursive_absolute(directory)
 var file := FileAccess.open(directory.path_join("bridge_status_" + str(OS.get_process_id()) + ".json"), FileAccess.WRITE)
 if file: file.store_string(JSON.stringify(record, "  "))

func finish_editing() -> void:
 commit_composition()
 _flush_native_commits()
 release_focus()

func _exit_tree() -> void:
 if is_instance_valid(_native_bridge):
  _write_native_status("closing")
  _native_bridge.call("detach")

func is_composing() -> bool:
 return has_ime_text()

func commit_composition() -> void:
 _flush_native_commits()
 if is_composing():
  if _native_bridge:
   _native_bridge.call("complete_composition")
   _flush_native_commits()
  else: apply_ime()

func request_submit() -> bool:
 if not editable or _submit_queued: return false
 _submit_queued = true
 # 포커스 해제/읽기 전용 전환보다 먼저 마지막 조합 글자를 본문에 확정합니다.
 commit_composition()
 _finish_submit.call_deferred()
 return true

func _finish_submit() -> void:
 # OS 확정 이벤트와 TextEdit의 지연 변경 신호가 처리될 시간을 줍니다.
 await get_tree().process_frame
 _submit_queued = false
 if not editable: return
 if is_composing():
  validation_failed.emit("글자 조합을 마친 뒤 다시 전송해 주세요.")
  return
 var message := text.strip_edges()
 if message.is_empty(): return
 if message.length() > message_limit:
  validation_failed.emit("질문은 %d자 이내로 입력해 주세요. 입력한 내용은 유지했습니다." % message_limit)
  return
 text_submitted.emit(message)

func _gui_input(event: InputEvent) -> void:
 _flush_native_commits()
 if not event is InputEventKey or not event.pressed: return
 if event.keycode in [KEY_ENTER, KEY_KP_ENTER] or event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
  accept_event()
  if not event.echo: request_submit()
 elif event.keycode == KEY_ESCAPE:
  accept_event()
  if is_composing():
   if _native_bridge: _native_bridge.call("cancel_composition")
   cancel_ime()
  else: release_focus()
