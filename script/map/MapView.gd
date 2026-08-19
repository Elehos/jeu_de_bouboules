extends Node2D
class_name MapView

@export var map_node_scene: PackedScene   # glisse MapNodeView.tscn dans l'Inspecteur
@export var floor_spacing: float = 200.0  # distance verticale entre étages
@export var node_spacing: float = 150.0   # distance horizontale entre nœuds d'un même étage
@export var view_offset: Vector2 = Vector2(200, 540)  # centre horizontal, bas de l'écran (le départ en bas, la fin en haut)
@export var starting_deck: Array[CardData] = []
@export var possible_events: Array[EventData] = []
# Événement fixe (pas tiré au hasard parmi possible_events) : se déclenche en
# cliquant sur la case de départ (type START), une seule fois par run. Laisse
# à null pour ne rien déclencher (la case de départ reste alors non cliquable).
@export var starting_event: EventData

@onready var gem_bag_button: Button = $UI/GemBagPanel/GemBagButton
@onready var gem_bag_panel: GemBag = $UI/GemBagPanel

@onready var nodes_container: Node2D = $NodesContainer

var floors: Array[Array] = []
var node_views: Array[Array] = []
var current_floor_index: int = 0
var current_position_in_floor: int = 0

func display_map(generated_floors: Array[Array]) -> void:
	floors = generated_floors
	node_views.clear()
	
	for f in range(floors.size()):
		var floor_nodes: Array = floors[f]
		var floor_height: float = (floor_nodes.size() - 1) * node_spacing
		var views_this_floor: Array = []
		
		for i in range(floor_nodes.size()):
			var node_data: MapNode = floor_nodes[i]
			var node_view: MapNodeView = map_node_scene.instantiate()
			nodes_container.add_child(node_view)
			node_view.setup(node_data)
			
			var x: float = f * floor_spacing
			var y: float = i * node_spacing - floor_height / 2
			#node_view.position = Vector2(x, y) + view_offset
			node_view.position = Vector2(x, y) + view_offset + node_data.visual_offset
			
			node_view.node_clicked.connect(_on_node_clicked)
			views_this_floor.append(node_view)
		
		node_views.append(views_this_floor)
	_draw_connections()
	_update_node_states()

@onready var connections_drawer: ConnectionsDrawer = $NodesContainer/ConnectionsDrawer

func _draw_connections() -> void:
	var segments: Array = []
	
	for f in range(floors.size() - 1):
		var current_floor: Array = floors[f]
		var current_views: Array = node_views[f]
		var next_views: Array = node_views[f + 1]
		
		for i in range(current_floor.size()):
			var node_data: MapNode = current_floor[i]
			var from_view: MapNodeView = current_views[i]
			
			for target_index in node_data.connections:
				var to_view: MapNodeView = next_views[target_index]
				segments.append({"from": from_view.position, "to": to_view.position})
	
	connections_drawer.set_segments(segments)

func _on_node_clicked(map_node: MapNode) -> void:
	RunManager.move_to(map_node)
	current_floor_index = map_node.floor_index
	current_position_in_floor = map_node.position_in_floor
	_update_node_states()
	
	match map_node.type:
		MapNode.NodeType.START:
			_start_starting_event()
		MapNode.NodeType.COMBAT:
			RunManager.is_boss_combat = false
			_start_combat()
		MapNode.NodeType.END:
			# Le nœud END est le dernier de l'arbre : c'est le combat de boss.
			RunManager.is_boss_combat = true
			_start_combat()
		MapNode.NodeType.EVENT:
			_start_event()

func _start_combat() -> void:
	get_tree().change_scene_to_file("res://scenes/combat/Combat.tscn")

func _start_event() -> void:
	if possible_events.is_empty():
		push_error("Possible Events est vide ! Assigne au moins un EventData dans l'inspecteur du nœud MapView.")
		return
	RunManager.pending_event = possible_events.pick_random()
	get_tree().change_scene_to_file("res://scenes/events/EventView.tscn")

func _start_starting_event() -> void:
	if not starting_event:
		return
	RunManager.starting_event_resolved = true
	RunManager.pending_event = starting_event
	get_tree().change_scene_to_file("res://scenes/events/EventView.tscn")

func _ready() -> void:
	GemInventory.gems_locked = false
	gem_bag_button.pressed.connect(gem_bag_panel.toggle)
	if not RunManager.map_generated:
		RunManager.start_new_run(8, starting_deck)

	current_floor_index = RunManager.current_floor_index
	current_position_in_floor = RunManager.current_position_in_floor
	display_map(RunManager.floors)


func _is_node_accessible(node_data: MapNode) -> bool:
	if node_data.type == MapNode.NodeType.START:
		var is_here: bool = node_data.floor_index == current_floor_index and node_data.position_in_floor == current_position_in_floor
		return is_here and starting_event != null and not RunManager.starting_event_resolved

	if node_data.floor_index != current_floor_index + 1:
		return false

	var current_node: MapNode = floors[current_floor_index][current_position_in_floor]
	return node_data.position_in_floor in current_node.connections
	
func _update_node_states() -> void:
	for f in range(node_views.size()):
		for i in range(node_views[f].size()):
			var view: MapNodeView = node_views[f][i]
			var data: MapNode = floors[f][i]
			
			var is_current: bool = (f == current_floor_index and i == current_position_in_floor)
			var is_accessible: bool = _is_node_accessible(data)
			
			view.set_state(is_current, is_accessible)
