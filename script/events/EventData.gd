extends Resource
class_name EventData

@export var event_name: String = ""
@export var description: String = ""
@export var background: Texture2D = null
# 1 à 4 choix normalement affichés.
@export var choices: Array[EventChoice] = []
# Si > 0 (et < choices.size()), seul un sous-ensemble aléatoire de cette
# taille est tiré parmi choices à chaque affichage (ex: 6 choix définis dans
# les données, 3 tirés et proposés au joueur à chaque partie). 0 = tout afficher.
@export var choices_shown: int = 0
