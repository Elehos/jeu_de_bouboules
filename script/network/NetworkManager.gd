extends Node

const DEFAULT_PORT: int = 7777
const MAX_CLIENTS: int = 8
const CLIENT_IDENTITY_PATH: String = "user://client_identity.dat"

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_succeeded()
signal connection_failed()
signal server_disconnected()

# Identifiant stable de ce client, persisté sur disque (un seul par machine,
# généré une fois puis toujours réutilisé) — sert à l'hôte pour reconnaître ce
# client s'il se reconnecte plus tard sous un nouveau peer_id (assigné
# aléatoirement par ENet à chaque connexion), y compris après un redémarrage
# complet du process (reprise d'une sauvegarde multijoueur). Si ce fichier est
# supprimé/changé, la machine redevient "inconnue" pour toute sauvegarde
# antérieure — dégradation propre (traité comme un nouveau venu), pas un crash.
var local_client_token: String = ""

func _ready() -> void:
	local_client_token = _load_or_create_local_token()
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

func _load_or_create_local_token() -> String:
	if FileAccess.file_exists(CLIENT_IDENTITY_PATH):
		var f: FileAccess = FileAccess.open(CLIENT_IDENTITY_PATH, FileAccess.READ)
		if f != null:
			var token = f.get_var()
			f.close()
			if typeof(token) == TYPE_STRING and not token.is_empty():
				return token
	var new_token: String = Crypto.new().generate_random_bytes(16).hex_encode()
	var f: FileAccess = FileAccess.open(CLIENT_IDENTITY_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("_load_or_create_local_token(): écriture impossible (code %d), token non persisté pour cette session." % FileAccess.get_open_error())
		return new_token
	f.store_var(new_token)
	f.close()
	return new_token
