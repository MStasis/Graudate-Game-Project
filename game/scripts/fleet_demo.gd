extends Node2D
## Story, room props and timed cues for the five-room demo. Combat and movement run in DemoWorld.

const Room := preload("res://scripts/fleet_demo_room.gd")
const Lines := preload("res://scripts/fleet_demo_lines.gd")
const Crew := preload("res://scenes/RiftCrew.tscn")
const MAPS := {
	"corridor": preload("res://assets/fleet_demo/rooms/corridor.tscn"),
	"mika_quarters": preload("res://assets/fleet_demo/rooms/mika_quarters.tscn"),
	"supply_room": preload("res://assets/fleet_demo/rooms/supply_room.tscn"),
	"power_room": preload("res://assets/fleet_demo/rooms/power_room.tscn"),
	"research_lab_b": preload("res://assets/fleet_demo/rooms/research_lab_b.tscn"),
}
const NAMES := {
	"corridor": "통창 복도", "mika_quarters": "미카의 방", "supply_room": "비품실",
	"power_room": "전기실", "research_lab_b": "연구실 B동",
}
const START := Vector2(77, 238)
const AMBUSH_SPAWN := Vector2(1190, 235)
const WAVE_PAUSE := 1.25
const INTERACT_RADIUS := 49.0
# Clear of both side banks, and offset from the player's interaction point.
const REPAIR_POSITION := Vector2(173, 203)
const AMBUSH_HINT := "좌클릭을 눌러 적을 공격하세요"
const WALK_HINT := "WASD로 이동하세요"
const CABINETS := ["cabinet_fuse", "cabinet_reserve", "personal_cabinet"]
const PROPS := {
	"mika_quarters": {"personal_cabinet": "개인 캐비닛"},
	"supply_room": {"cabinet_fuse": "왼쪽 캐비닛", "cabinet_reserve": "오른쪽 캐비닛", "crate_side": "상자 조사", "ammo_stock": "보급 탄약함"},
	"power_room": {"main_fuse_breaker": "주 퓨즈함", "power_terminal": "전력 단말"},
	"research_lab_b": {"eroded_stop": "침식 코어 레버", "normal_sector_crate": "봉쇄 보급함", "supply_cabinet": "봉쇄 보급함"},
}

enum Step { FIND_MIKA, FIND_FUSE, FUSE_HELD, AMBUSH, TO_POWER, REPAIR, ALARM, TO_LAB, CORES, WAVES, LEVER, ARMED, ENDING }

signal line_changed(speaker: String, body: String)
signal showing_reaction(active: bool)

var world: DemoWorld
var rooms := {}
var unit_pool: Array[MissionDrone]
var step := Step.FIND_MIKA
var cabinets := {}
var inserted := false
var core_seen := false
var lab_supply_used := false
var wave := 0
var wave_wait := -1.0
var camera_weight := 0.0
var camera_point := Vector2.ZERO
var fixed_aim := false
var show_mika_portrait := true
var npc_task := ""
var voice_active := false
var hint := ""
var opening_pending := false
var _sequence: Tween
var _fuse_toss: Tween
var _voice_left := 0.0
var _advance_allowed := false
var _dialogue: Array
var _after_dialogue: Callable
var _enemies_root: Node2D

func bind(mission: DemoWorld) -> void:
	world = mission
	# Like the existing FleetRoom, keep the map origin at (0, 0) for normal world coordinates.
	y_sort_enabled = true
	for id in MAPS:
		var room: Node2D = MAPS[id].instantiate()
		room.set_script(Room)
		room.hide()
		add_child(room)
		room.setup(id)
		rooms[id] = room
	_enemies_root = Node2D.new()
	_enemies_root.y_sort_enabled = true
	_enemies_root.z_index = 6
	add_child(_enemies_root)
	_add_enemy("HallCrew", "corridor", 0, AMBUSH_SPAWN)
	for index in range(1, 4):
		var markers: Node2D = rooms.research_lab_b.get_node("Wave_%d" % index)
		for marker: Marker2D in markers.get_children():
			_add_enemy("Wave%d_%s" % [index, marker.name], "research_lab_b", index, marker.position)
	hide()

