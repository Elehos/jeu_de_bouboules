extends Control
class_name GemIcon

@export var gem_data: GemData

@onready var label: Label = $Label
@onready var icon: TextureRect = $Icon

func _ready() -> void:
	update_display()

func update_display() -> void:
	if gem_data:
		label.text = gem_data.gem_name
		icon.texture = gem_data.icon

func _get_drag_data(_at_position: Vector2) -> Variant:
	var preview := TextureRect.new()
	preview.texture = gem_data.icon
	preview.custom_minimum_size = Vector2(50, 50)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	set_drag_preview(preview)
	
	return {"gem_data": gem_data}
