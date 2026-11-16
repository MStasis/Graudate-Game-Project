extends Node2D
## Story, room props and timed cues for the five-room demo. Combat and movement run in DemoWorld.

const Room := preload("res://scripts/fleet_demo_room.gd")
const Lines := preload("res://scripts/fleet_demo_lines.gd")
const Crew := preload("res://scenes/RiftCrew.tscn")
const RiftTurret := preload("res://scenes/RiftTurret.tscn")
const Sentry := preload("res://scripts/rift_turret.gd")
const OBJECTIVE_ARROW := preload("res://assets/fleet_demo/art/door_objective_arrow.png")
const BROKEN_FUSE := preload("res://resources/FuseBrokenTexture.tres")
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
const BREAKER_FUSE_SOCKET := Vector2(-2, -28)
const WAVE_PAUSE := 1.25
const INTERACT_RADIUS := 49.0
const HANDOFF_RADIUS := 72.0
# Clear of both side banks, and offset from the player's interaction point.
const REPAIR_POSITION := Vector2(173, 203)
const HANDOFF_POSITION := Vector2(135, 267)
const AMBUSH_HINT := "좌클릭을 눌러 적을 공격하세요"
const WALK_HINT := "WASD로 이동하세요"
const SENTRY_SPAWN := "Wave2_Spawn_4"
const CABINETS := ["cabinet_fuse", "cabinet_reserve", "personal_cabinet"]
const PROPS := {
	"mika_quarters": {"personal_cabinet": "개인 캐비닛"},
	"supply_room": {"cabinet_fuse": "왼쪽 캐비닛", "cabinet_reserve": "오른쪽 캐비닛", "crate_side": "상자 조사", "ammo_stock": "보급 탄약함"},
	"power_room": {"main_fuse_breaker": "주 퓨즈함", "power_terminal": "전력 단말"},
	"research_lab_b": {"eroded_stop": "침식 코어 레버", "normal_sector_crate": "봉쇄 보급함", "supply_cabinet": "봉쇄 보급함", "lab_ammo_stock": "탄약함"},
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
var lab_ammo_used := false
var fuse_handed := false
var wave := 0
var wave_wait := -1.0
var camera_weight := 0.0
var camera_point := Vector2.ZERO
var fixed_aim := false
var npc_task := ""
var voice_active := false
var hint := ""
var opening_pending := false
var _sequence: Tween
var _fuse_toss: Tween
var _dialogue: Array
var _after_dialogue: Callable
var _enemies_root: Node2D
var _door_arrow := Sprite2D.new()
var _arrow_time := 0.0

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
	_door_arrow.name = "ObjectiveDoorArrow"
	_door_arrow.texture = OBJECTIVE_ARROW
	_door_arrow.hframes = 8
	_door_arrow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_door_arrow.scale = Vector2.ONE * 1.5
	_door_arrow.z_index = 22
	_door_arrow.hide()
	add_child(_door_arrow)
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
	var scene := RiftTurret if id == SENTRY_SPAWN else Crew
	var enemy := scene.instantiate() as MissionDrone
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
	lab_ammo_used = false
	fuse_handed = false
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
	voice_active = false
	_door_arrow.hide()
	_arrow_time = 0.0
	_end_repair_walk()
	npc_task = ""
	fixed_aim = false
	camera_weight = 0.0
	opening_pending = false
	fuse_handed = inserted
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
	if inserted: rooms.power_room.play("main_fuse_breaker", "close_working", true, true)
	rooms.supply_room.set_ammo_crate_open("ammo_stock", world.cache_used)
	rooms.research_lab_b.set_ammo_crate_open("lab_ammo_stock", lab_ammo_used)
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
	return opening_pending or voice_active or _sequence != null or step in [Step.ARMED, Step.ENDING] or not npc_task.is_empty()

func allows_interact() -> bool:
	return step == Step.ARMED and not voice_active and _sequence == null

func can_save() -> bool:
	return _fuse_toss == null and (not locks_movement() or allows_interact())

func configuration() -> Dictionary:
	var markers := {}
	for enemy in unit_pool:
		var p: Vector2 = enemy.get_meta("spawn")
		markers[str(enemy.name)] = [p.x, p.y]
	return {"layout": 1, "crew_spawns": markers, "wave_pause": WAVE_PAUSE, "rift_sentry": SENTRY_SPAWN,
		"sentry_attack": {"bolts_per_laser": Sentry.BOLTS_PER_LASER, "laser_charge": Sentry.LASER_CHARGE, "laser_damage": Sentry.LASER_DAMAGE}}

func snapshot() -> Dictionary:
	var enemies := {}
	for enemy in unit_pool:
		if enemy.hp > 0:
			var state := {"hp": enemy.hp, "position": [enemy.position.x, enemy.position.y], "attack_wait": enemy.attack_wait}
			if enemy is Sentry: state["bolts_fired"] = enemy.bolts_fired
			enemies[str(enemy.name)] = state
	return {"step": step, "opened": cabinets.keys(), "inserted": inserted, "core_seen": core_seen,
		"lab_supply_used": lab_supply_used, "lab_ammo_used": lab_ammo_used, "wave": wave, "wave_wait": wave_wait, "enemies": enemies}

func restore(state: Dictionary) -> void:
	clear_cues()
	_reset_enemies()
	step = int(state.step) as Step
	cabinets.clear()
	for id in state.opened: cabinets[id] = true
	inserted = state.inserted
	fuse_handed = inserted
	core_seen = state.core_seen
	lab_supply_used = state.lab_supply_used
	lab_ammo_used = state.get("lab_ammo_used", false)
	wave = int(state.wave)
	wave_wait = float(state.wave_wait)
	hint = WALK_HINT if step == Step.FIND_MIKA else AMBUSH_HINT if step == Step.AMBUSH else ""
	for enemy in unit_pool:
		if not state.enemies.has(str(enemy.name)): continue
		var data: Dictionary = state.enemies[str(enemy.name)]
		enemy.hp = int(data.hp)
		enemy.position = Room.pixel(data.position)
		enemy.attack_wait = float(data.attack_wait)
		if enemy is Sentry: enemy.bolts_fired = int(data.get("bolts_fired", 0))
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
	if not data.get("lab_ammo_used", false) is bool: return false
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
		if enemy is Sentry and not store.whole(item.get("bolts_fired", 0), 0, Sentry.BOLTS_PER_LASER): return false
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
		enemy.sync_presence(in_room, combat_area() and not voice_active and not world.defeated and not world.finished and not world.transition_active())
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
	if npc_task == "clear_terminal" and not world.player.scripted_target.is_finite():
		npc_task = "breaker"
		world.npc_navigation.reset()
		world.npc_motion.arrived = false
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

func _say(lines: Array, after := Callable()) -> void:
	_dialogue = lines.duplicate()
	_after_dialogue = after
	voice_active = true
	_next_line()
	_updated()

func advance_dialogue() -> void:
	if voice_active: _next_line()

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
	if _can_handoff(): return HANDOFF_POSITION
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
		var slot: Vector2 = power.ground("main_fuse_breaker") + BREAKER_FUSE_SOCKET
		_show_fuse_motion(slot, slot + Vector2(-36, 69), BROKEN_FUSE)
		world._event("fleet_fuse_removed", {}))
	cue.tween_interval(0.66)
	cue.tween_callback(func():
		var slot: Vector2 = power.ground("main_fuse_breaker") + BREAKER_FUSE_SOCKET
		_show_fuse_motion(world.npc.position + Vector2(-8, -38), slot, world.fuse.object_texture))
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
		fixed_aim = false
		npc_task = "power"
		world.npc_motion.arrived = false)

