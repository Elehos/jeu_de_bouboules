extends CanvasLayer

@onready var panel: Panel = $Panel
@onready var label: Label = $Panel/Label
@onready var abandon_button: Button = $Panel/AbandonButton

func _ready() -> void:
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	abandon_button.pressed.connect(_on_abandon_pressed)

func show_peer_lost(message: String) -> void:
	label.text = message
	panel.visible = true

func hide_overlay() -> void:
	panel.visible = false

func _on_abandon_pressed() -> void:
	hide_overlay()
	NetworkManager.close_connection()
	RunManager.reset_run_state()
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
