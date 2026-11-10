extends SceneTree
var checks := {}
var app: Control
var world: DemoWorld
var rendered := false
var directory := ""

func _initialize() -> void:
 rendered = "--render-dialogue-notices" in OS.get_cmdline_user_args()
 call_deferred("run")

func check(label: String, passed: bool) -> void:
 checks[label] = passed
 if not passed: push_error("DIALOGUE_NOTICE_FAILED " + label)

func frames(count := 4) -> void:
 for index in range(count):
  await process_frame
  await physics_frame

func capture(stem: String) -> void:
 if not rendered: return
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(directory.path_join(stem + ".png"))

func run() -> void:
 directory = ProjectSettings.globalize_path("res://../evidence/dialogue_notices")
 DirAccess.make_dir_recursive_absolute(directory)
 app = load("res://main.tscn").instantiate()
 root.add_child(app)
 world = app.world
 app.brain.auto_enabled = false
 world.set_physics_process(false)
 world.npc_combat_enabled = false
 for enemy in world.get_node("Enemies").get_children(): enemy.set_physics_process(false)
 app.close_dialogue()
 world.player.position = Vector2(480, 320)
 world.npc.position = Vector2(380, 320)
 await frames()
 await test_notices()
 await test_conversation()
 await test_world_channels()
 if rendered:
  app.size = Vector2(960, 600)
  await frames()
  app._show_status("패널에서 E를 유지하세요. 하린이 반대편을 맡습니다.")
  await frames()
  check("small_canvas_notice_fits", app.play_rect().encloses(app.combat_hud.system_notices.get_rect()))
  await capture("03_small_canvas")
 var result := {"suite": "dialogue_and_system_notices", "passed": not checks.values().has(false), "check_count": checks.size(), "checks": checks, "gpu_rendered": rendered, "synthetic_inputs": true, "live_model_calls": 0, "human_playtest": false, "actual_microsoft_ime_tested": false}
 FileAccess.open(directory.path_join("render.json" if rendered else "test.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
 print("DIALOGUE_NOTICE_RESULT ", JSON.stringify(result))
 app.queue_free()
 await frames()
 quit(0 if result.passed else 1)

func test_notices() -> void:
 var hud: CombatInterface = app.combat_hud
 app._companion_says("나 여기 있어. 무슨 얘기야?")
 var original_answer: String = app.answer.text
 var original_bubble := hud.npc_bubble.full_text
 var transcript_count := hud.transcript.size()
 app._show_status("손전등 · 가까이에서 E로 줍기")
 await frames()
 check("system_notice_has_own_visible_control", hud.system_notices.visible and "E로" in hud.system_notices.latest_text)
 check("system_notice_preserves_character_dialogue", app.answer.text == original_answer and hud.npc_bubble.full_text == original_bubble)
 check("system_notice_is_not_in_conversation_history", hud.transcript.size() == transcript_count)
 check("system_notice_does_not_focus_or_block_movement", not app.question.has_focus() and world.can_move and hud.system_notices.mouse_filter == Control.MOUSE_FILTER_IGNORE)
 check("notice_starts_to_player_right", hud.system_notices.position == Vector2(282, 146))
 check("notice_fits_play_area", app.play_rect().encloses(hud.system_notices.get_rect()))
 check("legacy_dialogue_status_is_hidden", not app.status.visible)
 await capture("01_system_notice_right")
 hud.system_notices.tick(2.5)
 check("notice_fades_before_expiring", hud.system_notices.visible and hud.system_notices.entries[0].card.modulate.a > 0 and hud.system_notices.entries[0].card.modulate.a < 1)
 await capture("02_notice_fading")
 hud.system_notices.tick(1)
 check("notice_expires_without_erasing_dialogue", not hud.system_notices.visible and app.answer.text == original_answer)
 for index in range(5): hud.notify("알림 %d" % index)
 await frames()
 check("notification_burst_is_bounded", hud.system_notices.entries.size() <= 3 and hud.system_notices.latest_text == "알림 4")
 hud.speak("안내", "시스템 경로 검사")
 check("noncharacter_speaker_cannot_take_npc_bubble", hud.npc_bubble.full_text == original_bubble and hud.system_notices.latest_text == "시스템 경로 검사")
 app.brain.dialogue_error.emit("검사용 연결 오류")
 check("connection_error_is_system_notice", "연결 오류" in hud.system_notices.latest_text and app.answer.text == original_answer and hud.npc_bubble.full_text == original_bubble)
 app.brain.status_changed.emit("로컬 LLM 지원 판단 중")
 check("automatic_technical_status_does_not_spam_notice", "연결 오류" in hud.system_notices.latest_text)
 app.reset_demo(0)
 app.brain.auto_enabled = false
 app.close_dialogue()
 check("reset_clears_notifications", not hud.system_notices.visible and hud.system_notices.entries.is_empty())

func test_conversation() -> void:
 var state := world.game_state()
 check("pre_handoff_guidance_does_not_claim_drop", not "떨군" in state.current_guidance and not state.flashlight_owned and not state.flashlight_dropped)
 check("generic_question_is_not_mission_intent", NPCPolicy.rule_intent("질문이 있어") != "mission")
 var rule_greeting := NPCPolicy.template_response(NPCPolicy.rule_intent("안녕 하린"), state, "안녕 하린")
 check("rule_greeting_does_not_recap_mission", not NPCPolicy.has_word(rule_greeting, ["퓨즈", "손전등", "보관", "E로"]))
 var rule_food := NPCPolicy.template_response(NPCPolicy.rule_intent("밥 먹었어?"), state, "밥 먹었어?")
 check("rule_food_reply_stays_on_food", NPCPolicy.has_word(rule_food, ["먹", "밥", "메뉴"]) and not "퓨즈" in rule_food)
 var unknown := NPCPolicy.template_response("unknown", state, "질문이 있어")
 check("unknown_reply_does_not_redirect_to_mission", not NPCPolicy.has_word(unknown, ["임무", "퓨즈", "목표"]))
 var history := [{"question": "임무가 뭐야?", "answer": "보관 구역에서 퓨즈를 찾자."}, {"question": "밥 먹었어?", "answer": "배고프네. 넌?"}, {"question": "아까도 긴장됐어", "answer": "잠깐 숨 돌리자."}]
 var casual := HarinDialogue.build(state, "오늘 좀 긴장돼", history, world.npc.description, "")
 check("casual_prompt_keeps_relevant_emotion_without_mission_or_food_drift", not NPCPolicy.has_word(casual.prompt, ["퓨즈", "손전등", "패널", "현재 임무 안내"]) and "숨 돌리자" in casual.prompt)
 var before_light := HarinDialogue.build(state, "손전등은 네가 갖고 있어?", [], "", "")
 check("pre_handoff_context_says_not_delivered", "내 손 안" in before_light.prompt and not "사용 방법" in before_light.prompt)
 var narrow_light := HarinDialogue.build(state, "손전등은 어떻게 비춰?", [], "", "")
 check("flashlight_help_has_no_unrelated_panel_manual", "마우스" in narrow_light.prompt and not "패널" in narrow_light.prompt)
 var panel_offer := HarinDialogue.build(state, "패널 같이 누르자", [], "", "")
 check("panel_offer_does_not_add_key_and_timer", not "1초" in panel_offer.prompt and not "E를" in panel_offer.prompt)
 var panel_help := HarinDialogue.build(state, "패널은 어떻게 눌러?", [], "", "")
 check("explicit_controls_question_still_gets_correct_help", "1초" in panel_help.prompt and "E를" in panel_help.prompt)
 app.open_dialogue()
 app.question.text = "밥 먹었어?"
 app.question.request_submit()
 await frames()
 check("rule_chat_roundtrip_is_actual_food_reply", NPCPolicy.has_word(app.answer.text, ["먹", "밥", "메뉴"]) and app.combat_hud.npc_bubble.full_text == app.answer.text and not "퓨즈" in app.answer.text)
 check("sent_lab_message_is_cleared", app.question.text.is_empty() and not app.dialogue_panel.visible)
 app.open_dialogue()
 check("reopened_chat_has_no_sent_message", app.question.text.is_empty())
 app.close_dialogue()

func test_world_channels() -> void:
 app.reset_demo(0)
 app.brain.auto_enabled = false
 app.close_dialogue()
 world.npc.position = world.player.position + Vector2(60, 0)
 world.request_flashlight()
 await frames()
 check("flashlight_drop_has_short_human_line", world.flashlight_dropped and app.answer.text == "여기 놨어. 챙겨 가." and not "E" in app.answer.text)
 check("flashlight_pickup_key_is_only_system_notice", "E로" in app.combat_hud.system_notices.latest_text)
 var dropped := HarinDialogue.build(world.game_state(), "손전등 어디 있어?", [], "", "")
 check("drop_context_knows_pickup_has_not_happened", "연구실 바닥" in dropped.prompt and "네가 챙길 차례" in dropped.prompt)
 world.apply_interaction("flashlight")
 world.apply_interaction("storage_gate")
 for enemy in world.get_node("Enemies").get_children():
  enemy.hp = 0
  enemy.active = false
 world._sync_state()
 world.player.position = world.locker.panel_position(0) + Vector2(0, 35)
 app.interact("panel_a")
 check("panel_progress_is_system_notice", "1.0초" in app.combat_hud.system_notices.latest_text and not "1.0초" in app.answer.text)
 world.request_support("assist_panel")
 await frames()
 check("panel_support_uses_short_character_line", app.combat_hud.npc_bubble.full_text == "내가 반대편 누를게!" and not app.dialogue_panel.visible)
 check("system_instructions_never_enter_npc_transcript", not "\n".join(app.combat_hud.transcript).contains("1.0초") and app.combat_hud.journal.entries.any(func(item): return item.channel == "system" and "1.0초" in item.body))
 await capture("04_panel_channels")
 world.locker.cancel("test_done")
 world.active_action = ""
 world.player_hp = 50
 world.request_support("heal")
 world._finish_support()
 check("healing_has_separate_numeric_receipt", "체력 +35" in app.combat_hud.system_notices.latest_text and not "35" in app.combat_hud.npc_bubble.full_text and world.player_hp == 85)
