extends Control
class_name Card

@export var card_data: CardData

@onready var panel: Panel = $Panel
@onready var name_label: Label = $Panel/CardName
@onready var cost_label: Label = $Panel/CardCost
@onready var description_label: RichTextLabel = $Panel/CardDescription
@onready var type_label: Label = $Panel/TypeLabel
@onready var gem_slot: GemSlot = $GemSlot
@onready var card_background: TextureRect = $Panel/CardBackground
@onready var card_glow: TextureRect = $Panel/CardGlow

@export var card_name_max_width: float = 168.0

signal card_selected(card_data: CardData)
var reward_mode: bool = false

var dragging: bool = false
var drag_start_mouse: Vector2
var drag_start_position: Vector2
var drag_start_local_position: Vector2
var base_z_index: int = 0

const DRAG_THRESHOLD: float = 200.0
const CLICK_MOVE_THRESHOLD: float = 30.0

var interactive: bool = true
var click_follow_active: bool = false
var is_hovering: bool = false

var base_rotation_degrees: float = 0.0
var base_position: Vector2 = Vector2.ZERO

enum CardState { IDLE, DRAGGING, AWAITING_TARGET, PLAYED }
var state: CardState = CardState.IDLE

@export var hover_scale: float = 1.3
@export var hover_screen_margin: float = 100.0
@export var hover_x_offset: float = -30.0

var active_tween: Tween
var hover_count: int = 0


var glow_material_playable: ShaderMaterial
var glow_material_unplayable: ShaderMaterial

@export var glow_margin: float = 10.0
@export var glow_offset: Vector2 = Vector2.ZERO

@onready var mana_background: TextureRect = $Panel/ManaBackground
@export var mana_frames_texture: Texture2D

const MANA_FRAME_COUNT: int = 5
const MANA_ANIM_STEP_TIME: float = 0.10

var mana_frame_textures: Array[Texture2D] = []
var mana_current_frame: int = 4
var mana_anim_id: int = 0

func _ready() -> void:
	update_display()
	panel.gui_input.connect(_on_panel_gui_input)
	panel.mouse_entered.connect(_on_mouse_entered)
	panel.mouse_exited.connect(_on_mouse_exited)
	gem_slot.mouse_entered.connect(_on_mouse_entered)
	gem_slot.mouse_exited.connect(_on_mouse_exited)
	CombatEvents.mana_changed.connect(_on_mana_changed)
	CombatEvents.targeting_cancelled.connect(_on_targeting_cancelled)
	CombatEvents.gem_equip_changed.connect(_on_gem_equip_changed)
	
	card_glow.anchor_left = 0.0
	card_glow.anchor_top = 0.0
	card_glow.anchor_right = 0.0
	card_glow.anchor_bottom = 0.0

	var glow_total_size: Vector2 = card_background.size + Vector2(glow_margin * 2, glow_margin * 2)
	card_glow.size = glow_total_size
	card_glow.position = card_background.position - Vector2(glow_margin, glow_margin) + glow_offset
	var margin_uv: Vector2 = Vector2(glow_margin, glow_margin) / glow_total_size
	
	var current_material: ShaderMaterial = card_glow.material
	var shader: Shader = current_material.shader
	
	glow_material_playable = ShaderMaterial.new()
	glow_material_playable.shader = shader
	glow_material_playable.set_shader_parameter("glow_color", Color(1, 1, 1, 0.5))
	glow_material_playable.set_shader_parameter("glow_size", 0.03)
	glow_material_playable.set_shader_parameter("margin_uv", margin_uv)
	
	glow_material_unplayable = ShaderMaterial.new()
	glow_material_unplayable.shader = shader
	glow_material_unplayable.set_shader_parameter("glow_color", Color(0.9, 0.15, 0.15, 0.7))
	glow_material_unplayable.set_shader_parameter("glow_size", 0.035)
	glow_material_unplayable.set_shader_parameter("margin_uv", margin_uv)
	
	card_glow.material = glow_material_playable
	
	_update_affordability()
	_setup_mana_frames()

