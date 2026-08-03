extends Control
class_name GemIcon

@export var gem_data: GemData

@onready var label: Label = $Label
@onready var icon: TextureRect = $Icon

const ICON_SIZE: float = 60.0

var active_ghost: TextureRect = null

func _process(_delta: float) -> void:
	if active_ghost and is_instance_valid(active_ghost):
		active_ghost.size = Vector2(60, 60)
		active_ghost.global_position = get_global_mouse_position() - Vector2(20, 20)
		if not get_viewport().gui_is_dragging():
			active_ghost.queue_free()
			active_ghost = null

func _ready() -> void:
	update_display()

func update_display() -> void:
	visible = true
	if gem_data:
		label.text = gem_data.gem_name
		icon.texture = gem_data.icon

func _get_drag_data(_at_position: Vector2) -> Variant:
	print("GemIcon _get_drag_data appelée | gems_locked: ", GemInventory.gems_locked)
	
	if GemInventory.gems_locked:
		return null
	
	var ui_layer: Node = get_tree().current_scene.get_node("UI")
	active_ghost = TextureRect.new()
	active_ghost.texture = gem_data.icon
	active_ghost.size = Vector2(ICON_SIZE, ICON_SIZE)
	active_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	active_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	active_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	active_ghost.top_level = true
	ui_layer.add_child(active_ghost)
	
	var empty_preview := Control.new()
	visible = false
	set_drag_preview(empty_preview)
	
	return {"gem_data": gem_data}

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		if active_ghost and is_instance_valid(active_ghost):
			active_ghost.queue_free()
			active_ghost = null
		update_display()