func _add_enemy(id: String, room: String, group: int, start: Vector2) -> void:
	var enemy := Crew.instantiate() as MissionDrone
	enemy.name = id
	enemy.set_meta("room", room)
	enemy.set_meta("wave", group)
	enemy.set_meta("spawn", start)
	enemy.position = start
	enemy.hp = 0
	enemy.mission = world
	enemy.navigate_obstacles = true
	enemy.navigation.clearance = 22.0
	enemy.target = world.player
	enemy.companion = world.npc
	enemy.hit_player.connect(world.take_damage)
	enemy.hit_companion.connect(world.take_npc_damage)
	enemy.defeated.connect(_enemy_defeated)
	enemy.sync_presence(false, false)
	_enemies_root.add_child(enemy)
	unit_pool.append(enemy)

func reset() -> void:
	clear_cues()
	step = Step.FIND_MIKA
	cabinets.clear()
	inserted = false
	core_seen = false
	lab_supply_used = false
	wave = 0
	wave_wait = -1
	opening_pending = true
	hint = ""
	_reset_enemies()
	_restore_props()

func _exit_tree() -> void:
	if _sequence: _sequence.kill()
	if _fuse_toss: _fuse_toss.kill()
	_after_dialogue = Callable()

func clear_cues() -> void:
	if _sequence: _sequence.kill()
	if _fuse_toss: _fuse_toss.kill()
	_sequence = null
	_fuse_toss = null
	world.fuse.get_node("Sprite2D").rotation = 0.0
	_after_dialogue = Callable()
	_dialogue.clear()
	_voice_left = 0.0
	voice_active = false
	npc_task = ""
	fixed_aim = false
	camera_weight = 0.0
	opening_pending = false
	line_changed.emit("", "")
	showing_reaction.emit(false)

func _reset_enemies() -> void:
	for enemy in unit_pool:
		enemy.reset_animation()
		enemy.hp = 0
		enemy.velocity = Vector2.ZERO
		enemy.position = enemy.get_meta("spawn")
		enemy.navigation.reset()
		enemy.sync_presence(false, false)

func _restore_props() -> void:
	for id: String in CABINETS:
		var room = rooms.mika_quarters if id == "personal_cabinet" else rooms.supply_room
		room.play(id, "open", true, cabinets.get(id, false))
	rooms.power_room.play("main_fuse_breaker", "open_broken", true)
	rooms.research_lab_b.set_levers(step == Step.ENDING)
	world.fuse.position = rooms.supply_room.approach("cabinet_fuse") + Vector2(16, 19)

func room():
	return rooms[world.map_id]

func companion_spawn(player_spawn: Vector2) -> Vector2:
	var safe: Rect2 = room().bounds.grow(-18)
	var obstacles: Array[Rect2] = []
	for collider in room().find_children("*", "StaticBody2D", true, false):
		var center: Vector2 = world.to_local(collider.global_position)
		obstacles.append(Rect2(center - collider.footprint * 0.5, collider.footprint).grow(14))
	for offset in [Vector2(-32, 24), Vector2(32, 24), Vector2(32, -24), Vector2(-32, -24), Vector2(0, 42), Vector2(0, -42)]:
		var point: Vector2 = player_spawn + offset
		if safe.has_point(point) and not obstacles.any(func(rect): return rect.has_point(point)):
			return point
	return player_spawn

func room_enemies() -> Array:
	return unit_pool.filter(func(enemy): return enemy.get_meta("room") == world.map_id)

func combat_area() -> bool:
	return (world.map_id == "corridor" and step == Step.AMBUSH and not voice_active) or (world.map_id == "research_lab_b" and step == Step.WAVES)

func locks_movement() -> bool:
	return opening_pending or voice_active or _sequence != null or step in [Step.ARMED, Step.ENDING] or npc_task in ["breaker", "power"]

func allows_interact() -> bool:
	return step == Step.ARMED and not voice_active and _sequence == null

func can_save() -> bool:
	return _fuse_toss == null and (not locks_movement() or allows_interact())

func configuration() -> Dictionary:
	var markers := {}
	for enemy in unit_pool:
		var p: Vector2 = enemy.get_meta("spawn")
		markers[str(enemy.name)] = [p.x, p.y]
	return {"layout": 1, "crew_spawns": markers, "wave_pause": WAVE_PAUSE}

