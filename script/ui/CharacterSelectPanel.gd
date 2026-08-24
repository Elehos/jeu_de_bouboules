extends PanelContainer
class_name CharacterSelectPanel

@export var available_characters: Array[CharacterData] = []
@export var confirm_button_text: String = "Confirmer"

signal character_confirmed(character: CharacterData)

var selected_character: CharacterData = null

@onready var character_list: HBoxContainer = $VBox/CharacterList
@onready var confirm_button: Button = $VBox/ConfirmButton

func _ready() -> void:
	confirm_button.text = confirm_button_text
	confirm_button.disabled = true
	confirm_button.pressed.connect(_on_confirm_pressed)
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.35686275, 0.35686275, 0.35686275, 1)
	normal_style.set_corner_radius_all(16)
	var selected_style := StyleBoxFlat.new()
	selected_style.bg_color = Color(0.5, 0.42, 0.2, 1)
	selected_style.set_corner_radius_all(16)
	for character: CharacterData in available_characters:
		var button := Button.new()
		button.text = character.character_name
		button.icon = character.portrait
		button.expand_icon = true
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(160, 200)
		button.add_theme_stylebox_override("normal", normal_style)
		button.add_theme_stylebox_override("hover", normal_style)
		button.add_theme_stylebox_override("pressed", selected_style)
		button.pressed.connect(_on_character_button_pressed.bind(character, button))
		character_list.add_child(button)
	if available_characters.size() == 1:
		_on_character_button_pressed(available_characters[0], character_list.get_child(0))

func _on_character_button_pressed(character: CharacterData, button: Button) -> void:
	selected_character = character
	confirm_button.disabled = false
	for child in character_list.get_children():
		if child is Button:
			child.button_pressed = (child == button)

func _on_confirm_pressed() -> void:
	if selected_character:
		character_confirmed.emit(selected_character)
