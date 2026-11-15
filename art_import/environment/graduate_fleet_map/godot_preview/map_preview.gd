extends Node2D

const REACH := 57.0
const DARK := Color(0.05, 0.08, 0.11, 0.94)
const TEAL := Color("#a2cbd3")
const LABELS := {
	"cabinet": "보관함 열기 / 닫기", "craft_table": "총기 제작 작업대",
	"resupply": "보급 캐비닛", "main_screen": "메인 스크린",
	"personal_terminal": "미카의 터치패널", "power_terminal": "전기실 터치패널",
	"facility_console": "연구실 터치패널", "normal_core": "정상 코어",
	"eroded_core": "침식된 코어", "normal_stop": "정상 코어 정지 레버",
	"eroded_stop": "오염된 정지 레버", "supply_crate": "보관 상자",
	"lab_supply": "보급 상자", "breaker_bank": "보조 배전반",
}

var layouts: Dictionary = {}
var clips: Dictionary
var poses: Dictionary
var data: Dictionary
var room: Node2D
var player: CharacterBody2D
var art: Sprite2D
var camera: Camera2D
var title: Label
var objective: Label
var prompt: Label
var notice: Label
var fade: ColorRect
var clock := 0.0
var walk_clock := 0.0
var facing := 0
var notice_left := 0.0
var busy := false
var fuse_owned := false
var power_on := false
var breaker_open := false
var breaker_row := 0
var open_cabinets: Dictionary = {}
var wave := 0
var wave_overlay: Node2D
var alarms: Array[Sprite2D] = []
var ui_font: Font

func _ready() -> void:
	for key in ["mika_quarters", "supply_room", "power_room", "corridor", "research_lab_b"]:
		layouts[key] = read_layout(key)
	poses = read_layout("player_atlas")
	clips = read_layout("object_animations")
	ui_font = load("res://art/FleetMapSans.otf") as Font
	create_hud()
	enter_room("mika_quarters", "")
	if "--verify" in OS.get_cmdline_user_args():
		verify.call_deferred()

func read_layout(key: String) -> Dictionary:
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://layout/%s.json" % key))
	assert(result is Dictionary, key)
	return result

func xy(pair: Array) -> Vector2:
	return Vector2(pair[0], pair[1])

