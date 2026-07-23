extends Label
class_name DamageNumber

func _ready() -> void:
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 50, 1.2)
	tween.tween_property(self, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(queue_free)

func set_amount(amount: int) -> void:
	text = str(amount)