func _show_fuse_motion(from: Vector2, to: Vector2, texture: Texture2D) -> void:
	var part := Sprite2D.new()
	part.texture = texture
	part.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	part.position = from
	part.z_index = 10
	room().add_child(part)
	var motion := part.create_tween()
	motion.tween_property(part, "position", to, 0.28).set_trans(Tween.TRANS_QUAD)
	motion.parallel().tween_property(part, "rotation", PI, 0.28)
	motion.tween_property(part, "modulate:a", 0.0, 0.14)
	motion.finished.connect(part.queue_free)

func _restore_power() -> void:
	_end_repair_walk()
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
	cue.finished.connect(func():
		_sequence = null
		fixed_aim = false
		_say(Lines.BREAKER_FIXED, _start_alarm))

func _end_repair_walk() -> void:
	world.player.scripted_target = Vector2.INF
	world.npc.remove_collision_exception_with(world.player)

func _start_alarm() -> void:
	var cue := _new_sequence()
	step = Step.ALARM
	world.story_event("anomaly_alarm", "anomaly_alarm")
	world._event("anomaly_alarm", {})
	_updated()

	cue.tween_interval(0.20)
	cue.tween_callback(func():
		_face_each_other()
		showing_reaction.emit(true))

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
		enemy.face_spawn(SpriteTimeline.cardinal(enemy.position.direction_to(world.player.position)))
		count += 1
	world._event("fleet_wave_started", {"wave": wave, "count": count})
	world.epoch += 1
	if number == 1:
		_say(Lines.WAVE_START)
	else:
		if number == 2: world.notice.emit("침식 센트리 출현 · 붉은 사선을 Space로 회피하세요.")
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
			world._remember("연구실 B동에서 침식된 선원과 센트리를 모두 제압했다.")
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
		world._event("fleet_pull_signal", {}))

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
		return _prompt("eroded_stop", "침식 코어 레버 당기기", room().ground("eroded_stop")) if _near_lever() else {}
	var mika_distance := world.player.position.distance_to(world.npc.position) if world.npc.visible else INF
	var near_mika := mika_distance <= 54
	if near_mika and world.npc_hp <= 0: return _prompt("npc", "미카 소생", world.npc.position + Vector2(0, -42))
	if mika_distance <= HANDOFF_RADIUS and _can_handoff(): return _prompt("give_fuse", "미카에게 퓨즈 건네기", world.npc.position + Vector2(0, -42))
	if world.fuse.visible and not _fuse_toss and world.player.position.distance_to(world.fuse.position) <= 31:
		return _prompt("fuse", "정상 퓨즈 줍기", world.fuse.position)
	var nearest := {}
	var limit := INTERACT_RADIUS
	for item in landmarks():
		if item.id == "fuse": continue
		var distance := world.player.position.distance_to(Room.pixel(item.position))
		if distance > limit: continue
		if item.kind == "door":
			if not item.active: continue
			var door_art := room().get_node("Walls/" + item.id) as Sprite2D
			var bounds := door_art.get_rect()
			var center := door_art.position + bounds.get_center()
			var label := "복도로 나가기" if item.destination == "corridor" else str(item.name) + " 들어가기"
			var door_prompt := _prompt(item.id, label, center)
			if distance <= 32.0: return door_prompt
			nearest = door_prompt
		else:
			var action := _prop_prompt(item.id, item.name)
			if action.is_empty(): continue
			nearest = _prompt(item.id, action, room().ground(item.id) + Vector2(0, -20))
		limit = distance
	if nearest.is_empty() and near_mika and not world.is_combat_area():
		return _prompt("npc", "미카와 대화", world.npc.position + Vector2(0, -42))
	return nearest

