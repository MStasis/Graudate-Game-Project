class_name MissionSaveStore
extends RefCounted
## JSON만 읽고 전체 검증을 끝낸 후 호출자가 월드를 복원한다.
const VERSION := 3
var directory := "user://mission_saves"
var last_error := ""

func path_for(slot: int) -> String:
 return directory.path_join("slot_%d.json" % slot)

func has_slot(slot: int) -> bool:
 var path := path_for(slot)
 return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")

func slot_label(slot: int) -> String:
 if not has_slot(slot): return "비어 있음"
 var data := read_slot(slot)
 if not data.get("saved_at") is String or not data.get("world") is Dictionary:
  return "손상된 저장"
 var room: String = ExplorationMap.ROOM_NAMES.get(data.world.get("map_id"), "")
 if room.is_empty(): return "손상된 저장"
 return "%s · %s" % [data.saved_at, room]

func write_slot(slot: int, data: Dictionary) -> bool:
 last_error = ""
 if slot < 1 or slot > 3: return fail("저장 슬롯이 올바르지 않습니다.")
 if DirAccess.make_dir_recursive_absolute(directory) != OK: return fail("저장 폴더를 만들 수 없습니다.")
 var path := path_for(slot)
 var temp := path + ".tmp"
 var file := FileAccess.open(temp, FileAccess.WRITE)
 if not file: return fail("저장 파일을 열 수 없습니다.")
 file.store_string(JSON.stringify(data, "  "))
 file.flush()
 var error := file.get_error()
 file.close()
 if error != OK: return fail("저장 파일을 기록하지 못했습니다.")
 # 기존 슬롯은 교체가 성공할 때까지 백업으로 보존한다.
 var backup := path + ".bak"
 if not FileAccess.file_exists(path) and FileAccess.file_exists(backup):
  if DirAccess.rename_absolute(backup, path) != OK: return fail("이전 저장 백업을 복구하지 못했습니다.")
 if FileAccess.file_exists(backup):
  if DirAccess.remove_absolute(backup) != OK: return fail("기존 저장 백업을 정리하지 못했습니다.")
 var had_save := FileAccess.file_exists(path)
 if had_save and DirAccess.rename_absolute(path, backup) != OK: return fail("기존 저장 파일을 보존하지 못했습니다.")
 if DirAccess.rename_absolute(temp, path) != OK:
  if had_save: DirAccess.rename_absolute(backup, path)
  return fail("슬롯 교체에 실패했습니다. 기존 저장을 유지합니다.")
 if had_save: DirAccess.remove_absolute(backup)
 return true

func read_slot(slot: int) -> Dictionary:
 last_error = ""
 if slot < 1 or slot > 3:
  fail("저장 슬롯이 올바르지 않습니다.")
  return {}
 var path := path_for(slot)
 if not FileAccess.file_exists(path) and FileAccess.file_exists(path + ".bak"): path += ".bak"
 var file := FileAccess.open(path, FileAccess.READ)
 if not file:
  fail("저장 파일이 없습니다.")
  return {}
 if file.get_length() > 1048576:
  fail("저장 파일 크기가 올바르지 않습니다.")
  return {}
 var json := JSON.new()
 if json.parse(file.get_as_text()) != OK or not json.data is Dictionary or json.data.is_empty():
  fail("손상된 저장 파일입니다.")
  return {}
 return json.data

func fail(message: String) -> bool:
 last_error = message
 return false

func number(value: Variant, low: float, high: float) -> bool:
 return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

func whole(value: Variant, low: int, high: int) -> bool:
 return number(value, low, high) and float(value) == floorf(float(value))

func point(value: Variant, bounds: Rect2) -> bool:
 return value is Array and value.size() == 2 and number(value[0], bounds.position.x, bounds.end.x) and number(value[1], bounds.position.y, bounds.end.y)

