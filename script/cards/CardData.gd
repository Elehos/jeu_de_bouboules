extends Resource
class_name CardData

enum CardType { ATTACK, DEFENSE, SKILL }

@export var card_name: String = ""
@export var cost: int = 1
@export var description: String = ""
@export var card_type: CardType = CardType.ATTACK

@export var damage: int = 0
@export var block: int = 0

@export var requires_target: bool = false

@export var equipped_gem: GemData = null

func get_effective_damage() -> int:
	var bonus: int = 0
	if equipped_gem:
		bonus = equipped_gem.damage_bonus
	return damage + bonus

func get_type_label() -> String:
	match card_type:
		CardType.ATTACK:
			return "Attaque"
		CardType.DEFENSE:
			return "Défense"
		CardType.SKILL:
			return "Compétence"
		_:
			return ""
			
func get_display_description() -> String:
	if not description.contains("{damage}"):
		return description
	
	var effective: int = get_effective_damage()
	var damage_text: String = str(effective)
	
	if effective > damage:
		damage_text = "[color=#7CFC7C]" + damage_text + "[/color]"
	
	return description.replace("{damage}", damage_text)
