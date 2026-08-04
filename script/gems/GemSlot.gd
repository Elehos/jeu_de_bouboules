extends Control
class_name GemSlot

@export var card_data: CardData

@onready var equipped_icon: TextureRect = $EquippedIcon
@onready var pickup_area: Control = $GemPickupArea

const ICON_SIZE: float = 60.0
const FORBIDDEN_COLOR: Color = Color(0.9, 0.15, 0.15, 0.85)
const FORBIDDEN_WIDTH: float = 4.0

var active_ghost: TextureRect = null

func _ready() -> void:
	add_to_group("gem_slots")
	update_display()

func update_display() -> void:
	if not equipped_icon:
		return
	if card_data and card_data.equipped_gem:
		equipped_icon.texture = card_data.equipped_gem.icon
		equipped_icon.visible = true
		equipped_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		equipped_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		equipped_icon.size = Vector2(ICON_SIZE, ICON_SIZE)
		equipped_icon.position = card_data.equipped_gem_position - Vector2(ICON_SIZE, ICON_SIZE) / 2.0
		
		pickup_area.size = Vector2(ICON_SIZE, ICON_SIZE)
		pickup_area.position = card_data.equipped_gem_position - Vector2(ICON_SIZE, ICON_SIZE) / 2.0
		pickup_area.visible = true
	else:
		equipped_icon.visible = false
		pickup_area.visible = false

func _process(_delta: float) -> void:
	queue_redraw()
	
	if active_ghost and is_instance_valid(active_ghost):
		active_ghost.size = Vector2(ICON_SIZE, ICON_SIZE)
		active_ghost.global_position = get_global_mouse_position() - Vector2(ICON_SIZE, ICON_SIZE) / 2.0
		
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_resolve_drop()

func _draw() -> void:
	if not CombatEvents.dragging_gem:
		return
	
	var gem: GemData = CombatEvents.dragging_gem
	if not card_data or gem.allowed_card_type == CardData.CardType.ANY or gem.allowed_card_type == card_data.card_type:
		return
	
	draw_line(Vector2.ZERO, size, FORBIDDEN_COLOR, FORBIDDEN_WIDTH)
	draw_line(Vector2(size.x, 0), Vector2(0, size.y), FORBIDDEN_COLOR, FORBIDDEN_WIDTH)

func start_pickup_drag() -> void:
	if GemInventory.gems_locked:
		return
	if not card_data or not card_data.equipped_gem:
		return
	
	var gem: GemData = card_data.equipped_gem
	CombatEvents.dragging_gem = gem
	CombatEvents.dragging_gem_source = self
	
	var ui_layer: Node = get_tree().current_scene.get_node("UI")
	active_ghost = TextureRect.new()
	active_ghost.texture = gem.icon
	active_ghost.size = Vector2(ICON_SIZE, ICON_SIZE)
	active_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	active_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	active_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	active_ghost.top_level = true
	ui_layer.add_child(active_ghost)
	
	equipped_icon.visible = false

func _resolve_drop() -> void:
	var gem: GemData = CombatEvents.dragging_gem
	var source: Node = CombatEvents.dragging_gem_source
	var mouse_pos: Vector2 = get_global_mouse_position()
	
	var target_slot: GemSlot = _find_slot_at(mouse_pos)
	var target_unequip: Node = _find_unequip_zone_at(mouse_pos)
	
	if target_slot and (gem.allowed_card_type == CardData.CardType.ANY or gem.allowed_card_type == target_slot.card_data.card_type):
		var drop_local_pos: Vector2 = mouse_pos - target_slot.global_position
		
		if target_slot != source:
			if source is GemSlot and source.card_data:
				source.card_data.equipped_gem = null
				source.update_display()
			target_slot.card_data.equipped_gem = gem
		
		target_slot.card_data.equipped_gem_position = drop_local_pos
		target_slot.update_display()
		CombatEvents.gem_equip_changed.emit()
	
	elif target_unequip:
		if source is GemSlot and source.card_data:
			source.card_data.equipped_gem = null
			source.update_display()
		CombatEvents.gem_equip_changed.emit()
	
	_cancel_drag()

func _find_slot_at(mouse_pos: Vector2) -> GemSlot:
	var best_slot: GemSlot = null
	var best_z: int = -999999
	
	for candidate in get_tree().get_nodes_in_group("gem_slots"):
		if not candidate.get_global_rect().has_point(mouse_pos):
			continue
		var card_parent = candidate.get_parent()
		var z: int = card_parent.z_index if card_parent else 0
		if best_slot == null or z >= best_z:
			best_slot = candidate
			best_z = z
	
	return best_slot

func _find_unequip_zone_at(mouse_pos: Vector2) -> Node:
	for candidate in get_tree().get_nodes_in_group("gem_unequip_zones"):
		if candidate.get_global_rect().has_point(mouse_pos):
			return candidate
	return null

func _cancel_drag() -> void:
	CombatEvents.dragging_gem = null
	CombatEvents.dragging_gem_source = null
	if active_ghost and is_instance_valid(active_ghost):
		active_ghost.queue_free()
		active_ghost = null
	update_display()
