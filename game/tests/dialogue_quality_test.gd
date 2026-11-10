extends SceneTree
var checks := {}
var responses: Array[Dictionary] = []
var measurements: Array[Dictionary] = []
var app: Control
var world: DemoWorld

func _initialize() -> void:
 call_deferred("run")

func check(label: String, passed: bool) -> void:
 checks[label] = passed
 if not passed: push_error("DIALOGUE_QUALITY_FAILED " + label)

func ask(label: String, question: String) -> String:
 var count_before := measurements.size()
 app._send_question(question)
 var deadline := Time.get_ticks_msec() + 85000
 while measurements.size() == count_before and Time.get_ticks_msec() < deadline:
  await create_timer(0.02).timeout
 var expected: String = "common_executor" if not NPCPolicy.requested_action(question).is_empty() else app.brain.local_dialogue.settings.model
 var accepted: bool = measurements.size() > count_before and measurements.back().get("accepted", false) and measurements.back().get("actual_model") == expected
 check(label + "_actual_model_accepted", accepted)
 var text: String = app.answer.text if accepted else ""
 responses.append({"case": label, "question": question, "text": text, "accepted": accepted, "actual_model": expected, "snapshot": world.game_state().duplicate(true)})
 print("DIALOGUE_SAMPLE ", JSON.stringify({"case": label, "text": text, "accepted": accepted}))
 return text

func no_manual(text: String) -> bool:
 return not NPCPolicy.has_word(text, ["퓨즈", "보관", "손전등", "패널", "전력", "E키", "1초"])

func run() -> void:
 app = load("res://main.tscn").instantiate()
 root.add_child(app)
 world = app.world
 app.brain.new_trial(1)
 app.brain.auto_enabled = false
 world.set_physics_process(false)
 for enemy in world.get_node("Enemies").get_children(): enemy.set_physics_process(false)
 app.brain.measured.connect(func(record): measurements.append(record.duplicate(true)))
 var text := await ask("greeting", "안녕 하린! 오늘은 좀 어때?")
 check("greeting_stays_in_conversation", no_manual(text) and not NPCPolicy.has_word(text, ["허리", "아프", "치료"]))
 text = await ask("food", "밥 먹었어?")
 check("food_does_not_return_to_objective", no_manual(text))
 text = await ask("anxiety", "오늘 좀 긴장돼.")
 check("emotion_does_not_become_a_tutorial", no_manual(text))
 text = await ask("generic_question", "질문이 하나 있어.")
 check("generic_question_does_not_trigger_door_or_mission", no_manual(text))
 text = await ask("before_handoff", "손전등은 네가 가지고 있어?")
 check("before_handoff_has_no_fake_completed_delivery", not NPCPolicy.has_word(text, ["떨어뜨렸", "놓았", "놨어", "네가주웠", "네가 주웠", "네가 받았"]) and NPCPolicy.has_word(text, ["갖", "가지", "내가", "나한테", "아직", "내 손"]))
 world.npc.position = world.player.position + Vector2(60, 0)
 world.request_flashlight()
 text = await ask("ground_flashlight", "손전등 어디에 뒀어?")
 check("ground_flashlight_is_not_already_collected", NPCPolicy.has_word(text, ["바닥", "놓", "놨"]) and not NPCPolicy.has_word(text, ["네가 주웠", "네가 받았", "나중에 놓", "놓을 거", "놓을거"]))
 world.apply_interaction("flashlight")
 text = await ask("flashlight_controls", "손전등은 어떻게 비춰?")
 check("flashlight_answer_is_specific_and_correct", NPCPolicy.has_word(text, ["마우스", "조준"]) and not NPCPolicy.has_word(text, ["패널", "1초", "보관함", "E로", "놓여", "지금은 바닥"]))
 world.apply_interaction("storage_gate")
 for enemy in world.get_node("Enemies").get_children():
  enemy.hp = 0
  enemy.active = false
 world._sync_state()
 text = await ask("panel_offer", "패널 같이 누르자.")
 check("panel_offer_is_short_without_timer_or_keys", text.length() <= 100 and not NPCPolicy.has_word(text, ["1초", "E", "비프", "초 동안", "놓아야", "떼야"]))
 text = await ask("panel_controls", "패널은 어떻게 작동해?")
 check("asked_panel_help_keeps_two_roles", NPCPolicy.has_word(text, ["반대", "둘", "같이", "동시"]) and not NPCPolicy.has_word(text, ["놓아야", "떼야", "순서대로", "후 반대"]))
 text = await ask("food_after_mission_chat", "끝나면 뭐 먹고 싶어?")
 check("casual_reply_recovers_after_mission_history", no_manual(text))
 var directory := ProjectSettings.globalize_path("res://../evidence/dialogue_notices")
 DirAccess.make_dir_recursive_absolute(directory)
 var result := {"suite": "dialogue_live_quality_cases", "actual_model": app.brain.local_dialogue.settings.model, "actual_inference": true, "check_count": checks.size(), "passed": not checks.values().has(false), "checks": checks, "responses": responses, "measurements": measurements, "human_quality_review": "raw responses inspected separately; lexical checks do not prove general naturalness", "formal_comparison_benchmark": false}
 FileAccess.open(directory.path_join("local_dialogue_%d.json" % OS.get_process_id()), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
 print("DIALOGUE_QUALITY_RESULT ", JSON.stringify({"passed": result.passed, "check_count": checks.size(), "checks": checks}))
 app.queue_free()
 await process_frame
 quit(0 if result.passed else 1)
