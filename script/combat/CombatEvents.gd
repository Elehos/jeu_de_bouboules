extends Node

signal card_played(card_data: CardData, target: Character)
signal mana_changed(current: int, max: int)
signal player_turn_started
signal deck_counts_changed(draw_count: int, discard_count: int)
signal damage_taken(character: Character, amount: int)
signal targeting_cancelled
signal gem_equip_changed

var pending_card: Card = null
var targeting_arrow: TargetingArrow = null
var any_card_active: bool = false

var dragging_gem: GemData = null
var dragging_gem_source: Node = null

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

func gain_mana(amount: int) -> void:
	# Pas de plafond ici : le mana gagné peut dépasser le max pour ce tour
	# (comme une potion d'énergie), pour que la carte serve à jouer une carte en plus.
	current_mana += amount
	mana_changed.emit(current_mana, max_mana)

func request_targeting(card: Card) -> void:
	pending_card = card

func cancel_targeting() -> void:
	pending_card = null
	targeting_cancelled.emit()

func resolve_target(target: Character) -> void:
	if pending_card:
		if targeting_arrow:
			targeting_arrow.hide_arrow()
		pending_card.confirm_play(target)
		pending_card = null
