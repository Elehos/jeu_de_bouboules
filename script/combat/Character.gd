extends CharacterBody2D
class_name Character

# --- Statistiques de base ---
@export var max_hp: int = 50
var current_hp: int
@export var attack_power: int = 10
@export var defense_power: int = 5

var current_block: int = 0

@onready var hp_label: Label = $HP
@onready var block_label: Label = $Block

# Signal émis quand le personnage meurt
signal died

func _ready() -> void:
	current_hp = max_hp
	update_hp_display()
	update_block_display()

func take_damage(amount: int) -> void:
	var remaining_damage: int = amount
	
	if current_block > 0:
		var absorbed: int = min(current_block, remaining_damage)
		current_block -= absorbed
		remaining_damage -= absorbed
		update_block_display()
	
	if remaining_damage > 0:
		current_hp -= remaining_damage
		current_hp = max(current_hp, 0)
		update_hp_display()
	
	if current_hp <= 0:
		die()

func heal(amount: int) -> void:
	current_hp += amount
	current_hp = min(current_hp, max_hp)
	update_hp_display()

func gain_block(amount: int) -> void:
	current_block += amount
	update_block_display()

func reset_block() -> void:
	current_block = 0
	update_block_display()

func update_hp_display() -> void:
	if hp_label:
		hp_label.text = str(current_hp) + " / " + str(max_hp)

func update_block_display() -> void:
	if block_label:
		block_label.text = "🛡 " + str(current_block) if current_block > 0 else ""

func die() -> void:
	print(name + " est mort.")
	died.emit()
