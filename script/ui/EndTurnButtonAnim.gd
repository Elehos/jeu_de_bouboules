extends Button

@onready var anim_overlay: TextureRect = $AnimOverlay
@onready var button_label: Label = $ButtonLabel

@export var anim_texture: Texture2D
const FRAME_COUNT: int = 6
const FRAME_TIME: float = 0.05

const FADE_TIME: float = 0.05
const WRITE_TIME: float = 0.20

var frames: Array[Texture2D] = []

func _ready() -> void:
	pressed.connect(_play_animation)
	pressed.connect(_fade_out_text)
	_setup_frames()

func _setup_frames() -> void:
	if not anim_texture:
		return
	
	var frame_width: float = anim_texture.get_width() / float(FRAME_COUNT)
	var frame_height: float = anim_texture.get_height()
	
	frames.clear()
	for i in range(FRAME_COUNT):
		var reversed_index: int = FRAME_COUNT - 1 - i
		var atlas := AtlasTexture.new()
		atlas.atlas = anim_texture
		atlas.region = Rect2(reversed_index * frame_width, 0, frame_width, frame_height)
		frames.append(atlas)
	
	anim_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	anim_overlay.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

func _play_animation() -> void:
	if frames.is_empty():
		return
	
	anim_overlay.visible = true
	
	for i in range(FRAME_COUNT):
		anim_overlay.texture = frames[i]
		await get_tree().create_timer(FRAME_TIME).timeout
	
	anim_overlay.visible = false

func _fade_out_text() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(button_label, "modulate:a", 0.0, FADE_TIME)

func reveal_text() -> void:
	button_label.modulate.a = 1.0
	button_label.visible_ratio = 0.0
	
	var tween: Tween = create_tween()
	tween.tween_property(button_label, "visible_ratio", 1.0, WRITE_TIME)
