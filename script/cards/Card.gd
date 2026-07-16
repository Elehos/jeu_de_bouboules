extends Control
class_name Card

@export var card_data: CardData

@onready var name_label: Label = $Panel/VBoxContainer/CardName
@onready var cost_label: Label = $Panel/VBoxContainer/CardCost
@onready var description_label: Label = $Panel/VBoxContainer/CardDescription

func _ready() -> void:
	update_display()

func update_display() -> void:
	if card_data:
		name_label.text = card_data.card_name
		cost_label.text = str(card_data.cost)
		description_label.text = card_data.description
