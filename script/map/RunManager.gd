extends Node

var floors: Array[Array] = []
var current_floor_index: int = 0
var current_position_in_floor: int = 0
var map_generated: bool = false
var player_current_hp: int = -1  # -1 = pas encore initialisé (premier combat)
var player_max_hp: int = 50      # valeur de secours si jamais rien n'est encore défini

func start_new_run(floor_count: int = 8) -> void:
	var generator := MapGenerator.new()
	floors = generator.generate_map(floor_count)
	current_floor_index = 0
	current_position_in_floor = 0
	map_generated = true

func get_current_node() -> MapNode:
	return floors[current_floor_index][current_position_in_floor]

func move_to(map_node: MapNode) -> void:
	current_floor_index = map_node.floor_index
	current_position_in_floor = map_node.position_in_floor
