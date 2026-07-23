extends Control
class_name GemIcon

@export var gem_data: GemData

@onready var label: Label = $Label

func _ready() -> void:
	update_display()

func update_display() -> void:
	if gem_data:
		label.text = gem_data.gem_name
