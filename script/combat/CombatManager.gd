extends Node
class_name CombatManager

# Les différents états possibles du combat
enum TurnState { PLAYER_TURN, ENEMY_TURN, TRANSITION }

# État courant du combat, on démarre toujours au tour du joueur
var current_state: TurnState = TurnState.PLAYER_TURN

# Références aux nœuds de la scène, récupérées automatiquement au lancement
@onready var player: Character = $Player
@onready var enemy: Enemy = $Enemy
@onready var end_turn_button: Button = $UI/EndTurnButton

# Signaux émis pour prévenir d'autres scripts (UI, animations...) qu'un tour démarre/finit
signal turn_started(state: TurnState)
signal turn_ended(state: TurnState)


func _ready() -> void:
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	turn_started.connect(_on_turn_started)
	CombatEvents.card_played.connect(_on_card_played)
	start_turn(TurnState.PLAYER_TURN)


func start_turn(state: TurnState) -> void:
	# Met à jour l'état courant et prévient les autres scripts
	current_state = state
	turn_started.emit(state)
	
	# Déclenche l'action propre à ce tour
	match state:
		TurnState.PLAYER_TURN:
			player.reset_block()
		TurnState.ENEMY_TURN:
			# L'ennemi joue automatiquement son tour
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
	# Sécurité : on ne termine le tour que si c'est bien celui du joueur
	if current_state == TurnState.PLAYER_TURN:
		end_turn()


func _on_turn_started(state: TurnState) -> void:
	# Désactive le bouton "Fin de tour" sauf pendant le tour du joueur
	end_turn_button.disabled = (state != TurnState.PLAYER_TURN)
	
func _on_card_played(card_data: CardData) -> void:
	if current_state != TurnState.PLAYER_TURN:
		return
	
	if card_data.damage > 0:
		enemy.take_damage(card_data.damage)
	
	if card_data.block > 0:
		player.gain_block(card_data.block)
