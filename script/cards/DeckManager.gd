extends Node

# shuffle == false : remplit la pioche sans consommer un seul tirage de
# run_rng. Nécessaire quand la scène de combat est chargée sans qu'aucun tour
# n'y soit joué (réaffichage des récompenses après rechargement, cf.
# Hand._ready()) — la pioche/défausse restent affichées correctement, mais
# l'état du RNG reste exactement celui restauré depuis la sauvegarde.
func setup_deck(player: PlayerState, shuffle: bool = true) -> void:
	player.draw_pile.clear()
	player.draw_pile.append_array(player.deck)
	if shuffle:
		RngUtils.shuffle(RunManager.run_rng, player.draw_pile)
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
	RngUtils.shuffle(RunManager.run_rng, player.draw_pile)
	player.discard_pile.clear()
	_notify_counts(player)

func _notify_counts(player: PlayerState) -> void:
	CombatEvents.deck_counts_changed.emit(player.draw_pile.size(), player.discard_pile.size())

# Combine pioche + défausse : l'intégralité du deck, peu importe l'avancée du combat
func get_full_deck(player: PlayerState) -> Array[CardData]:
	return player.draw_pile + player.discard_pile
