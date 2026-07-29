extends Node

@export var all_possible_cards: Array[CardData] = []
@export var all_possible_gems: Array[GemData] = []

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
