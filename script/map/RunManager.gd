extends Node

var floors: Array[Array] = []
var current_floor_index: int = 0
var current_position_in_floor: int = 0
var map_generated: bool = false
var player_current_hp: int = -1  # -1 = pas encore initialisé (premier combat)
var player_max_hp: int = 50      # valeur de secours si jamais rien n'est encore défini
var player_deck: Array[CardData] = []
# Mis à true par MapView juste avant de lancer le combat du dernier nœud de
# l'arbre (type END) : CombatManager pioche alors dans possible_boss_encounters
# au lieu de possible_encounters.
var is_boss_combat: bool = false
# Mis par MapView juste avant de lancer un nœud d'événement (type EVENT) :
# EventView lit cette donnée à son _ready() puis la remet à null.
var pending_event: EventData = null
# Vrai une fois que le joueur a cliqué sur la case de départ (type START) et
# résolu MapView.starting_event : empêche de la relancer en la recliquant.
var starting_event_resolved: bool = false

func start_new_run(floor_count: int = 8, starting_deck: Array[CardData] = []) -> void:
	var generator := MapGenerator.new()
	floors = generator.generate_map(floor_count)
	current_floor_index = 0
	current_position_in_floor = 0
	map_generated = true
	starting_event_resolved = false

	player_deck.clear()
	for card in starting_deck:
		player_deck.append(card.duplicate(true))

func get_current_node() -> MapNode:
	return floors[current_floor_index][current_position_in_floor]

func move_to(map_node: MapNode) -> void:
	current_floor_index = map_node.floor_index
	current_position_in_floor = map_node.position_in_floor
