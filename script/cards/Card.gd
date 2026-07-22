extends Control
class_name Card

@export var card_data: CardData

@onready var panel: Panel = $Panel
@onready var name_label: Label = $Panel/CardName
@onready var cost_label: Label = $Panel/CardCost
@onready var description_label: Label = $Panel/CardDescription
@export var card_name_max_width: float = 110.0
var dragging: bool = false
var drag_start_mouse: Vector2
var drag_start_position: Vector2
var drag_start_local_position: Vector2
var base_z_index: int = 0

const DRAG_THRESHOLD: float = 200.0
var interactive: bool = true

# Pour stocker la rotation de base
var base_rotation_degrees: float = 0.0
var base_position: Vector2 = Vector2.ZERO

enum CardState { IDLE, DRAGGING, AWAITING_TARGET, PLAYED }
var state: CardState = CardState.IDLE

@export var hover_scale: float = 1.3
@export var hover_screen_margin: float = 100.0

var active_tween: Tween

@export var hover_x_offset: float = -30.0

var click_follow_active: bool = false
const CLICK_MOVE_THRESHOLD: float = 12.0


func _ready() -> void:
	update_display()
	panel.gui_input.connect(_on_panel_gui_input)
	panel.mouse_entered.connect(_on_mouse_entered)
	panel.mouse_exited.connect(_on_mouse_exited)
	CombatEvents.mana_changed.connect(_on_mana_changed)
	CombatEvents.targeting_started.connect(_on_targeting_started)
	CombatEvents.targeting_cancelled.connect(_on_targeting_cancelled)
	_update_affordability()

func update_display() -> void:
	if card_data:
		name_label.text = card_data.card_name
		_fit_label_text(name_label, card_name_max_width)
		cost_label.text = str(card_data.cost)
		description_label.text = card_data.description


func set_interactive(value: bool) -> void:
	interactive = value
	if not interactive:
		modulate = Color(1, 1, 1, 1)
	else:
		_update_affordability()

func _grow() -> void:
	if active_tween and active_tween.is_valid():
		active_tween.kill()
	
	pivot_offset = Vector2(size.x / 2, size.y)
	z_index = 1
	
	var viewport_height: float = get_viewport_rect().size.y
	var target_global_y: float = viewport_height - hover_screen_margin - size.y
	var target_global_x: float = get_parent().global_position.x + base_position.x + hover_x_offset
	var target_global_pos: Vector2 = Vector2(target_global_x, target_global_y)
	
	active_tween = create_tween()
	active_tween.set_parallel(true)
	active_tween.tween_property(self, "scale", Vector2(hover_scale, hover_scale), 0.10)
	active_tween.tween_property(self, "global_position", target_global_pos, 0.10)
	active_tween.tween_property(self, "rotation_degrees", 0.0, 0.10)

func _shrink() -> void:
	if active_tween and active_tween.is_valid():
		active_tween.kill()
	
	z_index = base_z_index
	pivot_offset = Vector2(size.x / 2, size.y)
	
	active_tween = create_tween()
	active_tween.set_parallel(true)
	active_tween.tween_property(self, "scale", Vector2.ONE, 0.10)
	active_tween.tween_property(self, "position", base_position, 0.10)
	active_tween.tween_property(self, "rotation_degrees", base_rotation_degrees, 0.10)
	
func move_to_base(duration: float = 0.15) -> void:
	if active_tween and active_tween.is_valid():
		active_tween.kill()
	
	active_tween = create_tween()
	active_tween.set_parallel(true)
	active_tween.tween_property(self, "position", base_position, duration)
	active_tween.tween_property(self, "rotation_degrees", base_rotation_degrees, duration)
	active_tween.tween_property(self, "scale", Vector2.ONE, duration)

func _on_mouse_entered() -> void:
	if CombatEvents.targeting_arrow and CombatEvents.targeting_arrow.active:
		return
	if interactive and state == CardState.IDLE:
		_grow()
		var hand = get_parent()
		if hand and hand.has_method("set_hovered_card"):
			hand.set_hovered_card(self)

func _on_mouse_exited() -> void:
	if interactive and state == CardState.IDLE:
		_shrink()
		var hand = get_parent()
		if hand and hand.has_method("set_hovered_card"):
			hand.set_hovered_card(null)

# --- Ciblage ---
func _on_targeting_started(_data: CardData) -> void:
	pass

func _on_targeting_cancelled() -> void:
	if state == CardState.AWAITING_TARGET:
		state = CardState.IDLE
		var hand = get_parent()
		if hand and hand.has_method("_update_hand_layout"):
			hand._update_hand_layout()
		_shrink()
	CombatEvents.targeting_arrow.hide_arrow()
	_update_affordability()

# --- Jeu de la carte ---
func confirm_play(target: Character) -> void:
	if CombatEvents.current_mana < card_data.cost:
		state = CardState.IDLE
		var hand = get_parent()
		if hand and hand.has_method("_update_hand_layout"):
			hand._update_hand_layout()
		_return_to_hand()
		_shrink()
		return
	
	state = CardState.PLAYED
	CombatEvents.try_spend_mana(card_data.cost)
	print("Carte jouée : ", card_data.card_name)
	CombatEvents.card_played.emit(card_data, target)
	DeckManager.discard_card(card_data)
	_play_confirmation_animation()

