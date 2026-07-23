extends Panel
class_name GemBag

@export var closed_position_x: float = -1304.0
@export var open_position_x: float = 0.0
@export var slide_duration: float = 0.25

@export var gem_icon_scene: PackedScene
@export var card_row_scene: PackedScene

@onready var gem_list: HFlowContainer = $Content/GemList
@onready var deck_list: HFlowContainer = $Content/DeckScroll/DeckList

var is_open: bool = false

func _ready() -> void:
	position.x = closed_position_x

func toggle() -> void:
	if is_open:
		close()
	else:
		open()

func open() -> void:
	is_open = true
	refresh_gems()
	refresh_deck()
	var tween: Tween = create_tween()
	tween.tween_property(self, "position:x", open_position_x, slide_duration)

func close() -> void:
	is_open = false
	var tween: Tween = create_tween()
	tween.tween_property(self, "position:x", closed_position_x, slide_duration)

func refresh_gems() -> void:
	for child in gem_list.get_children():
		child.queue_free()
	
	for gem in GemInventory.owned_gems:
		var gem_instance = gem_icon_scene.instantiate()
		gem_instance.gem_data = gem
		gem_list.add_child(gem_instance)

func refresh_deck() -> void:
	for child in deck_list.get_children():
		child.queue_free()
	
	var full_deck: Array[CardData] = DeckManager.get_full_deck()
	
	var hand_node = get_tree().get_first_node_in_group("hand")
	if hand_node:
		full_deck += hand_node.get_card_data_list()
	
	for card in full_deck:
		var row_instance = card_row_scene.instantiate()
		row_instance.card_data = card
		deck_list.add_child(row_instance)
