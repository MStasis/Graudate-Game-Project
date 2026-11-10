extends SceneTree
## 실제 원문·상태·제공자·지연을 수집한다. 자연스러움은 단어 검사로 판정하지 않는다.
var app: Control
var world: DemoWorld
var records: Array[Dictionary] = []
var samples := []
var checks := {}

func _initialize() -> void:
 call_deferred("run")

func ask(id: String, question: String) -> void:
 var before := records.size()
 app.brain.request_dialogue(question)
 var deadline := Time.get_ticks_msec() + 85000
 while records.size() == before and Time.get_ticks_msec() < deadline: await create_timer(0.02).timeout
 var record: Dictionary = records.back() if records.size() > before else {}
 var accepted: bool = record.get("accepted", false) and record.get("actual_model") == app.brain.local_dialogue.settings.model and record.get("dialogue_method") == "state_grounded_generation_plain"
 checks[id + "_actual_generation"] = accepted
 var text: String = app.brain.history.back().answer if accepted else ""
 samples.append({"id": id, "question": question, "text": text, "state": world.game_state(), "record": record, "quality_review": "manual_required; transport checks do not establish semantic quality"})
 print("STORY_LIVE_SAMPLE ", JSON.stringify({"id": id, "question": question, "text": text, "accepted": accepted, "elapsed_ms": record.get("elapsed_ms")}))

func run() -> void:
 app = load("res://main.tscn").instantiate()
 root.add_child(app)
 app.brain.new_trial(1)
 app.brain.auto_enabled = false
 world = app.world
 world.set_physics_process(false)
 for enemy in world.get_node("Enemies").get_children(): enemy.set_physics_process(false)
 app.brain.measured.connect(func(record): records.append(record.duplicate(true)))
 await ask("before_blackout", "교대 끝나려면 멀었나. 오늘 근무도 조용하겠지?")
 world.trigger_blackout()
 await ask("blackout", "방금까지 켜져 있었잖아. 어디부터 확인할까?")
 await ask("new_fear_banter", "솔직히 너도 지금 심장 빨리 뛰지?")
 await ask("new_banter_followup", "딴소리 하지 말고, 내 뒤에 숨으려는 건 아니지?")
 world.npc.position = world.player.position + Vector2(40, 0)
 world.request_flashlight()
 world.apply_interaction("flashlight")
 world.apply_interaction("storage_gate")
 await ask("fuse_search", "이 방에서 뭘 챙겨야 돌아갈 수 있어?")
 await ask("panel_question", "이 패널 둘 다 내가 누르면 되나?")
 await ask("panel_referent", "그럼 네가 맡는 건 어느 쪽이라고?")
 for enemy in world.get_node("Enemies").get_children(): enemy.hp = 0
 world.locker.opened = true # 대화 상태 fixture; 실제 기믹은 별도 회귀 검증.
 world.apply_interaction("fuse")
 world.apply_interaction("lab_gate")
 await ask("fuse_return", "아까 찾던 부품 챙겼어. 그럼 지금은?")
 world.apply_interaction("generator")
 await ask("power_restored", "이제 불 들어왔는데? 퓨즈는 더 필요 없어?")
 world.trigger_alarm()
 await ask("alarm", "경고등까지 켜졌네. 이제 다 해결된 거야?")
 world.apply_interaction("exit")
 await ask("main_entry", "아까 네가 말한 그 이상한 장치, 여기선 뭘 확인해?")
 await ask("food_new_question", "너 메뉴 고르는 데도 이렇게 진지해? 오늘 내가 한턱 낼까?")
 await ask("food_followup", "아까 그건 그냥 주문이지, 매일 먹는다는 뜻은 아니지?")
 await ask("fictional_memory", "우리 휴게실에서 스파게티 시켰던 거 기억해?")
 await ask("fictional_rule", "여긴 정말 퇴근을 못 하는 연구소야?")
 var directory := ProjectSettings.globalize_path("res://../evidence/story_ui")
 DirAccess.make_dir_recursive_absolute(directory)
 var result := {"passed": not checks.values().has(false), "check_count": checks.size(), "checks": checks, "samples": samples, "actual_inference": true, "model": app.brain.local_dialogue.settings.model, "created_utc": Time.get_datetime_string_from_system(true), "general_dialogue_quality_proven": false}
 FileAccess.open(directory.path_join("live_dialogue.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
 print("STORY_LIVE_RESULT ", JSON.stringify({"passed": result.passed, "check_count": checks.size()}))
 app.queue_free()
 await process_frame
 quit(0 if result.passed else 1)