func update_display() -> void:
	if card_data:
		name_label.text = card_data.card_name
		_fit_label_text(name_label, card_name_max_width, 25)
		cost_label.text = str(card_data.cost)
		description_label.text = card_data.get_display_description()
		type_label.text = card_data.get_type_label()
	
	if gem_slot:
		gem_slot.card_data = card_data
		gem_slot.update_display()

func _on_gem_equip_changed() -> void:
	update_display()

func set_interactive(value: bool) -> void:
	interactive = value
	if not interactive:
		modulate = Color(1, 1, 1, 1)
		card_glow.visible = false
	else:
		card_glow.visible = true
		_update_affordability()

# --- Grossissement / rétrécissement ---
func _grow() -> void:
	if active_tween and active_tween.is_valid():
		active_tween.kill()
	
	pivot_offset = Vector2(size.x / 2, size.y)
	z_index = 500
	rotation_degrees = 0.0
	
	var viewport_height: float = get_viewport_rect().size.y
	var target_global_y: float = viewport_height - hover_screen_margin - size.y
	var target_global_x: float = get_parent().global_position.x + base_position.x + hover_x_offset
	var target_global_pos: Vector2 = Vector2(target_global_x, target_global_y)
	
	active_tween = create_tween()
	active_tween.set_parallel(true)
	active_tween.tween_property(self, "scale", Vector2(hover_scale, hover_scale), 0.10)
	active_tween.tween_property(self, "global_position", target_global_pos, 0.10)

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

# --- Ciblage ---
func _on_targeting_cancelled() -> void:
	if state == CardState.AWAITING_TARGET:
		state = CardState.IDLE
		CombatEvents.any_card_active = false
		var hand = get_parent()
		if hand and hand.has_method("_update_hand_layout"):
			hand._update_hand_layout()
		_shrink()
	CombatEvents.targeting_arrow.hide_arrow()
	_update_affordability()

# --- Annulation (clic droit) ---
func _cancel_action() -> void:
	dragging = false
	state = CardState.IDLE
	click_follow_active = false
	CombatEvents.any_card_active = false
	
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

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if state == CardState.DRAGGING or state == CardState.AWAITING_TARGET:
			_cancel_action()

# --- Jeu de la carte ---
func confirm_play(target: Character) -> void:
	if CombatEvents.current_mana < card_data.cost:
		state = CardState.IDLE
		CombatEvents.any_card_active = false
		var hand = get_parent()
		if hand and hand.has_method("_update_hand_layout"):
			hand._update_hand_layout()
		_return_to_hand()
		_shrink()
		return
	
	state = CardState.PLAYED
	CombatEvents.any_card_active = false
	CombatEvents.try_spend_mana(card_data.cost)
	CombatEvents.card_played.emit(card_data, target)
	DeckManager.discard_card(card_data)
	_play_confirmation_animation()

func _play_confirmation_animation() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rotation_degrees = 0.0
	
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
	tween.tween_property(self, "global_position", target_position, 0.1)
	tween.parallel().tween_property(self, "scale", Vector2(hover_scale, hover_scale), 0.1)
	tween.tween_interval(0.4)
	tween.tween_callback(queue_free)

# --- Interaction souris / glisser-déposer ---
func _on_panel_gui_input(event: InputEvent) -> void:
	if reward_mode:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			card_selected.emit(card_data)
		return
		
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
			
			rotation_degrees = 0.0
			state = CardState.DRAGGING
			CombatEvents.any_card_active = true
			z_index = 500
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
				var current_global_pos: Vector2 = global_position
				top_level = true
				global_position = current_global_pos
		
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

func _on_mouse_entered() -> void:
	hover_count += 1
	if hover_count == 1 and interactive and state == CardState.IDLE and not CombatEvents.any_card_active:
		_grow()
		var hand = get_parent()
		if hand and hand.has_method("set_hovered_card"):
			hand.set_hovered_card(self)

