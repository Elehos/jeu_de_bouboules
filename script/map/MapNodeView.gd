extends Area2D
class_name MapNodeView

signal node_clicked(map_node: MapNode)

var map_node: MapNode

@export var combat_icon: Texture2D
@export var start_icon: Texture2D
# Optionnel : si aucune texture n'est assignée ici, le nœud de boss (type
# END) réutilise combat_icon en attendant un visuel dédié.
@export var boss_icon: Texture2D
# Optionnel : si aucune texture n'est assignée ici, un nœud d'événement
# réutilise start_icon en attendant un visuel dédié.
@export var event_icon: Texture2D

@onready var icon: Sprite2D = $Icon

func setup(data: MapNode) -> void:
	map_node = data
	input_event.connect(_on_input_event)
	_update_icon()

func _update_icon() -> void:
	match map_node.type:
		MapNode.NodeType.START:
			icon.texture = start_icon
		MapNode.NodeType.COMBAT:
			icon.texture = combat_icon
		MapNode.NodeType.END:
			icon.texture = boss_icon if boss_icon else combat_icon
		MapNode.NodeType.EVENT:
			icon.texture = event_icon if event_icon else start_icon

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not is_accessible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		node_clicked.emit(map_node)

var is_accessible: bool = false

func set_state(is_current: bool, accessible: bool) -> void:
	is_accessible = accessible
	
	if is_current:
		modulate = Color(1.0, 1.0, 0.0, 1.0)       # jaune : position actuelle
	elif accessible:
		modulate = Color(1, 1, 1)       # blanc : accessible, cliquable
	else:
		modulate = Color(0.4, 0.4, 0.4) # gris : pas encore accessible
