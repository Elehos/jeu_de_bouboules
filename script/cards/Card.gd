extends Control
class_name Card

@export var card_data: CardData

@onready var panel: Panel = $Panel
@onready var name_label: Label = $Panel/VBoxContainer/CardName
@onready var cost_label: Label = $Panel/VBoxContainer/CardCost
@onready var description_label: Label = $Panel/VBoxContainer/CardDescription

var dragging: bool = false
var drag_start_mouse: Vector2
var drag_start_position: Vector2

var normal_min_width: float
@export var hover_min_width: float = 160.0
@export var hover_scale: float = 1.15
var drag_start_local_position: Vector2
@export var hand_zone: Control

const DRAG_THRESHOLD: float = 250.0

func _ready() -> void:
	update_display()
	panel.gui_input.connect(_on_panel_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	normal_min_width = custom_minimum_size.x
	pivot_offset = size / 2
	CombatEvents.mana_changed.connect(_on_mana_changed)
	CombatEvents.targeting_started.connect(_on_targeting_started)
	CombatEvents.targeting_cancelled.connect(_on_targeting_cancelled)
	_update_affordability()

func _on_targeting_started(data: CardData) -> void:
	if CombatEvents.pending_card == self:
		modulate = Color(1.2, 1.2, 0.6)

func _on_targeting_cancelled() -> void:
	_update_affordability()

func update_display() -> void:
	if card_data:
		name_label.text = card_data.card_name
		cost_label.text = str(card_data.cost)
		description_label.text = card_data.description


# Premier clic : lance le ciblage si nécessaire, sinon joue direct
func play() -> void:
	if card_data.requires_target:
		CombatEvents.request_targeting(self)
	else:
		confirm_play(null)

# Appelé une fois la cible confirmée (ou immédiatement si pas de cible nécessaire)
func confirm_play(target: Character) -> void:
	if not CombatEvents.try_spend_mana(card_data.cost):
		return  # pas assez de mana, rien ne se passe
	print("Carte jouée : ", card_data.card_name)
	CombatEvents.card_played.emit(card_data, target)
	DeckManager.discard_card(card_data)
	queue_free()


func _on_panel_gui_input(event: InputEvent) -> void:
	if CombatEvents.current_mana < card_data.cost:
		return  # pas assez de mana : aucune interaction possible
	
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			drag_start_local_position = position
			var current_global_pos: Vector2 = global_position
			top_level = true
			global_position = current_global_pos
			dragging = true
			drag_start_mouse = get_global_mouse_position()
			drag_start_position = global_position
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if dragging:
				_end_drag()

func _process(_delta: float) -> void:
	if dragging:
		var offset: Vector2 = get_global_mouse_position() - drag_start_mouse
		global_position = drag_start_position + offset

func _end_drag() -> void:
	dragging = false
	var moved_distance: float = global_position.distance_to(drag_start_position)
	
	if card_data.requires_target:
		if moved_distance < 10.0:
			# Clic simple : passe en mode "en attente de cible"
			_return_to_hand()
			CombatEvents.request_targeting(self)
			return
		
		var target: Character = _find_target_under_mouse()
		if target:
			_return_to_hand()
			confirm_play(target)
		else:
			_return_to_hand()
	else:
		if _has_dragged_far_enough():
			_return_to_hand()
			confirm_play(null)
		else:
			_return_to_hand()

func _return_to_hand() -> void:
	top_level = false
	position = drag_start_local_position
	get_parent().queue_sort()

func _find_target_under_mouse() -> Character:
	var space_state := get_viewport().get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = get_global_mouse_position()
	query.collision_mask = 0b1000
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var results := space_state.intersect_point(query)
	for result in results:
		var collider = result.collider
		if collider.get_parent() is Enemy:
			return collider.get_parent()
	return null
	
func _on_mouse_entered() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "custom_minimum_size:x", hover_min_width, 0.15)
	tween.parallel().tween_property(self, "scale", Vector2(hover_scale, hover_scale), 0.15)

func _on_mouse_exited() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "custom_minimum_size:x", normal_min_width, 0.15)
	tween.parallel().tween_property(self, "scale", Vector2.ONE, 0.15)
	
func _update_affordability() -> void:
	var affordable: bool = CombatEvents.current_mana >= card_data.cost
	modulate = Color(1, 1, 1, 1) if affordable else Color(0.5, 0.5, 0.5, 0.6)

func _on_mana_changed(_current: int, _max: int) -> void:
	_update_affordability()
	
func _has_dragged_far_enough() -> bool:
	var delta: Vector2 = global_position - drag_start_position
	return delta.y < -DRAG_THRESHOLD