func snapshot() -> Dictionary:
	var enemies := {}
	for enemy in unit_pool:
		if enemy.hp > 0:
			enemies[str(enemy.name)] = {"hp": enemy.hp, "position": [enemy.position.x, enemy.position.y], "attack_wait": enemy.attack_wait}
	return {"step": step, "opened": cabinets.keys(), "inserted": inserted, "core_seen": core_seen,
		"lab_supply_used": lab_supply_used, "wave": wave, "wave_wait": wave_wait, "enemies": enemies}

func restore(state: Dictionary) -> void:
	clear_cues()
	_reset_enemies()
	step = int(state.step) as Step
	cabinets.clear()
	for id in state.opened: cabinets[id] = true
	inserted = state.inserted
	core_seen = state.core_seen
	lab_supply_used = state.lab_supply_used
	wave = int(state.wave)
	wave_wait = float(state.wave_wait)
	hint = WALK_HINT if step == Step.FIND_MIKA else AMBUSH_HINT if step == Step.AMBUSH else ""
	for enemy in unit_pool:
		if not state.enemies.has(str(enemy.name)): continue
		var data: Dictionary = state.enemies[str(enemy.name)]
		enemy.hp = int(data.hp)
		enemy.position = Room.pixel(data.position)
		enemy.attack_wait = float(data.attack_wait)
	_restore_props()
	if step == Step.ARMED:
		fixed_aim = true
		world.npc.show_pose("idle", room().ground("normal_stop"))

func validate(state: Dictionary, store: MissionSaveStore) -> bool:
	var data = state.get("fleet_demo")
	if not data is Dictionary or state.get("map_id") not in MAPS: return false
	if not store.whole(data.get("step"), Step.FIND_MIKA, Step.ARMED) or not store.whole(data.get("wave"), 0, 3): return false
	if not data.get("opened") is Array or data.opened.size() > CABINETS.size(): return false
	var unique := {}
	for id in data.opened:
		if id not in CABINETS or unique.has(id): return false
		unique[id] = true
	for key in ["inserted", "core_seen", "lab_supply_used"]:
		if not data.get(key) is bool: return false
	if not store.number(data.get("wave_wait"), -1, WAVE_PAUSE) or not data.get("enemies") is Dictionary: return false
	var phase := int(data.step)
	var group := int(data.wave)
	var map: String = state.map_id
	if (phase >= Step.FUSE_HELD) != state.fuse_collected or (phase >= Step.ALARM) != state.power_restored: return false
	if data.inserted != state.power_restored or (state.fuse_collected and "cabinet_fuse" not in data.opened): return false
	if phase in [Step.FIND_MIKA, Step.AMBUSH] and map != "corridor": return false
	if map == "research_lab_b" and phase < Step.CORES: return false
	if phase >= Step.WAVES and map != "research_lab_b": return false
	if phase < Step.WAVES and group != 0: return false
	if phase >= Step.LEVER and (group != 3 or not data.core_seen): return false
	if phase == Step.WAVES and (group == 0 or not data.core_seen): return false
	if phase == Step.AMBUSH and data.wave_wait != -1: return false
	if phase == Step.ARMED:
		var lever: Vector2 = rooms.research_lab_b.approach("eroded_stop")
		var partner: Vector2 = rooms.research_lab_b.approach("normal_stop")
		if Room.pixel(state.player_position).distance_to(lever) > INTERACT_RADIUS or Room.pixel(state.npc_position).distance_to(partner) > 19: return false
	if phase == Step.AMBUSH and data.enemies.size() != 1: return false
	if phase == Step.WAVES and (data.enemies.is_empty() != (data.wave_wait >= 0) or (group == 3 and data.enemies.is_empty())): return false
	if phase not in [Step.AMBUSH, Step.WAVES] and (not data.enemies.is_empty() or data.wave_wait != -1): return false
	var verified := 0
	for enemy in unit_pool:
		var id := str(enemy.name)
		if not data.enemies.has(id): continue
		var item = data.enemies[id]
		if not item is Dictionary or enemy.get_meta("room") != map or enemy.get_meta("wave") != group: return false
		if not store.whole(item.get("hp"), 1, enemy.max_hp) or not store.point(item.get("position"), rooms[map].bounds) or not store.number(item.get("attack_wait"), -3600, 60): return false
		verified += 1
	return verified == data.enemies.size()

