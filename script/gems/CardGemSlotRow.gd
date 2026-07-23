extends HBoxContainer
class_name CardGemSlotRow

@export var card_data: CardData

@onready var card_name_label: Label = $CardNameLabel
@onready var gem_slot: Panel = $GemSlot

func _ready() -> void:
	update_display()

func update_display() -> void:
	if card_data:
		card_name_label.text = card_data.card_name
