extends "res://tests/story_dialogue_live_test.gd"
## 두 설치 모델 비교 후, 최종 역할 분리 문맥의 핵심 장면을 추가 확인한다.
func run() -> void:
 app = load("res://main.tscn").instantiate()
 root.add_child(app)
 app.brain.new_trial(1)
 app.brain.auto_enabled = false
 world = app.world
 world.set_physics_process(false)
 for enemy in world.get_node("Enemies").get_children(): enemy.set_physics_process(false)
 app.brain.measured.connect(func(record): records.append(record.duplicate(true)))
 await ask("quiet_shift", "오늘은 아직 별일 없는 거지? 근무는 좀 조용했으면 좋겠네.")
 world.trigger_blackout()
 await ask("outage_next_step", "방금 불 꺼진 거 봤지? 어디부터 확인하면 돼?")
 world.npc.position = world.player.position + Vector2(40, 0)
 world.request_flashlight()
 world.apply_interaction("flashlight")
 world.apply_interaction("storage_gate")
 await ask("panel_roles", "저 패널 두 개 중 어느 쪽을 네가 맡는 거야?")
 for enemy in world.get_node("Enemies").get_children(): enemy.hp = 0
 world.locker.opened = true # 대화 상태 fixture. 실제 패널 기믹은 기존 회귀에서 별도 검증.
 world.apply_interaction("fuse")
 world.apply_interaction("lab_gate")
 world.apply_interaction("generator")
 await ask("power_without_alarm", "퓨즈 끼웠고 불 들어왔어. 그럼 지금은?")
 world.trigger_alarm()
 world.apply_interaction("exit")
 await ask("entry_referent", "그럼 여기선 뭘 확인해야 하는 거야?")
 await ask("fictional_meal_not_memory", "우리 실제로 휴게실에서 스파게티를 같이 먹은 적이 있었나?")
 var directory := ProjectSettings.globalize_path("res://../evidence/story_ui")
 DirAccess.make_dir_recursive_absolute(directory)
 var result := {"passed": not checks.values().has(false), "check_count": checks.size(), "checks": checks, "samples": samples, "actual_inference": true, "model": app.brain.local_dialogue.settings.model, "created_utc": Time.get_datetime_string_from_system(true), "general_dialogue_quality_proven": false}
 FileAccess.open(directory.path_join("final_dialogue_probe.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
 print("FINAL_DIALOGUE_PROBE ", JSON.stringify({"passed": result.passed, "check_count": checks.size()}))
 app.queue_free()
 await process_frame
 quit(0 if result.passed else 1)
