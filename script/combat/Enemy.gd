extends Character
class_name Enemy

# Les actions possibles pour l'ennemi
enum IntentionType { ATTACK, DEFEND }

# La séquence d'intentions à suivre, dans l'ordre, en boucle
# Modifiable directement dans l'inspecteur Godot (case Enemy)
@export var intention_sequence: Array[IntentionType] = [
	IntentionType.ATTACK,
	IntentionType.ATTACK,
	IntentionType.DEFEND
]

# Où on en est dans la séquence
var sequence_index: int = 0

# L'intention actuelle, visible pendant le tour du joueur
var current_intention: IntentionType

# Référence au Label qui affiche l'intention
@onready var sprite: Sprite2D = $Sprite2D
@onready var intention_label: Label = $IntentionLabel

@onready var target_highlight: Node2D = $TargetHighlight

# Signal émis à chaque fois que l'intention change
signal intention_changed(intention: IntentionType)

@export var enemy_data: EnemyData
var intention_override: Array[Enemy.IntentionType] = []

func _ready() -> void:
	if enemy_data:
		max_hp = enemy_data.max_hp
		attack_power = enemy_data.attack_power
		defense_power = enemy_data.defense_power
		if enemy_data.intention_sequence.size() > 0:
			intention_sequence = enemy_data.intention_sequence
		if enemy_data.sprite_texture:
			sprite.texture = enemy_data.sprite_texture
		sprite.scale = enemy_data.enemy_scale
	
	if intention_override.size() > 0:
		intention_sequence = intention_override
	
	super._ready()
	intention_changed.connect(_on_intention_changed)
	choose_intention()
	
	if intention_override.size() > 0:
		intention_sequence = intention_override
	
	super._ready()
	intention_changed.connect(_on_intention_changed)
	choose_intention()


func choose_intention() -> void:
	# Prend l'intention suivante dans la séquence définie
	current_intention = intention_sequence[sequence_index]
	intention_changed.emit(current_intention)
	
	# Avance dans la séquence, et revient au début une fois arrivé au bout (boucle)
	sequence_index = (sequence_index + 1) % intention_sequence.size()


func execute_intention(target: Character) -> void:
	match current_intention:
		IntentionType.ATTACK:
			target.take_damage(attack_power)
		IntentionType.DEFEND:
			gain_block(defense_power)
	choose_intention()


func _on_intention_changed(intention: IntentionType) -> void:
	match intention:
		IntentionType.ATTACK:
			intention_label.text = "⚔ Attaque (%d)" % attack_power
		IntentionType.DEFEND:
			intention_label.text = "🛡 Défense (%d)" % defense_power
			
func set_targeted(value: bool) -> void:
	target_highlight.set_active(value)
