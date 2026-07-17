extends Resource
class_name EncounterEnemySlot

@export var enemy_data: EnemyData

# Si non vide, remplace la séquence par défaut de enemy_data pour CE combat précis
@export var intention_override: Array[Enemy.IntentionType] = []
