extends Button

const SCAN_SHADER := preload("res://assets/ui/bulkhead/button_scan.gdshader")
const SCAN_START := -0.24
const SCAN_END := 1.24
const SCAN_SECONDS := 0.46

var _scan := ColorRect.new()
var _scan_material := ShaderMaterial.new()
var _scan_tween: Tween

func _ready() -> void:
 mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
 _scan_material.shader = SCAN_SHADER
 _scan.name = "HoverScan"
 _scan.material = _scan_material
 _scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
 _scan.hide()
 add_child(_scan)
 _scan.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_entered.connect(_start_scan)
 mouse_exited.connect(_stop_scan)
 visibility_changed.connect(_stop_scan)

func _start_scan() -> void:
 if disabled or not is_visible_in_tree(): return
 _stop_scan()
 _scan_material.set_shader_parameter("scan_position", SCAN_START)
 _scan.show()
 _scan_tween = create_tween()
 _scan_tween.tween_property(_scan_material, "shader_parameter/scan_position", SCAN_END, SCAN_SECONDS)
 _scan_tween.tween_callback(_scan.hide)

func _stop_scan() -> void:
 if _scan_tween: _scan_tween.kill()
 _scan.hide()
