extends Node
class_name CombatManager

# Les différents états possibles du combat
enum TurnState { PLAYER_TURN, ENEMY_TURN, TRANSITION }

# État courant du combat, on démarre toujours au tour du joueur
var current_state: TurnState = TurnState.PLAYER_TURN

# Références aux nœuds de la scène, récupérées automatiquement au lancement
@onready var player_zone_center: Marker2D = $WorldRoot/PlayerZoneCenter
@export var player_scene: PackedScene  # glisse player.tscn dans l'Inspecteur
@export var player_spacing: float = 300.0

var players: Array[Character] = []
var local_player: Character
var local_player_state: PlayerState

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
@onready var gem_bag_button: Button = $UI/GemBagPanel/GemBagButton
@onready var gem_bag: GemBag = $UI/GemBagPanel

var combat_over: bool = false
var _pending_victory: bool = false
# Ce joueur précis est tombé (0 PV), mais l'équipe continue — distinct de
# combat_over, qui ne devient vrai que sur une défaite d'équipe complète ou
# une victoire (sinon un joueur à terre arrêterait de recevoir les mises à
# jour réseau partagées, cf. _on_enemy_phase_started/_on_enemy_damage_received).
var is_down: bool = false
@onready var enemy_zone_center: Marker2D = $WorldRoot/EnemyZoneCenter
@export var enemy_spacing: float = 300.0
@export var enemy_scene: PackedScene  # glisse Enemy.tscn dans l'Inspecteur

var enemies: Array[Enemy] = []

# Signaux émis pour prévenir d'autres scripts (UI, animations...) qu'un tour démarre/finit
signal turn_started(state: TurnState)
signal turn_ended(state: TurnState)

@export var possible_encounters: Array[EncounterData] = []
# Piochées à la place de possible_encounters quand RunManager.is_boss_combat
# est vrai (nœud END de l'arbre, cf. MapView._on_node_clicked).
@export var possible_boss_encounters: Array[EncounterData] = []
var current_encounter: EncounterData
@export var damage_number_scene: PackedScene  
@export var reward_popup_scene: PackedScene   

@onready var mana_ui_icon: TextureRect = $UI/ManaIcon/Icon
@export var mana_frames_texture: Texture2D

const MANA_FRAME_COUNT: int = 5
const MANA_ANIM_STEP_TIME: float = 0.05

var mana_frame_textures: Array[Texture2D] = []
var mana_ui_current_frame: int = 4
var mana_ui_anim_id: int = 0

# Résout current_encounter à partir du pool déjà choisi (possible_encounters
# ou possible_boss_encounters selon RunManager.is_boss_combat, décidé avant
# l'appel). En solo, comportement strictement identique à avant (aucun accès
# réseau). En multi, l'hôte tire l'indice et le diffuse ; le client l'attend
# si besoin. pending_encounter_index est vérifié AVANT tout await : si le RPC
# est déjà arrivé (cas le plus probable — l'hôte atteint son propre _ready()
# sans latence réseau, le client est encore en train de recevoir), on
# l'utilise tout de suite sans jamais attendre un signal déjà émis.
func _resolve_encounter(pool: Array[EncounterData]) -> EncounterData:
	if RunManager.run_peer_ids.size() <= 1:
		return pool.pick_random()
	if NetworkManager.is_host():
		var index: int = RunManager.choose_combat_encounter(pool.size())
		return pool[index]
	var index: int = RunManager.pending_encounter_index
	if index < 0:
		index = await RunManager.encounter_chosen
	RunManager.pending_encounter_index = -1
	return pool[index]