func validate(data: Dictionary, world: DemoWorld) -> bool:
 var source_version = data.get("version")
 var current_config := world.scenario_configuration()
 if data.get("world") is Dictionary and data.world.has("fleet_demo"):
  return _validate_fleet_save(data, world, current_config)
 var current_hash := JSON.stringify(current_config).sha256_text()
 var legacy_config := world.scenario_configuration(true)
 var legacy_hash := JSON.stringify(legacy_config).sha256_text()
 var migrate_layout := false
 # v3 선택 확장: 이전 시나리오 해시를 정확히 확인하고 메모리 사본만 변환한다.
 var previous_config := legacy_config.duplicate(true)
 previous_config.erase("containment")
 var prior_hash := JSON.stringify(previous_config).sha256_text()
 previous_config.erase("companion_rules")
 var prior_without_companion := JSON.stringify(previous_config).sha256_text()
 if source_version == VERSION and data.get("world") is Dictionary:
  var without_companion := legacy_config.duplicate(true)
  without_companion.erase("companion_rules")
  if data.get("scenario") in [legacy_hash, JSON.stringify(without_companion).sha256_text()] or (not data.world.has("containment") and data.get("scenario") in [prior_hash, prior_without_companion]):
   migrate_layout = true
   data.scenario = current_hash
   if not data.world.has("containment"): data["migrated_containment"] = true
 if source_version in [1, 2] and data.get("world") is Dictionary:
  var compatible := []
  for base in [legacy_config, current_config]:
   var hashes := _compatible_hashes(base, source_version)
   compatible.append_array(hashes)
   if base == legacy_config: migrate_layout = data.get("scenario") in hashes
  if data.get("scenario") not in compatible: return fail("이전 저장의 전투 조건이 일치하지 않습니다.")
  data.scenario = current_hash
 if data.get("version") == 1:
  # 위 호환 해시 검사에서 원래 조건을 검증했다.
  # 검증할 메모리 사본만 변환한다. 원본 슬롯은 덮어쓰지 않는다.
  var old: Dictionary = data.world
  old.merge({"flashlight_owned": true, "flashlight_dropped": false, "flashlight_position": old.get("npc_position"), "facing": [1.0, 0.0], "locker": {"opened": old.get("fuse_collected", false), "supply_taken": false, "sequence_elapsed": -1.0, "beep_index": 0}})
  data.version = VERSION
  data.scenario = current_hash
  data["migrated_from"] = 1
 # 이전 v2의 전투 조건을 정확히 대조한 뒤 새 선택 필드만 보완한다. 원본 파일은 쓰지 않는다.
 if data.get("version") == VERSION and data.get("scenario") != current_hash:
  var previous := current_config.duplicate(true)
  previous.erase("companion_rules")
  if data.get("scenario") == JSON.stringify(previous).sha256_text():
   data.scenario = current_hash
   data["migrated_companion_rules"] = true
 if source_version in [1, 2]:
  data.version = VERSION
  data["migrated_from"] = source_version
  if not data.world.has("story"): data.world["story"] = StoryProgress.legacy(data.world)
  data["atlas"] = {}
  data["journal"] = []
  data.world["containment"] = world.containment.initial_snapshot()
 if data.get("version") != VERSION or data.get("scenario") != current_hash: return fail("다른 버전이나 전투 규칙의 저장 파일입니다.")
 if data.get("world") is Dictionary and not data.world.has("containment"):
  data.world["containment"] = world.containment.initial_snapshot()
  var old_story = data.world.get("story", {})
  if old_story is Dictionary and old_story.get("events") is Array and "anomaly_observed" in old_story.events:
   data.world.containment.stage = "ready"
   data.world.story.stage = "containment"
   if "containment_briefed" not in data.world.story.events: data.world.story.events.append("containment_briefed")
 if not whole(data.get("provider"), 0, 2) or not data.get("saved_at") is String: return fail("저장 정보가 올바르지 않습니다.")
 var state = data.get("world")
 if not state is Dictionary or state.get("map_id") not in ExplorationMap.ROOM_NAMES: return fail("구역 정보가 올바르지 않습니다.")
 if migrate_layout and not _migrate_layout(data, world): return fail("이전 구역의 위치 정보가 손상되었습니다.")
 var bounds := world.bounds_for(state.map_id)
 if not whole(state.get("npc_reserve", world.npc_initial_reserve), 0, world.npc_initial_reserve) or not number(state.get("npc_reload_time", 0), 0, world.npc_reload_seconds): return fail("미카 예비탄/장전 상태가 손상되었습니다.")
 if state.get("companion_mode", "follow") not in ["follow", "wait"]: return fail("동행 상태가 손상되었습니다.")
 if state.get("companion_mode", "follow") == "wait" and not point(state.get("wait_position"), bounds): return fail("대기 위치가 손상되었습니다.")
 var support = state.get("completed_support", {})
 if not support is Dictionary or support.size() > 7: return fail("지원 결과가 손상되었습니다.")
 for action in support:
  if action not in NPCPolicy.ACTIONS or not whole(support[action], 0, 1000): return fail("지원 결과가 손상되었습니다.")
 for key in ["fuse_collected", "power_restored", "finished", "defeated", "cache_used"]:
  if not state.get(key) is bool: return fail("임무 정보가 손상되었습니다.")
 if state.finished or state.defeated or (state.power_restored and not state.fuse_collected): return fail("복원할 수 없는 임무 상태입니다.")
 for entry in [["player_hp", 1, world.max_hp], ["ammo", 0, world.max_ammo], ["medkits", 0, world.initial_medkits], ["supply_packs", 0, world.initial_supply_packs], ["cover_charges", 0, world.initial_cover_charges], ["npc_hp", 0, world.npc_max_hp], ["npc_ammo", 0, world.npc_initial_ammo]]:
  if not whole(state.get(entry[0]), entry[1], entry[2]): return fail("체력·탄약·재고 정보가 손상되었습니다.")
 for key in ["cover_time", "guide_time", "heal_cd", "supply_cd", "guide_cd", "shoot_cd", "npc_shoot_cd"]:
  if not number(state.get(key), 0, maxf(60.0, world.cover_duration)): return fail("재사용 대기시간이 올바르지 않습니다.")
 for key in ["player_position", "npc_position"]:
  if not point(state.get(key), bounds): return fail("캐릭터 위치가 올바르지 않습니다.")
 for key in ["flashlight_owned", "flashlight_dropped"]:
  if not state.get(key) is bool: return fail("손전등 정보가 손상되었습니다.")
 if state.flashlight_owned and state.flashlight_dropped: return fail("손전등 보유/지급 상태가 올바르지 않습니다.")
 if (state.map_id == "storage" or state.fuse_collected) and not state.flashlight_owned: return fail("암전 구역 진입에 필요한 손전등 정보가 없습니다.")
 if not point(state.get("flashlight_position"), world.bounds_for("lab")): return fail("손전등 위치가 올바르지 않습니다.")
 var facing = state.get("facing")
 if not facing is Array or facing.size() != 2 or not number(facing[0], -1, 1) or not number(facing[1], -1, 1): return fail("시야 방향이 손상되었습니다.")
 if absf(Vector2(facing[0], facing[1]).length() - 1.0) > 0.01: return fail("시야 방향이 올바르지 않습니다.")
 var locker = state.get("locker")
 if not locker is Dictionary or not locker.get("opened") is bool or not locker.get("supply_taken") is bool: return fail("보관함 정보가 손상되었습니다.")
 if not number(locker.get("sequence_elapsed"), -1, 60) or not whole(locker.get("beep_index"), 0, 6): return fail("보관함 잠금 상태가 올바르지 않습니다.")
 if (state.fuse_collected or locker.supply_taken) and not locker.opened: return fail("잠긴 보관함의 물품 상태가 올바르지 않습니다.")
 if not state.get("enemies") is Dictionary or state.enemies.size() != world.get_node("Enemies").get_child_count(): return fail("적 목록이 손상되었습니다.")
 for enemy in world.get_node("Enemies").get_children():
  var item = state.enemies.get(str(enemy.name))
  if not item is Dictionary or not whole(item.get("hp"), 0, enemy.max_hp) or not point(item.get("position"), world.bounds_for("storage")) or not number(item.get("attack_wait"), -60, 60): return fail("적 상태가 손상되었습니다.")
 for key in ["history", "exploration"]:
  if not data.has(key): return fail("저장 데이터가 누락되었습니다.")
 if not state.get("recent_events") is Array or state.recent_events.size() > 6: return fail("임무 기억이 올바르지 않습니다.")
 for text in state.recent_events:
  if not text is String or text.length() > 1000: return fail("임무 기억이 손상되었습니다.")
 if not data.history is Array or data.history.size() > MikaDialogue.HISTORY_LIMIT: return fail("대화 기억이 올바르지 않습니다.")
 for item in data.history:
  if not item is Dictionary or not item.get("question") is String or not item.get("answer") is String: return fail("대화 기억이 손상되었습니다.")
  if item.question.length() > 300 or item.answer.length() > 2000: return fail("대화 기억이 너무 깁니다.")
 if not data.exploration is Dictionary: return fail("탐색 기록이 손상되었습니다.")
 for room in data.exploration:
  if room not in ExplorationMap.ROOM_NAMES or not data.exploration[room] is Array or data.exploration[room].size() > 384: return fail("탐색 구역이 올바르지 않습니다.")
  for cell in data.exploration[room]:
   if not whole(cell, 0, 383): return fail("탐색 위치가 올바르지 않습니다.")
 if not validate_story_ui(data, world) or not validate_containment(state, world): return false
 _migrate_companion_name(data)
 return true

