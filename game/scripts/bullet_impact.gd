class_name BulletImpact
extends Sprite2D

const DIRECTORY := "res://assets/fleet_sprites/characters/rift_crew/"
var _age_ms := 0.0
var _times: Array
var _cell: Vector2

func _ready() -> void:
 var effect: Dictionary = SpriteTimeline.manifest(DIRECTORY + "rift_crew_animations.json").effects.bullet_impact
 texture = load(DIRECTORY + effect.png)
 texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
 centered = false
 region_enabled = true
 region_filter_clip_enabled = true
 offset = -SpriteTimeline.pixel(effect.pivot_px)
 _cell = SpriteTimeline.pixel(effect.cell_px)
 _times = effect.frame_durations_ms
 region_rect = Rect2(Vector2.ZERO, _cell)

func _process(delta: float) -> void:
 _age_ms += delta * 1000.0
 var time := _age_ms
 for index in _times.size():
  time -= float(_times[index])
  if time < 0.0:
   region_rect = Rect2(Vector2(_cell.x * index, 0), _cell)
   return
 queue_free()
