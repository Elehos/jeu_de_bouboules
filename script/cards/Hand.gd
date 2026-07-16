extends HBoxContainer
class_name Hand

@export var card_scene: PackedScene  # on y glissera Card.tscn depuis l'Inspecteur
@export var starting_cards: Array[CardData] = []  # tes CardData de test, à remplir dans l'Inspecteur

func _ready() -> void:
	for card_data in starting_cards:
		add_card(card_data)

func add_card(data: CardData) -> void:
	var card_instance = card_scene.instantiate()
	add_child(card_instance)
	card_instance.card_data = data
	card_instance.update_display()
