extends SceneTree
class BridgeFixture:
 extends Node
 var queued := ""
 var composition := ""
 var completed := 0
 var detached := false
 func drain_commits() -> String:
  var value := queued
  queued = ""
  return value
 func complete_composition() -> bool:
  queued += composition
  composition = ""
  completed += 1
  return true
 func detach() -> void:
  detached = true

class InputFixture:
 extends ChatInput
 func is_composing() -> bool:
  return _native_bridge != null and not str(_native_bridge.get("composition")).is_empty()

var checks := {}
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var field := InputFixture.new()
 root.add_child(field)
 var native := BridgeFixture.new()
 field.add_child(native)
 field._native_bridge = native
 var expected := ""
 for character in "안녕하세요":
  native.queued = character
  field._flush_native_commits()
  expected += character
  checks["native_prefix_" + str(expected.length())] = field.text == expected
 field._flush_native_commits()
 checks["draining_twice_does_not_duplicate"] = field.text == "안녕하세요"
 field.text = ""
 field.set_caret_column(0)
 native.queued = "가나 까까 한글 English 日本語 🙂"
 field._flush_native_commits()
 checks["whole_native_result_preserved"] = field.text == "가나 까까 한글 English 日本語 🙂"
 field.text = "안녕하세"
 field.set_caret_column(4)
 native.composition = "요"
 var received: Array[String] = []
 field.text_submitted.connect(func(message): received.append(message))
 field.request_submit()
 for index in range(4): await process_frame
 checks["native_completion_called"] = native.completed == 1
 checks["native_last_syllable_sent"] = received == ["안녕하세요"] and field.text == "안녕하세요"
 field.finish_editing()
 checks["finishing_keeps_committed_text"] = field.text == "안녕하세요"
 field.free()
 checks["node_lifecycle_detaches_bridge"] = not is_instance_valid(native)
 var passed := true
 for value in checks.values(): passed = passed and value
 var report := {"suite": "native_ime_chat_integration", "check_count": checks.size(), "passed": passed, "checks": checks, "synthetic_native_backend": true, "actual_microsoft_ime_driver_tested": false, "screen_automation_used": false}
 var directory := ProjectSettings.globalize_path("res://../evidence/native_ime_fix").simplify_path()
 DirAccess.make_dir_recursive_absolute(directory)
 var file := FileAccess.open(directory.path_join("chat_native_integration_test.json"), FileAccess.WRITE)
 file.store_string(JSON.stringify(report, "  "))
 print("CHAT_NATIVE_INTEGRATION ", JSON.stringify(report))
 quit(0 if passed else 1)
