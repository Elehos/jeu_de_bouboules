extends Control
class_name CardGemSlotRow

@export var card_data: CardData
@export var card_scene: PackedScene

@onready var gem_slot: GemSlot = $GemSlot

var card_instance: Card

func _ready() -> void:
	update_display()

func update_display() -> void:
	if card_instance:
		card_instance.queue_free()
	
	if card_data and card_scene:
		card_instance = card_scene.instantiate()
		card_instance.card_data = card_data
		add_child(card_instance)
		move_child(card_instance, 0)
		card_instance.set_interactive(false)
		custom_minimum_size = card_instance.size
	
	if gem_slot:
		gem_slot.card_data = card_data
		gem_slot.update_display()
