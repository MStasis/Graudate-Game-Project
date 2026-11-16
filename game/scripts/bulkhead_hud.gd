extends Control

signal review_requested

const RELOADING_COLOR := Color("e6ad70")
const LOW_HEALTH_COLOR := Color("e78979")

@onready var minimap: ExplorationMap = %Minimap
@onready var _objective_panel: PanelContainer = %ObjectivePanel
@onready var _objective: Label = %Objective
@onready var _health: Label = %Health
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _rounds: Label = %Rounds
@onready var _capacity: Label = %Capacity
@onready var _magazines: Label = %Magazines
@onready var _reserve: HBoxContainer = %Reserve
@onready var _dialogue: PanelContainer = %Dialogue
@onready var _speaker: Label = %Speaker
@onready var _line: Label = %Line
@onready var _advance_hint: Label = %AdvanceHint

func _ready() -> void:
 %Review.pressed.connect(review_requested.emit)

func bind_minimap(world: DemoWorld, source: ExplorationMap = null) -> void:
 minimap.world = world
 minimap.source = source
 minimap.queue_redraw()

func set_objective(text: String) -> void:
 _objective.text = text
 _objective_panel.visible = not text.strip_edges().is_empty()

func set_vitals(hp: int, max_hp: int, rounds: int, capacity: int, magazines := -1, reloading := false) -> void:
 _health.text = str(hp)
 _health.modulate = LOW_HEALTH_COLOR if hp <= max_hp * 0.35 else Color.WHITE
 _health.accessibility_name = "체력 %d / %d" % [hp, max_hp]
 _health_bar.max_value = max_hp
 _health_bar.value = hp
 _rounds.text = "%02d" % rounds
 _rounds.modulate = RELOADING_COLOR if reloading else Color.WHITE
 _capacity.text = "/ %02d" % capacity
 _reserve.visible = magazines >= 0
 _magazines.text = str(magazines) if magazines >= 0 else ""
 _magazines.accessibility_name = "예비 탄창 %d개" % magazines if magazines >= 0 else ""

func set_dialogue(speaker: String, body: String, can_advance := false) -> void:
 _speaker.text = speaker
 _speaker.visible = not speaker.is_empty()
 _line.text = body
 _advance_hint.visible = can_advance
 _dialogue.visible = not body.strip_edges().is_empty()

func review_button_contains(screen_position: Vector2) -> bool:
 var button: Button = %Review
 return button.is_visible_in_tree() and Rect2(Vector2.ZERO, button.size).has_point(button.get_global_transform_with_canvas().affine_inverse() * screen_position)
