extends Node2D
# Menu principal. En multi, l'hôte contrôle le lancement de la partie via
# StartGameButton ; le client, lui, bascule sur MapView en réaction au push
# réseau de RunManager._receive_map() (pas de clic local de son côté).

@onready var choice_panel: VBoxContainer = $UI/ChoicePanel
@onready var multi_panel: Panel = $UI/MultiPanel
@onready var seed_field: LineEdit = $UI/ChoicePanel/SeedRow/SeedField
@onready var seed_error_label: Label = $UI/ChoicePanel/SeedErrorLabel
@onready var continue_button: Button = $UI/ChoicePanel/ContinueButton
@onready var solo_button: Button = $UI/ChoicePanel/SoloButton
@onready var multi_button: Button = $UI/ChoicePanel/MultiButton
@onready var host_button: Button = $UI/MultiPanel/Content/HostButton
@onready var continue_multi_button: Button = $UI/MultiPanel/Content/ContinueMultiButton
@onready var join_button: Button = $UI/MultiPanel/Content/JoinRow/JoinButton
@onready var address_field: LineEdit = $UI/MultiPanel/Content/JoinRow/AddressField
@onready var status_label: Label = $UI/MultiPanel/Content/StatusLabel
@onready var lobby_status_label: Label = $UI/MultiPanel/Content/LobbyStatusLabel
@onready var start_game_button: Button = $UI/MultiPanel/Content/StartGameButton
@onready var back_button: Button = $UI/MultiPanel/Content/BackButton

var pending_seed: int = 0

func _ready() -> void:
	multi_panel.visible = false
	start_game_button.visible = false
	lobby_status_label.visible = false
	continue_button.visible = RunManager.has_solo_save()
	continue_button.pressed.connect(_on_continue_pressed)
	solo_button.pressed.connect(_on_solo_pressed)
	multi_button.pressed.connect(_on_multi_pressed)
	host_button.pressed.connect(_on_host_pressed)
	continue_multi_button.visible = RunManager.has_multi_save()
	continue_multi_button.pressed.connect(_on_continue_multi_pressed)
	join_button.pressed.connect(_on_join_pressed)
	back_button.pressed.connect(_on_back_pressed)
	start_game_button.pressed.connect(_on_start_game_pressed)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	RunManager.join_rejected.connect(_on_join_rejected)

	if not RunManager.last_disconnect_message.is_empty():
		choice_panel.visible = false
		multi_panel.visible = true
		status_label.text = RunManager.last_disconnect_message
		RunManager.last_disconnect_message = ""

# Lit le champ de seed (vide = aléatoire, sinon doit être un nombre entier) —
# partagé entre Solo et Héberger, un LineEdit garde son texte même quand son
# parent (ChoicePanel) devient invisible, pas besoin d'un second champ dans
# MultiPanel.
func _resolve_seed_input() -> Dictionary:
	seed_error_label.text = ""
	var seed_text: String = seed_field.text.strip_edges()
	if seed_text.is_empty():
		return {"value": randi(), "ok": true}
	if not seed_text.is_valid_int():
		seed_error_label.text = "Le seed doit être un nombre entier."
		return {"ok": false}
	return {"value": seed_text.to_int(), "ok": true}

func _on_solo_pressed() -> void:
	var resolved: Dictionary = _resolve_seed_input()
	if not resolved["ok"]:
		return
	RunManager.start_new_run(8, resolved["value"], true)
	get_tree().change_scene_to_file("res://scenes/map/MapView.tscn")

func _on_continue_pressed() -> void:
	if not RunManager.load_run_from_disk():
		continue_button.visible = false
		return
	# MapView._ready() relance lui-même le nœud en cours (combat/événement)
	# si current_node_pending — jamais de changement de scène direct vers
	# Combat.tscn/EventView.tscn ici.
	get_tree().change_scene_to_file("res://scenes/map/MapView.tscn")

func _on_multi_pressed() -> void:
	choice_panel.visible = false
	multi_panel.visible = true
	continue_multi_button.visible = RunManager.has_multi_save()
	status_label.text = ""

func _on_back_pressed() -> void:
	NetworkManager.close_connection()
	RunManager.reset_run_state()
	_set_connect_buttons_enabled(true)
	start_game_button.visible = false
	multi_panel.visible = false
	choice_panel.visible = true

