extends Node

var draw_pile: Array[CardData] = []
var discard_pile: Array[CardData] = []

func setup_deck(starting_deck: Array[CardData]) -> void:
	draw_pile = starting_deck.duplicate()
	draw_pile.shuffle()
	discard_pile.clear()
	_notify_counts()

func draw_card() -> CardData:
	if draw_pile.is_empty():
		reshuffle_discard_into_draw()
	if draw_pile.is_empty():
		return null
	var card = draw_pile.pop_back()
	_notify_counts()
	return card

func discard_card(card_data: CardData) -> void:
	discard_pile.append(card_data)
	_notify_counts()

func reshuffle_discard_into_draw() -> void:
	draw_pile = discard_pile.duplicate()
	draw_pile.shuffle()
	discard_pile.clear()
	print("Pioche vide : défausse mélangée dans la pioche.")
	_notify_counts()

func _notify_counts() -> void:
	CombatEvents.deck_counts_changed.emit(draw_pile.size(), discard_pile.size())
