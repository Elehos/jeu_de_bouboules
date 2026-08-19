extends Control
class_name GemSlot

@export var card_data: CardData

# Interrupteur général du système de déchirure. Décochable directement ici
# dans l'inspecteur (sur le nœud GemSlot de Card.tscn) pour désactiver tout
# le système sans toucher au code — s'applique à toutes les cartes puisque
# c'est la même scène GemSlot qui est instanciée partout.
@export var tear_system_enabled: bool = true

@onready var equipped_icon: TextureRect = $EquippedIcon
@onready var pickup_area: Control = $GemPickupArea
@onready var torn_marks_container: Control = $TornMarks
@onready var card_background: TextureRect = get_parent().get_node("Panel/CardBackground")
@onready var mana_background: TextureRect = get_parent().get_node("Panel/ManaBackground")

const ICON_SIZE: float = 60.0

# En dessous de cette distance, on considère que la gemme n'a pas vraiment
# été déplacée (simple clic) : pas de déchirure dans ce cas.
const REPOSITION_TEAR_THRESHOLD: float = 5.0

# --- Traces de déchirure laissées par les gemmes retirées (s'accumulent) ---
const TORN_TEXTURE: Texture2D = preload("res://assets/cards/bg_card_torn.png")
const TORN_SHADER: Shader = preload("res://scenes/cards/torn_mark.gdshader")

var torn_shader_material: ShaderMaterial

# --- Animation "gem incompatible avec cette carte" ---
const FORBIDDEN_ANIM_TEXTURE: Texture2D = preload("res://assets/ui/nointeract_anim.png")
const FORBIDDEN_ANIM_FRAME_COUNT: int = 10
# La feuille va de gauche (scribble complet) à droite (petit trait).
# Pour l'apparition on la lit de droite à gauche (petit trait -> complet),
# donc on stocke ici l'index "feuille" correspondant à chaque étape 0..9.
const FORBIDDEN_ANIM_FRAME_ORDER: Array[int] = [9, 8, 7, 6, 5, 4, 3, 2, 1, 0]
const FORBIDDEN_ANIM_DURATION: float = 0.25 # durée pour une apparition/disparition complète

var active_ghost: TextureRect = null

var forbidden_anim: TextureRect = null
var forbidden_atlas: AtlasTexture
var forbidden_anim_step: float = 0.0 # 0 = caché, FORBIDDEN_ANIM_FRAME_COUNT-1 = complet
var forbidden_anim_tween: Tween
var forbidden_is_shown: bool = false

func _ready() -> void:
	add_to_group("gem_slots")
	_setup_torn_mark_material()
	update_display()
	_setup_forbidden_anim()

func _setup_torn_mark_material() -> void:
	torn_shader_material = ShaderMaterial.new()
	torn_shader_material.shader = TORN_SHADER
	torn_shader_material.set_shader_parameter("torn_tex", TORN_TEXTURE)

func _setup_forbidden_anim() -> void:
	var frame_width: float = FORBIDDEN_ANIM_TEXTURE.get_width() / float(FORBIDDEN_ANIM_FRAME_COUNT)
	var frame_height: float = FORBIDDEN_ANIM_TEXTURE.get_height()

	forbidden_atlas = AtlasTexture.new()
	forbidden_atlas.atlas = FORBIDDEN_ANIM_TEXTURE
	forbidden_atlas.region = Rect2(0, 0, frame_width, frame_height)

	forbidden_anim = TextureRect.new()
	forbidden_anim.texture = forbidden_atlas
	forbidden_anim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	forbidden_anim.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	forbidden_anim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	forbidden_anim.set_anchors_preset(Control.PRESET_FULL_RECT)
	forbidden_anim.visible = false
	add_child(forbidden_anim)
	_update_forbidden_frame()

func _update_forbidden_frame() -> void:
	var frame_width: float = FORBIDDEN_ANIM_TEXTURE.get_width() / float(FORBIDDEN_ANIM_FRAME_COUNT)
	var frame_height: float = FORBIDDEN_ANIM_TEXTURE.get_height()
	var step_index: int = clampi(int(round(forbidden_anim_step)), 0, FORBIDDEN_ANIM_FRAME_COUNT - 1)
	var sheet_frame: int = FORBIDDEN_ANIM_FRAME_ORDER[step_index]
	forbidden_atlas.region = Rect2(sheet_frame * frame_width, 0, frame_width, frame_height)

func _set_forbidden_anim_step(value: float) -> void:
	forbidden_anim_step = value
	_update_forbidden_frame()

func update_display() -> void:
	if not equipped_icon:
		return
	if card_data and card_data.equipped_gem:
		equipped_icon.texture = card_data.equipped_gem.icon
		equipped_icon.visible = true
		equipped_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		equipped_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		equipped_icon.size = Vector2(ICON_SIZE, ICON_SIZE)
		equipped_icon.position = card_data.equipped_gem_position - Vector2(ICON_SIZE, ICON_SIZE) / 2.0

		pickup_area.size = Vector2(ICON_SIZE, ICON_SIZE)
		pickup_area.position = card_data.equipped_gem_position - Vector2(ICON_SIZE, ICON_SIZE) / 2.0
		pickup_area.visible = true
	else:
		equipped_icon.visible = false
		pickup_area.visible = false

	_render_torn_marks()