func sync() -> void:
	show()
	for id in rooms:
		rooms[id].visible = id == world.map_id
	rooms.corridor.set_warning(alarm_active())
	rooms.corridor.set_door_available("to_lab", step >= Step.TO_LAB and step < Step.ENDING)
	rooms.research_lab_b.set_warning(alarm_active())
	rooms.power_room.set_terminal_powered(world.power_restored)
	world.npc.visible = step != Step.FIND_MIKA or world.map_id == "mika_quarters"
	world.fuse.visible = world.map_id == "supply_room" and cabinets.get("cabinet_fuse", false) and not world.fuse_collected
	for enemy in unit_pool:
		var in_room: bool = enemy.get_meta("room") == world.map_id
		enemy.sync_presence(in_room, combat_area() and not world.defeated and not world.finished and not world.transition_active())
		enemy.companion_alive = false

func _updated() -> void:
	world._sync_state()
	world.state_changed.emit()

func alarm_active() -> bool:
	return world.power_restored and step >= Step.ALARM and step < Step.ENDING

func tick(delta: float) -> void:
	if opening_pending:
		opening_pending = false
		_opening()
	if voice_active:
		_voice_left -= delta
		if _voice_left <= 0: _next_line()
	if locks_movement() or world.transition_active(): return
	match step:
		Step.CORES:
			if world.map_id != "research_lab_b": return
			if not core_seen and world.player.position.distance_to(room().approach("eroded_core")) <= 95:
				_discover_core()
			elif _near_lever():
				if not core_seen: _discover_core()
				else: _start_wave(1)
		Step.WAVES:
			if wave_wait >= 0.0:
				wave_wait = maxf(0.0, wave_wait - delta)
				if wave_wait <= 0.0: _start_wave(wave + 1)
		Step.LEVER:
			if _near_lever() and _mika_at_lever(): _countdown()

func _opening() -> void:
	world.story_event("blackout", "blackout")
	var black := world.get_node("RoomFade/Black") as ColorRect
	black.color.a = 1
	var cue := _new_sequence()
	cue.tween_interval(0.75)
	cue.tween_property(black, "color:a", 0.0, 0.48)
	cue.finished.connect(func():
		_sequence = null
		world._event("fleet_radio", {})
		_say(Lines.RADIO, func():
			hint = WALK_HINT
			_updated()))
	_updated()

func _new_sequence() -> Tween:
	_sequence = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	return _sequence

func _say(lines: Array, after := Callable(), advance := true) -> void:
	_dialogue = lines.duplicate()
	_after_dialogue = after
	_advance_allowed = advance
	voice_active = true
	_next_line()
	_updated()

func advance_dialogue() -> void:
	if voice_active and _advance_allowed and _voice_left > 0.0: _next_line()

func _next_line() -> void:
	if _dialogue.is_empty():
		voice_active = false
		line_changed.emit("", "")
		var after := _after_dialogue
		_after_dialogue = Callable()
		if after.is_valid(): after.call()
		_updated()
		return
	var line: Array = _dialogue.pop_front()
	show_mika_portrait = line[0] == "미카" and world.npc.visible
	_voice_left = clampf(1.15 + str(line[1]).length() * 0.060, 1.7, 5.8)
	if not _advance_allowed: _voice_left = 1.2 if line[1] == "당겨!" else 2.0
	line_changed.emit(line[0], line[1])

func on_enter(from: String) -> void:
	match world.map_id:
		"mika_quarters":
			if step != Step.FIND_MIKA: return
			world.npc.position = Room.pixel(room().layout.spawn_px)
			hint = ""
			_face_each_other()
			_say(Lines.QUARTERS, func():
				fixed_aim = false
				step = Step.FIND_FUSE
				world._remember("미카를 만났다. 비품실에서 퓨즈를 가져오기로 했다."))
		"corridor":
			if step == Step.FUSE_HELD and from == "supply_room": _start_ambush()
			elif step == Step.ALARM:
				_say(Lines.ALARM, func(): step = Step.TO_LAB)
		"power_room":
			if step != Step.TO_POWER: return
			step = Step.REPAIR
			world.npc.show_pose("idle", room().ground("main_fuse_breaker"))
			world.player.facing_direction = Vector2.UP
			fixed_aim = true
			_say(Lines.BREAKER, func(): fixed_aim = false)
		"research_lab_b":
			if step != Step.TO_LAB: return
			world.story.tutorial_completed = true
			world.story_event("main_entry", "main_entered")
			_say(Lines.LAB_ENTRY, _show_cores)