func _ready() -> void:
	# Défensif : si un combat multi précédent s'est terminé par une défaite
	# d'équipe et qu'on relance via "Recommencer", évite que downed_peer_ids
	# reste peuplé et bloque le tally de fin de tour dès le premier tour.
	RunManager.downed_peer_ids.clear()
	RunManager.pending_turn_ready.clear()
	RunManager.pending_combat_finished.clear()

	local_player_state = RunManager.get_local_player()
	local_player_state.gems_locked = true

	var encounter_pool: Array[EncounterData] = possible_boss_encounters if RunManager.is_boss_combat else possible_encounters
	if encounter_pool.is_empty():
		var pool_name: String = "Possible Boss Encounters" if RunManager.is_boss_combat else "Possible Encounters"
		push_error(pool_name + " est vide ! Assigne au moins un EncounterData dans l'inspecteur du nœud Combat.")
		return

	spawn_players()
	CombatEvents.damage_taken.connect(_on_damage_taken)
	current_encounter = await _resolve_encounter(encounter_pool)
	spawn_enemies()
	if local_player_state.current_hp >= 0:
		local_player.max_hp = local_player_state.max_hp
		local_player.current_hp = local_player_state.current_hp
		local_player.sync_hp_bars_instantly()
	else:
		local_player_state.max_hp = local_player.max_hp
		local_player_state.current_hp = local_player.current_hp

	CombatEvents.damage_taken.connect(_on_player_hp_changed)

	CombatEvents.deck_counts_changed.connect(_on_deck_counts_changed)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	turn_started.connect(_on_turn_started)
	RunManager.enemy_phase_started.connect(_on_enemy_phase_started)
	RunManager.team_wiped.connect(_on_team_wiped)
	RunManager.combat_finished.connect(_on_combat_finished)
	RunManager.enemy_damage_received.connect(_on_enemy_damage_received)
	for entry: Dictionary in RunManager.pending_enemy_damage:
		_on_enemy_damage_received(entry["spawn_id"], entry["amount"])
	RunManager.pending_enemy_damage.clear()
	CombatEvents.card_played.connect(_on_card_played)
	CombatEvents.mana_changed.connect(_on_mana_changed)
	local_player.died.connect(_on_player_died)
	restart_button.pressed.connect(_on_restart_pressed)
	draw_pile_icon.gui_input.connect(_on_draw_pile_input)
	discard_pile_icon.gui_input.connect(_on_discard_pile_input)
	gem_bag_button.pressed.connect(gem_bag.toggle)
	_setup_mana_ui_frames()
	start_turn(TurnState.PLAYER_TURN)

func spawn_players() -> void:
	var my_id: int = multiplayer.get_unique_id()
	var player_count: int = RunManager.players.size()
	for i in range(player_count):
		var player_state: PlayerState = RunManager.players[i]
		var new_player: Character = player_scene.instantiate()
		world_root.add_child(new_player)
		new_player.global_position = _compute_player_position(i, player_count)
		players.append(new_player)
		if player_state.peer_id == my_id:
			local_player = new_player

func _compute_player_position(index: int, total: int) -> Vector2:
	var offset_x: float = (index - (total - 1) / 2.0) * player_spacing
	return player_zone_center.global_position + Vector2(offset_x, 0)
	


func start_turn(state: TurnState) -> void:
	current_state = state
	turn_started.emit(state)
	
	match state:
		TurnState.PLAYER_TURN:
			local_player.reset_block()
			CombatEvents.refill_mana(local_player_state)
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
			e.execute_intention(local_player)
	end_turn()


func _on_end_turn_pressed() -> void:
	if combat_over or is_down:
		return
	if current_state == TurnState.PLAYER_TURN:
		end_turn_button.disabled = true
		RunManager.submit_end_turn()


func _on_enemy_phase_started() -> void:
	if combat_over:
		return
	end_turn()


func _on_turn_started(state: TurnState) -> void:
	end_turn_button.disabled = (state != TurnState.PLAYER_TURN)
	if state == TurnState.PLAYER_TURN:
		end_turn_button.reveal_text()


func _on_card_played(card_data: CardData, target: Character) -> void:
	if combat_over or is_down:
		return
	if current_state != TurnState.PLAYER_TURN:
		return
	
	if card_data.damage > 0 and target:
		var dmg: int = card_data.get_effective_damage()
		target.take_damage(dmg)
		if target is Enemy:
			RunManager.submit_enemy_damage((target as Enemy).combat_spawn_id, dmg)

	if card_data.block > 0:
		local_player.gain_block(card_data.block)

	if card_data.mana_gain > 0:
		CombatEvents.gain_mana(local_player_state, card_data.mana_gain)

	if card_data.equipped_gem and card_data.equipped_gem.heal_on_play > 0:
		local_player.heal(card_data.equipped_gem.heal_on_play)


func _on_enemy_damage_received(spawn_id: int, amount: int) -> void:
	if combat_over:
		return
	var target_enemy: Enemy = _find_enemy_by_spawn_id(spawn_id)
	if target_enemy and is_instance_valid(target_enemy):
		target_enemy.take_damage(amount)


func _find_enemy_by_spawn_id(spawn_id: int) -> Enemy:
	for e in enemies:
		if is_instance_valid(e) and e.combat_spawn_id == spawn_id:
			return e
	return null


func _on_mana_changed(current: int, max: int) -> void:
	current_mana_label.text = str(current)
	max_mana_label.text = str(max)
	
	if current <= 0:
		_play_mana_ui_animation(0)
	else:
		_play_mana_ui_animation(MANA_FRAME_COUNT - 1)
	
