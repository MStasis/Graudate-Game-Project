extends Node2D
## Visuals for the deployable healer. The world owns health and the support lifetime.

const ART := "res://assets/fleet_demo/art/mika_healer/"
const MANIFEST := "res://assets/fleet_demo/layout/mika_healer_animations.json"
const BEAM := preload(ART + "mika_healer_beam_tile.png")
const RANGE_ASPECT := 75.0 / 104.0
const HP_PER_SECOND := 5.0
const PATIENT_BODY := Vector2(0, -35)

var _device := AnimatedSprite2D.new()
var _range := AnimatedSprite2D.new()
var _sparks := AnimatedSprite2D.new()
var _ready_at := 0.0
var _elapsed := 0.0
var _emitter := Vector2.ZERO
var _beam_cell := Vector2.ZERO
var _beam_axis := 0.0
var _range_radius := 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 8
	var art := SpriteTimeline.manifest(MANIFEST)
	for clip in ["deploy", "idle", "heal"]:
		_add_clip(_device, clip, art.sprites)
	_add_clip(_range, "range", art.sprites)
	_add_clip(_sparks, "ally_sparks", art.sprites)
	_range.z_index = -9
	_range_radius = float(art.range.ground_radius_xy_px[0])
	_emitter = SpriteTimeline.pixel(art.beam.emit_from_px_on_device_cell) - SpriteTimeline.pixel(art.device.ground_pivot_px)
	_beam_cell = SpriteTimeline.pixel(art.sprites["mika_healer_beam_tile.png"].cell_px)
	_beam_axis = float(art.beam.axis_y_px)
	for event: Dictionary in art.device.events:
		if event.event == "healer_ready": _ready_at = float(event.time_ms) * 0.001
	stop()

func _add_clip(sprite: AnimatedSprite2D, clip: String, specs: Dictionary) -> void:
	var filename := "mika_healer_" + clip + ".png"
	var spec: Dictionary = specs[filename]
	if not sprite.get_parent():
		sprite.sprite_frames = SpriteFrames.new()
		sprite.centered = false
		add_child(sprite)
	var frames := sprite.sprite_frames
	frames.add_animation(clip)
	frames.set_animation_speed(clip, 1000.0)
	frames.set_animation_loop(clip, spec.loop)
	var sheet := load(ART + filename) as Texture2D
	var cell := SpriteTimeline.pixel(spec.cell_px)
	for index in int(spec.frames):
		var frame := AtlasTexture.new()
		frame.atlas = sheet
		frame.region = Rect2(Vector2(index * cell.x, 0), cell)
		frame.filter_clip = true
		frames.add_frame(clip, frame, float(spec.duration_ms[index]))
	sprite.offset = -SpriteTimeline.pixel(spec.pivot_px)

func begin(ground: Vector2, radius: float, elapsed := 0.0) -> void:
	position = ground
	_elapsed = maxf(0.0, elapsed)
	_range.scale = Vector2.ONE * radius / _range_radius
	_range.hide()
	_range.stop()
	_sparks.hide()
	_sparks.stop()
	_device.stop()
	_device.play("deploy")
	show()

func stop() -> void:
	if not visible: return
	hide()
	_device.stop()
	_range.stop()
	_sparks.stop()

func tick(delta: float) -> float:
	var previous := _elapsed
	_elapsed += delta
	if _elapsed < _ready_at: return 0.0
	if not _range.visible:
		_range.show()
		_range.play("range")
	return _elapsed - maxf(previous, _ready_at)

func set_patient(patient: Vector2) -> void:
	if not _range.visible: return
	var treating := patient.is_finite()
	var clip := "heal" if treating else "idle"
	if _device.animation != clip: _device.play(clip)
	if treating:
		_sparks.position = patient - position + PATIENT_BODY
		if not _sparks.visible: _sparks.play("ally_sparks")
	else:
		_sparks.stop()
	_sparks.visible = treating
	queue_redraw()

func _process(_delta: float) -> void:
	if visible and _sparks.visible: queue_redraw()

func _draw() -> void:
	if not _sparks.visible: return
	var offset := _sparks.position - _emitter
	draw_set_transform(_emitter, offset.angle())
	var length := offset.length()
	for tile in ceili(length / _beam_cell.x):
		var x := tile * _beam_cell.x
		var size := Vector2(minf(_beam_cell.x, length - x), _beam_cell.y)
		var source := Rect2(Vector2(_sparks.frame * _beam_cell.x, 0), size)
		draw_texture_rect_region(BEAM, Rect2(Vector2(x, -_beam_axis), size), source)