# preview: trace supplémentaire affichée en plus des traces déjà persistées sur
# card_data, sans être enregistrée. Utilisé pour montrer la déchirure dès la
# saisie d'une gemme, avant de savoir si le retrait sera confirmé ou annulé.
func _render_torn_marks(preview: Dictionary = {}) -> void:
	if not torn_marks_container:
		return
	for child in torn_marks_container.get_children():
		child.queue_free()

	if not tear_system_enabled or not card_data:
		return

	var marks: Array = card_data.torn_marks.duplicate()
	if not preview.is_empty():
		marks.append(preview)

	for mark in marks:
		var mark_size := Vector2(ICON_SIZE, ICON_SIZE)
		var mark_position: Vector2 = mark["position"] - mark_size / 2.0

		var mark_rect := TextureRect.new()
		mark_rect.texture = mark["icon"]
		mark_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark_rect.size = mark_size
		mark_rect.position = mark_position
		mark_rect.material = _make_torn_material(mark_position, mark_size)
		torn_marks_container.add_child(mark_rect)

# Chaque trace occupe un endroit différent sur la carte, donc chacune a besoin
# de son propre rectangle UV dans les textures masques : on ne peut pas
# partager un seul ShaderMaterial entre elles, on duplique le "modèle" à chaque fois.
func _make_torn_material(mark_local_position: Vector2, mark_size: Vector2) -> ShaderMaterial:
	var material: ShaderMaterial = torn_shader_material.duplicate()

	var card_uv: Dictionary = _compute_mask_uv(card_background, mark_local_position, mark_size)
	if not card_uv.is_empty():
		material.set_shader_parameter("card_mask_tex", card_background.texture)
		material.set_shader_parameter("card_mask_uv_origin", card_uv["origin"])
		material.set_shader_parameter("card_mask_uv_size", card_uv["size"])

	var mana_uv: Dictionary = _compute_mask_uv(mana_background, mark_local_position, mark_size)
	if not mana_uv.is_empty():
		material.set_shader_parameter("has_mana_mask", true)
		material.set_shader_parameter("mana_mask_tex", mana_background.texture)
		material.set_shader_parameter("mana_mask_uv_origin", mana_uv["origin"])
		material.set_shader_parameter("mana_mask_uv_size", mana_uv["size"])

	return material

# Calcule, dans l'espace UV [0,1] de source.texture, le rectangle exact que
# recouvre cette trace (mark_local_position/size, en espace local de GemSlot).
# source.position = origine du nœud dans l'espace local de Card ; self.position
# = origine de GemSlot dans ce même espace (Panel n'a aucun décalage propre,
# donc Panel == Card ici). Les deux ignorent le scale/rotation *live* de Card
# puisqu'il s'applique identiquement à toutes les couches et s'annule donc
# dans ce calcul relatif. Pour ManaBackground, .size ne change jamais (seule
# la frame de spritesheet affichée change), donc cette géométrie reste valable
# même pendant l'animation de rétrécissement.
func _compute_mask_uv(source: TextureRect, mark_local_position: Vector2, mark_size: Vector2) -> Dictionary:
	if not source or not source.texture:
		return {}

	var source_size: Vector2 = source.size * source.scale
	if source_size.x == 0.0 or source_size.y == 0.0:
		return {}

	var mark_top_left_in_card: Vector2 = position + mark_local_position
	var uv_origin: Vector2 = (mark_top_left_in_card - source.position) / source_size
	var uv_size: Vector2 = mark_size / source_size
	return {"origin": uv_origin, "size": uv_size}

func _process(_delta: float) -> void:
	if active_ghost and is_instance_valid(active_ghost):
		active_ghost.size = Vector2(ICON_SIZE, ICON_SIZE)
		active_ghost.global_position = get_global_mouse_position() - Vector2(ICON_SIZE, ICON_SIZE) / 2.0

		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_resolve_drop()

	_update_forbidden_state()

func _update_forbidden_state() -> void:
	var should_show: bool = false
	if CombatEvents.dragging_gem and card_data:
		var gem: GemData = CombatEvents.dragging_gem
		if gem.allowed_card_type != CardData.CardType.ANY and gem.allowed_card_type != card_data.card_type:
			should_show = true

	if should_show and not forbidden_is_shown:
		_show_forbidden_anim()
	elif not should_show and forbidden_is_shown:
		_hide_forbidden_anim()

func _show_forbidden_anim() -> void:
	forbidden_is_shown = true
	forbidden_anim.visible = true
	if forbidden_anim_tween and forbidden_anim_tween.is_valid():
		forbidden_anim_tween.kill()

	var max_step: float = float(FORBIDDEN_ANIM_FRAME_COUNT - 1)
	var remaining_ratio: float = 1.0 - (forbidden_anim_step / max_step)
	forbidden_anim_tween = create_tween()
	forbidden_anim_tween.tween_method(_set_forbidden_anim_step, forbidden_anim_step, max_step, FORBIDDEN_ANIM_DURATION * remaining_ratio)