func _prompt(id: String, label: String, anchor: Vector2) -> Dictionary:
	return {"id": id, "name": label, "anchor": anchor}

func _prop_prompt(id: String, label: String) -> String:
	match id:
		"main_fuse_breaker", "power_terminal", "eroded_stop": return ""
		"ammo_stock": return "" if world.cache_used else label + " 열기"
		"lab_ammo_stock": return "" if lab_ammo_used else label + " 열기"
		"normal_sector_crate", "supply_cabinet": return "" if lab_supply_used else label + " 열기"
	if id in CABINETS: return "" if cabinets.get(id, false) else label + " 열기"
	return label

func _can_handoff() -> bool:
	return world.map_id == "power_room" and step == Step.REPAIR and world.fuse_collected and not fuse_handed and world.npc_hp > 0

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
		"give_fuse":
			if not _can_handoff() or world.player.position.distance_to(world.npc.position) > HANDOFF_RADIUS: return ""
			fuse_handed = true
			fixed_aim = false
			_show_fuse_motion(world.player.position + Vector2(0, -38), world.npc.position + Vector2(0, -38), world.fuse.object_texture)
			world._event("fleet_fuse_handed", {})
			world.active_action = ""
			npc_task = "clear_terminal"
			world.npc.add_collision_exception_with(world.player)
			world.player.walk_to(active_room.get_node("PlayerRepairStand").position)
			_updated()
		"power_terminal":
			return "전력이 복구되었습니다." if world.power_restored else "주 퓨즈함의 정상 퓨즈부터 교체하세요."
		"ammo_stock", "lab_ammo_stock":
			if not active_room.props.has(id): return ""
			if id == "ammo_stock":
				if world.cache_used: return ""
				world.cache_used = true
			else:
				if lab_ammo_used: return ""
				lab_ammo_used = true
			active_room.set_ammo_crate_open(id, true, false)
			var amount := world.add_magazine_supply()
			world._event("fleet_ammo_collected", {"crate": id, "magazines": amount})
			_updated()
			return "예비 탄창 +%d" % amount
		"normal_sector_crate", "supply_cabinet":
			if not active_room.props.has(id) or lab_supply_used: return ""
			lab_supply_used = true
			world.add_magazine_supply()
			world.medkits = world.initial_medkits
			world.supply_packs = world.initial_supply_packs
			world.cover_charges = world.initial_cover_charges
			_updated()
			return "봉쇄 보급함 회수 · 예비 탄창 +%d" % world.MAGAZINES_PER_SUPPLY
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

