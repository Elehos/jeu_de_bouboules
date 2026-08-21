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

# Un PlayerState par joueur de la partie. Vide tant que start_new_run() /
# start_multiplayer_run() n'a pas tourné — ne jamais appeler get_local_player()
# avant ça.
var players: Array[PlayerState] = []

# IDs des pairs (multiplayer.get_unique_id()) participant au run courant,
# dans un ordre identique et partagé par tous — transmis explicitement par
# l'hôte plutôt que recalculé côté client (en topologie étoile, un client ne
# voit que l'hôte dans ses propres pairs, pas les autres clients).
var run_peer_ids: Array[int] = []
# true une fois players[] construit pour ce run (deck/gemmes de départ) —
# distinct de map_generated car côté client, la carte arrive par réseau avant
# que ce pair ait construit ses propres PlayerState.
var players_ready: bool = false

func _generate_map(floor_count: int) -> void:
	var generator := MapGenerator.new()
	floors = generator.generate_map(floor_count)
	current_floor_index = 0
	current_position_in_floor = 0
	map_generated = true
	players_ready = false

func start_new_run(floor_count: int = 8) -> void:
	_generate_map(floor_count)
	run_peer_ids = [multiplayer.get_unique_id()]

# Hôte uniquement : génère la carte (le RNG n'est pas seedé, chaque pair
# obtiendrait une carte différente s'il générait la sienne) et la diffuse.
func start_multiplayer_run(floor_count: int = 8) -> void:
	if not NetworkManager.is_host():
		push_error("start_multiplayer_run() doit être appelé uniquement par l'hôte.")
		return
	_generate_map(floor_count)
	run_peer_ids = [1]
	for id in multiplayer.get_peers():
		run_peer_ids.append(id)
	_receive_map.rpc(_serialize_floors(), run_peer_ids, current_floor_index, current_position_in_floor)

@rpc("authority", "call_remote", "reliable")
func _receive_map(serialized_floors: Array, peer_ids: Array, starting_floor_index: int, starting_position_in_floor: int) -> void:
	floors = _deserialize_floors(serialized_floors)
	current_floor_index = starting_floor_index
	current_position_in_floor = starting_position_in_floor
	map_generated = true
	players_ready = false
	run_peer_ids = []
	for id in peer_ids:
		run_peer_ids.append(id)
	get_tree().change_scene_to_file("res://scenes/map/MapView.tscn")

func _serialize_floors() -> Array:
	var out: Array = []
	for floor_nodes in floors:
		var floor_out: Array = []
		for node: MapNode in floor_nodes:
			floor_out.append({
				"type": node.type,
				"floor_index": node.floor_index,
				"position_in_floor": node.position_in_floor,
				"connections": node.connections.duplicate(),
				"visual_offset": node.visual_offset,
			})
		out.append(floor_out)
	return out

func _deserialize_floors(data: Array) -> Array[Array]:
	var out: Array[Array] = []
	for floor_data in data:
		var floor_nodes: Array[MapNode] = []
		for node_data: Dictionary in floor_data:
			var node := MapNode.new()
			node.type = node_data["type"]
			node.floor_index = node_data["floor_index"]
			node.position_in_floor = node_data["position_in_floor"]
			var conns: Array[int] = []
			for c in node_data["connections"]:
				conns.append(c)
			node.connections = conns
			node.visual_offset = node_data["visual_offset"]
			floor_nodes.append(node)
		out.append(floor_nodes)
	return out

# Construit players[] pour ce pair à partir de son propre contenu de départ
# local (deck/gemmes — fichiers identiques chez tous les pairs, donc jamais
# transmis par le réseau). Appelé depuis MapView._ready() car starting_deck/
# starting_gems sont des @export qui n'existent que sur cette instance de
# scène ; RunManager (autoload) n'y a pas accès directement.
func build_players_from_starting_content(starting_deck: Array[CardData], starting_gems: Array[GemData]) -> void:
	players.clear()
	for id in run_peer_ids:
		var state := PlayerState.new()
		state.peer_id = id
		for card in starting_deck:
			state.deck.append(card.duplicate(true))
		for gem in starting_gems:
			state.owned_gems.append(gem.duplicate(true))
		players.append(state)
	players_ready = true

func get_local_player() -> PlayerState:
	var my_id: int = multiplayer.get_unique_id()
	for p in players:
		if p.peer_id == my_id:
			return p
	push_error("get_local_player(): aucun PlayerState pour peer_id %d" % my_id)
	return null

func get_current_node() -> MapNode:
	return floors[current_floor_index][current_position_in_floor]

func move_to(map_node: MapNode) -> void:
	current_floor_index = map_node.floor_index
	current_position_in_floor = map_node.position_in_floor
