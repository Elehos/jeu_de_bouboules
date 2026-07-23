extends Control
class_name Hand

@export var card_scene: PackedScene
@export var deck_data: Array[CardData] = []
@export var cards_per_turn: int = 5

# Réglages de l'éventail
@export var card_spacing: float = 120.0      # distance horizontale entre cartes
@export var min_cards_threshold: int = 3
@export var max_cards_threshold: int = 10

@export var min_angle: float = 5.0
@export var max_angle: float = 10.0

@export var min_arc_height: float = 5.0
@export var max_arc_height: float = 50.0

@export var vertical_offset: float = 60.0  

var cards: Array[Card] = []

var hovered_card: Card = null
@export var push_strength: float = 0.5  # 50% de l'effet de remplacement complet
@export var push_falloff_range: int = 3  # nombre de cartes affectées de chaque côté

func _ready() -> void:
	add_to_group("hand")
	CombatEvents.player_turn_started.connect(new_turn)
	CombatEvents.card_played.connect(_on_card_played)
	DeckManager.setup_deck(deck_data)

func add_card(data: CardData) -> void:
	var card_instance = card_scene.instantiate()
	card_instance.card_data = data     # ← déplacé avant
	add_child(card_instance)
	card_instance.update_display()
	cards.append(card_instance)
	_update_hand_layout()

func discard_hand() -> void:
	hovered_card = null
	for card_instance in cards:
		if is_instance_valid(card_instance) and card_instance.get_parent() == self:
			DeckManager.discard_card(card_instance.card_data)
			card_instance.queue_free()
	cards.clear()

func draw_hand() -> void:
	for i in range(cards_per_turn):
		var data = DeckManager.draw_card()
		if data:
			add_card(data)

func new_turn() -> void:
	discard_hand()
	draw_hand()

func _update_hand_layout() -> void:
	cards = cards.filter(func(c): return is_instance_valid(c) and c.get_parent() == self)
	
	var settled: Array[Card] = cards.filter(func(c): return c.state == Card.CardState.IDLE)
	var count: int = settled.size()
	if count == 0:
		return
	
	var hovered_i: int = settled.find(hovered_card)
	
	var params: Dictionary = _compute_dynamic_params(count)
	var current_max_angle: float = params["angle"]
	var current_arc_height: float = params["arc"]
	
	var center_index: float = (count - 1) / 2.0
	
	for i in range(count):
		var card: Card = settled[i]
		var offset_from_center: float = i - center_index
		
		var x: float = offset_from_center * card_spacing
		
		if hovered_i >= 0 and i != hovered_i:
			var distance: int = i - hovered_i
			var direction: float = sign(distance)
			var falloff: float = clamp(1.0 - (abs(distance) - 1) / float(push_falloff_range), 0.0, 1.0)
			x += direction * card_spacing * push_strength * falloff
		
		var normalized: float = offset_from_center / max(center_index, 1.0)
		var y: float = current_arc_height * pow(normalized, 2)
		
		var rotation_deg: float = normalized * current_max_angle
		card.pivot_offset = Vector2(card.size.x / 2, card.size.y)
		
		var target_pos: Vector2 = Vector2(x, y + vertical_offset) + size / 2 - card.size / 2
		
		card.base_position = target_pos
		card.base_rotation_degrees = rotation_deg
		card.base_z_index = -i
		
		if i == hovered_i:
			continue
		
		card.z_index = -i
		card.move_to_base()

func _on_card_played(_card_data: CardData, _target: Character) -> void:
	await get_tree().create_timer(0.1).timeout
	cards = cards.filter(func(c): return is_instance_valid(c))
	hovered_card = null
	_update_hand_layout()
	
func _compute_dynamic_params(count: int) -> Dictionary:
	var t: float = float(count - min_cards_threshold) / float(max_cards_threshold - min_cards_threshold)
	t = clamp(t, 0.0, 1.0)
	
	return {
		"angle": lerp(min_angle, max_angle, t),
		"arc": lerp(min_arc_height, max_arc_height, t)
	}

func set_hovered_card(card: Card) -> void:
	hovered_card = card
	_update_hand_layout()
	
func get_card_data_list() -> Array[CardData]:
	var result: Array[CardData] = []
	for card in cards:
		if is_instance_valid(card) and card.card_data:
			result.append(card.card_data)
	return result