func objective_door() -> String:
	var destination := ""
	match step:
		Step.FIND_MIKA: destination = "mika_quarters"
		Step.FIND_FUSE: destination = "supply_room"
		Step.FUSE_HELD:
			destination = "corridor" if world.map_id == "supply_room" else "supply_room"
		Step.TO_POWER, Step.REPAIR: destination = "power_room"
		Step.ALARM: destination = "corridor"
		Step.TO_LAB, Step.CORES: destination = "research_lab_b"
	if destination.is_empty() or destination == world.map_id: return ""
	var via_corridor := ""
	for door: Dictionary in room().doors.values():
		if not _door_error(door).is_empty(): continue
		if door.target_room == destination: return door.id
		if door.target_room == "corridor": via_corridor = door.id
	return via_corridor

func update_objective_arrow(delta: float, visible_for_player: bool) -> Rect2:
	_door_arrow.hide()
	if not visible_for_player or locks_movement() or world.transition_active() or world.defeated or world.finished: return Rect2()
	var door := objective_door()
	if door.is_empty(): return Rect2()
	var art := room().get_node("Walls/" + door) as Sprite2D
	var bounds := art.get_rect()
	_arrow_time = fposmod(_arrow_time + delta, 0.96)
	_door_arrow.frame = int(_arrow_time / 0.12)
	_door_arrow.position = art.position + Vector2(bounds.get_center().x, bounds.position.y - 5.0)
	_door_arrow.position.y -= 3.0 * sin(_arrow_time / 0.96 * TAU)
	_door_arrow.show()
	return _door_arrow.get_global_transform_with_canvas() * _door_arrow.get_rect()

