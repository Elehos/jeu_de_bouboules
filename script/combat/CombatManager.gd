extends Node
class_name CombatManager

# Les différents états possibles du combat
enum TurnState { PLAYER_TURN, ENEMY_TURN, TRANSITION }

# État courant du combat, on démarre toujours au tour du joueur
var current_state: TurnState = TurnState.PLAYER_TURN

# Références aux nœuds de la scène, récupérées automatiquement au lancement
@onready var player: Character = $WorldRoot/Player
@onready var end_turn_button: Button = $UI/EndTurnButton
@onready var current_mana_label: Label = $UI/ManaIcon/ManaLabel/CurrentManaLabel
@onready var max_mana_label: Label = $UI/ManaIcon/ManaLabel/MaxManaLabel
@onready var end_screen: Panel = $UI/EndScreen
@onready var end_label: Label = $UI/EndScreen/EndLabel
@onready var restart_button: Button = $UI/EndScreen/RestartButton
@onready var draw_count_label: Label = $UI/DrawPileIcon/DrawCountLabel
@onready var discard_count_label: Label = $UI/DiscardPileIcon/DiscardCountLabel
@onready var world_root: Node2D = $WorldRoot
@onready var card_list_popup: CardListPopup = $UI/CardListPopup
@onready var draw_pile_icon: Control = $UI/DrawPileIcon
@onready var discard_pile_icon: Control = $UI/DiscardPileIcon

var combat_over: bool = false
@onready var enemy_zone_center: Marker2D = $WorldRoot/EnemyZoneCenter
@export var enemy_spacing: float = 300.0
@export var enemy_scene: PackedScene  # glisse Enemy.tscn dans l'Inspecteur

var enemies: Array[Enemy] = []

# Signaux émis pour prévenir d'autres scripts (UI, animations...) qu'un tour démarre/finit
signal turn_started(state: TurnState)
signal turn_ended(state: TurnState)

@export var possible_encounters: Array[EncounterData] = []
var current_encounter: EncounterData


func _ready() -> void:
	current_encounter = possible_encounters.pick_random()
	print("Combat choisi : ", current_encounter.encounter_name)
	spawn_enemies()
	CombatEvents.deck_counts_changed.connect(_on_deck_counts_changed)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	turn_started.connect(_on_turn_started)
	CombatEvents.card_played.connect(_on_card_played)
	CombatEvents.mana_changed.connect(_on_mana_changed)
	player.died.connect(_on_player_died)
	restart_button.pressed.connect(_on_restart_pressed)
	player.damage_taken.connect(_on_damage_taken)
	draw_pile_icon.gui_input.connect(_on_draw_pile_input)
	discard_pile_icon.gui_input.connect(_on_discard_pile_input)
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
			for e in enemies:
				if is_instance_valid(e):
					e.reset_block()
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
	for e in enemies:
		if is_instance_valid(e):
			await get_tree().create_timer(0.5).timeout
			e.execute_intention(player)
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
	current_mana_label.text = str(current)
	max_mana_label.text = str(max)
	
func _on_player_died() -> void:
	show_end_screen("Défaite...")

func _on_enemy_died(dead_enemy: Enemy) -> void:
	enemies.erase(dead_enemy)
	dead_enemy.queue_free()
	
	var all_dead = true
	for e in enemies:
		if is_instance_valid(e):
			all_dead = false
			break
	
	if all_dead:
		show_end_screen("Victoire !")

func show_end_screen(text: String) -> void:
	combat_over = true
	end_label.text = text
	end_screen.visible = true
	
func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()

func _on_deck_counts_changed(draw_count: int, discard_count: int) -> void:
	draw_count_label.text = str(draw_count)
	discard_count_label.text = str(discard_count)
	
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

func _on_draw_pile_clicked() -> void:
	card_list_popup.show_cards(DeckManager.draw_pile, "Pioche")

func _on_discard_pile_clicked() -> void:
	card_list_popup.show_cards(DeckManager.discard_pile, "Défausse")

func _on_draw_pile_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_draw_pile_clicked()

func _on_discard_pile_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_discard_pile_clicked()

func spawn_enemies() -> void:
	var enemy_count: int = current_encounter.enemies.size()
	print("Nombre d'ennemis à spawn : ", enemy_count)
	
	for i in range(enemy_count):
		var slot: EncounterEnemySlot = current_encounter.enemies[i]
		var new_enemy: Enemy = enemy_scene.instantiate()
		new_enemy.enemy_data = slot.enemy_data
		new_enemy.intention_override = slot.intention_override
		world_root.add_child(new_enemy)
		new_enemy.global_position = _compute_enemy_position(i, enemy_count)
		enemies.append(new_enemy)
		new_enemy.died.connect(_on_enemy_died.bind(new_enemy))
		new_enemy.damage_taken.connect(_on_damage_taken)

func _compute_enemy_position(index: int, total: int) -> Vector2:
	var offset_x: float = (index - (total - 1) / 2.0) * enemy_spacing
	return enemy_zone_center.global_position + Vector2(offset_x, 0)
