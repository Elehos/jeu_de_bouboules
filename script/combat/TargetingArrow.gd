extends Node2D
class_name TargetingArrow

var active: bool = false
var source_card: Control = null

const ARROW_COLOR: Color = Color(0.9, 0.15, 0.15)
const ARROW_WIDTH: float = 5.0
const CURVE_HEIGHT: float = 100.0
const ARROW_HEAD_SIZE: float = 18.0
const SEGMENTS: int = 24

func _ready() -> void:
	CombatEvents.targeting_arrow = self
	set_process(true)

func show_arrow(card: Control) -> void:
	source_card = card
	active = true

func hide_arrow() -> void:
	active = false
	source_card = null
	queue_redraw()

func _process(_delta: float) -> void:
	if active:
		if not is_instance_valid(source_card):
			hide_arrow()
			return
		queue_redraw()

func _draw() -> void:
	if not active or not is_instance_valid(source_card):
		return
	
	var start_point: Vector2 = to_local(source_card.global_position + (source_card.size * source_card.scale) / 2.0)
	var end_point: Vector2 = to_local(get_global_mouse_position())
	
	# Point de contrôle pour une courbe douce vers le haut
	var control_point: Vector2 = (start_point + end_point) / 2.0 + Vector2(0, -CURVE_HEIGHT)
	
	var points: PackedVector2Array = []
	for i in range(SEGMENTS + 1):
		var t: float = float(i) / SEGMENTS
		var a: Vector2 = start_point.lerp(control_point, t)
		var b: Vector2 = control_point.lerp(end_point, t)
		points.append(a.lerp(b, t))
	
	draw_polyline(points, ARROW_COLOR, ARROW_WIDTH, true)
	
	# Pointe de flèche à l'extrémité
	var tip: Vector2 = points[points.size() - 1]
	var direction: Vector2 = (tip - points[points.size() - 2]).normalized()
	var perpendicular: Vector2 = Vector2(-direction.y, direction.x)
	
	var left: Vector2 = tip - direction * ARROW_HEAD_SIZE + perpendicular * ARROW_HEAD_SIZE * 0.5
	var right: Vector2 = tip - direction * ARROW_HEAD_SIZE - perpendicular * ARROW_HEAD_SIZE * 0.5
	
	draw_polygon(PackedVector2Array([tip, left, right]), PackedColorArray([ARROW_COLOR]))