func _face_each_other() -> void:
	fixed_aim = true
	world.player.facing_direction = world.player.position.direction_to(world.npc.position)
	world.npc.show_pose("idle", world.player.position)

func _show_cores() -> void:
	var cue := _new_sequence()
	camera_point = room().ground("eroded_core") + Vector2(0, -60)
	cue.tween_property(self, "camera_weight", 1.0, 0.55).set_trans(Tween.TRANS_SINE)
	cue.tween_interval(1.05)
	cue.tween_property(self, "camera_point", room().ground("normal_core") + Vector2(0, -60), 0.72).set_trans(Tween.TRANS_SINE)
	cue.tween_interval(1.05)
	cue.tween_property(self, "camera_weight", 0.0, 0.60).set_trans(Tween.TRANS_SINE)
	cue.finished.connect(func():
		_sequence = null
		_say(Lines.LAB_PLAN, func():
			step = Step.CORES
			world.story_event("containment", "containment_briefed")
			world._remember("미카는 아래쪽 정상 코어의 격벽 장치를 맡았다. 플레이어는 위쪽 침식 코어 레버를 신호에 맞춰 당긴다.")))

func npc_target() -> Vector2:
	if npc_task == "breaker": return REPAIR_POSITION
	if npc_task == "power": return room().approach("power_terminal")
	if world.map_id == "research_lab_b" and step >= Step.CORES: return room().approach("normal_stop")
	return Vector2.INF

func npc_arrived() -> void:
	if npc_task == "breaker": _replace_fuse()
	elif npc_task == "power": _restore_power()

func _replace_fuse() -> void:
	npc_task = ""
	var power: Node2D = room()
	fixed_aim = true
	world.npc.show_pose("idle", power.ground("main_fuse_breaker"))
	var cue := _new_sequence()
	world.clear_projectiles()
	power.play("main_fuse_breaker", "open_broken")
	world._event("fleet_breaker_open", {})
	cue.tween_interval(0.70)
	cue.tween_callback(func():
		power.play("main_fuse_breaker", "open_empty", true, true)
		var slot: Vector2 = power.ground("main_fuse_breaker") + Vector2(5, -31)
		_show_fuse_motion(slot, slot + Vector2(-36, 69), Color("d3936a"))
		world._event("fleet_fuse_removed", {}))
	cue.tween_interval(0.66)
	cue.tween_callback(func():
		var slot: Vector2 = power.ground("main_fuse_breaker") + Vector2(5, -31)
		_show_fuse_motion(world.npc.position + Vector2(-8, -38), slot, Color("f2e3a5")))
	cue.tween_interval(0.30)
	cue.tween_callback(func():
		power.play("main_fuse_breaker", "open_working", true, true)
		inserted = true
		world._event("fleet_fuse_inserted", {})
		_updated())
	cue.tween_interval(0.54)
	cue.tween_callback(func(): power.play("main_fuse_breaker", "close_working"))
	cue.tween_interval(0.47)
	cue.finished.connect(func():
		_sequence = null
		_say(Lines.BREAKER_FIXED, func():
			fixed_aim = false
			npc_task = "power"
			world.npc_motion.arrived = false))

func _show_fuse_motion(from: Vector2, to: Vector2, tint: Color) -> void:
	var part := world.fuse.get_node("Sprite2D").duplicate() as Sprite2D
	part.position = from
	part.scale = Vector2.ONE * 0.26
	part.self_modulate = tint
	part.z_index = 10
	room().add_child(part)
	var motion := part.create_tween()
	motion.tween_property(part, "position", to, 0.28).set_trans(Tween.TRANS_QUAD)
	motion.parallel().tween_property(part, "rotation", PI, 0.28)
	motion.tween_property(part, "modulate:a", 0.0, 0.14)
	motion.finished.connect(part.queue_free)

