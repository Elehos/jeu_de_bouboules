extends Control
class_name RewardPopup

signal rewards_finished

@onready var card_reward_icon: Button = $Panel/VBoxContainer/ChoicesRow/Choix1/MarginContainer/CardRewardIcon
@onready var gem_reward_icon: Button = $Panel/VBoxContainer/ChoicesRow/Choix2/MarginContainer/GemRewardIcon
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton
@export var card_choice_scene: PackedScene   # glisse CardChoicePopup.tscn dans l'Inspecteur
var current_gem: GemData

func _ready() -> void:
	card_reward_icon.pressed.connect(_on_card_reward_pressed)
	gem_reward_icon.pressed.connect(_on_gem_reward_pressed)
	close_button.pressed.connect(_on_close_pressed)
	
	current_gem = RewardManager.get_random_gem()
	if current_gem:
		gem_reward_icon.icon = current_gem.icon
		gem_reward_icon.text = current_gem.description
	else:
		gem_reward_icon.visible = false



func _on_card_reward_pressed() -> void:
	var popup: CardChoicePopup = card_choice_scene.instantiate()
	get_parent().add_child(popup)
	popup.show_choices(RewardManager.get_random_cards(3))
	popup.choice_made.connect(func(chosen: bool): 
		if chosen:
			card_reward_icon.get_parent().get_parent().visible = false
)

func _on_gem_reward_pressed() -> void:
	GemInventory.owned_gems.append(current_gem.duplicate(true))
	gem_reward_icon.get_parent().get_parent().visible = false

func _on_close_pressed() -> void:
	rewards_finished.emit()
	get_tree().change_scene_to_file("res://scenes/map/MapView.tscn")
	queue_free()