func guidance(compact := false) -> String:
	match step:
		Step.FIND_MIKA: return "왼쪽 첫 문에서 미카 만나기" if compact else "복도 왼쪽 첫 번째 문에서 미카 만나기"
		Step.FIND_FUSE: return "비품실에서 정상 퓨즈 찾기" if compact else "미카 방 오른쪽 비품실에서 정상 퓨즈 찾기"
		Step.FUSE_HELD: return "퓨즈를 들고 전기실로 이동" if compact else "비품실 아래쪽 문으로 나가 오른쪽 전기실로 이동"
		Step.AMBUSH: return "복도의 침식된 선원 제압"
		Step.TO_POWER: return "복도 오른쪽의 전기실로 이동"
		Step.REPAIR:
			if world.map_id != "power_room": return "복도 오른쪽 전기실로 이동"
			return "미카에게 정상 퓨즈 건네기" if not fuse_handed else "미카의 전력 복구 작업"
		Step.ALARM: return "복도로 나가 경보 확인"
		Step.TO_LAB: return "복도 오른쪽 끝의 연구실 B동으로 이동"
		Step.CORES:
			if compact: return "위쪽 침식 코어 조사" if world.map_id == "research_lab_b" else "연구실 B동으로 복귀"
			return "위쪽 침식 코어의 레버로 이동 · 필요하면 아래쪽에서 보급" if world.map_id == "research_lab_b" else "복도 오른쪽 끝에서 연구실 B동으로 복귀"
		Step.WAVES: return "연구실 B동의 적 제압 · %d / 3차" % wave
		Step.LEVER: return "레버 앞에서 미카 신호 대기" if compact else "침식 코어 레버 앞에서 미카의 신호를 기다리기"
		Step.ARMED: return "E로 침식 코어 레버 당기기"
		Step.ENDING: return "연구실 B동 임시 격리"
	return ""

func context() -> Dictionary:
	var fuse_location := "미확인"
	if step >= Step.FIND_FUSE:
		fuse_location = "비품실에서 찾아야 함. 정확한 위치 미확인"
	if inserted: fuse_location = "전기실의 주 퓨즈함"
	elif fuse_handed: fuse_location = "미카가 교체 중"
	elif world.fuse_collected: fuse_location = "플레이어 보유"
	elif cabinets.get("cabinet_fuse", false):
		fuse_location = "비품실 왼쪽 캐비닛 앞 바닥" if _fuse_toss == null else "비품실 왼쪽 캐비닛에서 떨어지는 중"
	# The line is already known once shown, even during the locked conversation.
	var comms_reported := step >= Step.FIND_FUSE or (
		world.map_id == "mika_quarters" and voice_active and Lines.QUARTERS[1] not in _dialogue)
	var plan_known := "containment_briefed" in world.story.events
	var lever_ready := allows_interact() and not world.finished and not world.defeated and _near_lever() and _mika_at_lever()
	var goal := world.current_guidance()
	if step == Step.FIND_FUSE:
		if "앞 바닥" in fuse_location: goal = "비품실 왼쪽 캐비닛 앞 바닥에 떨어진 정상 퓨즈 줍기"
		elif world.map_id == "supply_room": goal = "현재 비품실에서 정상 퓨즈 찾기"
		elif world.map_id == "corridor": goal = "통창 복도의 가운데 문으로 비품실에 들어가 정상 퓨즈 찾기"
	elif step == Step.FUSE_HELD and world.map_id != "supply_room":
		goal = "비품실로 돌아가 아래쪽 문으로 나오기"
	elif step == Step.WAVES and wave_wait >= 0.0:
		goal = "현재 무리 제압 완료. 다음 공격에 대비"
	if world.defeated or world.npc_hp <= 0: goal = world.current_guidance()
	return {
		"진행 단계": Step.keys()[step],
		"현재 목표": goal,
		"정전 확인": "blackout" in world.story.events,
		"통신 장애 확인": comms_reported,
		"퓨즈 위치": fuse_location,
		"퓨즈 장착": inserted,
		"오른쪽 캐비닛 확인": cabinets.get("cabinet_reserve", false),
		"복도 적 발견": step >= Step.AMBUSH,
		"복도 적 제압": step >= Step.TO_POWER,
		"경보 발생 확인": "anomaly_alarm" in world.story.events,
		"복도 경보": alarm_active(),
		"B동 진입": world.story.tutorial_completed,
		"격벽 계획 공유": plan_known,
		"침식 코어 근접 확인": core_seen,
		"현재 전투 차수": wave,
		"웨이브 사이 대기": step == Step.WAVES and wave_wait >= 0.0,
		"B동 전투 종료": step >= Step.LEVER,
		"레버 신호 완료": step >= Step.ARMED,
		"레버 조작 가능": lever_ready,
		"격벽 설치": step == Step.ENDING,
		"미카 역할": "B동 아래쪽 정상 코어 장치 담당" if plan_known else "함선 정비사",
	}