func create_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var top := make_panel(overlay, Control.PRESET_TOP_WIDE)
	top.offset_bottom = 70
	title = make_label(top, Vector2(18, 5), 23, Color.WHITE)
	objective = make_label(top, Vector2(19, 40), 15, TEAL)
	var bottom := make_panel(overlay, Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -61
	prompt = make_label(bottom, Vector2(19, 5), 16, Color.WHITE)
	var controls := make_label(bottom, Vector2(19, 32), 13, TEAL)
	controls.text = "WASD / 방향키 이동    E 상호작용    Tab B동 웨이브 위치    Esc 종료"
	notice = make_label(overlay, Vector2(19, 77), 16, Color("#ffe1a5"))
	notice.add_theme_color_override("font_outline_color", Color("#111a22"))
	notice.add_theme_constant_override("outline_size", 4)
	fade = make_panel(overlay, Control.PRESET_FULL_RECT)
	fade.color = Color.BLACK
	fade.modulate.a = 0.0

func make_panel(parent: Control, preset: int) -> ColorRect:
	var panel := ColorRect.new()
	panel.color = DARK
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	panel.set_anchors_and_offsets_preset(preset)
	return panel

func make_label(parent: Control, pos: Vector2, px: int, color: Color) -> Label:
	var label := Label.new()
	label.position = pos
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", ui_font)
	label.add_theme_font_size_override("font_size", px)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func enter_room(key: String, entrance: String) -> void:
	if is_instance_valid(room):
		remove_child(room)
		room.queue_free()
	data = layouts[key]
	room = (load("res://rooms/%s.tscn" % key) as PackedScene).instantiate() as Node2D
	add_child(room)
	wave_overlay = null
	wave = 0
	alarms.clear()
	var spawn := xy(data["spawn_px"]) if data["spawn_px"] != null else xy(data["floor_origin_px"]) + Vector2(48,48)
	for door: Dictionary in data["doors"]:
		if door["id"] == entrance:
			spawn = xy(door["arrival_px"])
			match door["edge"]:
				"north": facing = 0
				"west": facing = 2
				"east": facing = 1
				"south": facing = 3
			break
	player = CharacterBody2D.new()
	player.name = "Player"
	player.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	player.position = spawn
	room.get_node("Objects").add_child(player)
	var hitbox := CollisionShape2D.new()
	var body := CircleShape2D.new()
	body.radius = 8
	hitbox.shape = body
	player.add_child(hitbox)
	art = Sprite2D.new()
	art.texture = load("res://art/rsc07_final_atlas.png")
	art.centered = false
	art.region_enabled = true
	art.position = -xy(poses["ground_pivot_px"])
	player.add_child(art)
	camera = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	player.add_child(camera)
	camera.make_current()
	walk_clock = 0
	set_pose(false, 0)
	update_camera()
	camera.reset_smoothing()
	for prop: Dictionary in data["props"]:
		if prop.has("light"):
			alarms.append(room.get_node("Walls/"+str(prop["id"])) as Sprite2D)
		elif prop["sprite"] == "sliding_cabinet" and open_cabinets.get(prop_key(prop), false):
			show_frame(prop_sprite(prop), "sliding_cabinet", last_frame("sliding_cabinet"))
		elif prop["id"] == "main_fuse_breaker" and breaker_open:
			show_frame(prop_sprite(prop), "fuse_breaker_door", last_frame("fuse_breaker_door"), breaker_row)
	update_goal()

func update_camera() -> void:
	var origin := xy(data["floor_origin_px"])
	var floor_size := xy(data["grid"]) * float(data["tile_px"])
	var corridor: bool = data["name"] == "corridor"
	var bounds := Rect2(Vector2(0,0), origin + floor_size + Vector2(24, 124 if corridor else 35))
	var viewport := get_viewport_rect().size
	var center := player.position + Vector2(0, -22)
	if corridor:
		center.y = bounds.size.y/2.0
	for axis in [0,1]:
		if bounds.size[axis] <= viewport[axis]:
			center[axis] = bounds.size[axis]/2.0
		else:
			center[axis] = clampf(center[axis], viewport[axis]/2.0, bounds.size[axis]-viewport[axis]/2.0)
	camera.position = center - player.position

func set_pose(walking: bool, delta: float) -> void:
	var clip: Dictionary = poses["animations"]["move" if walking else "idle"]
	var durations: Array = clip["frame_durations_ms_by_direction"][poses["direction_rows"][facing]] if walking else clip["frame_durations_ms"]
	var period := 0.0
	for ms: int in durations:
		period += ms
	walk_clock = fmod(walk_clock + delta*1000.0,period)
	var elapsed := walk_clock
	var frame := 0
	for ms: int in durations:
		if elapsed < ms:
			break
		elapsed -= ms
		frame += 1
	var cell := xy(poses["cell_px"])
	art.region_rect = Rect2(xy(clip["origin_px"])+Vector2(cell.x*frame,cell.y*facing),cell)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) -
		float(Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) -
		float(Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	)
	if busy:
		direction = Vector2.ZERO
	if direction.x != 0:
		facing = 2 if direction.x>0 else 1
	elif direction.y != 0:
		facing = 0 if direction.y>0 else 3
	player.velocity = direction.normalized() * 164.0
	player.move_and_slide()
	set_pose(direction != Vector2.ZERO, delta)
	update_camera()

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if notice_left>0:
		notice_left -= delta
		if notice_left<=0:
			notice.text = ""
	clock += delta
	if power_on and not alarms.is_empty():
		var durations: Array = clips["warning_light"]["duration_ms"]
		var elapsed := fmod(clock*1000.0, 800.0)
		var frame := 0
		for ms: int in durations:
			if elapsed<ms:
				break
			elapsed -= ms
			frame += 1
		for alarm in alarms:
			show_frame(alarm,"warning_light",frame)
	var candidate := closest_interaction()
	prompt.text = "[E]  "+interaction_label(candidate) if not busy and not candidate.is_empty() else ""

func prop_key(prop: Dictionary) -> String:
	return str(data["name"])+"/"+str(prop["id"])

func prop_sprite(prop: Dictionary) -> Sprite2D:
	return room.get_node("Objects/"+str(prop["id"])+"/Sprite") as Sprite2D

func last_frame(clip: String) -> int:
	return int(clips[clip]["frames"])-1

