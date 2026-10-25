extends SceneTree
## 화면·키보드를 조작하지 않는 씬 상태/입력 전파/배치 검사.
var checks := {}
var layout := []
var app: Control

func _initialize() -> void:
 call_deferred("run")

func check(name: String, value: bool) -> void:
 checks[name] = value
 if not value: push_error("UI_CHECK_FAILED " + name)

func frames(count: int = 3) -> void:
 for index in range(count): await process_frame

func click_at(point: Vector2) -> void:
 var event := InputEventMouseButton.new()
 event.button_index = MOUSE_BUTTON_LEFT
 event.position = point
 event.global_position = point
 event.pressed = true
 root.push_input(event, true)
 event = event.duplicate()
 event.pressed = false
 root.push_input(event, true)
 await frames()

func run() -> void:
 root.size = Vector2i(1280, 800)
 app = load("res://main.tscn").instantiate()
 root.add_child(app)
 await frames()
 app.brain.auto_enabled = false
 app.brain.set_process(false)
 var field: ChatInput = app.question
 check("research_controls_hidden_initially", not app.get_node("DebugPanel").visible)
 check("portrait_loaded", app.get_node("RadioPanel/PortraitFrame/Portrait").texture.get_size() == Vector2(200, 200))
 check("portrait_nearest_filter", app.get_node("RadioPanel/PortraitFrame/Portrait").texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
 check("radio_above_darkness", app.get_node("RadioPanel").z_index > app.world.get_node("Darkness").z_index)
 check("objective_above_darkness", app.get_node("MissionBar").z_index > app.world.get_node("Darkness").z_index)
 check("starts_with_truthful_idle_state", app.get_node("RadioPanel/RadioState").text == "● 대기")
 app.prepare_question("지금 뭘 해야 해?")
 check("prompt_is_only_a_draft", field.text == "지금 뭘 해야 해?" and app.brain.history.is_empty())
 check("draft_focus_stops_movement", field.has_focus() and not app.world.can_move)
 field.text = "직접 작성 중인 문장"
 app.prepare_question("새로운 질문")
 check("prompt_preserves_unsent_draft", field.text == "직접 작성 중인 문장")
 app.get_node("Header/SettingsButton").pressed.emit()
 check("settings_opens_and_commits_draft", app.get_node("DebugPanel").visible and not field.has_focus() and field.text == "직접 작성 중인 문장")
 check("settings_blocks_game_movement", not app.world.can_move)
 app.get_node("DebugPanel/CloseSettings").pressed.emit()
 check("settings_close_returns_control", not app.get_node("DebugPanel").visible and app.world.can_move)
 app.world.player_hp = 30
 app.world.ammo = 2
 app.world.medkits = 1
 app.world.state_changed.emit()
 await create_timer(0.25).timeout
 check("health_bar_matches_real_hp", is_equal_approx(app.get_node("Header/HealthBar").value, 30.0))
 check("low_health_has_text_cue", "위험" in app.get_node("Header/HealthValue").text)
 check("ammo_matches_real_state", app.get_node("Header/AmmoValue").text == "02 / 20")
 check("support_stock_matches_real_state", "치료 01" in app.get_node("Header/SupportValue").text)
 app.world.apply_interaction("storage_gate")
 check("location_tracks_room", app.get_node("MissionBar/Location").text == "보관 구역")
 check("objective_tracks_combat", "드론 3기" in app.get_node("MissionBar/Objective").text)
 check("mission_step_tracks_room", app.get_node("MissionBar/MissionStep").text.begins_with("02"))
 app.world.shoot_cd = 0.0
 var ammo: int = app.world.ammo
 await click_at(Vector2(500, 695))
 check("radio_background_does_not_fire_weapon", app.world.ammo == ammo)
 await click_at(Vector2(500, 20))
 check("header_does_not_fire_weapon", app.world.ammo == ammo)
 await click_at(Vector2(500, 788))
 check("footer_does_not_fire_weapon", app.world.ammo == ammo)
 await click_at(Vector2(650, 350))
 check("playfield_click_still_fires", app.world.ammo == ammo - 1)
 app.brain.pending = {"kind": "decision"}
 app._send_question("지원이 필요해")
 check("pending_locks_only_composer", not field.editable and app.send_button.disabled and app.world.can_move)
 check("pending_disables_draft_buttons", app.get_node("RadioPanel/MissionPrompt").disabled)
 check("pending_has_visible_state", app.get_node("RadioPanel/RadioState").text == "● 응답 중")
 app.brain.pending = {}
 app.brain.queued_question = ""
 app.brain.dialogue_ready.emit("검사용 합성 대사입니다.")
 check("reply_unlocks_composer", field.editable and not app.send_button.disabled)
 check("reply_shows_clean_dialogue", app.answer.text == "검사용 합성 대사입니다.")
 app.brain.dialogue_error.emit("합성 연결 오류")
 check("error_is_explicit", "답변 미제공" in app.answer.text and app.get_node("RadioPanel/RadioState").text == "● 응답 오류")
 app.reset_demo(2)
 check("provider_and_badge_stay_in_sync", app.brain.provider == 2 and app.get_node("DebugPanel/Provider").selected == 2 and "Jev" in app.get_node("Footer/ProviderBadge").text)
 check("reset_restores_hud", app.get_node("Header/AmmoValue").text == "06 / 20" and app.get_node("RadioPanel/RadioState").text == "● 대기")
 app.reset_demo(0)
 app.toggle_settings()
 app.get_node("DebugPanel/RestartButton").pressed.emit()
 check("restart_keeps_open_settings_from_moving_player", app.get_node("DebugPanel").visible and not app.world.can_move)
 app.toggle_settings()
 field.text = ""
 await create_timer(0.25).timeout
 var out_of_bounds := []
 collect_layout(app, out_of_bounds)
 check("all_visible_ui_fits_reference_canvas", out_of_bounds.is_empty())
 var overlapping: bool = app.get_node("RadioPanel/Answer").get_global_rect().intersects(field.get_global_rect())
 check("dialogue_does_not_overlap_composer", not overlapping)
 check("send_button_keeps_native_ime_focus", app.send_button.focus_mode == Control.FOCUS_NONE)
 var result := {"suite": "ui_redesign", "passed": not checks.values().has(false), "check_count": checks.size(), "checks": checks, "out_of_bounds": out_of_bounds, "screen_automation_used": false, "actual_gpu_render_verified": false, "live_model_calls": 0}
 var directory := ProjectSettings.globalize_path("res://../evidence/ui_redesign")
 DirAccess.make_dir_recursive_absolute(directory)
 FileAccess.open(directory.path_join("ui_layout_test.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
 FileAccess.open(directory.path_join("layout_manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"width": 1280, "height": 800, "kind": "static_scene_layout_preview_not_game_capture", "items": layout}, "  "))
 print("UI_LAYOUT_TEST ", JSON.stringify(result))
 app.queue_free()
 await frames()
 quit(0 if result.passed else 1)

func color_hex(color: Color) -> String:
 return "#" + color.to_html(false)

func collect_layout(node: Node, out_of_bounds: Array) -> void:
 if node is CanvasItem and not node.is_visible_in_tree(): return
 var item := {}
 if node is Control:
  var rect: Rect2 = node.get_global_rect()
  var is_world: bool = app.world.is_ancestor_of(node)
  if not is_world and not Rect2(-1, -1, 1282, 802).encloses(rect): out_of_bounds.append(str(node.get_path()))
  item = {"name": str(node.get_path()), "type": node.get_class(), "x": rect.position.x, "y": rect.position.y, "width": rect.size.x, "height": rect.size.y, "z": node.z_index}
  if node is Label or node is Button or node is TextEdit or node is RichTextLabel:
   var font_key := "normal_font_size" if node is RichTextLabel else "font_size"
   var color_key := "default_color" if node is RichTextLabel else "font_color"
   item["font_size"] = node.get_theme_font_size(font_key)
   item["color"] = color_hex(node.get_theme_color("font_placeholder_color" if node is TextEdit and node.text.is_empty() else color_key) * node.modulate * node.self_modulate)
   item["text"] = node.placeholder_text if node is TextEdit and node.text.is_empty() else node.text
   item["align"] = node.horizontal_alignment if node is Label else 1 if node is Button else 0
   item["wrap"] = node is RichTextLabel or (node is Label and node.autowrap_mode != TextServer.AUTOWRAP_OFF)
  if node is Panel or node is Button or node is TextEdit or node is ProgressBar:
   var style_key := "panel" if node is Panel else "background" if node is ProgressBar else "normal"
   var style: StyleBox = node.get_theme_stylebox(style_key)
   if style is StyleBoxFlat:
    item["background"] = color_hex(style.bg_color)
    item["border"] = color_hex(style.border_color)
    item["border_width"] = style.border_width_top
   if node is ProgressBar: item["progress"] = node.value / node.max_value
  if node is TextureRect and node.texture:
   item["image"] = node.texture.resource_path
   item["stretch_mode"] = node.stretch_mode
  if node is ColorRect: item["background"] = color_hex(node.color)
 elif node is Sprite2D and node.texture:
  var rect: Rect2 = node.get_rect()
  var t: Transform2D = node.get_global_transform()
  item = {"type": "Sprite2D", "x": t.origin.x + rect.position.x, "y": t.origin.y + rect.position.y, "width": rect.size.x, "height": rect.size.y, "z": node.z_index, "image": node.texture.resource_path, "tint": [node.self_modulate.r, node.self_modulate.g, node.self_modulate.b]}
 if not item.is_empty(): layout.append(item)
 for child in node.get_children(): collect_layout(child, out_of_bounds)
