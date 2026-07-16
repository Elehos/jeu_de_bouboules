extends Resource
class_name CardData

@export var card_name: String = ""
@export var cost: int = 1
@export var description: String = ""

# Effets (à 0 = pas d'effet de ce type sur cette carte)
@export var damage: int = 0
@export var block: int = 0
