extends Node2D
# Menu principal. En multi, l'hôte contrôle le lancement de la partie via
# StartGameButton ; le client, lui, bascule sur MapView en réaction au push
# réseau de RunManager._receive_map() (pas de clic local de son côté).

@onready var choice_panel: VBoxContainer = $UI/ChoicePanel
@onready var multi_panel: Panel = $UI/MultiPanel
@onready var solo_button: Button = $UI/ChoicePanel/SoloButton
@onready var multi_button: Button = $UI/ChoicePanel/MultiButton
@onready var host_button: Button = $UI/MultiPanel/Content/HostButton
@onready var join_button: Button = $UI/MultiPanel/Content/JoinRow/JoinButton
@onready var address_field: LineEdit = $UI/MultiPanel/Content/JoinRow/AddressField
@onready var status_label: Label = $UI/MultiPanel/Content/StatusLabel
@onready var start_game_button: Button = $UI/MultiPanel/Content/StartGameButton
@onready var back_button: Button = $UI/MultiPanel/Content/BackButton

func _ready() -> void:
	multi_panel.visible = false
	start_game_button.visible = false
	solo_button.pressed.connect(_on_solo_pressed)
	multi_button.pressed.connect(_on_multi_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	back_button.pressed.connect(_on_back_pressed)
	start_game_button.pressed.connect(_on_start_game_pressed)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

func _on_solo_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map/MapView.tscn")

func _on_multi_pressed() -> void:
	choice_panel.visible = false
	multi_panel.visible = true
	status_label.text = ""

func _on_back_pressed() -> void:
	NetworkManager.close_connection()
	_set_connect_buttons_enabled(true)
	start_game_button.visible = false
	multi_panel.visible = false
	choice_panel.visible = true

func _on_host_pressed() -> void:
	var err: Error = NetworkManager.host_game()
	if err != OK:
		status_label.text = "Erreur lors de l'hébergement (code %d)" % err
		return
	status_label.text = "En attente d'un joueur..."
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
	RunManager.start_multiplayer_run()
	get_tree().change_scene_to_file("res://scenes/map/MapView.tscn")

func _set_connect_buttons_enabled(enabled: bool) -> void:
	host_button.disabled = not enabled
	join_button.disabled = not enabled
