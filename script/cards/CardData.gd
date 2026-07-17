extends Resource
class_name CardData

@export var card_name: String = ""
@export var cost: int = 1
@export var description: String = ""

@export var damage: int = 0
@export var block: int = 0

# true = la carte doit être jouée sur une cible précise (ex : cartes de dégâts)
@export var requires_target: bool = false