func _validate_fleet_save(data: Dictionary, world: DemoWorld, shared_config: Dictionary) -> bool:
 var config := shared_config.duplicate()
 config["fleet_demo"] = world.fleet_demo.configuration()
 if data.get("version") != VERSION or data.get("scenario") != JSON.stringify(config).sha256_text():
  return fail("다른 버전이나 전투 규칙의 함선 저장입니다.")
 var state: Dictionary = data.world
 var map = state.get("map_id")
 if map not in world.fleet_demo.rooms: return fail("구역 정보가 올바르지 않습니다.")
 for key in ["finished", "defeated", "cache_used", "power_restored", "fuse_collected"]:
  if not state.get(key) is bool: return fail("임무 정보가 손상되었습니다.")
 if state.finished or state.defeated: return fail("복원할 수 없는 임무 상태입니다.")
 var bounds := world.bounds_for(map)
 for key in ["player_position", "npc_position", "wait_position"]:
  if not point(state.get(key), bounds): return fail("캐릭터 위치가 올바르지 않습니다.")
 if not world.fleet_demo.validate(state, self): return fail("함선 진행 상태가 손상되었습니다.")
 # The fleet uses the original v3 resource, history and cooldown checks.
 var common := data.duplicate(true)
 common.scenario = JSON.stringify(shared_config).sha256_text()
 var legacy: Dictionary = common.world
 legacy.erase("fleet_demo")
 var p := world.bounds_for("lab").get_center()
 legacy.map_id = "lab"
 for key in ["player_position", "npc_position", "wait_position", "flashlight_position"]: legacy[key] = [p.x, p.y]
 legacy.flashlight_owned = false
 legacy.flashlight_dropped = false
 legacy.fuse_collected = false
 legacy.power_restored = false
 legacy.story = StoryProgress.new().snapshot()
 common.exploration = {}
 common.atlas = {}
 legacy.containment = world.containment.initial_snapshot()
 if not validate(common, world): return false
 var explored = data.get("exploration")
 if not explored is Dictionary: return fail("탐색 기록이 손상되었습니다.")
 for room in explored:
  if room not in world.fleet_demo.rooms or not explored[room] is Array or explored[room].size() > 384: return fail("탐색 구역이 올바르지 않습니다.")
  for cell in explored[room]:
   if not whole(cell, 0, 383): return fail("탐색 위치가 올바르지 않습니다.")
 return validate_story_ui(data, world)

