extends Node2D
# Menu principal. En multi, l'hôte contrôle le lancement de la partie via
# StartGameButton ; le client, lui, bascule sur MapView en réaction au push
# réseau de RunManager._receive_map() (pas de clic local de son côté).

@onready var choice_panel: VBoxContainer = $UI/ChoicePanel
@onready var multi_panel: Panel = $UI/MultiPanel
@onready var continue_button: Button = $UI/ChoicePanel/ContinueButton
@onready var abandon_button: Button = $UI/ChoicePanel/AbandonButton
@onready var solo_button: Button = $UI/ChoicePanel/SoloButton
@onready var multi_button: Button = $UI/ChoicePanel/MultiButton
@onready var host_button: Button = $UI/MultiPanel/Content/HostButton
@onready var continue_multi_button: Button = $UI/MultiPanel/Content/ContinueMultiButton
@onready var join_row: HBoxContainer = $UI/MultiPanel/Content/JoinRow
@onready var join_button: Button = $UI/MultiPanel/Content/JoinRow/JoinButton
@onready var address_field: LineEdit = $UI/MultiPanel/Content/JoinRow/AddressField
@onready var status_label: Label = $UI/MultiPanel/Content/StatusLabel
@onready var multi_seed_row: HBoxContainer = $UI/MultiPanel/Content/MultiSeedRow
@onready var multi_seed_field: LineEdit = $UI/MultiPanel/Content/MultiSeedRow/SeedField
@onready var multi_seed_error_label: Label = $UI/MultiPanel/Content/MultiSeedErrorLabel
@onready var multi_character_panel: CharacterSelectPanel = $UI/MultiPanel/Content/MultiCharacterPanel
@onready var lobby_status_label: Label = $UI/MultiPanel/Content/LobbyStatusLabel
@onready var start_game_button: Button = $UI/MultiPanel/Content/StartGameButton
@onready var back_button: Button = $UI/MultiPanel/Content/BackButton

@onready var character_panel: Panel = $UI/CharacterPanel
@onready var solo_seed_field: LineEdit = $UI/CharacterPanel/Content/SeedRow/SeedField
@onready var solo_seed_error_label: Label = $UI/CharacterPanel/Content/SeedErrorLabel
@onready var solo_character_select: CharacterSelectPanel = $UI/CharacterPanel/Content/SoloCharacterSelect
@onready var character_panel_back_button: Button = $UI/CharacterPanel/Content/BackButton

# Vrai une fois la connexion réseau établie (hôte : host_game() a réussi ;
# client : connection_succeeded) — pilote l'affichage du sélecteur de
# personnage et masque les contrôles Héberger/Rejoindre devenus inutiles.
# Reste faux pendant un salon de reprise (RunManager.resume_mode) : pas de
# personnage à choisir dans ce cas, cf. _process().
var is_connected: bool = false

func _ready() -> void:
	multi_panel.visible = false
	start_game_button.visible = false
	lobby_status_label.visible = false
	continue_button.visible = RunManager.has_solo_save()
	continue_button.pressed.connect(_on_continue_pressed)
	abandon_button.visible = RunManager.has_solo_save()
	abandon_button.pressed.connect(_on_abandon_pressed)
	solo_button.pressed.connect(_on_solo_pressed)
	multi_button.pressed.connect(_on_multi_pressed)
	host_button.pressed.connect(_on_host_pressed)
	continue_multi_button.visible = RunManager.has_multi_save()
	continue_multi_button.pressed.connect(_on_continue_multi_pressed)
	join_button.pressed.connect(_on_join_pressed)
	back_button.pressed.connect(_on_back_pressed)
	start_game_button.pressed.connect(_on_start_game_pressed)
	multi_character_panel.character_confirmed.connect(_on_multi_character_confirmed)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	RunManager.join_rejected.connect(_on_join_rejected)

	character_panel.visible = false
	solo_character_select.character_confirmed.connect(_on_solo_character_confirmed)
	character_panel_back_button.pressed.connect(_on_character_panel_back_pressed)

	if not RunManager.last_disconnect_message.is_empty():
		choice_panel.visible = false
		multi_panel.visible = true
		status_label.text = RunManager.last_disconnect_message
		RunManager.last_disconnect_message = ""

# Lit un champ de seed donné (vide = aléatoire, sinon doit être un nombre
# entier) — un champ séparé par contexte (solo/multi) plutôt qu'un seul
# partagé : chacun est résolu au moment où la seed devient réellement
# nécessaire (juste avant de démarrer la run), pas avant.
func _resolve_seed_input(field: LineEdit, error_label: Label) -> Dictionary:
	error_label.text = ""
	var seed_text: String = field.text.strip_edges()
	if seed_text.is_empty():
		return {"value": randi(), "ok": true}
	if not seed_text.is_valid_int():
		error_label.text = "Le seed doit être un nombre entier."
		return {"ok": false}
	return {"value": seed_text.to_int(), "ok": true}

func _on_solo_pressed() -> void:
	choice_panel.visible = false
	character_panel.visible = true

func _on_solo_character_confirmed(character: CharacterData) -> void:
	var resolved: Dictionary = _resolve_seed_input(solo_seed_field, solo_seed_error_label)
	if not resolved["ok"]:
		return
	# Une nouvelle partie remplace toujours l'ancienne sauvegarde solo (si une
	# existait) — sans ça, quitter avant le premier point de contrôle de cette
	# nouvelle run laisserait "Continuer" reprendre l'ancienne run abandonnée.
	RunManager.delete_solo_save()
	RunManager.start_new_run(8, resolved["value"], true, character.resource_path)
	get_tree().change_scene_to_file("res://scenes/map/MapView.tscn")

