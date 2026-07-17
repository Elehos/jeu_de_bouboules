extends Node

signal card_played(card_data: CardData, target: Character)
signal mana_changed(current: int, max: int)
signal player_turn_started
signal deck_counts_changed(draw_count: int, discard_count: int)

signal targeting_started(card_data: CardData)
signal targeting_cancelled

var pending_card: Card = null

@export var max_mana: int = 3
var current_mana: int = max_mana

func refill_mana() -> void:
	current_mana = max_mana
	mana_changed.emit(current_mana, max_mana)

func try_spend_mana(amount: int) -> bool:
	if current_mana < amount:
		return false
	current_mana -= amount
	mana_changed.emit(current_mana, max_mana)
	return true

func request_targeting(card: Card) -> void:
	pending_card = card
	targeting_started.emit(card.card_data)

func cancel_targeting() -> void:
	pending_card = null
	targeting_cancelled.emit()

func resolve_target(target: Character) -> void:
	if pending_card:
		pending_card.confirm_play(target)
		pending_card = null
