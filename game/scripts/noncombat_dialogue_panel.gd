@tool
class_name NoncombatDialoguePanel
extends Panel
## 연구실과 전투 구역에서 같은 채팅 입력 및 버튼을 사용한다.

@export var noncombat_mode := true

func _ready() -> void:
 theme = preload("res://resources/BulkheadHUDTheme.tres")
 theme_type_variation = &"HUDChatPanel"
 for path in ["LabChrome", "LabPortrait", "PortraitFrame", "PortraitCaption", "CompanionName", "CompanionRole", "NameAccent", "Answer", "Status", "RadioState", "MissionPrompt", "SupportPrompt", "EverydayPrompt", "KeyHint", "Question/FieldChrome", "SendButton/ButtonChrome"]:
  get_node(path).hide()
 $Question.placeholder_text = "미카에게 말하기…"
 $Question.add_theme_font_size_override("font_size", 17)
 $SendButton.text = "전송"
 if get_parent() is Control: get_parent().resized.connect(_apply_layout)
 _apply_layout()

func set_noncombat(enabled: bool) -> void:
 noncombat_mode = enabled

func _apply_layout() -> void:
 if not get_parent() is Control: return
 var canvas: Vector2 = get_parent().size
 position = Vector2(canvas.x * 0.28, canvas.y - 86.0)
 size = Vector2(canvas.x * 0.44, 64.0)
 $Question.position = Vector2(12, 10)
 $Question.size = Vector2(size.x - 128, 44)
 $SendButton.position = Vector2(size.x - 108, 10)
 $SendButton.size = Vector2(64, 44)
 $CloseDialogue.position = Vector2(size.x - 39, 10)
 $CloseDialogue.size = Vector2(29, 44)
