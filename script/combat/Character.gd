extends CharacterBody2D
class_name Character

@export var max_hp: int = 50
var current_hp: int
@export var attack_power: int = 10
@export var defense_power: int = 5

var current_block: int = 0

@onready var hp_label: Label = $HP
@onready var block_label: Label = $Block
@onready var hp_bar: ProgressBar = $HPBar
@onready var hp_bar_delayed: ProgressBar = $HPBarDelayed
@onready var click_area: Area2D = $ClickArea

const TWEEN_DURATION: float = 0.4
const DAMAGE_TRAIL_DELAY: float = 1.0
const CORNER_RADIUS: int = 10

var fill_normal: StyleBoxFlat
var fill_shielded: StyleBoxFlat

signal died
signal damage_taken(amount: int)

@onready var sprite: Sprite2D = $Sprite2D
@export var hp_bar_padding: float = 10.0  # marge de chaque côté, au-delà de la largeur du sprite

@onready var hp_bar_outline: Panel = $HPBarOutline

const OUTLINE_COLOR: Color = Color(0.09, 0.09, 0.09, 0.898)
const OUTLINE_WIDTH: int = 3
@export var outline_margin: float = 4.0

@onready var hp_bar_shading: TextureRect = $HPBarShading
@onready var hp_bar_highlight: TextureRect = $HPBarHighlight

func _ready() -> void:
	current_hp = max_hp
	
	fill_normal = make_fill_style(Color(0.8, 0.2, 0.2))
	fill_shielded = make_fill_style(Color(0.3, 0.6, 0.9))
	var fill_delayed := make_fill_style(Color(1.0, 0.9, 0.4))
	var transparent_bg := make_fill_style(Color(0, 0, 0, 0))
	
	fill_normal.anti_aliasing = false
	fill_shielded.anti_aliasing = false
	fill_delayed.anti_aliasing = false
	transparent_bg.anti_aliasing = false
	
	hp_bar.add_theme_stylebox_override("background", transparent_bg)
	hp_bar.add_theme_stylebox_override("fill", fill_normal)
	hp_bar_delayed.add_theme_stylebox_override("fill", fill_delayed)
	hp_bar_delayed.add_theme_stylebox_override("background", transparent_bg)
	
	var outline_style := StyleBoxFlat.new()
	outline_style.bg_color = Color(0, 0, 0, 0)
	outline_style.border_width_left = OUTLINE_WIDTH
	outline_style.border_width_right = OUTLINE_WIDTH
	outline_style.border_width_top = OUTLINE_WIDTH
	outline_style.border_width_bottom = OUTLINE_WIDTH
	outline_style.border_color = OUTLINE_COLOR
	outline_style.corner_radius_top_left = CORNER_RADIUS
	outline_style.corner_radius_top_right = CORNER_RADIUS
	outline_style.corner_radius_bottom_left = CORNER_RADIUS
	outline_style.corner_radius_bottom_right = CORNER_RADIUS
	outline_style.anti_aliasing = false
	hp_bar_outline.add_theme_stylebox_override("panel", outline_style)
	
	var shading_gradient := Gradient.new()
	shading_gradient.set_color(0, Color(0, 0, 0, 0))
	shading_gradient.set_color(1, Color(0, 0, 0, 0.5))
	shading_gradient.add_point(0.7, Color(0, 0, 0, 0))
	
	var shading_texture := GradientTexture2D.new()
	shading_texture.gradient = shading_gradient
	shading_texture.fill = GradientTexture2D.FILL_LINEAR
	shading_texture.fill_from = Vector2(0, 0)
	shading_texture.fill_to = Vector2(0, 1)
	
	var highlight_gradient := Gradient.new()
	highlight_gradient.set_color(0, Color(1, 1, 1, 0.4))
	highlight_gradient.set_color(1, Color(1, 1, 1, 0))
	highlight_gradient.add_point(0.3, Color(1, 1, 1, 0))

	var highlight_texture := GradientTexture2D.new()
	highlight_texture.gradient = highlight_gradient
	highlight_texture.fill = GradientTexture2D.FILL_LINEAR
	highlight_texture.fill_from = Vector2(0, 0)
	highlight_texture.fill_to = Vector2(0, 1)

	hp_bar_highlight.texture = highlight_texture
	hp_bar_highlight.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hp_bar_highlight.stretch_mode = TextureRect.STRETCH_SCALE
	hp_bar_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	hp_bar_shading.texture = shading_texture
	hp_bar_shading.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hp_bar_shading.stretch_mode = TextureRect.STRETCH_SCALE
	hp_bar_shading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	_resize_hp_bar_to_sprite()
	
	hp_bar.max_value = max_hp
	hp_bar.value = max_hp
	hp_bar_delayed.max_value = max_hp
	hp_bar_delayed.value = max_hp
	
	update_hp_display()
	update_block_display()
	
	click_area.input_event.connect(_on_click_area_input_event)

func _resize_hp_bar_to_sprite() -> void:
	if not sprite or not sprite.texture:
		return
	
	var sprite_width: float = sprite.texture.get_width() * sprite.scale.x
	var bar_width: float = round(sprite_width + hp_bar_padding * 2)
	
	hp_bar.size.x = bar_width
	hp_bar_delayed.size.x = bar_width
	hp_bar.position.x = round(-bar_width / 2)
	hp_bar_delayed.position.x = round(-bar_width / 2)
	
	hp_bar_outline.size = hp_bar.size + Vector2(outline_margin * 2, outline_margin * 2)
	hp_bar_outline.position = hp_bar.position - Vector2(outline_margin, outline_margin)
	hp_bar_shading.size = hp_bar.size
	hp_bar_shading.position = hp_bar.position
	
	hp_bar_highlight.size = hp_bar.size
	hp_bar_highlight.position = hp_bar.position
	
	if hp_label:
		hp_label.size.x = bar_width
		hp_label.position.x = round(-bar_width / 2)
		hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

# Crée un style de remplissage avec une couleur donnée, coins arrondis inclus
func make_fill_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = CORNER_RADIUS
	style.corner_radius_top_right = CORNER_RADIUS
	style.corner_radius_bottom_left = CORNER_RADIUS
	style.corner_radius_bottom_right = CORNER_RADIUS
	return style

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
	hp_bar_delayed.value = current_hp
	update_hp_display()

func gain_block(amount: int) -> void:
	current_block += amount
	update_block_display()

func reset_block() -> void:
	current_block = 0
	update_block_display()

# Mise à jour instantanée (utilisée à l'init et au soin)
func update_hp_display() -> void:
	hp_bar.value = current_hp
	if hp_label:
		hp_label.text = str(current_hp) + " / " + str(max_hp)

# Effet de dégâts : chute instantanée + traînée claire qui rattrape après un délai
func show_damage_trail() -> void:
	hp_bar.value = current_hp
	if hp_label:
		hp_label.text = str(current_hp) + " / " + str(max_hp)
	
	var tween: Tween = create_tween()
	tween.tween_interval(DAMAGE_TRAIL_DELAY)
	tween.tween_property(hp_bar_delayed, "value", current_hp, TWEEN_DURATION)

func update_block_display() -> void:
	hp_bar.add_theme_stylebox_override("fill", fill_shielded if current_block > 0 else fill_normal)
	
	if block_label:
		block_label.text = "🛡 " + str(current_block) if current_block > 0 else ""
		block_label.visible = current_block > 0

func die() -> void:
	print(name + " est mort.")
	died.emit()
	
func _on_click_area_input_event(viewport, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if self is Enemy:
			CombatEvents.resolve_target(self)
