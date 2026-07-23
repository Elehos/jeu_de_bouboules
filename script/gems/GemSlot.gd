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
	return typeof(data) == TYPE_DICTIONARY and data.has("gem_data")

func _drop_data(_at_position: Vector2, data) -> void:
	if card_data:
		card_data.equipped_gem = data["gem_data"]
		update_display()
