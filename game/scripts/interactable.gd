@tool
class_name DemoInteractable
extends Area2D
## 이름·설명은 화면과 AI 문맥에서 함께 사용합니다. Interaction Id는 게임 규칙의 식별자입니다.

@export_group("상호작용")
@export_enum("npc", "fuse", "generator", "exit", "storage_gate", "lab_gate", "cache") var interaction_id: String = "fuse"
@export var display_name: String = "퓨즈":
	set(value):
		display_name = value
		_sync_visual()
@export var location_hint: String = "B구역"
@export_multiline var description: String = "전력 장치에 장착할 수 있는 부품"

@export_group("외형")
@export var base_color: Color = Color("f1c66d"):
	set(value):
		base_color = value
		_sync_visual()
@export var activated_color: Color = Color("8ce1b0"):
	set(value):
		activated_color = value
		_sync_visual()
@export var object_texture: Texture2D:
	set(value):
		object_texture = value
		_sync_visual()

var activated := false

func _ready() -> void:
	_sync_visual()

func set_active(value: bool) -> void:
	activated = value
	_sync_visual()

func _sync_visual() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	var name_label := get_node_or_null("NameLabel") as Label
	if sprite:
		sprite.self_modulate = activated_color if activated else base_color
		sprite.texture = object_texture
	if name_label:
		name_label.text = display_name
		name_label.add_theme_color_override("font_color", activated_color if activated else base_color)