func _hide_forbidden_anim() -> void:
	forbidden_is_shown = false
	if forbidden_anim_tween and forbidden_anim_tween.is_valid():
		forbidden_anim_tween.kill()

	var max_step: float = float(FORBIDDEN_ANIM_FRAME_COUNT - 1)
	var progress_ratio: float = forbidden_anim_step / max_step
	forbidden_anim_tween = create_tween()
	forbidden_anim_tween.tween_method(_set_forbidden_anim_step, forbidden_anim_step, 0.0, FORBIDDEN_ANIM_DURATION * progress_ratio)
	forbidden_anim_tween.tween_callback(func(): forbidden_anim.visible = false)

func start_pickup_drag() -> void:
	if GemInventory.gems_locked:
		return
	if not card_data or not card_data.equipped_gem:
		return

	var gem: GemData = card_data.equipped_gem

	CombatEvents.dragging_gem = gem
	CombatEvents.dragging_gem_source = self

	var ui_layer: Node = get_tree().current_scene.get_node("UI")
	active_ghost = TextureRect.new()
	active_ghost.texture = gem.icon
	active_ghost.size = Vector2(ICON_SIZE, ICON_SIZE)
	active_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	active_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	active_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	active_ghost.top_level = true
	ui_layer.add_child(active_ghost)

	equipped_icon.visible = false
	# Aperçu immédiat de la déchirure : elle ne devient définitive (accumulée
	# dans card_data.torn_marks) que si le retrait est confirmé dans
	# _resolve_drop(). Un geste annulé la fait juste disparaître au prochain
	# update_display(), sans laisser de trace fantôme.
	_render_torn_marks({"icon": gem.icon, "position": card_data.equipped_gem_position})

func _resolve_drop() -> void:
	var gem: GemData = CombatEvents.dragging_gem
	var source: Node = CombatEvents.dragging_gem_source
	var mouse_pos: Vector2 = get_global_mouse_position()

	var target_slot: GemSlot = _find_slot_at(mouse_pos)
	var target_unequip: Node = _find_unequip_zone_at(mouse_pos)

	if target_slot and (gem.allowed_card_type == CardData.CardType.ANY or gem.allowed_card_type == target_slot.card_data.card_type):
		var drop_local_pos: Vector2 = mouse_pos - target_slot.global_position

		if target_slot != source:
			if source is GemSlot and source.card_data:
				if source.tear_system_enabled:
					source.card_data.mark_torn(source.card_data.equipped_gem)
				source.card_data.equipped_gem = null
				source.update_display()
			target_slot.card_data.equipped_gem = gem
		elif tear_system_enabled and drop_local_pos.distance_to(target_slot.card_data.equipped_gem_position) > REPOSITION_TEAR_THRESHOLD:
			# Repositionnée ailleurs sur la même carte : déchire aussi l'ancien emplacement.
			target_slot.card_data.mark_torn(gem)

		target_slot.card_data.equipped_gem_position = drop_local_pos
		target_slot.update_display()
		CombatEvents.gem_equip_changed.emit()

	elif target_unequip:
		if source is GemSlot and source.card_data:
			if source.tear_system_enabled:
				source.card_data.mark_torn(source.card_data.equipped_gem)
			source.card_data.equipped_gem = null
			source.update_display()
		CombatEvents.gem_equip_changed.emit()

	_cancel_drag()

func _find_slot_at(mouse_pos: Vector2) -> GemSlot:
	return find_topmost_slot_at(get_tree(), mouse_pos)

# Parmi les GemSlot du groupe "gem_slots" dont le rectangle contient mouse_pos,
# retourne celui dont la carte parente a le z_index le plus élevé (celle au premier plan).
static func find_topmost_slot_at(tree: SceneTree, mouse_pos: Vector2) -> GemSlot:
	var best_slot: GemSlot = null
	var best_z: int = -999999

	for candidate in tree.get_nodes_in_group("gem_slots"):
		if not candidate.get_global_rect().has_point(mouse_pos):
			continue
		var card_parent = candidate.get_parent()
		var z: int = card_parent.z_index if card_parent else 0
		if best_slot == null or z >= best_z:
			best_slot = candidate
			best_z = z

	return best_slot

func _find_unequip_zone_at(mouse_pos: Vector2) -> Node:
	for candidate in get_tree().get_nodes_in_group("gem_unequip_zones"):
		if candidate.get_global_rect().has_point(mouse_pos):
			return candidate
	return null

func _cancel_drag() -> void:
	CombatEvents.dragging_gem = null
	CombatEvents.dragging_gem_source = null
	if active_ghost and is_instance_valid(active_ghost):
		active_ghost.queue_free()
		active_ghost = null
	update_display()