func _compatible_hashes(base: Dictionary, version: int) -> Array:
 var hashes := []
 for prompt in [NPCPolicy.PROMPT_VERSION, "companion_v2.1_validated_context_order"]:
  var config := base.duplicate(true)
  config.companion_rules.prompt_version = prompt
  if version == 1: config.erase("mechanics")
  for drop_companion in [false, true]:
   if drop_companion: config.erase("companion_rules")
   hashes.append(JSON.stringify(config).sha256_text())
   var without_containment := config.duplicate(true)
   without_containment.erase("containment")
   hashes.append(JSON.stringify(without_containment).sha256_text())
 return hashes

func _migrate_layout(data: Dictionary, world: DemoWorld) -> bool:
 var state: Dictionary = data.world
 var previous := world.legacy_bounds()
 if state.map_id not in ["lab", "storage", "main_entry"] or not state.get("enemies") is Dictionary: return false
 var room := world.fleet_rooms.get(state.map_id) as FleetRoom
 for key in ["player_position", "npc_position", "wait_position", "flashlight_position"]:
  if key == "wait_position" and not state.has(key): continue
  if not point(state.get(key), previous): return false
  var destination := world.fleet_rooms.lab as FleetRoom if key == "flashlight_position" else room
  if destination: state[key] = _mapped_point(state[key], destination, previous)
 for enemy in state.enemies.values():
  if not enemy is Dictionary or not point(enemy.get("position"), previous): return false
  enemy.position = _mapped_point(enemy.position, world.fleet_rooms.storage, previous)
 # Previously explored cells use different terrain and interaction coordinates.
 for changed_room in ["lab", "storage"]:
  if data.get("exploration") is Dictionary: data.exploration.erase(changed_room)
  if data.get("atlas") is Dictionary:
   for group in ["known", "rooms"]:
    if data.atlas.get(group) is Dictionary: data.atlas[group].erase(changed_room)
 return true

