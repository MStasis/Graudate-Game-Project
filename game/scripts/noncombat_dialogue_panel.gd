@tool
class_name NoncombatDialoguePanel
extends Panel
## 같은 Answer/ChatInput/SendButton의 배치만 바꾸며 AI와 IME 경로를 공유한다.
@export var noncombat_mode := true:
 set(value):
  noncombat_mode = value
  if is_node_ready(): _apply_profile()
@export_range(208, 320, 1) var dialogue_height := 216.0:
 set(value):
  dialogue_height = value
  if is_node_ready(): _apply_layout()
@export_range(160, 360, 1) var portrait_width := 280.0:
 set(value):
  portrait_width = value
  if is_node_ready(): _apply_layout()
@export var lab_theme: Theme = preload("res://resources/LabDialogueTheme.tres")
@export var combat_theme: Theme = preload("res://resources/GameTheme.tres")
var scripted := false

func _ready() -> void:
 if get_parent() is Control: get_parent().resized.connect(_apply_layout)
 _apply_profile()

func set_noncombat(enabled: bool) -> void:
 noncombat_mode = enabled

func set_scripted(enabled: bool) -> void:
 if scripted == enabled: return
 scripted = enabled
 _apply_profile()

func _apply_profile() -> void:
 var enabled := noncombat_mode
 theme = lab_theme if enabled else combat_theme
 for path in ["LabChrome", "LabPortrait", "CloseDialogue", "KeyHint", "NameAccent", "Question/FieldChrome", "SendButton/ButtonChrome"]:
  get_node(path).visible = enabled
 for path in ["PortraitFrame", "PortraitCaption", "CompanionRole", "MissionPrompt", "SupportPrompt", "EverydayPrompt"]:
  get_node(path).visible = false
 $CompanionName.visible = enabled
 $Answer.visible = enabled
 $SendButton.visible = enabled
 $RadioState.visible = enabled
 $Status.visible = false
 $CompanionName.add_theme_color_override("font_color", Color("edb45e") if enabled else Color("dbeede"))
 $CompanionName.add_theme_font_size_override("font_size", 25 if enabled else 21)
 $Answer.add_theme_font_size_override("normal_font_size", 26 if enabled else 20)
 $Question.add_theme_font_size_override("font_size", 19 if enabled else 18)
 $SendButton.add_theme_font_size_override("font_size", 20 if enabled else 17)
 $SendButton.text = "전송" if enabled else "전송  ↵"
 $Question.placeholder_text = "미카에게 말하기…" if enabled else "미카에게 말하기…  Enter 전송 / Esc 이동"
 $Question.visible = not scripted
 if scripted:
  for path in ["CloseDialogue", "SendButton", "RadioState", "KeyHint"]:
   get_node(path).hide()
 _apply_layout()

func place(path: NodePath, rect: Rect2) -> void:
 var control := get_node(path) as Control
 control.position = rect.position
 control.size = rect.size

func _apply_layout() -> void:
 if not is_node_ready() or not get_parent() is Control: return
 var canvas: Vector2 = get_parent().size
 if noncombat_mode:
  position = Vector2(16, canvas.y - dialogue_height - 16)
  size = Vector2(canvas.x - 32, dialogue_height)
  var portrait_w := minf(portrait_width, canvas.x * 0.22)
  var text_left := portrait_w + 20
  var portrait_h := portrait_w * 1.35
  place("LabPortrait", Rect2(0, dialogue_height - portrait_h, portrait_w, portrait_h))
  place("NameAccent", Rect2(text_left - 16, 23, 5, 29))
  place("CompanionName", Rect2(text_left, 17, size.x - text_left - 220, 38))
  place("RadioState", Rect2(size.x - 214, 22, 164, 28))
  place("CloseDialogue", Rect2(size.x - 40, 10, 30, 36))
  place("Answer", Rect2(text_left, 60, size.x - text_left - 28, 128 if scripted else 76))
  place("Question", Rect2(text_left, 144, size.x - text_left - 150, 50))
  place("SendButton", Rect2(size.x - 134, 142, 106, 54))
  place("Status", Rect2(text_left, 196, maxf(40, size.x - text_left - 312), 20))
  place("KeyHint", Rect2(size.x - 302, 196, 274, 20))
 else:
  position = Vector2(20, canvas.y - 76)
  size = Vector2(minf(680, canvas.x - 40), 56)
  place("Question", Rect2(8, 6, size.x - 16, 44))
