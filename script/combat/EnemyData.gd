extends Resource
class_name EnemyData

@export var enemy_name: String = ""
@export var max_hp: int = 50
@export var attack_power: int = 10
@export var defense_power: int = 5
@export var intention_sequence: Array[Enemy.IntentionType] = []
@export var sprite_texture: Texture2D
@export var enemy_scale: Vector2 = Vector2(1, 1)