func _restore_power() -> void:
	npc_task = ""
	var cue := _new_sequence()
	fixed_aim = true
	world.npc.show_pose("idle", room().ground("power_terminal"))
	world._event("fleet_terminal_operated", {})
	cue.tween_interval(0.85)
	cue.tween_callback(func():
		world.power_restored = true
		world.story_event("power_restored", "power_restored")
		world._event("power_restored", {})
		world._remember("전기실에서 퓨즈를 교체하고 미카가 단말로 전력을 복구했다.")
		_updated())
	cue.tween_interval(0.40)
	cue.tween_callback(func():
		step = Step.ALARM
		world.story_event("anomaly_alarm", "anomaly_alarm")
		world._event("anomaly_alarm", {})
		_face_each_other()
		showing_reaction.emit(true)
		_updated())
	cue.tween_interval(1.45)
	cue.finished.connect(func():
		_sequence = null
		fixed_aim = false
		showing_reaction.emit(false)
		_updated())

func _start_ambush() -> void:
	step = Step.AMBUSH
	var enemy := unit_pool[0]
	enemy.reset_enemy()
	enemy.attack_wait = 1.2
	enemy.animation.hold("move", "left")
	world.player.facing_direction = Vector2.RIGHT
	world.npc.show_pose("idle", enemy.position)
	_say(Lines.AMBUSH, func(): hint = AMBUSH_HINT)
	world._event("fleet_corridor_encounter", {"count": 1})

func _discover_core() -> void:
	core_seen = true
	_say(Lines.CORE)

func _start_wave(number: int) -> void:
	step = Step.WAVES
	wave = number
	wave_wait = -1.0
	var count := 0
	for enemy in unit_pool:
		if enemy.get_meta("wave") != wave: continue
		enemy.reset_enemy()
		enemy.attack_wait = 1.5
		enemy.animation.hold("move", SpriteTimeline.cardinal(enemy.position.direction_to(world.player.position)))
		count += 1
	world._event("fleet_wave_started", {"wave": wave, "count": count})
	world.epoch += 1
	_updated()

func _enemy_defeated() -> void:
	var remaining := world.enemies_remaining()
	world._event("enemy_defeated", {"mission": "fleet_demo", "remaining": remaining, "wave": wave})
	if remaining == 0:
		if step == Step.AMBUSH:
			hint = ""
			step = Step.TO_POWER
			world._remember("복도에서 처음 마주친 침식된 선원을 제압했다.")
			_say(Lines.AMBUSH_CLEAR)
		elif step == Step.WAVES and wave < 3: wave_wait = WAVE_PAUSE
		elif step == Step.WAVES:
			step = Step.LEVER
			world.clear_projectiles.call_deferred()
			world._remember("연구실 B동의 침식된 선원 세 무리를 모두 제압했다.")
			_say(Lines.WAVES_CLEAR)
	_updated()

func _near_lever() -> bool:
	return world.player.position.distance_to(room().approach("eroded_stop")) <= INTERACT_RADIUS

func _mika_at_lever() -> bool:
	return world.npc_hp > 0 and world.npc.position.distance_to(room().approach("normal_stop")) <= 19

func _countdown() -> void:
	world.active_action = ""
	world.npc.show_pose("idle", room().ground("normal_stop"))
	world.player.facing_direction = world.player.position.direction_to(room().ground("eroded_stop"))
	fixed_aim = true
	_say(Lines.COUNTDOWN, func():
		step = Step.ARMED
		world._event("fleet_pull_signal", {}), false)

func _pull() -> void:
	step = Step.ENDING
	room().set_levers(true)
	world._remember("미카의 신호에 맞춰 두 레버를 동시에 작동했다.")
	world._event("fleet_levers_pulled", {"player": "eroded_stop", "mika": "normal_stop"})
	var black := world.get_node("RoomFade/Black") as ColorRect
	var cue := _new_sequence()
	cue.tween_interval(0.33)
	cue.tween_property(black, "color:a", 1.0, 0.4)
	cue.tween_callback(func():
		var spawn := Room.pixel(rooms.corridor.doors.to_lab.arrival_px)
		world._change_map("corridor", spawn)
		_face_each_other())
	cue.tween_interval(0.20)
	cue.tween_property(black, "color:a", 0.0, 0.46)
	cue.finished.connect(func():
		_sequence = null
		_say(Lines.ENDING, world.complete_demo))
	_updated()

