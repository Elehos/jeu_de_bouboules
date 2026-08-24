extends CanvasLayer

@onready var corner_button: Button = $CornerButton
@onready var panel: Panel = $Panel
@onready var seed_label: Label = $Panel/SeedLabel
@onready var save_quit_button: Button = $Panel/SaveQuitButton
@onready var close_button: Button = $Panel/CloseButton

func _ready() -> void:
	panel.visible = false
	corner_button.visible = false
	corner_button.pressed.connect(_on_corner_button_pressed)
	save_quit_button.pressed.connect(_quit_without_saving)
	close_button.pressed.connect(_on_close_pressed)

# RunManager.map_generated est vrai pendant toute la durée d'une run (solo ou
# multi), remis à faux uniquement par reset_run_state() — équivaut
# exactement à "une partie est en cours" (MapView/Combat/EventView), faux
# sur MainMenu. Évite tout câblage par scène.
func _process(_delta: float) -> void:
	corner_button.visible = RunManager.map_generated

func _on_corner_button_pressed() -> void:
	panel.visible = true
	get_tree().paused = true
	seed_label.text = "Seed : %d" % RunManager.run_seed

func _on_close_pressed() -> void:
	panel.visible = false
	get_tree().paused = false

# N'écrit jamais rien sur disque ici : RunManager sauvegarde déjà tout seul
# aux bons moments (entrée dans un nœud, victoire avant récompenses, sortie
# du nœud — cf. RunManager.save_run_to_disk() call sites). Sauvegarder ici
# aussi capturerait un instant arbitraire choisi par le joueur (typiquement
# en pleine bagarre, dégâts déjà pris) au lieu d'un point de progression
# réellement acquis — ce bouton se contente donc de quitter.
func _quit_without_saving() -> void:
	panel.visible = false
	get_tree().paused = false
	# En solo, multiplayer.multiplayer_peer n'est PAS null par défaut (Godot y
	# assigne un pair implicite qui fait que get_unique_id() renvoie 1) —
	# appeler close_connection() le fermerait quand même et le mettrait à
	# null, cassant get_unique_id() (et donc get_local_player()) pour le
	# reste du processus. Ne toucher au réseau que si une vraie session
	# multijoueur est en cours.
	if RunManager.run_peer_ids.size() > 1:
		NetworkManager.close_connection()
	RunManager.reset_run_state()
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
