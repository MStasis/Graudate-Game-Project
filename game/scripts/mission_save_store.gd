class_name MissionSaveStore
extends RefCounted
## JSON만 읽고 전체 검증을 끝낸 후 호출자가 월드를 복원한다.
const VERSION := 2
var directory := "user://mission_saves"
var last_error := ""

func path_for(slot: int) -> String:
 return directory.path_join("slot_%d.json" % slot)

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
 if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
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
 if data.get("version") == 1:
  var legacy := world.scenario_configuration().duplicate(true)
  legacy.erase("mechanics")
  if data.get("scenario") != JSON.stringify(legacy).sha256_text() or not data.get("world") is Dictionary: return fail("이전 저장의 전투 조건이 일치하지 않습니다.")
  # 검증할 메모리 사본만 변환한다. 원본 슬롯은 덮어쓰지 않는다.
  var old: Dictionary = data.world
  old.merge({"flashlight_owned": true, "flashlight_dropped": false, "flashlight_position": old.get("npc_position"), "facing": [1.0, 0.0], "locker": {"opened": old.get("fuse_collected", false), "supply_taken": false, "sequence_elapsed": -1.0, "beep_index": 0}})
  data.version = VERSION
  data.scenario = JSON.stringify(world.scenario_configuration()).sha256_text()
  data["migrated_from"] = 1
 if data.get("version") != VERSION or data.get("scenario") != JSON.stringify(world.scenario_configuration()).sha256_text(): return fail("다른 버전이나 전투 규칙의 저장 파일입니다.")
 if not whole(data.get("provider"), 0, 2) or not data.get("saved_at") is String: return fail("저장 정보가 올바르지 않습니다.")
 var state = data.get("world")
 if not state is Dictionary or state.get("map_id") not in ["lab", "storage"]: return fail("구역 정보가 올바르지 않습니다.")
 for key in ["fuse_collected", "power_restored", "finished", "defeated", "cache_used"]:
  if not state.get(key) is bool: return fail("임무 정보가 손상되었습니다.")
 if state.finished or state.defeated or (state.power_restored and not state.fuse_collected): return fail("복원할 수 없는 임무 상태입니다.")
 for entry in [["player_hp", 1, world.max_hp], ["ammo", 0, world.max_ammo], ["medkits", 0, world.initial_medkits], ["supply_packs", 0, world.initial_supply_packs], ["cover_charges", 0, world.initial_cover_charges], ["npc_hp", 0, world.npc_max_hp], ["npc_ammo", 0, world.npc_initial_ammo]]:
  if not whole(state.get(entry[0]), entry[1], entry[2]): return fail("체력·탄약·재고 정보가 손상되었습니다.")
 for key in ["cover_time", "guide_time", "heal_cd", "supply_cd", "guide_cd", "shoot_cd", "npc_shoot_cd"]:
  if not number(state.get(key), 0, maxf(60.0, world.cover_duration)): return fail("재사용 대기시간이 올바르지 않습니다.")
 for key in ["player_position", "npc_position"]:
  if not point(state.get(key), world.room_rect): return fail("캐릭터 위치가 올바르지 않습니다.")
 for key in ["flashlight_owned", "flashlight_dropped"]:
  if not state.get(key) is bool: return fail("손전등 정보가 손상되었습니다.")
 if state.flashlight_owned and state.flashlight_dropped: return fail("손전등 보유/지급 상태가 올바르지 않습니다.")
 if (state.map_id == "storage" or state.fuse_collected) and not state.flashlight_owned: return fail("암전 구역 진입에 필요한 손전등 정보가 없습니다.")
 if not point(state.get("flashlight_position"), world.room_rect): return fail("손전등 위치가 올바르지 않습니다.")
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
  if not item is Dictionary or not whole(item.get("hp"), 0, enemy.max_hp) or not point(item.get("position"), world.room_rect) or not number(item.get("attack_wait"), -60, 60): return fail("적 상태가 손상되었습니다.")
 for key in ["history", "exploration"]:
  if not data.has(key): return fail("저장 데이터가 누락되었습니다.")
 if not state.get("recent_events") is Array or state.recent_events.size() > 6: return fail("임무 기억이 올바르지 않습니다.")
 for text in state.recent_events:
  if not text is String or text.length() > 1000: return fail("임무 기억이 손상되었습니다.")
 if not data.history is Array or data.history.size() > 3: return fail("대화 기억이 올바르지 않습니다.")
 for item in data.history:
  if not item is Dictionary or not item.get("question") is String or not item.get("answer") is String: return fail("대화 기억이 손상되었습니다.")
  if item.question.length() > 300 or item.answer.length() > 2000: return fail("대화 기억이 너무 깁니다.")
 if not data.exploration is Dictionary: return fail("탐색 기록이 손상되었습니다.")
 for room in data.exploration:
  if room not in ["lab", "storage"] or not data.exploration[room] is Array or data.exploration[room].size() > 384: return fail("탐색 구역이 올바르지 않습니다.")
  for cell in data.exploration[room]:
   if not whole(cell, 0, 383): return fail("탐색 위치가 올바르지 않습니다.")
 return true
