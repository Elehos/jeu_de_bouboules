extends Control
class_name CardChoicePopup

signal choice_made(card_chosen: bool)

@export var card_scene: PackedScene   # glisse Card.tscn dans l'Inspecteur

@onready var cards_row: HBoxContainer = $Panel/VBoxContainer/CardsRow
@onready var skip_button: Button = $Panel/VBoxContainer/SkipButton

func _ready() -> void:
	skip_button.pressed.connect(_on_skip_pressed)

func show_choices(cards: Array[CardData]) -> void:
	for child in cards_row.get_children():
		child.queue_free()
	
	for card_data in cards:
		var card_instance: Card = card_scene.instantiate()
		cards_row.add_child(card_instance)
		card_instance.card_data = card_data
		card_instance.update_display()
		card_instance.set_interactive(false)
		card_instance.reward_mode = true
		card_instance.card_selected.connect(_on_card_clicked)
		
		await get_tree().process_frame   # ← attendre que le layout calcule sa vraie position
		card_instance.base_position = card_instance.position


func _on_card_clicked(card_data: CardData) -> void:
	RunManager.player_deck.append(card_data.duplicate(true))
	choice_made.emit(true)
	queue_free()
	

func _on_skip_pressed() -> void:
	choice_made.emit(false)
	queue_free()