func _mapped_point(value: Array, destination: FleetRoom, previous: Rect2) -> Array:
 var mapped := destination.migrate_position(SpriteTimeline.pixel(value), previous)
 return [mapped.x, mapped.y]

func _migrate_companion_name(data: Dictionary) -> void:
 for item in data.get("journal", []):
  if item.sender == "하린": item.sender = "미카"
  if item.sender != "플레이어": item.body = _companion_name(item.body)
 for turn in data.history: turn.answer = _companion_name(turn.answer)
 for index in data.world.recent_events.size():
  data.world.recent_events[index] = _companion_name(data.world.recent_events[index])

func _companion_name(value: String) -> String:
 return value.replace("하린이", "미카가").replace("하린은", "미카는").replace("하린을", "미카를").replace("하린과", "미카와").replace("하린", "미카")

func validate_containment(state: Dictionary, world: DemoWorld) -> bool:
 var mission = state.get("containment")
 if not mission is Dictionary or mission.get("stage") not in ContainmentMission.STAGES or not mission.get("supply_used") is bool: return fail("봉쇄 임무 단계가 손상되었습니다.")
 var stage: String = mission.stage
 if stage == "complete": return fail("완료된 봉쇄 임무는 불러올 수 없습니다.")
 if stage == "unobserved" and ("containment_briefed" in state.story.events or state.story.stage in ["containment", "contained"]): return fail("봉쇄 관측 사건과 단계가 일치하지 않습니다.")
 if stage != "unobserved" and (not state.power_restored or not state.story.tutorial_completed or state.story.stage != "containment" or "containment_briefed" not in state.story.events): return fail("봉쇄 서사와 임무 단계가 일치하지 않습니다.")
 if stage in ["wave_one", "wave_two"] and (state.map_id != "main_entry" or not mission.supply_used): return fail("봉쇄 전투 구역/보급 상태가 일치하지 않습니다.")
 var panel = mission.get("panel")
 if not panel is Dictionary or not panel.get("opened") is bool or not panel.get("supply_taken") is bool or not number(panel.get("sequence_elapsed"), -1, 1.1) or not whole(panel.get("beep_index"), 0, 6): return fail("봉쇄 패널 상태가 손상되었습니다.")
 if panel.opened or panel.supply_taken or (panel.sequence_elapsed >= 0 and stage != "panel_ready"): return fail("봉쇄 패널과 임무 단계가 일치하지 않습니다.")
 if not mission.get("enemies") is Dictionary or mission.enemies.size() != world.containment.enemies().size(): return fail("봉쇄 적 목록이 손상되었습니다.")
 var alive := 0
 for drone in world.containment.enemies():
  var enemy = mission.enemies.get(str(drone.name))
  if not enemy is Dictionary or not whole(enemy.get("hp"), 0, drone.max_hp) or not point(enemy.get("position"), world.bounds_for("main_entry")) or not number(enemy.get("attack_wait"), -60, 60): return fail("봉쇄 적 상태가 손상되었습니다.")
  if enemy.hp > 0:
   alive += 1
   if stage not in ["wave_one", "wave_two"] or drone.get_meta("wave") != (1 if stage == "wave_one" else 2): return fail("봉쇄 무리와 적 상태가 일치하지 않습니다.")
 if stage in ["wave_one", "wave_two"] and alive == 0: return fail("진행할 봉쇄 전투 대상이 없습니다.")
 for event in ["containment_wave_1", "containment_wave_2", "containment_waves_cleared"]:
  var required: bool = stage_event_index(event) <= ContainmentMission.STAGES.find(stage)
  if required != (event in state.story.events): return fail("봉쇄 사건 순서가 일치하지 않습니다.")
 return true

