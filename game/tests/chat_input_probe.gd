extends SceneTree
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var app = load("res://main.tscn").instantiate()
 root.add_child(app)
 await process_frame
 app.brain.auto_enabled = false
 var field: ChatInput = app.question
 field.text = ""
 field.grab_focus()
 await process_frame
 var records := []
 for character in "안녕하세요":
  var event := InputEventKey.new()
  event.pressed = true
  event.unicode = character.unicode_at(0)
  root.push_input(event, true)
  await process_frame
  records.append({"unicode": event.unicode, "text": field.text, "caret": field.get_caret_column(), "selection": field.get_selected_text(), "focused": field.has_focus()})
 print("CHAT_UNICODE_PROBE ", JSON.stringify(records))
 quit(0 if field.text == "안녕하세요" else 1)
