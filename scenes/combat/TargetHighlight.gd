extends Node2D
class_name TargetHighlight

@export var rect_size: Vector2 = Vector2(300, 300)
@export var corner_length: float = 30.0
@export var line_width: float = 4.0
@export var highlight_color: Color = Color(1, 0.9, 0.2)

func _ready() -> void:
	visible = false

func set_active(value: bool) -> void:
	visible = value

func _draw() -> void:
	var half: Vector2 = rect_size / 2.0
	var tl: Vector2 = -half
	var tr: Vector2 = Vector2(half.x, -half.y)
	var bl: Vector2 = Vector2(-half.x, half.y)
	var br: Vector2 = half
	
	draw_line(tl, tl + Vector2(corner_length, 0), highlight_color, line_width)
	draw_line(tl, tl + Vector2(0, corner_length), highlight_color, line_width)
	
	draw_line(tr, tr + Vector2(-corner_length, 0), highlight_color, line_width)
	draw_line(tr, tr + Vector2(0, corner_length), highlight_color, line_width)
	
	draw_line(bl, bl + Vector2(corner_length, 0), highlight_color, line_width)
	draw_line(bl, bl + Vector2(0, -corner_length), highlight_color, line_width)
	
	draw_line(br, br + Vector2(-corner_length, 0), highlight_color, line_width)
	draw_line(br, br + Vector2(0, -corner_length), highlight_color, line_width)
