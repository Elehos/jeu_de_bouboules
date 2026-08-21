extends Node

func setup_deck(player: PlayerState) -> void:
	player.draw_pile.clear()
	player.draw_pile.append_array(player.deck)
	player.draw_pile.shuffle()
	player.discard_pile.clear()
	_notify_counts(player)

func draw_card(player: PlayerState) -> CardData:
	if player.draw_pile.is_empty():
		reshuffle_discard_into_draw(player)
	if player.draw_pile.is_empty():
		return null
	var card = player.draw_pile.pop_back()
	_notify_counts(player)
	return card

func discard_card(player: PlayerState, card_data: CardData) -> void:
	player.discard_pile.append(card_data)
	_notify_counts(player)

func reshuffle_discard_into_draw(player: PlayerState) -> void:
	player.draw_pile = player.discard_pile.duplicate()
	player.draw_pile.shuffle()
	player.discard_pile.clear()
	_notify_counts(player)

func _notify_counts(player: PlayerState) -> void:
	CombatEvents.deck_counts_changed.emit(player.draw_pile.size(), player.discard_pile.size())

# Combine pioche + défausse : l'intégralité du deck, peu importe l'avancée du combat
func get_full_deck(player: PlayerState) -> Array[CardData]:
	return player.draw_pile + player.discard_pile
