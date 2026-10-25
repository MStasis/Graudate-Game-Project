extends SceneTree
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var ok := ClassDB.class_exists("WindowsIMEBridge")
 print("NATIVE_IME_CLASS ", ok)
 if not ok:
  quit(1)
  return
 var bridge = ClassDB.instantiate("WindowsIMEBridge")
 root.add_child(bridge)
 var checks := {"starts_detached": not bridge.is_attached(), "invalid_handle_rejected": not bridge.attach(0), "empty_buffer": bridge.drain_commits().is_empty()}
 bridge.set_active(true)
 checks["cannot_complete_without_window"] = not bridge.complete_composition()
 checks["cannot_cancel_without_window"] = not bridge.cancel_composition()
 bridge.detach()
 checks["detach_is_safe"] = not bridge.is_attached()
 bridge.free()
 var passed := true
 for value in checks.values(): passed = passed and value
 var report := {"suite": "native_ime_load", "check_count": checks.size(), "passed": passed, "checks": checks, "screen_automation_used": false, "dll_sha256": FileAccess.get_sha256("res://native/windows_ime/windows_ime.dll")}
 var directory := ProjectSettings.globalize_path("res://../evidence/native_ime_fix").simplify_path()
 DirAccess.make_dir_recursive_absolute(directory)
 var file := FileAccess.open(directory.path_join("native_load_test.json"), FileAccess.WRITE)
 file.store_string(JSON.stringify(report, "  "))
 print("NATIVE_IME_LOAD_TEST ", JSON.stringify(report))
 quit(0 if passed else 1)
