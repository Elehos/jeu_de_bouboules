extends CharacterBody2D
class_name Character

@export var max_hp: int = 50
var current_hp: int
@export var attack_power: int = 10
@export var defense_power: int = 5

var current_block: int = 0

@onready var hp_label: Label = $HP
# Rouge (PV actuels) et jaune (traînée de dégâts) : chacun est un NinePatchRect
# (image, coins non déformés) placé dans un Control qui le découpe (clip)
# selon le pourcentage de vie — le NinePatchRect lui-même reste toujours à la
# largeur pleine de la barre, seul le clip réduit sa partie visible.
@onready var hp_bar_background: NinePatchRect = $HPBarBackground
@onready var hp_bar_delayed_clip: Control = $HPBarDelayedClip
@onready var hp_bar_delayed: NinePatchRect = $HPBarDelayedClip/HPBarDelayed
@onready var hp_bar_clip: Control = $HPBarClip
@onready var hp_bar: NinePatchRect = $HPBarClip/HPBar
@onready var click_area: Area2D = $ClickArea
@onready var sprite: Sprite2D = $Sprite2D
@onready var shield_icon: TextureRect = $ShieldIcon
@onready var block_label: Label = $ShieldIcon/Block

const TWEEN_DURATION: float = 0.4
const DAMAGE_TRAIL_DELAY: float = 1.0

const LABEL_OUTLINE_COLOR: Color = Color(0.694, 0.212, 0.0, 1.0)
const LABEL_OUTLINE_COLOR_SHIELDED: Color = Color(0.0, 0.478, 0.694, 1.0)
const LABEL_OUTLINE_SIZE: int = 15

const HP_BAR_TEXTURE_NORMAL: Texture2D = preload("res://assets/ui/vie_rouge.png")
const HP_BAR_TEXTURE_SHIELDED: Texture2D = preload("res://assets/ui/vie_bleu.png")

const SHIELD_ICON_EDGE_OFFSET: float = 8.0

# Le chiffre de bouclier doit rester lisible et centré sur l'icône, quelle
# que soit sa largeur en pixels — au-delà d'un chiffre, la police et le
# contour rétrécissent proportionnellement pour ne pas déborder de l'icône.
const BLOCK_LABEL_SCALE_1_DIGIT: float = 1.0
const BLOCK_LABEL_SCALE_2_DIGITS: float = 0.75
const BLOCK_LABEL_SCALE_3_DIGITS: float = 0.55

# Correction visuelle manuelle : à deux chiffres, le rendu paraît légèrement
# décalé à droite dans l'icône (forme du bouclier) — on recentre à l'oeil.
const BLOCK_LABEL_NUDGE_X_2_DIGITS: float = -1.0

# Animation d'apparition du bouclier (pop + fade) : parle d'échelle 0, dépasse
# légèrement 1.0 puis se stabilise.
const SHIELD_APPEAR_OVERSHOOT_SCALE: float = 1.15
const SHIELD_APPEAR_POP_DURATION: float = 0.18
const SHIELD_APPEAR_SETTLE_DURATION: float = 0.1
const SHIELD_APPEAR_FADE_DURATION: float = 0.15

@export var hp_bar_padding: float = 25.0

var bar_width: float = 0.0
var block_label_base_font_size: int = 20
var block_label_base_outline_size: int = 5
var block_label_base_offset_left: float = 0.0
var block_label_base_offset_right: float = 0.0

signal died
signal damage_taken(amount: int)

func _ready() -> void:
	current_hp = max_hp

	if hp_label:
		hp_label.add_theme_color_override("font_outline_color", LABEL_OUTLINE_COLOR)
		hp_label.add_theme_constant_override("outline_size", LABEL_OUTLINE_SIZE)

	if block_label:
		block_label_base_font_size = block_label.get_theme_font_size("font_size")
		block_label_base_outline_size = block_label.get_theme_constant("outline_size")
		block_label_base_offset_left = block_label.offset_left
		block_label_base_offset_right = block_label.offset_right

	_resize_hp_bar_to_sprite()

	update_hp_display()
	update_block_display()

	click_area.input_event.connect(_on_click_area_input_event)

func _resize_hp_bar_to_sprite() -> void:
	if not sprite or not sprite.texture:
		return

	var sprite_width: float = sprite.texture.get_width() * sprite.scale.x
	bar_width = round(sprite_width + hp_bar_padding * 2)
	var bar_pos_x: float = round(-bar_width / 2)

	hp_bar_background.size.x = bar_width
	hp_bar_background.position.x = bar_pos_x

	hp_bar_delayed_clip.position.x = bar_pos_x
	hp_bar_clip.position.x = bar_pos_x
	hp_bar_delayed.size.x = bar_width
	hp_bar.size.x = bar_width

	if hp_label:
		hp_label.size.x = bar_width
		hp_label.position.x = bar_pos_x
		hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if shield_icon:
		# Icône centrée sur le bord gauche de la barre (légèrement décalée vers
		# la droite pour bien chevaucher la barre), joueur comme monstres.
		shield_icon.position.x = round(bar_pos_x - shield_icon.size.x / 2.0 + SHIELD_ICON_EDGE_OFFSET)

	# Réapplique le pourcentage courant à la nouvelle largeur de barre.
	_set_bar_fill(hp_bar_clip, current_hp)
	_set_bar_fill(hp_bar_delayed_clip, current_hp)

