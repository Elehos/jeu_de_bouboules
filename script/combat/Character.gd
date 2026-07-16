extends CharacterBody2D


# --- Statistiques de base ---
@export var max_hp: int = 50
var current_hp: int

# Référence au Label qui affiche les PV (à assigner dans l'éditeur ou via le chemin du nœud)
@onready var hp_label: Label = $HP

func _ready() -> void:
	current_hp = max_hp
	update_hp_display()
	take_damage(100)  # ligne de test temporaire

# Applique des dégâts au personnage
func take_damage(amount: int) -> void:
	current_hp -= amount
	current_hp = max(current_hp, 0)  # empêche les PV négatifs
	update_hp_display()

	if current_hp <= 0:
		die()

# Soigne le personnage (utile plus tard pour les cartes de soin)
func heal(amount: int) -> void:
	current_hp += amount
	current_hp = min(current_hp, max_hp)  # empêche de dépasser le max
	update_hp_display()

# Met à jour l'affichage des PV
func update_hp_display() -> void:
	if hp_label:
		hp_label.text = str(current_hp) + " / " + str(max_hp)

# Appelé quand les PV tombent à 0
func die() -> void:
	print(name + " est mort.")
	# Plus tard : jouer une animation, retirer le personnage du combat, etc.
