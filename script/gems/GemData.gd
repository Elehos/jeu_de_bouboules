extends Resource
class_name GemData

@export var gem_name: String = ""
@export var description: String = ""
@export var icon: Texture2D

@export var damage_bonus: int = 0

@export var allowed_card_type: CardData.CardType = CardData.CardType.ATTACK
