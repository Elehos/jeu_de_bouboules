extends Panel
class_name GemBag

@export var closed_position_x: float = -1304.0
@export var open_position_x: float = 0.0
@export var slide_duration: float = 0.25

@export var gem_icon_scene: PackedScene
@export var card_row_scene: PackedScene

@export var deck_list_h_separation: int = 25
@export var deck_list_v_separation: int = 50

@onready var gem_list: HFlowContainer = $Content/GemList
@onready var deck_list: HFlowContainer = $Content/DeckScroll/MarginContainer/DeckList

var is_open: bool = false

func _ready() -> void:
	position.x = closed_position_x
	CombatEvents.gem_equip_changed.connect(_on_gem_equip_changed)
	deck_list.add_theme_constant_override("h_separation", deck_list_h_separation)
	deck_list.add_theme_constant_override("v_separation", deck_list_v_separation)

func _on_gem_equip_changed() -> void:
	if is_open:
		refresh_gems()

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
	
	var equipped_gems: Array[GemData] = _get_all_equipped_gems()
	
	for gem in GemInventory.owned_gems:
		if gem in equipped_gems:
			continue
		var gem_instance = gem_icon_scene.instantiate()
		gem_instance.gem_data = gem
		gem_list.add_child(gem_instance)

func refresh_deck() -> void:
	for child in deck_list.get_children():
		child.queue_free()
	
	for card in RunManager.player_deck:
		var row_instance = card_row_scene.instantiate()
		row_instance.card_data = card
		deck_list.add_child(row_instance)

func _get_all_equipped_gems() -> Array[GemData]:
	var result: Array[GemData] = []
	
	for card in RunManager.player_deck:
		if card.equipped_gem:
			result.append(card.equipped_gem)
	
	return result
