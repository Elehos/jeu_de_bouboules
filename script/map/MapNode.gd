extends Resource
class_name MapNode

enum NodeType { START, COMBAT, END }

@export var type: NodeType
@export var floor_index: int
@export var position_in_floor: int
@export var connections: Array[int] = []
var visited: bool = false
