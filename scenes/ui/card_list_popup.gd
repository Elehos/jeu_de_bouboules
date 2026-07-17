extends Control
class_name CardListPopup

@export var card_scene: PackedScene  # glisse Card.tscn dans l'Inspecteur

@onready var title_label: Label = $Panel/VBoxContainer/TitleLabel
@onready var card_grid: GridContainer = $Panel/VBoxContainer/ScrollContainer/CardGrid
@onready var background: ColorRect = $Background
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton

func _ready() -> void:
	visible = false
	background.gui_input.connect(_on_background_input)
	close_button.pressed.connect(close_popup)

func show_cards(card_list: Array[CardData], title_text: String) -> void:
	title_label.text = title_text
	
	# Nettoie les anciennes cartes affichées avant d'en remettre de nouvelles
	for child in card_grid.get_children():
		child.queue_free()
	
	print("Nombre de cartes à afficher : ", card_list.size())  # ← ligne de test
	
	for data in card_list:
		var card_instance = card_scene.instantiate()
		card_grid.add_child(card_instance)
		card_instance.card_data = data
		card_instance.update_display()
		card_instance.set_interactive(false)
	
	visible = true

func close_popup() -> void:
	visible = false

func _on_background_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close_popup()
