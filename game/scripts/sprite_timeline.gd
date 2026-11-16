@tool
class_name SpriteTimeline
extends Sprite2D

signal event_reached(event: Dictionary)
signal clip_finished(clip: String)

@export_file("*.json") var metadata_path: String
@export var atlas: Texture2D
@export var initial_clip := "idle"

static var manifests: Dictionary
static var atlas_images: Dictionary
var data: Dictionary
var clip := ""
var facing := "down"
var frame_index := 0
var elapsed_ms := 0.0
var playing := false
var _playback_id := 0
var _reversed := false
var _repeat := false

static func manifest(path: String) -> Dictionary:
 if not manifests.has(path):
  manifests[path] = JSON.parse_string(FileAccess.get_file_as_string(path))
 return manifests[path]

static func pixel(pair: Array) -> Vector2:
 return Vector2(pair[0], pair[1])

static func cardinal(direction: Vector2, fallback := "down") -> String:
 if direction.is_zero_approx(): return fallback
 if absf(direction.x) > absf(direction.y): return "right" if direction.x > 0 else "left"
 return "down" if direction.y > 0 else "up"

func _ready() -> void:
 if metadata_path.is_empty(): return
 data = manifest(metadata_path)
 texture = atlas
 texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
 centered = false
 region_enabled = true
 region_filter_clip_enabled = true
 offset = -pixel(data.ground_pivot_px)
 show_frame(initial_clip, facing, 0)

func durations(animation: String, direction: String) -> Array:
 var motion: Dictionary = data.animations[animation]
 if motion.has("frame_durations_ms_by_direction"): return motion.frame_durations_ms_by_direction[direction]
 return motion.frame_durations_ms

func muzzle(point: Array) -> Vector2:
 return to_global(offset + pixel(point))

func contains_ink(point: Vector2) -> bool:
 var inside := to_local(point) - offset
 if not Rect2(Vector2.ZERO, region_rect.size).has_point(inside): return false
 if not atlas_images.has(atlas.resource_path): atlas_images[atlas.resource_path] = atlas.get_image()
 var pixels: Image = atlas_images[atlas.resource_path]
 return pixels.get_pixelv(Vector2i(region_rect.position + inside)).a > 0.1

func show_frame(animation: String, direction: String, index: int) -> void:
 var motion: Dictionary = data.animations[animation]
 var cell := pixel(data.cell_px)
 var origin := pixel(motion.get("origin_cell", [motion.get("start_column", 0), motion.get("first_row", 0)]))
 facing = direction
 frame_index = index
 region_rect = Rect2((origin + Vector2(index, data.direction_rows.find(direction))) * cell, cell)

func hold(animation: String, direction: String, index := 0) -> void:
 _playback_id += 1
 playing = false
 clip = animation
 show_frame(animation, direction, index)

func start(animation: String, direction: String, reversed := false, once := false) -> void:
 _playback_id += 1
 clip = animation
 elapsed_ms = 0.0
 playing = true
 _reversed = reversed
 var motion: Dictionary = data.animations[clip]
 _repeat = not once and motion.get("loop", motion.get("mode", "") == "loop")
 var times := durations(clip, direction)
 show_frame(clip, direction, times.size() - 1 if reversed else 0)

func advance(milliseconds: float) -> void:
 if not playing: return
 var times := durations(clip, facing)
 var duration := 0.0
 for time in times: duration += float(time)
 var advance_to := elapsed_ms + milliseconds
 var playback := _playback_id
 while playing:
  var boundary := minf(duration, advance_to)
  if not _reversed:
   for event: Dictionary in data.animations[clip].get("events", []):
    if elapsed_ms < float(event.time_ms) and float(event.time_ms) <= boundary:
     show_frame(clip, facing, int(event.frame))
     event_reached.emit(event)
     if playback != _playback_id: return
  elapsed_ms = boundary
  if advance_to < duration: break
  if not _repeat:
   playing = false
   show_frame(clip, facing, 0 if _reversed else times.size() - 1)
   clip_finished.emit(clip)
   return
  advance_to -= duration
  elapsed_ms = 0.0
 var clock := elapsed_ms
 for step in times.size():
  var index := times.size() - 1 - step if _reversed else step
  clock -= float(times[index])
  if clock < 0:
   show_frame(clip, facing, index)
   break
