extends RefCounted
## 저장된 UI 위치·테마를 정적으로 검토하는 자료. GPU 화면 캡처가 아니다.
var items := []

func collect(node: Node) -> Array:
 items.clear()
 _visit(node)
 return items.duplicate(true)

func _visit(node: Node) -> void:
 if node is CanvasItem and not node.is_visible_in_tree(): return
 for child in node.get_children():
  if child is CanvasItem and child.show_behind_parent: _visit(child)
 var item := {}
 if node is Control:
  var rect: Rect2 = node.get_global_rect()
  item = {"name": str(node.get_path()), "type": node.get_class(), "x": rect.position.x, "y": rect.position.y, "width": rect.size.x, "height": rect.size.y, "z": node.z_index}
  if node is Label or node is Button or node is TextEdit or node is RichTextLabel:
   var font_key := "normal_font_size" if node is RichTextLabel else "font_size"
   var color_key := "default_color" if node is RichTextLabel else "font_color"
   item["font_size"] = node.get_theme_font_size(font_key)
   item["color"] = "#" + (node.get_theme_color("font_placeholder_color" if node is TextEdit and node.text.is_empty() else color_key) * node.modulate * node.self_modulate).to_html(false)
   item["text"] = node.placeholder_text if node is TextEdit and node.text.is_empty() else node.text
   item["align"] = node.horizontal_alignment if node is Label else 1 if node is Button else 0
   item["vertical_align"] = node.vertical_alignment if node is Label else 0
   item["wrap"] = node is RichTextLabel or (node is Label and node.autowrap_mode != TextServer.AUTOWRAP_OFF)
  if node is Panel or node is Button or node is TextEdit or node is ProgressBar:
   var style_key := "panel" if node is Panel else "background" if node is ProgressBar else "normal"
   var style: StyleBox = node.get_theme_stylebox(style_key)
   if style is StyleBoxFlat:
    item["background"] = "#" + style.bg_color.to_html(false)
    item["border"] = "#" + style.border_color.to_html(false)
    item["border_width"] = style.border_width_top
   if node is ProgressBar: item["progress"] = node.value / node.max_value
  if node is TextureRect and node.texture:
   item["image"] = node.texture.resource_path
   item["stretch_mode"] = node.stretch_mode
  if node is ColorRect: item["background"] = "#" + node.color.to_html(false)
  if node.has_method("frame_geometry"): item["industrial_frame"] = node.frame_geometry()
  if node.get_script() and node.get_script().resource_path == "res://scripts/dialogue_speech_bubble.gd":
   item["speech_bubble"] = {"fill": "#" + node.fill_color.to_html(false), "border": "#" + node.border_color.to_html(false)}
 elif node is Sprite2D and node.texture:
  var rect: Rect2 = node.get_rect()
  var t: Transform2D = node.get_global_transform()
  item = {"type": "Sprite2D", "x": t.origin.x + rect.position.x, "y": t.origin.y + rect.position.y, "width": rect.size.x, "height": rect.size.y, "z": node.z_index, "image": node.texture.resource_path, "tint": [node.self_modulate.r, node.self_modulate.g, node.self_modulate.b]}
 if not item.is_empty(): items.append(item)
 for child in node.get_children():
  if not child is CanvasItem or not child.show_behind_parent: _visit(child)
