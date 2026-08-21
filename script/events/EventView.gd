extends Control
class_name EventView

# Interface construite entièrement par code (comme le reste de l'UI
# dynamique du projet, ex: GemSlot) plutôt que positionnée à la main dans la
# scène : plus simple à garder cohérente quel que soit le nombre de choix
# (1 à 4) et la présence ou non d'un fond dédié à l'événement.

const CHOICES_WIDTH: float = 420.0
const CHOICES_MIN_HEIGHT: float = 60.0

var event_data: EventData

var description_label: RichTextLabel
var choices_container: VBoxContainer
var result_label: RichTextLabel
var continue_button: Button

func _ready() -> void:
	event_data = RunManager.pending_event
	RunManager.pending_event = null

	set_anchors_preset(Control.PRESET_FULL_RECT)

	_setup_background()
	_setup_description_label()
	_setup_choices_container()
	_setup_result_label()
	_setup_continue_button()

	_show_choices()

func _setup_background() -> void:
	var fallback := ColorRect.new()
	fallback.color = Color(0.12, 0.1, 0.15)
	fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fallback)

	if event_data and event_data.background:
		var background := TextureRect.new()
		background.texture = event_data.background
		background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		background.stretch_mode = TextureRect.STRETCH_SCALE
		background.set_anchors_preset(Control.PRESET_FULL_RECT)
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(background)

func _setup_description_label() -> void:
	description_label = RichTextLabel.new()
	description_label.bbcode_enabled = true
	description_label.fit_content = true
	description_label.scroll_active = false
	description_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description_label.anchor_left = 0.12
	description_label.anchor_right = 0.88
	description_label.anchor_top = 0.08
	description_label.anchor_bottom = 0.4
	description_label.add_theme_font_size_override("normal_font_size", 22)
	description_label.add_theme_font_size_override("bold_font_size", 30)
	description_label.add_theme_color_override("default_color", Color(1, 1, 1))
	add_child(description_label)

func _setup_choices_container() -> void:
	# Liste verticale des choix, côté droit de l'écran.
	choices_container = VBoxContainer.new()
	choices_container.anchor_left = 0.6
	choices_container.anchor_right = 0.92
	choices_container.anchor_top = 0.45
	choices_container.anchor_bottom = 0.9
	choices_container.add_theme_constant_override("separation", 16)
	add_child(choices_container)

func _setup_result_label() -> void:
	result_label = RichTextLabel.new()
	result_label.bbcode_enabled = true
	result_label.fit_content = true
	result_label.scroll_active = false
	result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_label.anchor_left = 0.12
	result_label.anchor_right = 0.88
	result_label.anchor_top = 0.45
	result_label.anchor_bottom = 0.78
	result_label.add_theme_font_size_override("normal_font_size", 20)
	result_label.add_theme_color_override("default_color", Color(1, 1, 1))
	result_label.visible = false
	add_child(result_label)

func _setup_continue_button() -> void:
	continue_button = Button.new()
	continue_button.text = "Continuer"
	continue_button.anchor_left = 0.4
	continue_button.anchor_right = 0.6
	continue_button.anchor_top = 0.82
	continue_button.anchor_bottom = 0.9
	continue_button.visible = false
	continue_button.pressed.connect(_on_continue_pressed)
	add_child(continue_button)

func _show_choices() -> void:
	if not event_data:
		description_label.text = "[i]Erreur : aucun événement chargé.[/i]"
		continue_button.visible = true
		return

	description_label.text = "[b]%s[/b]\n\n%s" % [event_data.event_name, event_data.description]

	for child in choices_container.get_children():
		child.queue_free()

	for choice in _pick_choices_to_show():
		var button := Button.new()
		button.text = choice.choice_text
		button.custom_minimum_size = Vector2(CHOICES_WIDTH, CHOICES_MIN_HEIGHT)
		button.pressed.connect(_on_choice_selected.bind(choice))
		choices_container.add_child(button)

# Si event_data.choices_shown est fixé, tire ce nombre de choix au hasard
# parmi event_data.choices (ex: 6 choix définis, 3 montrés à chaque partie).
# Sinon, tous les choix sont affichés.
func _pick_choices_to_show() -> Array[EventChoice]:
	var shown: int = event_data.choices_shown
	if shown <= 0 or shown >= event_data.choices.size():
		return event_data.choices

	var shuffled: Array[EventChoice] = event_data.choices.duplicate()
	shuffled.shuffle()
	return shuffled.slice(0, shown)

func _on_choice_selected(choice: EventChoice) -> void:
	for effect in choice.effects:
		_apply_effect(effect)

	choices_container.visible = false

	var text: String = ""
	if choice.result_text != "":
		text += choice.result_text + "\n\n"
	for effect in choice.effects:
		var color: String = "#7CFC7C" if effect.is_positive() else "#FF6B6B"
		text += "[color=%s]%s[/color]\n" % [color, effect.get_description()]
	result_label.text = text
	result_label.visible = true

	continue_button.visible = true

func _apply_effect(effect: EventEffect) -> void:
	var player: PlayerState = RunManager.get_local_player()
	match effect.type:
		EventEffect.EffectType.HEAL:
			player.current_hp = min(player.current_hp + effect.amount, player.max_hp)
		EventEffect.EffectType.DAMAGE:
			# Ne tue jamais depuis un événement : il n'y a pas d'écran de
			# défaite en dehors du combat, donc on plafonne à 1 PV restant.
			player.current_hp = max(player.current_hp - effect.amount, 1)
		EventEffect.EffectType.GAIN_CARD:
			if effect.card:
				player.deck.append(effect.card.duplicate(true))
		EventEffect.EffectType.REMOVE_RANDOM_CARD:
			if not player.deck.is_empty():
				player.deck.remove_at(randi() % player.deck.size())
		EventEffect.EffectType.GAIN_GEM:
			if effect.gem:
				player.owned_gems.append(effect.gem.duplicate(true))

func _on_continue_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map/MapView.tscn")
