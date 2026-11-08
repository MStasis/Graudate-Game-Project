class_name ActorStatus
extends Control
var target: Node2D
var actor_kind := "enemy"

func show_state(hp: int, maximum: int, ammo: int = -1, capacity: int = 0) -> void:
 $Health.max_value = maximum
 $Health.value = hp
 $Value.text = "%d / %d" % [hp, maximum]
 $Weapon.visible = ammo >= 0
 $Ammo.visible = ammo >= 0
 $Ammo.text = "%02d / %02d" % [ammo, capacity] if ammo >= 0 else ""
 $Value.modulate = Color("e78979") if hp <= maximum * 0.35 else Color.WHITE
 tooltip_text = ("플레이어" if actor_kind == "player" else "하린" if actor_kind == "npc" else "드론") + " · 체력 %d/%d" % [hp, maximum]
 if ammo >= 0: tooltip_text += " · 펄스 권총 · 보유 %d / 최대 %d (탄창 구분 없음)" % [ammo, capacity]
 size = Vector2(120, 52 if ammo >= 0 else 24)
