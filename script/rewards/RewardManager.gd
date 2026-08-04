extends Node

var all_possible_cards: Array[CardData] = []
var all_possible_gems: Array[GemData] = []

func _ready() -> void:
	all_possible_cards = [
		load("res://ressoucesCards/attackCard.tres"),
		load("res://ressoucesCards/defenseCard.tres"),
		load("res://ressoucesCards/superAttackCard.tres"),
		load("res://ressoucesCards/manaCard.tres")
		# ajoute ici tous tes autres fichiers .tres de cartes
	]
	
	all_possible_gems = [
		load("res://ressourcesGems/ruby1.tres"),
		load("res://ressourcesGems/heal1_gem.tres"),
		# ajoute ici tous tes autres fichiers .tres de gemmes
	]

func get_random_cards(count: int = 3) -> Array[CardData]:
	var pool: Array = all_possible_cards.duplicate()
	pool.shuffle()
	var result: Array[CardData] = []
	for i in range(min(count, pool.size())):
		result.append(pool[i])
	return result

func get_random_gem() -> GemData:
	if all_possible_gems.is_empty():
		return null
	return all_possible_gems[randi() % all_possible_gems.size()]
