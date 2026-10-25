extends RefCounted
func run(app) -> void:
 var world: DemoWorld = app.world
 var brain: NPCBrain = app.brain
 brain.new_trial(0)
 brain.auto_enabled = false
 await app.get_tree().create_timer(0.3).timeout
 await app.capture_screen("01_lab")
 world.apply_interaction("storage_gate")
 await app.get_tree().create_timer(0.3).timeout
 await app.capture_screen("02_dark_storage")
 world.player_hp = 40
 world.npc.position = world.player.position + Vector2(70, 0)
 brain.request_decision()
 await app.get_tree().create_timer(0.6).timeout
 world.ammo = 2
 brain.request_decision()
 await app.get_tree().create_timer(0.6).timeout
 world.player.position = world.safe_position - Vector2(0, 100)
 world.npc.position = world.safe_position - Vector2(90, 0)
 brain.request_decision()
 await app.get_tree().create_timer(0.8).timeout
 brain.request_decision()
 await app.get_tree().create_timer(0.3).timeout
 await app.capture_screen("03_support_and_guide")
 world.player.position = world.safe_position
 brain.auto_enabled = true
 var elapsed := 0.0
 while world.enemies_remaining() > 0 and elapsed < 22.0 and not world.defeated:
  world.shoot(world.nearest_enemy_position())
  if world.ammo <= 0 and not world.cache_used: world.apply_interaction("cache")
  await app.get_tree().create_timer(0.3).timeout
  elapsed += 0.3
 if world.defeated or world.enemies_remaining() > 0:
  print("MISSION_EVIDENCE_FAIL combat")
  app.get_tree().quit(1)
  return
 brain.auto_enabled = false
 world.apply_interaction("fuse")
 await app.capture_screen("04_fuse_found")
 world.apply_interaction("lab_gate")
 brain.request_dialogue("오늘 나랑 같이 와 보니까 어때?")
 await app.get_tree().create_timer(0.2).timeout
 await app.capture_screen("05_return_with_friend")
 world.apply_interaction("generator")
 world.apply_interaction("exit")
 await app.capture_screen("06_completed")
 print("MISSION_EVIDENCE_PASS escaped=", world.finished)
 app.get_tree().quit(0)
