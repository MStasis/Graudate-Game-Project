extends SceneTree
var checks := {}
var app: Control
var directory := ""
var recorder = preload("res://tests/helpers/ui_snapshot.gd").new()

func _initialize() -> void:
 call_deferred("run")

func check(name: String, passed: bool) -> void:
 checks[name] = passed
 if not passed: push_error("NONCOMBAT_UI_FAILED " + name)

func frames(count: int = 3) -> void:
 for index in range(count): await process_frame

func key(code: int) -> void:
 var event := InputEventKey.new()
 event.pressed = true
 event.physical_keycode = code
 event.keycode = code
 root.push_input(event, true)
 await frames()

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

func count_chat_fields(node: Node) -> int:
 var count := 1 if node is ChatInput else 0
 for child in node.get_children(): count += count_chat_fields(child)
 return count

func snapshot(stem: String) -> void:
 var result := {"width": int(app.size.x), "height": int(app.size.y), "kind": "static_scene_layout_preview_not_game_capture", "items": recorder.collect(app)}
 FileAccess.open(directory.path_join(stem + ".json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))

func ui_fits() -> bool:
 var bounds := Rect2(Vector2.ZERO, app.size)
 for path in ["RadioPanel", "RadioPanel/LabPortrait", "RadioPanel/Answer", "RadioPanel/Question", "RadioPanel/SendButton", "RadioPanel/CloseDialogue", "LabObjective", "LabModeBadge"]:
  var control := app.get_node(path) as Control
  if control.is_visible_in_tree() and not bounds.encloses(control.get_global_rect()): return false
 return true

func run() -> void:
 root.size = Vector2i(1280, 800)
 directory = ProjectSettings.globalize_path("res://../evidence/noncombat_ui")
 DirAccess.make_dir_recursive_absolute(directory)
 app = load("res://main.tscn").instantiate()
 root.add_child(app)
 await frames()
 app.brain.auto_enabled = false
 app.brain.set_process(false)
 var field: ChatInput = app.question
 var field_id := field.get_instance_id()
 var local_client_id: int = app.brain.local_dialogue.get_instance_id()
 var portrait: TextureRect = app.get_node("RadioPanel/LabPortrait")
 check("noncombat_starts_in_lab", app.is_noncombat() and app.dialogue_panel.noncombat_mode)
 check("large_dialogue_opens_without_forcing_focus", app.dialogue_panel.visible and not field.has_focus() and app.world.can_move)
 check("portrait_is_separate_alpha_asset", portrait.texture.resource_path.ends_with("harin_bust_v1.png") and portrait.texture.get_image().detect_alpha() != Image.ALPHA_NONE)
 check("single_shared_chat_input", count_chat_fields(app) == 1)
 check("shared_native_input_script", field.get_script().resource_path == "res://scripts/chat_input.gd")
 check("native_bridge_binary_unchanged", FileAccess.get_sha256("res://native/windows_ime/windows_ime.dll") == "72082b7d2f61f9b1f2435be8f70f2012ccb63d656dd73c3d12ba6777c66851a6")
 check("body_is_real_rich_text", app.answer is RichTextLabel and app.answer.text == NPCPolicy.opening_line(app.world.game_state()))
 check("speaker_comes_from_npc", app.get_node("RadioPanel/CompanionName").text == app.world.npc.display_name.trim_prefix("정비사 "))
 check("goal_comes_from_mission", "퓨즈" in app.get_node("LabObjective/LabObjectiveText").text)
 check("combat_hud_not_redesigned_in_lab", not app.get_node("Header").visible and not app.get_node("MissionBar").visible)
 check("chrome_has_no_baked_textures", app.get_node("RadioPanel/LabChrome") is IndustrialUIFrame and field.get_node("FieldChrome") is IndustrialUIFrame and app.send_button.get_node("ButtonChrome") is IndustrialUIFrame)
 check("reference_canvas_fits", ui_fits())
 field.text = "안녕하세요. 입력 중인 문장"
 field.set_caret_column(field.text.length())
 field.grab_focus()
 await key(KEY_ESCAPE)
 check("escape_closes_and_releases_player", not app.dialogue_panel.visible and not field.has_focus() and app.world.can_move)
 check("closing_keeps_draft", field.text == "안녕하세요. 입력 중인 문장")
 check("closed_state_has_enter_prompt", app.get_node("TalkPrompt").visible)
 await key(KEY_ENTER)
 check("enter_reopens_same_draft", app.dialogue_panel.visible and field.has_focus() and field.text == "안녕하세요. 입력 중인 문장")
 check("opening_does_not_call_ai", app.brain.history.is_empty() and app.brain.pending.is_empty())
 field.text = "안녕하세요"
 field.set_caret_column(field.text.length())
 await key(KEY_ENTER)
 check("enter_uses_existing_ai_dispatch", app.brain.history.size() == 1 and app.brain.history[0].question == "안녕하세요" and app.answer.text == app.brain.history[0].answer)
 check("reply_returns_input_without_stealing_focus", field.editable and not app.send_button.disabled and not field.has_focus())
 field.text = "아직 보내지 않은 초안"
 app.get_node("RadioPanel/CloseDialogue").pressed.emit()
 check("close_button_keeps_text", not app.dialogue_panel.visible and field.text == "아직 보내지 않은 초안")
 app.get_node("TalkPrompt").pressed.emit()
 check("prompt_button_opens_dialogue", app.dialogue_panel.visible and field.has_focus())
 app.brain.pending = {"kind": "decision"}
 app._send_question("임무가 뭐야?")
 check("pending_shows_real_waiting_state", not field.editable and app.get_node("RadioPanel/RadioState").text == "● 응답 중")
 app.close_dialogue()
 check("close_does_not_cancel_inference", not app.brain.pending.is_empty() and app.brain.queued_question == "임무가 뭐야?")
 app.open_dialogue()
 check("reopen_pending_has_no_readonly_focus", app.dialogue_panel.visible and not field.has_focus() and not field.editable)
 app.close_dialogue()
 app.brain.pending = {}
 app.brain.queued_question = ""
 app.brain.dialogue_ready.emit("닫힌 상태에서 받은 합성 대사")
 check("background_reply_does_not_force_open", not app.dialogue_panel.visible and app.answer.text == "닫힌 상태에서 받은 합성 대사")
 app.open_dialogue()
 app.brain.dialogue_error.emit("합성 오류")
 check("failure_is_not_replaced_by_fake_dialogue", "합성 오류" in app.combat_hud.system_notices.latest_text and app.answer.text == "닫힌 상태에서 받은 합성 대사" and app.get_node("RadioPanel/RadioState").text == "● 응답 오류")
 app.brain.dialogue_ready.emit("긴".repeat(160))
 await frames()
 check("long_reply_kept_and_scrollable", app.answer.text.length() == 160 and app.answer.scroll_active and app.answer.get_content_height() > app.answer.size.y)
 field.text = "맵 전환 중에도 보존"
 app.world.flashlight_owned = true # Fixture: 기존 회귀의 전투/입력 조건. 지급 흐름은 mission_mechanics_test에서 별도 검증.
 app.world.apply_interaction("storage_gate")
 check("combat_uses_actor_hud", not app.dialogue_panel.noncombat_mode and not app.get_node("Header").visible and not portrait.visible and not app.get_node("LabObjective").visible)
 check("input_and_client_reused_across_modes", app.question.get_instance_id() == field_id and app.brain.local_dialogue.get_instance_id() == local_client_id and field.text == "맵 전환 중에도 보존")
 check("no_duplicate_send_connections", field.get_signal_connection_list("text_submitted").size() == 1)
 check("combat_uses_compact_composer", app.dialogue_panel.size.y == 56 and not app.answer.visible)
 for enemy in app.world.get_node("Enemies").get_children():
  enemy.hp = 0
  enemy.active = false
 app.world.state_changed.emit()
 await frames()
 check("storage_stays_compact_after_wave_clears", not app.is_noncombat() and not app.dialogue_panel.noncombat_mode and not app.dialogue_panel.visible)
 app.open_dialogue()
 field.finish_editing()
 app.world.ammo = 6
 app.world.shoot_cd = 0.0
 await click_at(app.dialogue_panel.position + Vector2(20, 4))
 check("dialogue_background_click_does_not_fire", app.world.ammo == 6)
 app.world.locker.opened = true
 app.world.apply_interaction("fuse")
 app.world.apply_interaction("lab_gate")
 app.open_dialogue()
 field.finish_editing()
 await click_at(portrait.get_global_rect().get_center())
 check("portrait_click_does_not_fire", app.world.ammo == 6)
 check("goal_updates_after_fuse_return", app.get_node("LabObjective/LabObjectiveText").text == "전력 장치에 퓨즈 장착")
 app.world.apply_interaction("generator")
 check("goal_updates_after_power_restored", app.get_node("LabObjective/LabObjectiveText").text == "연구실 출구로 이동")
 var composing = load("res://tests/fixtures/composing_chat_input.gd").new()
 root.add_child(composing)
 var close_signals := []
 composing.editing_closed.connect(func(): close_signals.append(true))
 composing.composition = "녕"
 var escape := InputEventKey.new()
 escape.keycode = KEY_ESCAPE
 escape.pressed = true
 composing._gui_input(escape)
 check("escape_during_composition_closes_chat", close_signals.size() == 1)
 composing.composition = ""
 composing._gui_input(escape)
 check("escape_after_composition_can_close", close_signals.size() == 2)
 composing.queue_free()
 app.reset_demo(0)
 await frames()
 app.world.npc.position = Vector2(-500, 100)
 app._update_speaker_bubble()
 check("availability_hint_hidden_offscreen", not app.get_node("SpeakerBubble").visible)
 app.world.npc.position = Vector2(365, 245)
 app._update_speaker_bubble()
 var expected: Vector2 = app.combat_hud.screen_point(app.world.npc) + Vector2(-24, -76)
 check("bubble_follows_actual_npc", app.get_node("SpeakerBubble").visible and app.get_node("SpeakerBubble").position.is_equal_approx(expected))
 field.text = ""
 field.finish_editing()
 app.answer.text = NPCPolicy.template_response("mission", app.world.game_state())
 snapshot("noncombat_open_layout")
 app.close_dialogue()
 snapshot("noncombat_closed_layout")
 app.open_dialogue()
 app.size = Vector2(960, 600)
 await frames()
 check("smaller_logical_canvas_fits", ui_fits())
 snapshot("noncombat_960_layout")
 app.size = Vector2(1280, 800)
 app.open_dialogue()
 field.finish_editing()
 await frames()
 check("resizing_keeps_same_input", app.question.get_instance_id() == field_id and count_chat_fields(app) == 1)
 var result := {"suite": "noncombat_dialogue_ui", "check_count": checks.size(), "passed": not checks.values().has(false), "checks": checks, "screen_automation_used": false, "gpu_render_verified": false, "actual_microsoft_ime_tested": false, "live_llm_calls": 0, "synthetic_ui_events": true}
 FileAccess.open(directory.path_join("noncombat_dialogue_test.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
 print("NONCOMBAT_UI_TEST ", JSON.stringify(result))
 app.queue_free()
 await frames()
 quit(0 if result.passed else 1)
