extends Panel
class_name GemSlot

@export var card_data: CardData

@onready var equipped_icon: TextureRect = $EquippedIcon

func _ready() -> void:
	update_display()

func update_display() -> void:
	if not equipped_icon:
		return
	if card_data and card_data.equipped_gem:
		equipped_icon.texture = card_data.equipped_gem.icon
		equipped_icon.visible = true
	else:
		equipped_icon.visible = false

func _can_drop_data(_at_position: Vector2, data) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("gem_data"):
		return false
	
	var gem: GemData = data["gem_data"]
	if not card_data:
		return false
	
	return gem.allowed_card_type == card_data.card_type

func _drop_data(_at_position: Vector2, data) -> void:
	if data.has("source_slot") and data["source_slot"] == self:
		return
	
	if data.has("source_slot"):
		var source: GemSlot = data["source_slot"]
		source.card_data.equipped_gem = null
		source.update_display()
	
	if card_data:
		card_data.equipped_gem = data["gem_data"]
		update_display()
	
	CombatEvents.gem_equip_changed.emit()

func _get_drag_data(_at_position: Vector2) -> Variant:
	if not card_data or not card_data.equipped_gem:
		return null
	
	var gem: GemData = card_data.equipped_gem
	
	var preview := TextureRect.new()
	preview.texture = gem.icon
	preview.custom_minimum_size = Vector2(50, 50)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	set_drag_preview(preview)
	
	return {"gem_data": gem, "source_slot": self}