func _on_mouse_exited() -> void:
	hover_count -= 1
	if hover_count <= 0:
		hover_count = 0
		if interactive and state == CardState.IDLE:
			_shrink()
			var hand = get_parent()
			if hand and hand.has_method("set_hovered_card"):
				hand.set_hovered_card(null)

func _end_drag() -> void:
	dragging = false
	
	if card_data.requires_target:
		var moved_distance: float = get_global_mouse_position().distance_to(drag_start_mouse)
		
		if moved_distance < 10.0:
			state = CardState.AWAITING_TARGET
			CombatEvents.request_targeting(self)
			CombatEvents.targeting_arrow.show_arrow(self)
			return
		
		var target: Character = _find_target_under_mouse()
		CombatEvents.targeting_arrow.hide_arrow()
		if target:
			confirm_play(target)
		else:
			state = CardState.IDLE
			CombatEvents.any_card_active = false
			var hand = get_parent()
			if hand and hand.has_method("_update_hand_layout"):
				hand._update_hand_layout()
			_shrink()
	else:
		if _has_dragged_far_enough():
			confirm_play(null)
		else:
			state = CardState.IDLE
			CombatEvents.any_card_active = false
			var hand = get_parent()
			if hand and hand.has_method("_update_hand_layout"):
				hand._update_hand_layout()
			_return_to_hand()
			_shrink()

func _return_to_hand() -> void:
	top_level = false
	position = drag_start_local_position

func _find_target_under_mouse() -> Character:
	return CombatTargeting.find_enemy_at(get_viewport(), get_global_mouse_position())

func _has_dragged_far_enough() -> bool:
	var delta: Vector2 = global_position - drag_start_position
	return delta.y < -DRAG_THRESHOLD

func _update_affordability() -> void:
	if not interactive or not card_data:
		return
	if state == CardState.AWAITING_TARGET or state == CardState.PLAYED:
		return
	
	var affordable: bool = CombatEvents.current_mana >= card_data.cost
	modulate = Color(1, 1, 1, 1)
	
	if affordable:
		card_glow.visible = false
		_play_mana_animation(MANA_FRAME_COUNT - 1)
	else:
		card_glow.visible = true
		card_glow.material = glow_material_unplayable
		_play_mana_animation(0)

func _on_mana_changed(_current: int, _max: int) -> void:
	_update_affordability()

func _fit_label_text(label: Label, max_width: float, max_font_size: int = 18, min_font_size: int = 8) -> void:
	var font_size = max_font_size
	label.add_theme_font_size_override("font_size", font_size)
	
	while label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x > max_width and font_size > min_font_size:
		font_size -= 1
		label.add_theme_font_size_override("font_size", font_size)
		
func _setup_mana_frames() -> void:
	if not mana_frames_texture:
		return
	
	var frame_width: float = mana_frames_texture.get_width() / float(MANA_FRAME_COUNT)
	var frame_height: float = mana_frames_texture.get_height()
	
	mana_frame_textures.clear()
	for i in range(MANA_FRAME_COUNT):
		var atlas := AtlasTexture.new()
		atlas.atlas = mana_frames_texture
		atlas.region = Rect2(i * frame_width, 0, frame_width, frame_height)
		mana_frame_textures.append(atlas)
	
	mana_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mana_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mana_background.texture = mana_frame_textures[mana_current_frame]

func _play_mana_animation(target_frame: int) -> void:
	if mana_frame_textures.is_empty():
		return
	
	mana_anim_id += 1
	var my_id: int = mana_anim_id
	var direction: int = 1 if target_frame > mana_current_frame else -1
	
	while mana_current_frame != target_frame:
		if my_id != mana_anim_id:
			return
		mana_current_frame += direction
		mana_background.texture = mana_frame_textures[mana_current_frame]
		await get_tree().create_timer(MANA_ANIM_STEP_TIME).timeout
