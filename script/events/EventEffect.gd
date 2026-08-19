extends Resource
class_name EventEffect

enum EffectType { HEAL, DAMAGE, GAIN_CARD, REMOVE_RANDOM_CARD, GAIN_GEM }

@export var type: EffectType = EffectType.HEAL
@export var amount: int = 0        # PV concernés, pour HEAL / DAMAGE
@export var card: CardData = null  # carte concernée, pour GAIN_CARD
@export var gem: GemData = null    # gemme concernée, pour GAIN_GEM

func get_description() -> String:
	match type:
		EffectType.HEAL:
			return "+%d PV" % amount
		EffectType.DAMAGE:
			return "-%d PV" % amount
		EffectType.GAIN_CARD:
			return "+ carte : " + (card.card_name if card else "?")
		EffectType.REMOVE_RANDOM_CARD:
			return "- une carte au hasard du deck"
		EffectType.GAIN_GEM:
			return "+ gemme : " + (gem.gem_name if gem else "?")
		_:
			return ""

func is_positive() -> bool:
	return type == EffectType.HEAL or type == EffectType.GAIN_CARD or type == EffectType.GAIN_GEM
