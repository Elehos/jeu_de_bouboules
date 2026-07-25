extends Node2D
class_name MapView

@export var map_node_scene: PackedScene   # glisse MapNodeView.tscn dans l'Inspecteur
@export var floor_spacing: float = 200.0  # distance verticale entre étages
@export var node_spacing: float = 150.0   # distance horizontale entre nœuds d'un même étage
@export var view_offset: Vector2 = Vector2(200, 540)  # centre horizontal, bas de l'écran (le départ en bas, la fin en haut)
@export var starting_deck: Array[CardData] = []

@onready var gem_bag_button: TextureButton = $UI/GemBagPanel/GemBagButton
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
			node_view.position = Vector2(x, y) + view_offset
			
			node_view.node_clicked.connect(_on_node_clicked)
			views_this_floor.append(node_view)
		
		node_views.append(views_this_floor)
	_draw_connections()
	_update_node_states()

func _draw_connections() -> void:
	for f in range(floors.size() - 1):
		var current_floor: Array = floors[f]
		var current_views: Array = node_views[f]
		var next_views: Array = node_views[f + 1]
		
		for i in range(current_floor.size()):
			var node_data: MapNode = current_floor[i]
			var from_view: MapNodeView = current_views[i]
			
			for target_index in node_data.connections:
				var to_view: MapNodeView = next_views[target_index]
				var line := Line2D.new()
				line.add_point(from_view.position)
				line.add_point(to_view.position)
				line.width = 4.0
				line.default_color = Color(1, 1, 1, 0.6)
				nodes_container.add_child(line)
				nodes_container.move_child(line, 0)  # les lignes passent DERRIÈRE les nœuds

func _on_node_clicked(map_node: MapNode) -> void:
	RunManager.move_to(map_node)
	current_floor_index = map_node.floor_index
	current_position_in_floor = map_node.position_in_floor
	_update_node_states()
	
	if map_node.type == MapNode.NodeType.COMBAT:
		_start_combat()

func _start_combat() -> void:
	get_tree().change_scene_to_file("res://scenes/combat/Combat.tscn")
	
func _ready() -> void:
	GemInventory.gems_locked = false
	gem_bag_button.pressed.connect(gem_bag_panel.toggle)
	if not RunManager.map_generated:
		RunManager.start_new_run(8, starting_deck)
	
	current_floor_index = RunManager.current_floor_index
	current_position_in_floor = RunManager.current_position_in_floor
	display_map(RunManager.floors)


func _is_node_accessible(node_data: MapNode) -> bool:
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
