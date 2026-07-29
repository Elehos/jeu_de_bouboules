extends Node2D
class_name ConnectionsDrawer

var segments: Array = []  # liste de {from: Vector2, to: Vector2}

func set_segments(new_segments: Array) -> void:
	segments = new_segments
	queue_redraw()

func _draw() -> void:
	for segment in segments:
		draw_dashed_line(segment["from"], segment["to"], Color(0.537, 0.537, 0.537, 1.0), 4.0, 17.0, true)
