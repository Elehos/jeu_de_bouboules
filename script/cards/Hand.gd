extends Control
class_name Hand

@export var card_scene: PackedScene
@export var deck_data: Array[CardData] = []
@export var cards_per_turn: int = 5
@export var hover_lift: float = 60.0

# Réglages de l'éventail
@export var card_spacing: float = 110.0      # distance horizontale entre cartes
@export var max_angle: float = 25.0          # angle max (en degrés) sur les cartes des extrémités
@export var arc_height: float = 40.0         # hauteur de la courbe (plus haut au centre ou sur les bords)

var cards: Array[Card] = []

func _ready() -> void:
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
	var count: int = cards.size()
	if count == 0:
		return
	
	var center_index: float = (count - 1) / 2.0
	var hover_target_y: float = size.y / 2 - hover_lift
	
	for i in range(count):
		var card: Card = cards[i]
		card.base_z_index = -i
		card.z_index = -i
		var offset_from_center: float = i - center_index
		
		# Position horizontale : centrée, espacée régulièrement
		var x: float = offset_from_center * card_spacing
		
		# Courbe : les cartes sur les bords remontent légèrement (parabole)
		var normalized: float = offset_from_center / max(center_index, 1.0)
		var y: float = arc_height * pow(normalized, 2)
		
		# Rotation : plus on s'éloigne du centre, plus l'angle est prononcé
		var rotation_deg: float = normalized * max_angle
		card.pivot_offset = Vector2(card.size.x / 2, card.size.y)
		
		var target_pos: Vector2 = Vector2(x, y) + size / 2  # centré dans CardZone
		
		var tween: Tween = create_tween()
		tween.set_parallel(true)
		card.base_position = target_pos
		card.base_rotation_degrees = rotation_deg
		tween.tween_property(card, "position", target_pos, 0.2)
		tween.tween_property(card, "rotation_degrees", rotation_deg, 0.2)

func _on_card_played(_card_data: CardData, _target: Character) -> void:
	# On retire la carte jouée après un court délai (le temps de son animation)
	await get_tree().create_timer(0.1).timeout
	cards = cards.filter(func(c): return is_instance_valid(c))
	_update_hand_layout()
