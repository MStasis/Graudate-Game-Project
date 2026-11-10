class_name SystemNotifications
extends VBoxContainer
## 화면 고정 영역의 페이드 알림. 통합 기록은 CombatInterface가 별도로 기록한다.
var entries: Array[Dictionary] = []
var latest_text := ""
const LIFETIME := 3.2
const FADE_TIME := 0.9

func _ready() -> void:
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_theme_constant_override("separation", 5)
 hide()

func post(message: String) -> void:
 message = message.strip_edges()
 if message.is_empty(): return
 latest_text = message
 if not entries.is_empty() and entries.back().message == message:
  entries.back().remaining = LIFETIME
  entries.back().card.modulate.a = 1
  return
 if entries.size() >= 3:
  entries.pop_front().card.queue_free()
 var card := PanelContainer.new()
 card.mouse_filter = Control.MOUSE_FILTER_IGNORE
 card.custom_minimum_size = Vector2(300, 32)
 var style := StyleBoxFlat.new()
 style.bg_color = Color(0.045, 0.065, 0.085, 0.9)
 style.border_color = Color("8b9da2")
 style.border_width_left = 2
 for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]: style.set_content_margin(side, 8)
 style.corner_radius_top_left = 4
 style.corner_radius_top_right = 4
 style.corner_radius_bottom_left = 4
 style.corner_radius_bottom_right = 4
 card.add_theme_stylebox_override("panel", style)
 var label := Label.new()
 label.text = "[시스템] " + message
 label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 label.max_lines_visible = 2
 label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
 label.add_theme_font_size_override("font_size", 16)
 label.add_theme_color_override("font_color", Color("d8e2df"))
 label.mouse_filter = Control.MOUSE_FILTER_IGNORE
 card.add_child(label)
 add_child(card)
 entries.append({"message": message, "card": card, "remaining": LIFETIME})
 show()

func tick(delta: float) -> void:
 for index in range(entries.size() - 1, -1, -1):
  entries[index].remaining -= delta
  if entries[index].remaining <= 0:
   entries[index].card.queue_free()
   entries.remove_at(index)
  else:
   entries[index].card.modulate.a = clampf(entries[index].remaining / FADE_TIME, 0, 1)
 visible = not entries.is_empty()

func clear() -> void:
 for entry in entries: entry.card.queue_free()
 entries.clear()
 latest_text = ""
 hide()