func landmarks() -> Array:
	var result := []
	for door: Dictionary in room().doors.values():
		result.append({"id": door.id, "name": NAMES[door.target_room], "kind": "door",
			"position": door.point_px, "destination": door.target_room, "active": _door_error(door).is_empty()})
	var items: Dictionary = PROPS.get(world.map_id, {})
	for id in items:
		var point: Vector2 = room().approach(id)
		result.append({"id": id, "name": items[id], "kind": "device", "position": [point.x, point.y],
			"destination": "", "active": id == "eroded_stop" and step == Step.ARMED})
	if world.fuse.visible:
		result.append({"id": "fuse", "name": "정상 퓨즈", "kind": "objective",
			"position": [world.fuse.position.x, world.fuse.position.y], "destination": "", "active": true})
	return result

func nearest_interaction() -> Dictionary:
	if not world.can_move and not allows_interact(): return {}
	if allows_interact():
		return {"id": "eroded_stop", "name": "침식 코어 레버 당기기"} if _near_lever() else {}
	var nearest := {}
	var limit := INTERACT_RADIUS
	for item in landmarks():
		if item.id == "fuse" or (step == Step.AMBUSH and item.kind == "door"): continue
		var distance := world.player.position.distance_to(Room.pixel(item.position))
		if item.kind == "door" and distance <= 32.0: return item
		if distance > limit: continue
		nearest = item
		limit = distance
	# A landed fuse and a downed companion take priority over the surrounding fixtures.
	if world.fuse.visible and not _fuse_toss and world.player.position.distance_to(world.fuse.position) <= 31:
		return {"id": "fuse", "name": "정상 퓨즈 줍기"}
	if world.npc.visible and world.player.position.distance_to(world.npc.position) <= 42:
		if world.npc_hp <= 0: return {"id": "npc", "name": "미카 소생"}
		if nearest.is_empty(): return {"id": "npc", "name": "미카와 대화"}
	return nearest

func _door_error(door: Dictionary) -> String:
	if step == Step.AMBUSH: return "복도의 침식된 선원을 먼저 제압하세요."
	match door.target_room:
		"supply_room":
			if step < Step.FIND_FUSE: return "미카의 방에서 먼저 미카를 만나세요."
		"power_room":
			if step < Step.TO_POWER: return "복도 첫 조우를 마치고 전기실로 가세요." if step == Step.AMBUSH else "비품실에서 정상 퓨즈를 먼저 챙기세요."
		"research_lab_b":
			if step < Step.TO_LAB: return "전력을 복구하고 복도의 경보를 확인하세요."
		"corridor":
			if world.map_id == "research_lab_b" and step >= Step.WAVES: return "격벽 작업이 끝나면 복도로 돌아갈 수 있습니다."
	return ""

func interact(id: String, animate: bool) -> String:
	if (locks_movement() and not allows_interact()) or world.transition_active(): return ""
	var active_room: Node2D = room()
	if active_room.doors.has(id):
		var door: Dictionary = active_room.doors[id]
		var blocked := _door_error(door)
		if not blocked.is_empty(): return blocked
		var destination: Node2D = rooms[door.target_room]
		var spawn := Room.pixel(destination.doors[door.target_door].arrival_px)
		var from := world.map_id
		world._event("fleet_door_open", {"door": id})
		world._animate_travel(func(): world._change_map(door.target_room, spawn),
			func(action): active_room.play_door(id, action),
			func(action): destination.play_door(door.target_door, action),
			active_room.has_animated_door(id), destination.has_animated_door(door.target_door), animate, on_enter.bind(from))
		return ""
	match id:
		"cabinet_fuse", "cabinet_reserve", "personal_cabinet":
			if not active_room.props.has(id) or cabinets.get(id, false): return ""
			cabinets[id] = true
			active_room.play(id, "open")
			if id == "cabinet_fuse": _drop_fuse()
			_updated()
		"crate_side": return "이곳엔 퓨즈가 없다"
		"fuse":
			if not world.fuse.visible or _fuse_toss: return ""
			world.fuse_collected = true
			step = Step.FUSE_HELD
			world.story_event("fuse_return", "fuse_collected")
			world._remember("비품실 왼쪽 캐비닛에서 바닥에 떨어진 정상 퓨즈를 주웠다.")
			_say(Lines.FUSE)
		"main_fuse_breaker":
			if step != Step.REPAIR: return "정상 퓨즈 교체가 끝났습니다."
			if world.npc_hp <= 0: return "미카를 먼저 소생시키세요."
			world.active_action = ""
			world.npc_navigation.reset()
			npc_task = "breaker"
			world.npc_motion.arrived = false
			_updated()
		"power_terminal":
			return "전력이 복구되었습니다." if world.power_restored else "주 퓨즈함의 정상 퓨즈부터 교체하세요."
		"ammo_stock":
			if world.cache_used: return "이미 탄약함을 사용했습니다."
			if world.ammo >= world.max_ammo: return "탄약이 충분합니다."
			world.ammo = mini(world.max_ammo, world.ammo + world.resupply_amount)
			world.cache_used = true
			_updated()
			return "탄약 회수"
		"normal_sector_crate", "supply_cabinet":
			if lab_supply_used: return "이미 봉쇄 보급함을 사용했습니다."
			if world.ammo == world.max_ammo and world.player_hp == world.max_hp and world.supply_packs == world.initial_supply_packs: return "보급이 충분합니다."
			lab_supply_used = true
			var message := world.containment.replenish()
			_updated()
			return message
		"eroded_stop":
			if not allows_interact(): return "세 차례의 선원을 제압하고 미카의 신호를 기다리세요."
			if _near_lever() and _mika_at_lever(): _pull()
	return ""

