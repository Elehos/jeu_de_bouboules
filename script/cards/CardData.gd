extends Resource
class_name CardData

@export var card_name: String = ""
@export var cost: int = 1
@export var description: String = ""

@export var damage: int = 0
@export var block: int = 0

@export var requires_target: bool = false

# Gem équipée sur cet exemplaire précis de la carte
@export var equipped_gem: GemData = null

func get_effective_damage() -> int:
	var bonus: int = 0
	if equipped_gem:
		bonus = equipped_gem.damage_bonus
	return damage + bonus
