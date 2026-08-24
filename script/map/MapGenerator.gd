extends Node
class_name MapGenerator

# Probabilité qu'un emplacement de combat intermédiaire devienne un
# événement à la place, façon Slay the Spire.
const EVENT_CHANCE: float = 0.3

# RNG de la run en cours, transmis par RunManager._generate_map() —
# n'apparaît que le temps d'un appel à generate_map(), MapGenerator lui-même
# n'a aucune dépendance permanente vers l'autoload RunManager.
var rng: RandomNumberGenerator

func generate_map(floor_count: int, rng_in: RandomNumberGenerator) -> Array[Array]:
	rng = rng_in
	var floors: Array[Array] = []

	floors.append([_make_node(MapNode.NodeType.START, 0, 0)])

	for f in range(1, floor_count - 1):
		var nodes_in_floor: Array[MapNode] = []
		var count = rng.randi_range(2, 4) # ici pour changer le nombre de positions mini et maxi dans un étage intermédiaire
		for i in range(count):
			var node_type: MapNode.NodeType = MapNode.NodeType.EVENT if rng.randf() < EVENT_CHANCE else MapNode.NodeType.COMBAT
			nodes_in_floor.append(_make_node(node_type, f, i))
		floors.append(nodes_in_floor)
	
	floors.append([_make_node(MapNode.NodeType.END, floor_count - 1, 0)])
	
	_connect_floors(floors)
	_remove_crossings(floors)
	return floors

func _make_node(type: MapNode.NodeType, floor_idx: int, pos_idx: int) -> MapNode:
	var node := MapNode.new()
	node.type = type
	node.floor_index = floor_idx
	node.position_in_floor = pos_idx
	
	if type == MapNode.NodeType.COMBAT or type == MapNode.NodeType.EVENT:
		node.visual_offset = Vector2(
			randf_range(-35, 35),
			randf_range(-35, 35)
		)
	
	return node

func _connect_floors(floors: Array[Array]) -> void:
	for f in range(floors.size() - 1):
		var current_floor: Array = floors[f]
		var next_floor: Array = floors[f + 1]
		
		# Étage de départ ou d'arrivée : pas de restriction (un seul nœud de toute façon)
		var restrict_distance: bool = current_floor.size() > 1 and next_floor.size() > 1
		
		# Étape 1 : connexions aléatoires sortantes, limitées aux positions proches
		for node in current_floor:
			var possible_targets: Array = range(next_floor.size())
			
			if restrict_distance:
				var filtered: Array = possible_targets.filter(
					func(t): return abs(t - node.position_in_floor) <= 1
				)
				# Filet de sécurité : si aucune cible n'est assez proche, on élargit à la plus proche possible
				if filtered.is_empty():
					var closest: int = possible_targets[0]
					for t in possible_targets:
						if abs(t - node.position_in_floor) < abs(closest - node.position_in_floor):
							closest = t
					filtered = [closest]
				possible_targets = filtered
			
			RngUtils.shuffle(rng, possible_targets)
			var connection_count: int = 1 if next_floor.size() == 1 else rng.randi_range(1, 2)
			
			for c in range(min(connection_count, possible_targets.size())):
				node.connections.append(possible_targets[c])
		
		# Étape 2 : vérifier les orphelins, en respectant la même contrainte de distance
		for target_index in range(next_floor.size()):
			var has_incoming: bool = false
			for node in current_floor:
				if target_index in node.connections:
					has_incoming = true
					break
			
			if not has_incoming:
				var eligible_sources: Array = current_floor
				
				if restrict_distance:
					eligible_sources = current_floor.filter(
						func(n): return abs(target_index - n.position_in_floor) <= 1
					)
				
				if eligible_sources.is_empty():
					eligible_sources = current_floor  # filet de sécurité si jamais rien n'est proche
				
				var random_source: MapNode = eligible_sources[rng.randi_range(0, eligible_sources.size() - 1)]
				random_source.connections.append(target_index)

func _remove_crossings(floors: Array[Array]) -> void:
	for f in range(floors.size() - 1):
		var current_floor: Array = floors[f]
		var edges: Array = []
		
		for node in current_floor:
			for idx in range(node.connections.size()):
				edges.append({"node": node, "idx": idx})
		
		var changed: bool = true
		while changed:
			changed = false
			for a in range(edges.size()):
				for b in range(a + 1, edges.size()):
					var e1: Dictionary = edges[a]
					var e2: Dictionary = edges[b]
					var from1: int = e1["node"].position_in_floor
					var from2: int = e2["node"].position_in_floor
					var to1: int = e1["node"].connections[e1["idx"]]
					var to2: int = e2["node"].connections[e2["idx"]]
					
					if (from1 - from2) * (to1 - to2) < 0:
						e1["node"].connections[e1["idx"]] = to2
						e2["node"].connections[e2["idx"]] = to1
						changed = true
