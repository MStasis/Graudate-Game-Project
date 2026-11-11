extends Sprite2D
## 임시 그림만 회전한다. 캐릭터의 충돌·속도·사격 판정에는 관여하지 않는다.
func _process(_delta: float) -> void:
 var actor := get_parent() as Node2D
 if actor.has_meta("visual_aim"):
  rotation = actor.position.angle_to_point(actor.get_meta("visual_aim"))
  return
 var world := actor.get_parent() as DemoWorld
 if not world: return
 var target := world.player.position
 if actor == world.player:
  target = world.get_global_mouse_position()
  if Input.is_physical_key_pressed(KEY_SPACE):
   var nearest := world.nearest_enemy_position()
   if nearest.is_finite(): target = nearest
 elif world.is_combat_area():
  var distance := INF
  for enemy in world.room_enemies():
   if enemy.hp > 0 and enemy.visible and actor.position.distance_squared_to(enemy.position) < distance:
    target = enemy.position
    distance = actor.position.distance_squared_to(enemy.position)
 rotation = actor.position.angle_to_point(target)
