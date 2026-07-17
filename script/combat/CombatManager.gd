extends Node
class_name CombatManager

# Les différents états possibles du combat
enum TurnState { PLAYER_TURN, ENEMY_TURN, TRANSITION }

# État courant du combat, on démarre toujours au tour du joueur
var current_state: TurnState = TurnState.PLAYER_TURN

# Références aux nœuds de la scène, récupérées automatiquement au lancement
@onready var player: Character = $WorldRoot/Player
@onready var enemy: Enemy = $WorldRoot/Enemy
@onready var end_turn_button: Button = $UI/EndTurnButton
@onready var mana_label: Label = $UI/ManaLabel
@onready var end_screen: Panel = $UI/EndScreen
@onready var end_label: Label = $UI/EndScreen/EndLabel
@onready var restart_button: Button = $UI/EndScreen/RestartButton
@onready var draw_count_label: Label = $UI/DrawCountLabel
@onready var discard_count_label: Label = $UI/DiscardCountLabel
@onready var world_root: Node2D = $WorldRoot

var combat_over: bool = false

# Signaux émis pour prévenir d'autres scripts (UI, animations...) qu'un tour démarre/finit
signal turn_started(state: TurnState)
signal turn_ended(state: TurnState)


func _ready() -> void:
	CombatEvents.deck_counts_changed.connect(_on_deck_counts_changed)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	turn_started.connect(_on_turn_started)
	CombatEvents.card_played.connect(_on_card_played)
	CombatEvents.mana_changed.connect(_on_mana_changed)
	player.died.connect(_on_player_died)
	enemy.died.connect(_on_enemy_died)
	restart_button.pressed.connect(_on_restart_pressed)
	player.damage_taken.connect(_on_damage_taken)
	enemy.damage_taken.connect(_on_damage_taken)
	start_turn(TurnState.PLAYER_TURN)


func start_turn(state: TurnState) -> void:
	current_state = state
	turn_started.emit(state)
	
	match state:
		TurnState.PLAYER_TURN:
			player.reset_block()
			CombatEvents.refill_mana()
			CombatEvents.player_turn_started.emit()
		TurnState.ENEMY_TURN:
			enemy.reset_block()
			enemy_play_turn()


func end_turn() -> void:
	# Prévient que le tour courant vient de se terminer
	turn_ended.emit(current_state)
	
	# Enchaîne automatiquement sur le tour suivant
	match current_state:
		TurnState.PLAYER_TURN:
			start_turn(TurnState.ENEMY_TURN)
		TurnState.ENEMY_TURN:
			start_turn(TurnState.PLAYER_TURN)


func enemy_play_turn() -> void:
	await get_tree().create_timer(0.5).timeout
	enemy.execute_intention(player) 
	end_turn()


func _on_end_turn_pressed() -> void:
	if combat_over:
		return
	if current_state == TurnState.PLAYER_TURN:
		end_turn()


func _on_turn_started(state: TurnState) -> void:
	# Désactive le bouton "Fin de tour" sauf pendant le tour du joueur
	end_turn_button.disabled = (state != TurnState.PLAYER_TURN)


func _on_card_played(card_data: CardData, target: Character) -> void:
	if combat_over:
		return
	if current_state != TurnState.PLAYER_TURN:
		return
	
	if card_data.damage > 0 and target:
		target.take_damage(card_data.damage)
	
	if card_data.block > 0:
		player.gain_block(card_data.block)
		
		
func _on_mana_changed(current: int, max: int) -> void:
	mana_label.text = "💧 " + str(current) + " / " + str(max)
	
func _on_player_died() -> void:
	show_end_screen("Défaite...")

func _on_enemy_died() -> void:
	show_end_screen("Victoire !")

func show_end_screen(text: String) -> void:
	combat_over = true
	end_label.text = text
	end_screen.visible = true
	
func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()

func _on_deck_counts_changed(draw_count: int, discard_count: int) -> void:
	draw_count_label.text = "🂠 " + str(draw_count)
	discard_count_label.text = "🗑 " + str(discard_count)
	
func _on_damage_taken(amount: int) -> void:
	shake_screen(amount)

func shake_screen(amount: int) -> void:
	# Ramène les dégâts entre 1 et 50 sur une échelle de 0.0 à 1.0
	var intensity: float = clamp(amount, 1, 50) / 50.0
	
	# Plus l'intensité est haute, plus le tremblement est fort et long
	var max_offset: float = lerp(1.0, 25.0, intensity)
	var duration: float = lerp(0.25, 0.35, intensity)
	
	var steps: int = 6
	var shake_tween: Tween = create_tween()
	
	for i in steps:
		var offset := Vector2(randf_range(-max_offset, max_offset), randf_range(-max_offset, max_offset))
		shake_tween.tween_property(world_root, "position", offset, duration / steps)
	
	# Revient exactement à sa position d'origine à la fin
	shake_tween.tween_property(world_root, "position", Vector2.ZERO, duration / steps)
