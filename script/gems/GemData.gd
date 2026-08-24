extends Resource
class_name GemData

@export var gem_name: String = ""
@export var description: String = ""
@export var icon: Texture2D

@export var damage_bonus: int = 0
@export var heal_on_play: int = 0
@export var shield_on_play: int = 0

@export var allowed_card_type: CardData.CardType = CardData.CardType.ATTACK

# Chemin de la ressource statique (.tres) d'origine dont cette instance a été
# dupliquée — resource_path est vidé par Godot sur toute copie (pour ne
# jamais entrer en collision avec l'original dans le cache de ressources),
# donc c'est le seul moyen fiable de retrouver le template pour la
# resynchronisation réseau.
var template_path: String = ""
