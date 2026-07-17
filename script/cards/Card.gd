extends Control
class_name Card

@export var card_data: CardData

@onready var panel: Panel = $Panel
@onready var name_label: Label = $Panel/VBoxContainer/CardName
@onready var cost_label: Label = $Panel/VBoxContainer/CardCost
@onready var description_label: Label = $Panel/VBoxContainer/CardDescription

var interactive: bool = true

func _ready() -> void:
	update_display()
	panel.gui_input.connect(_on_panel_gui_input)

func update_display() -> void:
	if card_data:
		name_label.text = card_data.card_name
		cost_label.text = str(card_data.cost)
		description_label.text = card_data.description

func play() -> void:
	if not CombatEvents.try_spend_mana(card_data.cost):
		# Pas assez de mana : la carte ne se joue pas, rien ne se passe
		return
	print("Carte jouée : ", card_data.card_name)
	CombatEvents.card_played.emit(card_data)
	DeckManager.discard_card(card_data)
	queue_free()

func _on_panel_gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		play()


func set_interactive(value: bool) -> void:
	interactive = value
