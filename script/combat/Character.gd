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
const CORNER_RADIUS: int = 6

var fill_normal: StyleBoxFlat
var fill_shielded: StyleBoxFlat

signal died
signal damage_taken(amount: int)
signal clicked_as_target

func _ready() -> void:
	current_hp = max_hp
	
	fill_normal = make_fill_style(Color(0.8, 0.2, 0.2))       # rouge
	fill_shielded = make_fill_style(Color(0.3, 0.6, 0.9))     # bleu
	var fill_delayed := make_fill_style(Color(1.0, 0.9, 0.4)) # jaune clair
	var transparent_bg := make_fill_style(Color(0, 0, 0, 0))  # fond invisible
	
	hp_bar.add_theme_stylebox_override("background", transparent_bg)
	hp_bar.add_theme_stylebox_override("fill", fill_normal)
	hp_bar_delayed.add_theme_stylebox_override("fill", fill_delayed)
	hp_bar_delayed.add_theme_stylebox_override("background", transparent_bg)
	
	hp_bar.max_value = max_hp
	hp_bar.value = max_hp
	hp_bar_delayed.max_value = max_hp
	hp_bar_delayed.value = max_hp
	
	update_hp_display()
	update_block_display()
	
	click_area.input_event.connect(_on_click_area_input_event)

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
