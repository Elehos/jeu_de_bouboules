extends Control
class_name GemPickupArea

@onready var gem_slot: GemSlot = get_parent()

func _get_drag_data(_at_position: Vector2) -> Variant:
	if GemInventory.gems_locked:
		return null
	if not gem_slot.card_data or not gem_slot.card_data.equipped_gem:
		return null
	
	var gem: GemData = gem_slot.card_data.equipped_gem
	var result: Dictionary = gem_slot.start_pickup_drag(gem)
	
	var empty_preview := Control.new()
	set_drag_preview(empty_preview)
	
	return result
