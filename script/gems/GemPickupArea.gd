extends Control
class_name GemPickupArea

@onready var gem_slot: GemSlot = get_parent()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		gem_slot.start_pickup_drag()