func _on_player_died() -> void:
	if is_down:
		return
	is_down = true
	RunManager.submit_player_down()

func _on_team_wiped() -> void:
	show_end_screen("Défaite...", false)

func _on_enemy_died(dead_enemy: Enemy) -> void:
	enemies.erase(dead_enemy)
	dead_enemy.queue_free()  
	
	var all_dead = true
	for e in enemies:
		if is_instance_valid(e):
			all_dead = false
			break
	
	if all_dead:
		combat_over = true
		if is_down:
			is_down = false
			local_player_state.current_hp = 1
			local_player.current_hp = 1
			local_player.sync_hp_bars_instantly()
		_show_rewards()

func _show_rewards() -> void:
	var popup: RewardPopup = reward_popup_scene.instantiate()
	$UI.add_child(popup)

func _on_combat_finished() -> void:
	get_tree().change_scene_to_file("res://scenes/map/MapView.tscn")

func show_end_screen(text: String, is_victory: bool) -> void:
	combat_over = true
	end_label.text = text
	end_screen.visible = true
	
	if is_victory:
		restart_button.text = "Continuer"
	else:
		restart_button.text = "Recommencer"
	
	_pending_victory = is_victory
	
func _on_restart_pressed() -> void:
	if _pending_victory:
		get_tree().change_scene_to_file("res://scenes/map/MapView.tscn")
	else:
		get_tree().reload_current_scene()

func _on_deck_counts_changed(draw_count: int, discard_count: int) -> void:
	draw_count_label.text = str(draw_count)
	discard_count_label.text = str(discard_count)
	

func _on_damage_taken(character: Character, amount: int) -> void:
	var number_instance: DamageNumber = damage_number_scene.instantiate()
	get_tree().current_scene.add_child(number_instance)
	number_instance.global_position = character.global_position + Vector2(0, -80)
	number_instance.set_amount(amount)
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
	card_list_popup.show_cards(local_player_state.draw_pile, "Pioche")

func _on_discard_pile_clicked() -> void:
	card_list_popup.show_cards(local_player_state.discard_pile, "Défausse")

func _on_draw_pile_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_draw_pile_clicked()

func _on_discard_pile_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_discard_pile_clicked()

func spawn_enemies() -> void:
	var enemy_count: int = current_encounter.enemies.size()

	for i in range(enemy_count):
		var slot: EncounterEnemySlot = current_encounter.enemies[i]
		var new_enemy: Enemy = enemy_scene.instantiate()
		new_enemy.enemy_data = slot.enemy_data
		new_enemy.intention_override = slot.intention_override
		new_enemy.combat_spawn_id = i
		world_root.add_child(new_enemy)
		new_enemy.global_position = _compute_enemy_position(i, enemy_count)
		enemies.append(new_enemy)
		new_enemy.died.connect(_on_enemy_died.bind(new_enemy))

func _compute_enemy_position(index: int, total: int) -> Vector2:
	var offset_x: float = (index - (total - 1) / 2.0) * enemy_spacing
	return enemy_zone_center.global_position + Vector2(offset_x, 0)

func _on_player_hp_changed(character: Character, _amount: int) -> void:
	if character == local_player:
		local_player_state.current_hp = local_player.current_hp
		
func _setup_mana_ui_frames() -> void:
	if not mana_frames_texture:
		return
	
	var frame_width: float = mana_frames_texture.get_width() / float(MANA_FRAME_COUNT)
	var frame_height: float = mana_frames_texture.get_height()
	
	mana_frame_textures.clear()
	for i in range(MANA_FRAME_COUNT):
		var atlas := AtlasTexture.new()
		atlas.atlas = mana_frames_texture
		atlas.region = Rect2(i * frame_width, 0, frame_width, frame_height)
		mana_frame_textures.append(atlas)
	
	mana_ui_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mana_ui_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mana_ui_icon.texture = mana_frame_textures[mana_ui_current_frame]

func _play_mana_ui_animation(target_frame: int) -> void:
	if mana_frame_textures.is_empty():
		return
	
	mana_ui_anim_id += 1
	var my_id: int = mana_ui_anim_id
	var direction: int = 1 if target_frame > mana_ui_current_frame else -1
	
	while mana_ui_current_frame != target_frame:
		if my_id != mana_ui_anim_id:
			return
		mana_ui_current_frame += direction
		mana_ui_icon.texture = mana_frame_textures[mana_ui_current_frame]
		await get_tree().create_timer(MANA_ANIM_STEP_TIME).timeout
