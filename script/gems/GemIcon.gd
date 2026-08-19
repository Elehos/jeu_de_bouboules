extends Control
class_name GemIcon

@export var gem_data: GemData

@onready var label: Label = $Label
@onready var icon: TextureRect = $Icon

const ICON_SIZE: float = 60.0

var active_ghost: TextureRect = null

func _ready() -> void:
	update_display()

func update_display() -> void:
	visible = true
	if gem_data:
		label.text = gem_data.gem_name
		icon.texture = gem_data.icon

func _gui_input(event: InputEvent) -> void:
	if GemInventory.gems_locked:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		CombatEvents.dragging_gem = gem_data
		CombatEvents.dragging_gem_source = null
		
		var ui_layer: Node = get_tree().current_scene.get_node("UI")
		active_ghost = TextureRect.new()
		active_ghost.texture = gem_data.icon
		active_ghost.size = Vector2(ICON_SIZE, ICON_SIZE)
		active_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		active_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		active_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		active_ghost.top_level = true
		ui_layer.add_child(active_ghost)
		
		visible = false

func _process(_delta: float) -> void:
	if active_ghost and is_instance_valid(active_ghost):
		active_ghost.size = Vector2(ICON_SIZE, ICON_SIZE)
		active_ghost.global_position = get_global_mouse_position() - Vector2(ICON_SIZE, ICON_SIZE) / 2.0
		
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_resolve_drop()

func _resolve_drop() -> void:
	var mouse_pos: Vector2 = get_global_mouse_position()
	var target_slot: GemSlot = GemSlot.find_topmost_slot_at(get_tree(), mouse_pos)

	if target_slot and target_slot.card_data and (gem_data.allowed_card_type == CardData.CardType.ANY or gem_data.allowed_card_type == target_slot.card_data.card_type):
		var drop_local_pos: Vector2 = mouse_pos - target_slot.global_position
		if target_slot.tear_system_enabled and target_slot.card_data.equipped_gem:
			target_slot.card_data.mark_torn(target_slot.card_data.equipped_gem)
		target_slot.card_data.equipped_gem = gem_data
		target_slot.card_data.equipped_gem_position = drop_local_pos
		target_slot.update_display()
		CombatEvents.gem_equip_changed.emit()
	
	_cancel_drag()

func _cancel_drag() -> void:
	CombatEvents.dragging_gem = null
	CombatEvents.dragging_gem_source = null
	if active_ghost and is_instance_valid(active_ghost):
		active_ghost.queue_free()
		active_ghost = null
	update_display()
