class_name FleetRoom
extends Node2D

const ROOT := "res://assets/fleet_sprites/environment/fleet_lab/"
const ROOMS := {"lab": "research_lab", "storage": "supply_room", "quarters": "gunsmith_quarters"}
const ROOM_IDS := {"research_lab": "lab", "supply_room": "storage", "gunsmith_quarters": "quarters", "next_stage": "main_entry"}

var layout: Dictionary
var manifest: Dictionary
var bounds: Rect2
var extent: Vector2
var _tile: Vector2
var _textures: Dictionary
var _doors: Dictionary
var _warnings: Array[AnimatedSprite2D]
var cabinets: Array[AnimatedSprite2D]
var cabinet_cells: Array[Vector2]

static func assets() -> Dictionary:
 return SpriteTimeline.manifest(ROOT + "assets.json")

static func sprite_texture(id: String) -> Texture2D:
 return load(ROOT + assets().sprites[id].png)

static func build_sprite(id: String) -> Sprite2D:
 var sprite := Sprite2D.new()
 sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
 sprite.centered = false
 sprite.texture = sprite_texture(id)
 sprite.offset = -SpriteTimeline.pixel(assets().sprites[id].pivot_px)
 return sprite

static func prop_footprint(id: String) -> Rect2:
 var sprite: Dictionary = assets().sprites[id]
 var rect: Array = sprite.collision_rect_px
 var origin := Vector2(rect[0], rect[1]) - SpriteTimeline.pixel(sprite.pivot_px)
 return Rect2(origin, Vector2(rect[2], rect[3]))

func setup(id: String) -> void:
 layout = SpriteTimeline.manifest(ROOT + "rooms/" + ROOMS[id] + ".json")
 manifest = assets()
 texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
 y_sort_enabled = true
 _tile = SpriteTimeline.pixel(layout.tile_px)
 bounds = Rect2(SpriteTimeline.pixel(layout.floor_origin_px), SpriteTimeline.pixel(layout.grid_size) * _tile)
 extent = bounds.end + Vector2(32, 40)
 var ground := Node2D.new()
 ground.z_index = -3
 add_child(ground)
 _build_tiles(ground)
 for item: Dictionary in layout.sprite_instances:
  if item.sprite == "flashlight" and item.get("interaction", "") == "take_flashlight": continue
  var mount := SpriteTimeline.pixel(item.pivot_world_px)
  var floor_object: bool = item.layer in ["object", "surface"]
  var art: Node2D
  if item.sprite in ["stage_door", "sliding_cabinet", "warning_light"]:
   var animated := _build_animation(item.sprite)
   art = animated
   if item.sprite == "warning_light": _warnings.append(animated)
   if item.sprite == "sliding_cabinet":
    animated.frame = int(item.get("animation_frame", 0))
    cabinets.append(animated)
    cabinet_cells.append(cell(item.approach_cell))
  else: art = build_sprite(item.sprite)
  art.position = mount
  if item.has("exit_edge"): _doors[item.exit_edge] = art
  if floor_object:
   art.z_index = 6
   add_child(art)
  else: ground.add_child(art)
  if item.has("blocked_tiles"):
   var obstacle := RoundedObstacle.new()
   obstacle.name = "Solid"
   obstacle.fit_rect(prop_footprint(item.sprite))
   art.add_child(obstacle)

func cell(coordinates: Array) -> Vector2:
 return bounds.position + (SpriteTimeline.pixel(coordinates) + Vector2(0.5, 0.5)) * _tile

func approach(kind: String) -> Vector2:
 for item: Dictionary in layout.sprite_instances:
  if item.get("interaction", "") == kind: return cell(item.approach_cell)
 return Vector2.INF

func exit_data(edge: String) -> Dictionary:
 for door: Dictionary in layout.exits:
  if door.edge == edge: return door
 return {}

func on_approach(point: Vector2, edge: String) -> bool:
 var door := exit_data(edge)
 if door.is_empty(): return false
 var tile := ((point - bounds.position) / _tile).floor()
 if door.approach_cells.any(func(candidate): return SpriteTimeline.pixel(candidate) == tile): return true
 # The outer tile is the one the player stands in when stopped against the door.
 var vertical_wall := edge in ["w", "e"]
 var boundary := 0.0 if edge in ["w", "n"] else float(layout.grid_size[0 if vertical_wall else 1]) - 1.0
 return (tile.x if vertical_wall else tile.y) == boundary and (tile.y if vertical_wall else tile.x) in door.edge_tiles

