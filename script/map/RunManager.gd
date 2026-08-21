extends Node

var floors: Array[Array] = []
var current_floor_index: int = 0
var current_position_in_floor: int = 0
var map_generated: bool = false
# Mis à true par MapView juste avant de lancer le combat du dernier nœud de
# l'arbre (type END) : CombatManager pioche alors dans possible_boss_encounters
# au lieu de possible_encounters.
var is_boss_combat: bool = false
# Mis par MapView juste avant de lancer un nœud d'événement (type EVENT) :
# EventView lit cette donnée à son _ready() puis la remet à null.
var pending_event: EventData = null

# Un PlayerState par joueur de la partie (un seul pour l'instant). Vide tant
# que start_new_run() n'a pas tourné — ne jamais appeler get_local_player()
# avant ça.
var players: Array[PlayerState] = []

func start_new_run(floor_count: int = 8, starting_deck: Array[CardData] = [], starting_gems: Array[GemData] = []) -> void:
	var generator := MapGenerator.new()
	floors = generator.generate_map(floor_count)
	current_floor_index = 0
	current_position_in_floor = 0
	map_generated = true

	players.clear()
	var local_player := PlayerState.new()
	for card in starting_deck:
		local_player.deck.append(card.duplicate(true))
	for gem in starting_gems:
		local_player.owned_gems.append(gem.duplicate(true))
	players.append(local_player)

func get_local_player() -> PlayerState:
	return players[0]

func get_current_node() -> MapNode:
	return floors[current_floor_index][current_position_in_floor]

func move_to(map_node: MapNode) -> void:
	current_floor_index = map_node.floor_index
	current_position_in_floor = map_node.position_in_floor