# Découpe (clip) horizontalement le NinePatchRect contenu dans clip_control
# pour ne montrer que la fraction value/max_hp de la barre — le NinePatchRect
# reste toujours à bar_width pleine, seul le Control parent le recadre, donc
# ses coins ne sont jamais déformés.
func _set_bar_fill(clip_control: Control, value: int) -> void:
	var ratio: float = clamp(float(value) / float(max_hp), 0.0, 1.0) if max_hp > 0 else 0.0
	clip_control.size.x = round(bar_width * ratio)

func take_damage(amount: int) -> void:
	var remaining_damage: int = amount
	
	if current_block > 0:
		var absorbed: int = min(current_block, remaining_damage)
		current_block -= absorbed
		remaining_damage -= absorbed
		update_block_display()
	
	if remaining_damage > 0:
		current_hp -= remaining_damage
		current_hp = max(current_hp, 0)
		show_damage_trail()
		damage_taken.emit(remaining_damage)
		CombatEvents.damage_taken.emit(self, remaining_damage)
	
	if current_hp <= 0:
		die()

func heal(amount: int) -> void:
	current_hp += amount
	current_hp = min(current_hp, max_hp)
	_set_bar_fill(hp_bar_delayed_clip, current_hp)
	update_hp_display()

func gain_block(amount: int) -> void:
	current_block += amount
	update_block_display()

func reset_block() -> void:
	current_block = 0
	update_block_display()

func update_hp_display() -> void:
	_set_bar_fill(hp_bar_clip, current_hp)
	if hp_label:
		hp_label.text = str(current_hp) + " / " + str(max_hp)

func sync_hp_bars_instantly() -> void:
	_set_bar_fill(hp_bar_clip, current_hp)
	_set_bar_fill(hp_bar_delayed_clip, current_hp)
	if hp_label:
		hp_label.text = str(current_hp) + " / " + str(max_hp)

func show_damage_trail() -> void:
	_set_bar_fill(hp_bar_clip, current_hp)
	if hp_label:
		hp_label.text = str(current_hp) + " / " + str(max_hp)

	var target_width: float = round(bar_width * (clamp(float(current_hp) / float(max_hp), 0.0, 1.0) if max_hp > 0 else 0.0))
	var tween: Tween = create_tween()
	tween.tween_interval(DAMAGE_TRAIL_DELAY)
	tween.tween_property(hp_bar_delayed_clip, "size:x", target_width, TWEEN_DURATION)

# Le bouclier est indiqué par l'icône ShieldIcon (avec son chiffre) sur la
# barre, le passage de la barre en bleu, et la couleur du contour du texte des PV.
func update_block_display() -> void:
	if hp_label:
		var label_outline: Color = LABEL_OUTLINE_COLOR_SHIELDED if current_block > 0 else LABEL_OUTLINE_COLOR
		hp_label.add_theme_color_override("font_outline_color", label_outline)

	if hp_bar:
		hp_bar.texture = HP_BAR_TEXTURE_SHIELDED if current_block > 0 else HP_BAR_TEXTURE_NORMAL

	if shield_icon:
		var was_shielded: bool = shield_icon.visible
		shield_icon.visible = current_block > 0
		if shield_icon.visible and not was_shielded:
			_play_shield_appear_animation()

	if block_label:
		var block_text: String = str(current_block) if current_block > 0 else ""
		block_label.text = block_text

		var scale: float = BLOCK_LABEL_SCALE_1_DIGIT
		if block_text.length() == 2:
			scale = BLOCK_LABEL_SCALE_2_DIGITS
		elif block_text.length() >= 3:
			scale = BLOCK_LABEL_SCALE_3_DIGITS
		block_label.add_theme_font_size_override("font_size", max(8, round(block_label_base_font_size * scale)))
		block_label.add_theme_constant_override("outline_size", max(2, round(block_label_base_outline_size * scale)))

		var nudge_x: float = BLOCK_LABEL_NUDGE_X_2_DIGITS if block_text.length() == 2 else 0.0
		block_label.offset_left = block_label_base_offset_left + nudge_x
		block_label.offset_right = block_label_base_offset_right + nudge_x

func _play_shield_appear_animation() -> void:
	shield_icon.pivot_offset = shield_icon.size / 2.0
	shield_icon.scale = Vector2.ZERO
	shield_icon.modulate.a = 0.0

	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(shield_icon, "scale", Vector2.ONE * SHIELD_APPEAR_OVERSHOOT_SCALE, SHIELD_APPEAR_POP_DURATION)
	tween.parallel().tween_property(shield_icon, "modulate:a", 1.0, SHIELD_APPEAR_FADE_DURATION)
	tween.tween_property(shield_icon, "scale", Vector2.ONE, SHIELD_APPEAR_SETTLE_DURATION)

func die() -> void:
	died.emit()

func _on_click_area_input_event(viewport, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if self is Enemy:
			CombatEvents.resolve_target(self)