func migrate_position(point: Vector2, previous: Rect2) -> Vector2:
 var mapped := bounds.position + (point - previous.position) / previous.size * bounds.size
 var blocked: Array[Rect2] = []
 for obstacle: RoundedObstacle in find_children("*", "StaticBody2D", true, false):
  blocked.append(Rect2(to_local(obstacle.global_position) - obstacle.footprint * 0.5, obstacle.footprint).grow(13))
 var legal := func(candidate: Vector2) -> bool:
  return bounds.grow(-16).has_point(candidate) and not blocked.any(func(rect): return rect.has_point(candidate))
 if legal.call(mapped): return mapped
 var best := Vector2.INF
 var distance := INF
 for row in int(layout.grid_size[1]):
  for column in int(layout.grid_size[0]):
   var candidate := cell([column, row])
   if not legal.call(candidate): continue
   var score := mapped.distance_squared_to(candidate)
   if score < distance:
    distance = score
    best = candidate
 return best

func play_door(edge: String, action: String) -> void:
 var door := _doors.get(edge) as AnimatedSprite2D
 if not door: return
 if action == "open" or action == "close":
  door.stop()
  door.play(action)
 else:
  door.stop()
  door.animation = "open"
  door.frame = manifest.animations.stage_door.open_frame if action == "opened" else manifest.animations.stage_door.closed_frame

func set_warning(active: bool) -> void:
 for warning in _warnings:
  if active and not warning.is_playing(): warning.play("open")
  elif not active and warning.is_playing(): warning.stop()

func toggle_cabinet(index: int) -> void:
 var cabinet := cabinets[index]
 if cabinet.is_playing(): return
 var open: bool = cabinet.animation == "open" and cabinet.frame == cabinet.sprite_frames.get_frame_count("open") - 1
 cabinet.play("close" if open else "open")

func set_locked_cabinet(open: bool, instant := false) -> void:
 var cabinet := cabinets[0]
 var target := "open" if open else "close"
 if instant:
  cabinet.stop()
  cabinet.animation = target
  cabinet.frame = cabinet.sprite_frames.get_frame_count(target) - 1
 elif cabinet.animation != target:
  cabinet.stop()
  cabinet.play(target)

func _build_tiles(ground: Node2D) -> void:
 var backdrop := ColorRect.new()
 backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
 backdrop.size = extent
 backdrop.color = Color("101d26")
 ground.add_child(backdrop)
 for row in layout.floor_tiles.size():
  var tiles: Array = layout.floor_tiles[row]
  for column in tiles.size():
   _tile_sprite(ground, tiles[column], bounds.position + Vector2(column, row) * _tile)
 var wall := SpriteTimeline.pixel(layout.north_wall_origin_px)
 for column in layout.north_wall_tiles.size():
  _tile_sprite(ground, layout.north_wall_tiles[column], wall + Vector2(column * _tile.x, 0))
  _tile_sprite(ground, "wall_edge_horizontal", Vector2(bounds.position.x + column * _tile.x, bounds.end.y))
 for row in int(layout.grid_size[1]):
  for x in [bounds.position.x - 20, bounds.end.x]:
   _tile_sprite(ground, "wall_edge_vertical", Vector2(x, bounds.position.y + row * _tile.y))
 for marking: Dictionary in layout.markings:
  var box: Array = marking.tile_rect
  var area := Rect2(bounds.position + Vector2(box[0], box[1]) * _tile, Vector2(box[2], box[3]) * _tile)
  var outline := Line2D.new()
  outline.default_color = Color(marking.ink, 0.75)
  outline.width = 2
  outline.closed = true
  outline.points = PackedVector2Array([area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)])
  ground.add_child(outline)

func _tile_sprite(ground: Node2D, id: String, top_left: Vector2) -> void:
 var tile := Sprite2D.new()
 if not _textures.has(id): _textures[id] = sprite_texture(id)
 tile.texture = _textures[id]
 tile.centered = false
 tile.position = top_left
 ground.add_child(tile)

func _build_animation(id: String) -> AnimatedSprite2D:
 var animation: Dictionary = manifest.animations[id]
 var sheet: Texture2D = load(ROOT + animation.png)
 var size_px := SpriteTimeline.pixel(animation.frame_px)
 var sprite := AnimatedSprite2D.new()
 var frames := SpriteFrames.new()
 frames.remove_animation("default")
 var forward: Array = animation.get("open_order", range(int(animation.frames)))
 var orders := {"open": forward}
 if animation.has("close_order"): orders["close"] = animation.close_order
 for action in orders:
  frames.add_animation(action)
  frames.set_animation_speed(action, 1000.0)
  frames.set_animation_loop(action, animation.loop)
  for index in orders[action]:
   var frame_texture := AtlasTexture.new()
   frame_texture.atlas = sheet
   frame_texture.region = Rect2(Vector2(index * size_px.x, 0), size_px)
   frame_texture.filter_clip = true
   frames.add_frame(action, frame_texture, float(animation.duration_ms[index]))
 sprite.sprite_frames = frames
 sprite.animation = "open"
 sprite.centered = false
 sprite.offset = -SpriteTimeline.pixel(animation.pivot_px)
 return sprite
