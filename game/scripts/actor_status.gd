class_name ActorStatus
extends Control
var target: Node2D
var actor_kind := "enemy"

func _ready() -> void:
 # 형제 상태바/월드 물체와의 겹침은 위치 회피 대신 그리기 순서로 처리한다.
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 z_index = 2 if actor_kind == "npc" else 1

func show_state(hp: int, maximum: int, ammo: int = -1, capacity: int = 0) -> void:
 $Health.max_value = maximum
 $Health.value = hp
 $Value.text = "%d / %d" % [hp, maximum]
 $Weapon.visible = ammo >= 0
 $Ammo.visible = ammo >= 0
 $Ammo.text = "%02d / %02d" % [ammo, capacity] if ammo >= 0 else ""
 $Value.modulate = Color("e78979") if hp <= maximum * 0.35 else Color.WHITE
 tooltip_text = ("플레이어" if actor_kind == "player" else "미카" if actor_kind == "npc" else "침식된 선원") + " · 체력 %d/%d" % [hp, maximum]
 if ammo >= 0:
  if actor_kind == "npc" and target is MikaActor:
   var world := target.get_parent() as DemoWorld
   tooltip_text += " · 펄스 권총 · 장전 %d/%d · 예비탄 %d · %s" % [ammo, capacity, world.npc_reserve, target.get_node("NameLabel").text]
  else: tooltip_text += " · 펄스 권총 · 보유 %d / 최대 %d (탄창 구분 없음)" % [ammo, capacity]
 size = Vector2(120, 52 if ammo >= 0 else 24)
