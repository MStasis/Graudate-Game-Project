extends Node2D
## The imported scene supplies visuals and markers. The world owns the boundary walls.

const ASSETS := "res://assets/fleet_demo/"
const ANIMATIONS := ASSETS + "layout/object_animations.json"

var layout: Dictionary
var bounds: Rect2
var extent: Vector2
var doors := {}
var props := {}
var _warning_sprites: Array[AnimatedSprite2D]
var _animations := {}
var _lever_handles: Array[Polygon2D]

func setup(id: String) -> void:
	layout = SpriteTimeline.manifest(ASSETS + "layout/" + id + ".json")
	bounds = Rect2(pixel(layout.floor_origin_px), pixel(layout.grid) * float(layout.tile_px))
	extent = bounds.end + Vector2(24, 124 if id == "corridor" else 35)
	for door: Dictionary in layout.doors:
		doors[door.id] = door
	$Collision.free()
	y_sort_enabled = true
	for layer in [$Floor, $Walls, $Decals, $Markings]:
		layer.z_index = -2
	$Objects.z_index = 6
	$Foreground.z_index = 7
	var clips := SpriteTimeline.manifest(ANIMATIONS)
	for prop: Dictionary in layout.props:
		var key: String = prop.id
		props[key] = prop
		if prop.has("solid"):
			var object := $Objects.get_node(key)
			object.get_node(key + "_collision").free()
			var footprint := pixel(prop.solid)
			var obstacle := RoundedObstacle.new()
			obstacle.fit_rect(Rect2(Vector2(-footprint.x * 0.5, -footprint.y), footprint))
			object.add_child(obstacle)
		match prop.sprite:
			"sliding_cabinet":
				_add_animation(key, $Objects.get_node(key + "/Sprite"), "sliding_cabinet", clips)
			"stage_door", "warning_light":
				var sprite := _add_animation(key, $Walls.get_node(key), prop.sprite, clips)
				if prop.sprite == "warning_light": _warning_sprites.append(sprite)
			"fuse_breaker_closed":
				_add_animation(key, $Objects.get_node(key + "/Sprite"), "fuse_breaker_door", clips)

static func pixel(pair: Array) -> Vector2:
	return Vector2(float(pair[0]), float(pair[1]))

func ground(id: String) -> Vector2:
	return pixel(props[id].ground)

func approach(id: String) -> Vector2:
	var prop: Dictionary = props[id]
	if prop.has("approach"): return pixel(prop.approach)
	return ground(id) + Vector2(0, 27)

func play(id: String, clip: String, instant := false, end := false) -> void:
	var sprite := _animations.get(id) as AnimatedSprite2D
	if not sprite: return
	sprite.stop()
	sprite.animation = clip
	if instant: sprite.frame = sprite.sprite_frames.get_frame_count(clip) - 1 if end else 0
	else: sprite.play(clip)

func has_animated_door(id: String) -> bool:
	return doors.has(id) and _animations.has(id)

func play_door(id: String, action: String) -> void:
	if action in ["open", "close"]: play(id, action)
	else: play(id, "open", true, action == "opened")

func set_warning(active: bool) -> void:
	for sprite in _warning_sprites:
		if active and not sprite.is_playing(): sprite.play("open")
		elif not active and sprite.is_playing(): sprite.stop()

func set_door_available(id: String, available: bool) -> void:
	var door := $Walls.get_node(id) as Sprite2D
	door.self_modulate = Color.WHITE if available else Color("bd9c94")

func set_terminal_powered(active: bool) -> void:
	$Objects/power_terminal/Sprite.self_modulate = Color(0.66, 1.0, 1.22) if active else Color.WHITE

func set_levers(active: bool) -> void:
	if _lever_handles.is_empty():
		for id in ["normal_stop", "eroded_stop"]:
			var sprite := $Objects.get_node(id + "/Sprite") as Sprite2D
			var handle := Polygon2D.new()
			handle.polygon = PackedVector2Array([Vector2(-4, -2), Vector2(3, -2), Vector2(3, 11), Vector2(10, 11),
				Vector2(10, 16), Vector2(-4, 16)])
			handle.position = Vector2(22, 28)
			handle.color = Color("80e3bb")
			sprite.add_child(handle)
			_lever_handles.append(handle)
	for handle in _lever_handles: handle.visible = active

func _add_animation(id: String, source: Sprite2D, clip_name: String, clips: Dictionary) -> AnimatedSprite2D:
	var clip: Dictionary = clips[clip_name]
	var sheet := load(ASSETS + "art/" + clip_name + "_animation.png") as Texture2D
	var sprite := AnimatedSprite2D.new()
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var opening: Array = clip.get("open_order", range(int(clip.frames)))
	var frame_size := pixel(clip.frame_px)
	var rows: Array = clip.get("state_rows", [""])
	for row in rows.size():
		var suffix := "_" + str(rows[row]) if not str(rows[row]).is_empty() else ""
		_add_clip(frames, "open" + suffix, sheet, frame_size, row, opening, clip.duration_ms, clip.loop)
		if clip.has("close_order"):
			_add_clip(frames, "close" + suffix, sheet, frame_size, row, clip.close_order, clip.duration_ms, false)
	sprite.sprite_frames = frames
	sprite.animation = "open_broken" if rows.size() > 1 else "open"
	sprite.centered = false
	sprite.position = source.position
	source.add_sibling(sprite)
	source.hide()
	_animations[id] = sprite
	return sprite

func _add_clip(frames: SpriteFrames, clip: String, sheet: Texture2D, size: Vector2, row: int, order: Array, duration: Array, loop: bool) -> void:
	frames.add_animation(clip)
	frames.set_animation_speed(clip, 1000.0)
	frames.set_animation_loop(clip, loop)
	for index in order:
		var region := AtlasTexture.new()
		region.atlas = sheet
		region.region = Rect2(Vector2(index, row) * size, size)
		region.filter_clip = true
		frames.add_frame(clip, region, float(duration[index]))
