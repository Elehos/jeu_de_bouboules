extends Area2D
class_name MapNodeView

signal node_clicked(map_node: MapNode)

var map_node: MapNode

func setup(data: MapNode) -> void:
	map_node = data
	input_event.connect(_on_input_event)

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not is_accessible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		node_clicked.emit(map_node)

var is_accessible: bool = false

func set_state(is_current: bool, accessible: bool) -> void:
	is_accessible = accessible
	
	if is_current:
		modulate = Color(1, 1, 0)       # jaune : position actuelle
	elif accessible:
		modulate = Color(1, 1, 1)       # blanc : accessible, cliquable
	else:
		modulate = Color(0.4, 0.4, 0.4) # gris : pas encore accessible