func _drop_fuse() -> void:
	var landing := world.fuse.position
	world.fuse.position = room().ground("cabinet_fuse") + Vector2(0, -18)
	var sprite := world.fuse.get_node("Sprite2D") as Sprite2D
	_fuse_toss = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_fuse_toss.tween_interval(0.28)
	var arc := landing.lerp(world.fuse.position, 0.5) + Vector2(0, -18)
	_fuse_toss.tween_property(world.fuse, "position", arc, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fuse_toss.parallel().tween_property(sprite, "rotation", PI, 0.18)
	_fuse_toss.tween_property(world.fuse, "position", landing, 0.21).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fuse_toss.parallel().tween_property(sprite, "rotation", TAU, 0.21)
	_fuse_toss.finished.connect(func():
		_fuse_toss = null
		sprite.rotation = 0.0
		world._event("fleet_fuse_landed", {}))

func guidance() -> String:
	match step:
		Step.FIND_MIKA: return "복도 왼쪽 첫 번째 문에서 미카 만나기"
		Step.FIND_FUSE: return "미카 방 오른쪽 비품실에서 정상 퓨즈 찾기"
		Step.FUSE_HELD: return "비품실 아래쪽 문으로 나가 오른쪽 전기실로 이동"
		Step.AMBUSH: return "복도의 침식된 선원 제압"
		Step.TO_POWER: return "복도 오른쪽의 전기실로 이동"
		Step.REPAIR:
			if world.map_id != "power_room": return "복도 오른쪽 전기실의 주 퓨즈함으로 이동"
			return "방 끝의 주 퓨즈함에서 E" if npc_task.is_empty() and _sequence == null and not inserted else "미카의 전력 복구 작업"
		Step.ALARM: return "복도로 나가 경보 확인"
		Step.TO_LAB: return "복도 오른쪽 끝의 연구실 B동으로 이동"
		Step.CORES: return "위쪽 침식 코어의 레버로 이동 · 필요하면 아래쪽에서 보급" if world.map_id == "research_lab_b" else "복도 오른쪽 끝에서 연구실 B동으로 복귀"
		Step.WAVES: return "침식된 선원 제압 · %d / 3차" % wave
		Step.LEVER: return "침식 코어 레버 앞에서 미카의 신호를 기다리기"
		Step.ARMED: return "E로 침식 코어 레버 당기기"
		Step.ENDING: return "연구실 B동 임시 격리"
	return ""

func context() -> Dictionary:
	var fuse_location := "비품실 왼쪽 캐비닛"
	if inserted: fuse_location = "전기실의 주 퓨즈함"
	elif world.fuse_collected: fuse_location = "플레이어 보유"
	elif cabinets.get("cabinet_fuse", false): fuse_location = "비품실 왼쪽 캐비닛 앞 바닥"
	return {"퓨즈 위치": fuse_location, "현재 전투 차수": wave, "레버 조작 가능": allows_interact(),
		"복도 경보": alarm_active(), "미카 역할": "아래쪽 정상 코어 장치 조작" if step >= Step.CORES else "동행과 전력 복구"}