func show_frame(sprite: Sprite2D, clip: String, frame: int, row := 0) -> void:
	var path := "res://art/%s_animation.png" % clip
	if sprite.texture == null or sprite.texture.resource_path != path:
		sprite.texture = load(path)
	var cell := xy(clips[clip]["frame_px"])
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2(cell.x*frame,cell.y*row),cell)

func animate(sprite: Sprite2D, clip: String, opening: bool, row := 0) -> void:
	var count := int(clips[clip]["frames"])
	var durations: Array = clips[clip]["duration_ms"]
	for i in count:
		var frame := i if opening else count-1-i
		show_frame(sprite,clip,frame,row)
		await get_tree().create_timer(float(durations[frame])/1000.0).timeout

func restore(sprite: Sprite2D, key: String) -> void:
	sprite.texture = load("res://art/%s.png" % key)
	sprite.region_enabled = false

func closest_interaction() -> Dictionary:
	var best: Dictionary = {}
	var distance := REACH
	for door: Dictionary in data["doors"]:
		var measure := player.position.distance_to(xy(door["point_px"]))
		if measure<distance:
			distance = measure
			best = door
	for prop: Dictionary in data["props"]:
		if not prop.has("interaction"):
			continue
		var where := xy(prop["approach"]) if prop.has("approach") else xy(prop["ground"])+Vector2(0,16)
		var measure := player.position.distance_to(where)
		if measure<distance:
			distance = measure
			best = prop
	return best

func interaction_label(item: Dictionary) -> String:
	if item.has("target_room"):
		return "%s 이동" % layouts[item["target_room"]]["title"]
	match item["interaction"]:
		"fuse_cabinet":
			if not open_cabinets.get(prop_key(item),false):
				return "퓨즈 보관함 열기"
			return "정상 퓨즈 챙기기" if not power_on and not fuse_owned else "보관함 닫기"
		"replace_fuse":
			if not breaker_open:
				return "주 배전함 열기"
			return ["고장 퓨즈 빼기","정상 퓨즈 끼우기","배전함 닫기"][breaker_row]
	return LABELS.get(item["interaction"],"장비 확인")

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		get_tree().quit()
	elif event.physical_keycode == KEY_E and not busy:
		var target := closest_interaction()
		if not target.is_empty():
			interact(target)
	elif event.keycode == KEY_TAB and data["name"] == "research_lab_b" and not busy:
		show_wave(wave%3+1)

func interact(item: Dictionary) -> void:
	if item.has("target_room"):
		if item["target_room"] == "research_lab_b" and not power_on:
			say("격벽에 전력이 없습니다. 전기실에서 퓨즈를 교체하세요.")
			return
		await travel(item)
		return
	match item["interaction"]:
		"fuse_cabinet","cabinet":
			await use_cabinet(item)
		"replace_fuse":
			await use_breaker(item)
		"eroded_stop":
			show_wave(1 if wave==0 else wave)
		"main_screen","facility_console":
			say("연구실 B동 격리 구역 · 1차부터 3차까지 순차 배치")
		_:
			say(interaction_label(item))

func use_cabinet(prop: Dictionary) -> void:
	var key := prop_key(prop)
	var opened: bool = open_cabinets.get(key,false)
	if opened and prop["interaction"]=="fuse_cabinet" and not power_on and not fuse_owned:
		fuse_owned = true
		say("정상 퓨즈를 챙겼습니다.")
		update_goal()
		return
	busy = true
	var sprite := prop_sprite(prop)
	await animate(sprite,"sliding_cabinet",not opened)
	if opened:
		restore(sprite,"sliding_cabinet")
	open_cabinets[key] = not opened
	busy = false

func use_breaker(prop: Dictionary) -> void:
	var sprite := prop_sprite(prop)
	if not breaker_open:
		busy = true
		await animate(sprite,"fuse_breaker_door",true,breaker_row)
		breaker_open = true
		busy = false
	elif breaker_row == 0:
		breaker_row = 1
		show_frame(sprite,"fuse_breaker_door",last_frame("fuse_breaker_door"),breaker_row)
		say("고장 퓨즈를 뺐습니다.")
	elif breaker_row == 1:
		if not fuse_owned:
			say("비품실에서 정상 퓨즈를 가져오세요.")
			return
		fuse_owned = false
		power_on = true
		breaker_row = 2
		show_frame(sprite,"fuse_breaker_door",last_frame("fuse_breaker_door"),breaker_row)
		say("전력을 복구했습니다. 복도 오른쪽 끝으로 이동하세요.")
		update_goal()
	else:
		busy = true
		await animate(sprite,"fuse_breaker_door",false,breaker_row)
		restore(sprite,"fuse_breaker_closed")
		breaker_open = false
		busy = false

