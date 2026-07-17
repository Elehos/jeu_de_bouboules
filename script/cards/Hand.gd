extends HBoxContainer
class_name Hand

@export var card_scene: PackedScene  # on y glissera Card.tscn depuis l'Inspecteur
@export var starting_cards: Array[CardData] = []  # tes CardData de test, à remplir dans l'Inspecteur
@export var deck_data: Array[CardData] = []  # ton deck complet, assigné dans l'Inspecteur
@export var cards_per_turn: int = 3

func _ready() -> void:
	CombatEvents.player_turn_started.connect(new_turn)
	DeckManager.setup_deck(deck_data)

func add_card(data: CardData) -> void:
	var card_instance = card_scene.instantiate()
	add_child(card_instance)
	card_instance.card_data = data
	card_instance.update_display()

func draw_hand() -> void:
	for i in range(cards_per_turn):
		var data = DeckManager.draw_card()
		if data:
			add_card(data)

func discard_hand() -> void:
	for card_instance in get_children():
		DeckManager.discard_card(card_instance.card_data)
		card_instance.queue_free()

func new_turn() -> void:
	discard_hand()
	draw_hand()
