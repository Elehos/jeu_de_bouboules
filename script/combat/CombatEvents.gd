extends Node

# Signal émis par n'importe quel script de carte quand une carte est jouée
signal card_played(card_data: CardData)

# Signal émis à chaque fois que le mana change (pour l'affichage)
signal mana_changed(current: int, max: int)

@export var max_mana: int = 3
var current_mana: int = max_mana

# Recharge le mana au max (appelé au début du tour du joueur)
func refill_mana() -> void:
	current_mana = max_mana
	mana_changed.emit(current_mana, max_mana)

# Tente de dépenser du mana. Retourne true si réussi, false si pas assez de mana
func try_spend_mana(amount: int) -> bool:
	if current_mana < amount:
		return false
	current_mana -= amount
	mana_changed.emit(current_mana, max_mana)
	return true