func _on_character_panel_back_pressed() -> void:
	character_panel.visible = false
	choice_panel.visible = true

func _on_continue_pressed() -> void:
	if not RunManager.load_run_from_disk():
		continue_button.visible = false
		abandon_button.visible = false
		return
	# MapView._ready() relance lui-même le nœud en cours (combat/événement)
	# si current_node_pending — jamais de changement de scène direct vers
	# Combat.tscn/EventView.tscn ici.
	get_tree().change_scene_to_file("res://scenes/map/MapView.tscn")

func _on_abandon_pressed() -> void:
	RunManager.delete_solo_save()
	continue_button.visible = false
	abandon_button.visible = false

func _on_multi_pressed() -> void:
	choice_panel.visible = false
	multi_panel.visible = true
	continue_multi_button.visible = RunManager.has_multi_save()
	status_label.text = ""

func _on_back_pressed() -> void:
	NetworkManager.close_connection()
	RunManager.reset_run_state()
	is_connected = false
	_set_connect_buttons_enabled(true)
	start_game_button.visible = false
	multi_panel.visible = false
	choice_panel.visible = true

func _on_host_pressed() -> void:
	var err: Error = NetworkManager.host_game()
	if err != OK:
		status_label.text = "Erreur lors de l'hébergement (code %d)" % err
		return
	is_connected = true
	status_label.text = "En attente d'un joueur..."
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
	is_connected = true
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

func _on_player_disconnected(peer_id: int) -> void:
	status_label.text = "Joueur %d déconnecté." % peer_id

func _on_connection_succeeded() -> void:
	is_connected = true
	status_label.text = "Connecté !"

func _on_connection_failed() -> void:
	status_label.text = "Échec de la connexion."
	is_connected = false
	_set_connect_buttons_enabled(true)

func _on_server_disconnected() -> void:
	status_label.text = "Hôte déconnecté."
	is_connected = false
	_set_connect_buttons_enabled(true)

func _on_start_game_pressed() -> void:
	if not NetworkManager.is_host():
		return
	if RunManager.resume_mode:
		start_game_button.disabled = true
		RunManager.resume_multiplayer_run()
		get_tree().change_scene_to_file("res://scenes/map/MapView.tscn")
		return
	var resolved: Dictionary = _resolve_seed_input(multi_seed_field, multi_seed_error_label)
	if not resolved["ok"]:
		return
	start_game_button.disabled = true
	RunManager.start_multiplayer_run(8, resolved["value"], true)
	get_tree().change_scene_to_file("res://scenes/map/MapView.tscn")

# Le client s'est déjà déconnecté lui-même juste avant l'émission de ce
# signal (cf. RunManager._receive_join_rejection) — pas de double
# désinscription réseau à faire ici, juste afficher le message et repermettre
# une nouvelle tentative.
func _on_join_rejected(reason: String) -> void:
	status_label.text = reason
	is_connected = false
	_set_connect_buttons_enabled(true)

func _on_multi_character_confirmed(character: CharacterData) -> void:
	RunManager.submit_character_pick(character.resource_path)
	if not NetworkManager.is_host():
		status_label.text = "Personnage choisi ! En attente que l'hôte lance la partie..."

func _format_lobby_roster(flags: Array) -> String:
	var lines: PackedStringArray = []
	for i in flags.size():
		var connected: bool = flags[i]
		var who: String = "Joueur %d (hôte)" % (i + 1) if i == 0 else "Joueur %d" % (i + 1)
		lines.append("%s : %s" % [who, "Connecté" if connected else "En attente..."])
	return "\n".join(lines)

# Actif uniquement pendant l'affichage de MultiPanel. Une fois connecté
# (is_connected), les contrôles Héberger/Rejoindre n'ont plus lieu d'être —
# ils cèdent la place soit au sélecteur de personnage (partie fraîche), soit
# au statut du salon de reprise (RunManager.resume_mode), qui n'active le
# bouton de démarrage qu'une fois tous les joueurs d'origine reconnectés
# (décision utilisateur : pas de reprise partielle). Pour une partie fraîche,
# le bouton ne s'active que si tous les pairs connectés ont choisi un
# personnage.
func _process(_delta: float) -> void:
	if not multi_panel.visible:
		return
	host_button.visible = not is_connected
	continue_multi_button.visible = not is_connected and RunManager.has_multi_save()
	join_row.visible = not is_connected
	var show_fresh_lobby: bool = is_connected and not RunManager.resume_mode
	var show_host_seed: bool = show_fresh_lobby and NetworkManager.is_host()
	multi_seed_row.visible = show_host_seed
	multi_seed_error_label.visible = show_host_seed
	multi_character_panel.visible = show_fresh_lobby
	lobby_status_label.visible = RunManager.resume_mode
	if RunManager.resume_mode:
		lobby_status_label.text = _format_lobby_roster(RunManager.lobby_roster_flags)
		start_game_button.text = "Reprendre la partie"
		start_game_button.visible = NetworkManager.is_host() and not RunManager.lobby_roster_flags.has(false)
	else:
		start_game_button.text = "Démarrer la partie"
		start_game_button.visible = NetworkManager.is_host() and not multiplayer.get_peers().is_empty() and RunManager.all_connected_peers_picked_character()

func _set_connect_buttons_enabled(enabled: bool) -> void:
	host_button.disabled = not enabled
	join_button.disabled = not enabled
	continue_multi_button.disabled = not enabled
