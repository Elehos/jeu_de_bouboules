extends Node2D
# Phase 1 seulement : prouve que 2 instances se connectent. Aucune transition
# de scène au succès de connexion — ça viendra dans une phase ultérieure une
# fois le tour-par-tour et la carte partagée tranchés en design.

@onready var choice_panel: VBoxContainer = $UI/ChoicePanel
@onready var multi_panel: Panel = $UI/MultiPanel
@onready var solo_button: Button = $UI/ChoicePanel/SoloButton
@onready var multi_button: Button = $UI/ChoicePanel/MultiButton
@onready var host_button: Button = $UI/MultiPanel/Content/HostButton
@onready var join_button: Button = $UI/MultiPanel/Content/JoinRow/JoinButton
@onready var address_field: LineEdit = $UI/MultiPanel/Content/JoinRow/AddressField
@onready var status_label: Label = $UI/MultiPanel/Content/StatusLabel
@onready var back_button: Button = $UI/MultiPanel/Content/BackButton

func _ready() -> void:
	multi_panel.visible = false
	solo_button.pressed.connect(_on_solo_pressed)
	multi_button.pressed.connect(_on_multi_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	back_button.pressed.connect(_on_back_pressed)
	NetworkManager.player_connected.connect(_on_player_connected)
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

func _on_connection_succeeded() -> void:
	status_label.text = "Connecté !"

func _on_connection_failed() -> void:
	status_label.text = "Échec de la connexion."
	_set_connect_buttons_enabled(true)

func _on_server_disconnected() -> void:
	status_label.text = "Hôte déconnecté."
	_set_connect_buttons_enabled(true)

func _set_connect_buttons_enabled(enabled: bool) -> void:
	host_button.disabled = not enabled
	join_button.disabled = not enabled
