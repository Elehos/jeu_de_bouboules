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
		if not get_viewport().gui_is_dragging():
			active_ghost.queue_free()
			active_ghost = null

func _draw() -> void:
	if not get_viewport().gui_is_dragging():
		return
	
	var drag_data = get_viewport().gui_get_drag_data()
	if typeof(drag_data) != TYPE_DICTIONARY or not drag_data.has("gem_data"):
		return
	
	var gem: GemData = drag_data["gem_data"]
	if not card_data or gem.allowed_card_type == CardData.CardType.ANY or gem.allowed_card_type == card_data.card_type:
		return
	
	draw_line(Vector2.ZERO, size, FORBIDDEN_COLOR, FORBIDDEN_WIDTH)
	draw_line(Vector2(size.x, 0), Vector2(0, size.y), FORBIDDEN_COLOR, FORBIDDEN_WIDTH)

func _can_drop_data(_at_position: Vector2, data) -> bool:
	print("gems_locked: ", GemInventory.gems_locked, " | data valide: ", typeof(data) == TYPE_DICTIONARY and data.has("gem_data"), " | card_data: ", card_data)
	
	if GemInventory.gems_locked:
		return false
	if typeof(data) != TYPE_DICTIONARY or not data.has("gem_data"):
		return false
	
	var gem: GemData = data["gem_data"]
	if not card_data:
		return false
	
	print("gem type: ", gem.allowed_card_type, " | card type: ", card_data.card_type)
	
	return gem.allowed_card_type == CardData.CardType.ANY or gem.allowed_card_type == card_data.card_type

func _drop_data(at_position: Vector2, data) -> void:
	if data.has("source_slot") and data["source_slot"] == self:
		card_data.equipped_gem_position = at_position
		update_display()
		CombatEvents.gem_equip_changed.emit()
		return
	
	if data.has("source_slot"):
		var source: GemSlot = data["source_slot"]
		if source and source.card_data:
			source.card_data.equipped_gem = null
			source.update_display()
	
	if card_data:
		card_data.equipped_gem = data["gem_data"]
		card_data.equipped_gem_position = at_position
		update_display()
	
	CombatEvents.gem_equip_changed.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		if active_ghost and is_instance_valid(active_ghost):
			active_ghost.queue_free()
			active_ghost = null
		update_display()

func start_pickup_drag(gem: GemData) -> Dictionary:
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
	
	return {"gem_data": gem, "source_slot": self}