func stage_event_index(event: String) -> int:
 return {"containment_wave_1": 2, "containment_wave_2": 3, "containment_waves_cleared": 4}[event]

func validate_story_ui(data: Dictionary, world: DemoWorld) -> bool:
 var state: Dictionary = data.world
 var story = state.get("story")
 if not story is Dictionary or story.get("stage") not in StoryProgress.STAGES or not story.get("events") is Array or story.events.size() > 16 or not story.get("tutorial_completed") is bool or not number(story.get("elapsed"), 0, 1000000): return fail("서사 상태가 손상되었습니다.")
 for event in story.events:
  if event not in ["blackout", "flashlight_collected", "storage_entered", "fuse_collected", "power_restored", "anomaly_alarm", "main_entered", "anomaly_observed", "containment_briefed", "containment_wave_1", "containment_wave_2", "containment_waves_cleared", "containment_completed"]: return fail("서사 사건이 손상되었습니다.")
 var unique_events := {}
 for event in story.events:
  if unique_events.has(event): return fail("서사 사건이 중복되었습니다.")
  unique_events[event] = true
 if story.stage in ["power_restored", "anomaly_alarm", "main_entry", "containment", "contained"] and not state.power_restored: return fail("서사와 전력이 일치하지 않습니다.")
 if state.map_id == "main_entry" and (not story.tutorial_completed or not state.power_restored): return fail("본편 진입 조건이 일치하지 않습니다.")
 if story.tutorial_completed and (story.stage not in ["main_entry", "containment", "contained"] or "main_entered" not in story.events): return fail("튜토리얼 완료 사건이 일치하지 않습니다.")
 var journal = data.get("journal", [])
 if not journal is Array or journal.size() > MessageJournal.LIMIT: return fail("통합 기록이 손상되었습니다.")
 var previous := 0
 var ids := {}
 for item in journal:
  if not item is Dictionary or not whole(item.get("sequence"), previous + 1, 1000000000) or not item.get("id") is String or ids.has(item.id): return fail("기록 순서·ID가 손상되었습니다.")
  for key in ["sender", "body", "room", "trial", "time"]:
   if not item.get(key) is String or item[key].length() > 2000: return fail("기록 본문이 손상되었습니다.")
  if item.get("channel") not in ["dialogue", "system"] or not whole(item.get("repeat"), 1, 100000): return fail("기록 채널이 손상되었습니다.")
  previous = int(item.sequence)
  ids[item.id] = true
 var atlas = data.get("atlas", {})
 if not atlas is Dictionary: return fail("지도 데이터가 손상되었습니다.")
 for group in ["known", "rooms"]:
  if not atlas.get(group, {}) is Dictionary: return fail("지도 정보가 손상되었습니다.")
  for room in atlas.get(group, {}):
   if room not in ExplorationMap.ROOM_NAMES: return fail("지도 방이 손상되었습니다.")
 for room in atlas.get("known", {}):
  var items = atlas.known[room]
  if not items is Dictionary or items.size() > 16: return fail("지도 표식이 손상되었습니다.")
  for item in items.values():
   if not item is Dictionary or not point(item.get("position"), world.bounds_for(room)) or item.get("kind") not in ["door", "objective", "supply", "device"] or not item.get("active") is bool or not item.get("id") is String or not item.get("name") is String or not item.get("destination") is String: return fail("지도 표식 위치가 손상되었습니다.")
 for room in atlas.get("rooms", {}):
  var geometry = atlas.rooms[room]
  var bounds := world.bounds_for(room)
  if not geometry is Dictionary or geometry.get("bounds") != [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y] or not geometry.get("obstacles") is Array or geometry.obstacles.size() > 32: return fail("지도 지형이 손상되었습니다.")
  for rect in geometry.obstacles:
   if not rect is Array or rect.size() != 4: return fail("지도 장애물이 손상되었습니다.")
   for value in rect:
    if not number(value, 0, 2000): return fail("지도 장애물 좌표가 손상되었습니다.")
 return true
