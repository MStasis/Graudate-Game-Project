extends RefCounted

const FleetDemo := preload("res://scripts/fleet_demo.gd")
const SCENARIOS := "res://resources/experiments/scenarios.json"
const QUESTIONS := "res://resources/experiments/questions.json"
var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SCENARIOS))
var questions := []
var question_error := ""

func _init() -> void:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(QUESTIONS)) != OK or not json.data is Array:
		question_error = "questions.json 질문 목록을 읽을 수 없습니다. %d행 · %s" % [json.get_error_line(), json.get_error_message()]
		return
	var ids := {}
	for q in json.data:
		if not q is Dictionary or not ["id","scenario_id","text","purpose","fact"].all(func(key): return q.get(key) is String and not q[key].strip_edges().is_empty()):
			question_error = "questions.json에 필수 항목이 비어 있는 질문이 있습니다."
			return
		if ids.has(q.id) or not catalog.dialogue.any(func(s): return s.id == q.scenario_id) or q.text.length() > MikaDialogue.QUESTION_LIMIT:
			question_error = "questions.json의 ID, 적용 상황 또는 질문 길이를 확인하세요. " + q.id
			return
		ids[q.id] = true
	questions = json.data

func find_scenario(id: String) -> Dictionary:
	for kind in ["dialogue", "decision", "combat"]:
		for item in catalog[kind]:
			if item.id == id: return item
	return {}

# Call on a newly reset Fleet world. The save validator checks real map/stage/enemy constraints.
func apply(world: DemoWorld, item: Dictionary) -> bool:
	var scene := find_scenario(item.get("base", item.id))
	var demo := world.fleet_demo
	var step: int = FleetDemo.Step[scene.step]
	demo.clear_cues()
	demo.step = step as FleetDemo.Step
	world.story.advance("blackout", "blackout")
	if step >= FleetDemo.Step.FIND_FUSE:
		world._remember("미카를 만났다. 비품실에서 퓨즈를 가져오기로 했다.")
	if scene.id == "D03" or step >= FleetDemo.Step.FUSE_HELD:
		demo.cabinets.cabinet_fuse = true
	if step >= FleetDemo.Step.FUSE_HELD:
		world.fuse_collected = true
		world.story.advance("fuse_return", "fuse_collected")
		world._remember("비품실 왼쪽 캐비닛에서 바닥에 떨어진 정상 퓨즈를 주웠다.")
	if step >= FleetDemo.Step.TO_POWER:
		world._remember("복도에서 처음 마주친 침식된 선원을 제압했다.")
	if step >= FleetDemo.Step.ALARM:
		demo.inserted = true
		demo.fuse_handed = true
		world.power_restored = true
		world.story.advance("power_restored", "power_restored")
		world._remember("전기실에서 퓨즈를 교체하고 미카가 단말로 전력을 복구했다.")
		world.story.advance("anomaly_alarm", "anomaly_alarm")
	if step >= FleetDemo.Step.CORES:
		world.story.tutorial_completed = true
		world.story.advance("main_entry", "main_entered")
		world.story.advance("containment", "containment_briefed")
		world._remember("미카는 아래쪽 정상 코어의 격벽 장치를 맡았다. 플레이어는 위쪽 침식 코어 레버를 신호에 맞춰 당긴다.")
		demo.core_seen = true
		demo.wave = 2 if step == FleetDemo.Step.WAVES else 3
	if step >= FleetDemo.Step.LEVER:
		world._remember("연구실 B동에서 침식된 선원과 센트리를 모두 제압했다.")
	for enemy in demo.unit_pool:
		if (step == FleetDemo.Step.AMBUSH and enemy.get_meta("wave") == 0) or (step == FleetDemo.Step.WAVES and enemy.get_meta("wave") == demo.wave):
			enemy.reset_enemy()
			enemy.attack_wait = 1.2 if step == FleetDemo.Step.AMBUSH else 1.5
	var spawn := world.bounds_for(scene.map).get_center()
	var room = demo.rooms[scene.map]
	match scene.id:
		"D01": spawn = FleetDemo.START
		"D02": spawn = FleetDemo.Room.pixel(room.doors.to_corridor.arrival_px)
		"D03", "D04": spawn = room.approach("cabinet_fuse")
		"D05", "D06": spawn = FleetDemo.Room.pixel(room.doors.to_supply.arrival_px)
		"D07": spawn = FleetDemo.Room.pixel(room.doors.to_power.arrival_px)
	if item.has("spawn"): spawn = Vector2(item.spawn[0], item.spawn[1])
	world._change_map(scene.map, spawn)
	if scene.id == "D02": world.npc.position = FleetDemo.Room.pixel(room.layout.spawn_px)
	demo._restore_props()
	if step >= FleetDemo.Step.WAVES: world.npc.position = demo.room().approach("normal_stop")
	if step == FleetDemo.Step.ARMED: world.player.position = demo.room().approach("eroded_stop")
	if item.has("hp"):
		world.player_hp = int(item.hp)
		for key in ["ammo", "magazines", "medkits", "supply_packs", "cover_charges"]:
			world.set(key, int(item[key]))
		if item.get("device", "off") != "off":
			world.cover_time = world.cover_duration
			world.healer.begin(world.safe_position, world.cover_radius)
			if item.device == "outside": world.player.position = world.safe_position + Vector2(world.cover_radius + 48, 0)
	if item.has("seconds"):
		# Keep real enemy physics and damage, isolate wave/cutscene progression.
		for enemy in demo.unit_pool:
			enemy.defeated.disconnect(demo._enemy_defeated)
		world.npc.position = demo.companion_spawn(world.player.position)
	world._sync_state()
	world.state_changed.emit()
	return demo.validate(world.save_snapshot(), MissionSaveStore.new())