func fade_to(value: float) -> void:
	var tween := create_tween()
	tween.tween_property(fade,"modulate:a",value,0.18)
	await tween.finished

func travel(door: Dictionary) -> void:
	busy = true
	if door["edge"]=="north":
		await animate(room.get_node("Walls/"+str(door["id"])) as Sprite2D,"stage_door",true)
	await fade_to(1.0)
	enter_room(door["target_room"],door["target_door"])
	var incoming: Sprite2D = null
	for entry: Dictionary in data["doors"]:
		if entry["id"]==door["target_door"] and entry["edge"]=="north":
			incoming = room.get_node("Walls/"+str(entry["id"])) as Sprite2D
			show_frame(incoming,"stage_door",last_frame("stage_door"))
			break
	await fade_to(0.0)
	if incoming != null:
		await animate(incoming,"stage_door",false)
		restore(incoming,"stage_door")
	busy = false

func show_wave(number: int) -> void:
	wave = number
	if is_instance_valid(wave_overlay):
		room.remove_child(wave_overlay)
		wave_overlay.queue_free()
	wave_overlay = Node2D.new()
	wave_overlay.z_index = 2
	room.add_child(wave_overlay)
	var spots := room.get_node("Wave_%d" % number)
	for anchor: Marker2D in spots.get_children():
		var mark := Polygon2D.new()
		mark.position = anchor.position
		mark.polygon = PackedVector2Array([Vector2(0,-7),Vector2(11,0),Vector2(0,7),Vector2(-11,0)])
		mark.color = Color("#c785d4")
		wave_overlay.add_child(mark)
	say("웨이브 %d / 3 · 스폰 지점 %d곳" % [wave,spots.get_child_count()])

func update_goal() -> void:
	title.text = data["title"]
	if not power_on:
		objective.text = "전기실에서 퓨즈를 교체하세요." if fuse_owned else "비품실 캐비닛에서 정상 퓨즈를 확보하세요."
	elif data["name"]=="research_lab_b":
		objective.text = "Tab 키로 1~3차 웨이브 스폰 지점을 확인하세요."
	else:
		objective.text = "전력 복구 완료 · 통창 복도 오른쪽 끝의 연구실 B동으로 이동하세요."

func say(message: String) -> void:
	notice.text = message
	notice_left = 2.6

func verify_at(item: Dictionary, position_px: Array) -> void:
	player.position = xy(position_px)
	assert(closest_interaction()["id"] == item["id"], item["id"])
	await interact(item)

func verify() -> void:
	var door: Dictionary = data["doors"][0]
	await verify_at(door, door["point_px"])
	assert(data["name"]=="supply_room")
	var cabinet: Dictionary = data["props"][0]
	await verify_at(cabinet, cabinet["approach"])
	assert(open_cabinets["supply_room/cabinet_fuse"])
	await verify_at(cabinet, cabinet["approach"])
	assert(fuse_owned)
	door = data["doors"][1]
	await verify_at(door, door["point_px"])
	assert(data["name"]=="corridor" and fade.modulate.a==0.0)
	door = data["doors"][3]
	await verify_at(door, door["point_px"])
	assert(data["name"]=="corridor" and not power_on)
	door = data["doors"][2]
	await verify_at(door, door["point_px"])
	assert(data["name"]=="power_room")
	var breaker: Dictionary = data["props"][0]
	for i in 3:
		await verify_at(breaker, breaker["approach"])
	assert(power_on and breaker_open and not fuse_owned and breaker_row==2)
	await verify_at(breaker, breaker["approach"])
	assert(not breaker_open)
	door = data["doors"][0]
	await verify_at(door, door["point_px"])
	door = data["doors"][3]
	await verify_at(door, door["point_px"])
	assert(data["name"]=="research_lab_b")
	for i in range(1,4):
		show_wave(i)
		assert(wave_overlay.get_child_count()==i+2)
	await get_tree().physics_frame
	assert(not player.test_move(player.transform, Vector2(-6,0)))
	assert(player.test_move(player.transform, Vector2(-60,0)))
	print("MAP WALKTHROUGH VERIFIED: 5 rooms, exit gate, cabinet, fuse replacement, 3 wave marker sets and collision")
	get_tree().quit()
