extends HFlowContainer

const DASH_COLOR: Color = Color(1, 1, 1, 0.6)
const DASH_LENGTH: float = 6.0
const DASH_GAP: float = 4.0

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if get_viewport().gui_is_dragging():
		_draw_dashed_rect(Rect2(Vector2.ZERO, size), DASH_COLOR, 2.0)

func _draw_dashed_rect(rect: Rect2, color: Color, width: float) -> void:
	var corners: Array[Vector2] = [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y)
	]
	for i in range(4):
		_draw_dashed_line(corners[i], corners[(i + 1) % 4], color, width)

func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var length: float = from.distance_to(to)
	var direction: Vector2 = (to - from).normalized()
	var step: float = DASH_LENGTH + DASH_GAP
	var count: int = int(length / step)
	
	for i in range(count + 1):
		var start: Vector2 = from + direction * (i * step)
		var end: Vector2 = start + direction * min(DASH_LENGTH, length - i * step)
		if start.distance_to(from) < length:
			draw_line(start, end, color, width)

func _can_drop_data(_at_position: Vector2, data) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("gem_data") and data.has("source_slot")

func _drop_data(_at_position: Vector2, data) -> void:
	var source: GemSlot = data["source_slot"]
	if source and source.card_data:
		source.card_data.equipped_gem = null
		source.update_display()
	CombatEvents.gem_equip_changed.emit()