func _on_host_pressed() -> void:
	var resolved: Dictionary = _resolve_seed_input()
	if not resolved["ok"]:
		return
	pending_seed = resolved["value"]
	var err: Error = NetworkManager.host_game()
	if err != OK:
		status_label.text = "Erreur lors de l'hébergement (code %d)" % err
		return
	status_label.text = "En attente d'un joueur... (Seed : %d)" % pending_seed
	_set_connect_buttons_enabled(false)

# Charge la sauvegarde multi et héberge un salon de reprise (RunManager.
# resume_mode passe à true) : les joueurs d'origine s'y reconnectent via
# _try_lobby_rejoin_match() côté hôte, _process() ci-dessous affiche leur
# statut et n'active le bouton de reprise qu'une fois tout le monde revenu.
func _on_continue_multi_pressed() -> void:
	if not RunManager.load_multi_run_from_disk():
		continue_multi_button.visible = false
		return
	var err: Error = NetworkManager.host_game()
	if err != OK:
		status_label.text = "Erreur lors de l'hébergement (code %d)" % err
		RunManager.reset_run_state()
		return
	status_label.text = "Salon de reprise ouvert. En attente des joueurs d'origine..."
	_set_connect_buttons_enabled(false)

func _on_join_pressed() -> void:
	var address: String = address_field.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var err: Error = NetworkManager.join_game(address)
	if err != OK:
		status_label.text = "Erreur de connexion (code %d)" % err
		return
	status_label.text = "Connexion en cours..."
	_set_connect_buttons_enabled(false)

func _on_player_connected(peer_id: int) -> void:
	status_label.text = "Joueur %d connecté !" % peer_id
	if NetworkManager.is_host():
		start_game_button.visible = true

func _on_player_disconnected(peer_id: int) -> void:
	status_label.text = "Joueur %d déconnecté." % peer_id
	if NetworkManager.is_host() and multiplayer.get_peers().is_empty():
		start_game_button.visible = false

func _on_connection_succeeded() -> void:
	status_label.text = "Connecté !"

func _on_connection_failed() -> void:
	status_label.text = "Échec de la connexion."
	_set_connect_buttons_enabled(true)

func _on_server_disconnected() -> void:
	status_label.text = "Hôte déconnecté."
	_set_connect_buttons_enabled(true)

func _on_start_game_pressed() -> void:
	if not NetworkManager.is_host():
		return
	start_game_button.disabled = true
	if RunManager.resume_mode:
		RunManager.resume_multiplayer_run()
	else:
		RunManager.start_multiplayer_run(8, pending_seed, true)
	get_tree().change_scene_to_file("res://scenes/map/MapView.tscn")

# Le client s'est déjà déconnecté lui-même juste avant l'émission de ce
# signal (cf. RunManager._receive_join_rejection) — pas de double
# désinscription réseau à faire ici, juste afficher le message et repermettre
# une nouvelle tentative.
func _on_join_rejected(reason: String) -> void:
	status_label.text = reason
	_set_connect_buttons_enabled(true)

func _format_lobby_roster(flags: Array) -> String:
	var lines: PackedStringArray = []
	for i in flags.size():
		var connected: bool = flags[i]
		var who: String = "Joueur %d (hôte)" % (i + 1) if i == 0 else "Joueur %d" % (i + 1)
		lines.append("%s : %s" % [who, "Connecté" if connected else "En attente..."])
	return "\n".join(lines)

# Actif uniquement pendant l'affichage de MultiPanel. En salon de reprise
# (RunManager.resume_mode), affiche le statut de chaque joueur d'origine et
# n'active le bouton de démarrage qu'une fois tous reconnectés (décision
# utilisateur : pas de reprise partielle) — sinon, laisse la logique
# existante de _on_player_connected/_on_player_disconnected piloter sa
# visibilité pour une partie fraîche.
func _process(_delta: float) -> void:
	if not multi_panel.visible:
		return
	lobby_status_label.visible = RunManager.resume_mode
	if RunManager.resume_mode:
		lobby_status_label.text = _format_lobby_roster(RunManager.lobby_roster_flags)
		start_game_button.text = "Reprendre la partie"
		start_game_button.visible = NetworkManager.is_host() and not RunManager.lobby_roster_flags.has(false)
	else:
		start_game_button.text = "Démarrer la partie"

func _set_connect_buttons_enabled(enabled: bool) -> void:
	host_button.disabled = not enabled
	join_button.disabled = not enabled
	continue_multi_button.disabled = not enabled
