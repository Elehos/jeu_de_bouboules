extends Node

const DEFAULT_PORT: int = 7777
const MAX_CLIENTS: int = 8

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_succeeded()
signal connection_failed()
signal server_disconnected()

# Identifiant stable de ce client, généré une fois par processus (jamais
# sauvegardé sur disque, aucun système de persistance dans ce projet) — sert
# à l'hôte pour reconnaître ce client s'il se reconnecte plus tard sous un
# nouveau peer_id (assigné aléatoirement par ENet à chaque connexion).
var local_client_token: String = ""

func _ready() -> void:
	local_client_token = Crypto.new().generate_random_bytes(16).hex_encode()
	multiplayer.peer_connected.connect(func(id: int): player_connected.emit(id))
	multiplayer.peer_disconnected.connect(func(id: int): player_disconnected.emit(id))
	multiplayer.connected_to_server.connect(func(): connection_succeeded.emit())
	multiplayer.connection_failed.connect(func(): connection_failed.emit())
	multiplayer.server_disconnected.connect(func(): server_disconnected.emit())

func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK

func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK

func close_connection() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

func is_host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()
