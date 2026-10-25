extends SceneTree
var checks := {}
func _initialize() -> void:
 call_deferred("run")
func check(name: String, value: bool) -> void:
 checks[name] = value
 if not value: push_error("CHAT_CHECK_FAILED " + name)
func frames(count: int = 4) -> void:
 for index in range(count): await process_frame
func key(code: int, unicode_value: int = 0, echo_value: bool = false) -> void:
 var event := InputEventKey.new()
 event.pressed = true
 event.keycode = code
 event.physical_keycode = code
 event.unicode = unicode_value
 event.echo = echo_value
 root.push_input(event, true)
 await process_frame

func run() -> void:
 var app = load("res://main.tscn").instantiate()
 root.add_child(app)
 await process_frame
 app.brain.auto_enabled = false
 app.brain.run_kind = "chat_input_regression"
 var field: ChatInput = app.question
 check("uses_composition_aware_textedit", field is TextEdit and field.has_method("request_submit"))
 check("input_starts_empty", field.text.is_empty())
 field.grab_focus()
 var expected := ""
 for character in "안녕하세요":
  expected += character
  await key(0, character.unicode_at(0))
  check("preserves_prefix_" + str(expected.length()), field.text == expected)
 check("caret_after_five_syllables", field.get_caret_column() == 5)
 await key(KEY_BACKSPACE)
 check("backspace_removes_only_last_syllable", field.text == "안녕하세")
 await key(0, "요".unicode_at(0))
 check("can_reenter_deleted_syllable", field.text == "안녕하세요")
 field.select(0, 1, 0, 2)
 await key(0, "뇽".unicode_at(0))
 check("selection_replaces_only_selected_syllable", field.text == "안뇽하세요")
 field.text = "한글 English 123 日本語 🙂"
 field.set_caret_column(field.text.length())
 var retained := field.text
 field.release_focus()
 await frames()
 check("focus_loss_preserves_committed_text", field.text == retained)
 field.grab_focus()
 var submissions: Array[String] = []
 field.text_submitted.connect(func(message): submissions.append(message))
 field.text = "안녕하세요"
 field.set_caret_column(5)
 await key(KEY_ENTER)
 await frames()
 check("enter_submits_complete_message", submissions.size() == 1 and submissions[0] == "안녕하세요")
 check("enter_does_not_insert_newline", field.text == "안녕하세요")
 check("game_receives_complete_message", app.brain.history.size() == 1 and app.brain.history[0].question == "안녕하세요")
 field.grab_focus()
 await key(KEY_ENTER, 0, true)
 await frames()
 check("held_enter_does_not_repeat_submission", submissions.size() == 1)
 field.text = ""
 field.request_submit()
 await frames()
 check("empty_message_is_not_submitted", submissions.size() == 1)
 field.text = "한".repeat(301)
 var errors: Array[String] = []
 field.validation_failed.connect(func(message): errors.append(message))
 field.request_submit()
 await frames()
 check("over_limit_not_submitted", submissions.size() == 1 and not errors.is_empty())
 check("over_limit_does_not_destroy_input", field.text.length() == 301)
 field.text = "한글 대화"
 field.set_caret_column(field.text.length())
 app.ask_npc()
 await frames()
 check("button_path_submits_same_full_message", submissions.size() == 2 and submissions.back() == "한글 대화")
 field.grab_focus()
 var position: Vector2 = app.world.player.position
 Input.action_press("move_right")
 for index in range(5): await physics_frame
 Input.action_release("move_right")
 check("typing_keeps_game_movement_disabled", app.world.player.position.distance_to(position) < 1)
 await key(KEY_ESCAPE)
 check("escape_returns_movement", not field.has_focus() and app.world.can_move)
 # OS 입력기를 재현하지 않고 마지막 조합 글자의 확정·전송 순서를 검사합니다.
 var composing = load("res://tests/fixtures/composing_chat_input.gd").new()
 root.add_child(composing)
 composing.text = "안녕하세"
 composing.set_caret_column(4)
 composing.composition = "요"
 var composed_messages: Array[String] = []
 composing.text_submitted.connect(func(message):
  composed_messages.append(message)
  composing.release_focus()
  composing.editable = false)
 check("composition_submit_queued", composing.request_submit())
 check("duplicate_submit_coalesced", not composing.request_submit())
 await frames()
 check("last_composition_committed_before_submission", composed_messages == ["안녕하세요"] and composing.commit_count == 1)
 check("locking_editor_keeps_final_syllable", composing.text == "안녕하세요")
 composing.editable = true
 composing.text = "안녕하세"
 composing.composition = "요"
 composing.block_commit = true
 composing.request_submit()
 await frames()
 check("uncommitted_composition_not_sent", composed_messages.size() == 1 and composing.text == "안녕하세")
 var passed := true
 for value in checks.values(): passed = passed and value
 var result := {"suite": "chat_input", "passed": passed, "check_count": checks.size(), "checks": checks, "native_windows_ime_tested": false, "synthetic_unicode_events": true, "synthetic_composition_buffer": true, "screen_automation_used": false}
 var directory := ProjectSettings.globalize_path("res://../evidence/chat_input_fix").simplify_path()
 DirAccess.make_dir_recursive_absolute(directory)
 var file := FileAccess.open(directory.path_join("chat_input_test.json"), FileAccess.WRITE)
 file.store_string(JSON.stringify(result, "  "))
 print("CHAT_INPUT_TEST ", JSON.stringify(result))
 quit(0 if passed else 1)