func _play_confirmation_animation() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var current_global: Vector2 = global_position
	var ui_layer: Node = get_tree().current_scene.get_node("UI")
	var hand_parent := get_parent()
	
	if hand_parent:
		hand_parent.remove_child(self)
	ui_layer.add_child(self)
	top_level = true
	global_position = current_global
	
	var viewport_size: Vector2 = get_viewport_rect().size
	var target_position: Vector2 = viewport_size / 2 - (size * hover_scale) / 2
	
	var tween: Tween = create_tween()
	tween.tween_property(self, "global_position", target_position, 0.1)  # trajet raccourci
	tween.parallel().tween_property(self, "scale", Vector2(hover_scale, hover_scale), 0.1)
	tween.tween_interval(0.4)  # pause raccourcie
	tween.tween_callback(queue_free)

# --- Interaction souris / glisser-déposer ---
func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if state == CardState.DRAGGING or state == CardState.AWAITING_TARGET:
			_cancel_action()
			return
	
	if not interactive:
		return
	if state == CardState.PLAYED:
		return
	if CombatEvents.current_mana < card_data.cost:
		return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if click_follow_active:
				click_follow_active = false
				_end_drag()
				return
			
			if state != CardState.IDLE:
				return
			
			if active_tween and active_tween.is_valid():
				active_tween.kill()
			
			# Finalise instantanément l'état "zoomé", peu importe où en était l'animation
			pivot_offset = Vector2(size.x / 2, size.y)
			scale = Vector2(hover_scale, hover_scale)
			rotation_degrees = 0.0
			var viewport_height: float = get_viewport_rect().size.y
			var target_global_y: float = viewport_height - hover_screen_margin - size.y
			var target_global_x: float = get_parent().global_position.x + base_position.x + hover_x_offset
			global_position = Vector2(target_global_x, target_global_y)
			
			state = CardState.DRAGGING
			z_index = 1
			dragging = true
			drag_start_mouse = get_global_mouse_position()
			drag_start_position = global_position
			
			var hand = get_parent()
			if hand and hand.has_method("set_hovered_card"):
				hand.set_hovered_card(null)
			
			if card_data.requires_target:
				CombatEvents.targeting_arrow.show_arrow(self)
			else:
				drag_start_local_position = position
				top_level = true
				global_position = drag_start_position
		
		else:
			if dragging and not card_data.requires_target:
				var moved: float = get_global_mouse_position().distance_to(drag_start_mouse)
				if moved < CLICK_MOVE_THRESHOLD:
					click_follow_active = true
					return
			if dragging:
				_end_drag()

func _process(_delta: float) -> void:
	if dragging and not card_data.requires_target:
		var offset: Vector2 = get_global_mouse_position() - drag_start_mouse
		global_position = drag_start_position + offset
		
func _end_drag() -> void:
	dragging = false
	
	if card_data.requires_target:
		var moved_distance: float = get_global_mouse_position().distance_to(drag_start_mouse)
		
		if moved_distance < 10.0:
			state = CardState.AWAITING_TARGET
			CombatEvents.request_targeting(self)
			return
		
		var target: Character = _find_target_under_mouse()
		CombatEvents.targeting_arrow.hide_arrow()
		if target:
			confirm_play(target)
		else:
			state = CardState.IDLE
			var hand = get_parent()
			if hand and hand.has_method("_update_hand_layout"):
				hand._update_hand_layout()
			_shrink()
	else:
		if _has_dragged_far_enough():
			confirm_play(null)
		else:
			state = CardState.IDLE
			var hand = get_parent()
			if hand and hand.has_method("_update_hand_layout"):
				hand._update_hand_layout()
			_return_to_hand()
			_shrink()

func _return_to_hand() -> void:
	top_level = false
	position = drag_start_local_position

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

func _has_dragged_far_enough() -> bool:
	var delta: Vector2 = global_position - drag_start_position
	return delta.y < -DRAG_THRESHOLD

func _update_affordability() -> void:
	if not interactive or not card_data:
		return
	if state == CardState.AWAITING_TARGET or state == CardState.PLAYED:
		return
	var affordable: bool = CombatEvents.current_mana >= card_data.cost
	modulate = Color(1, 1, 1, 1) if affordable else Color(0.5, 0.5, 0.5, 0.6)

func _on_mana_changed(_current: int, _max: int) -> void:
	_update_affordability()

func _fit_label_text(label: Label, max_width: float, max_font_size: int = 14, min_font_size: int = 8) -> void:
	var font_size = max_font_size
	label.add_theme_font_size_override("font_size", font_size)
	
	while label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x > max_width and font_size > min_font_size:
		font_size -= 1
		label.add_theme_font_size_override("font_size", font_size)
		
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if state == CardState.DRAGGING or state == CardState.AWAITING_TARGET:
			_cancel_action()

func _cancel_action() -> void:
	dragging = false
	state = CardState.IDLE
	click_follow_active = false
	
	if card_data.requires_target:
		CombatEvents.targeting_arrow.hide_arrow()
		if CombatEvents.pending_card == self:
			CombatEvents.pending_card = null
	else:
		var current_global_pos: Vector2 = global_position
		top_level = false
		global_position = current_global_pos
	
	var hand = get_parent()
	if hand and hand.has_method("_update_hand_layout"):
		hand._update_hand_layout()
	
	_shrink()
