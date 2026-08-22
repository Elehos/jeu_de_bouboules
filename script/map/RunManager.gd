extends Node

var floors: Array[Array] = []
var current_floor_index: int = 0
var current_position_in_floor: int = 0
var map_generated: bool = false
# Mis à true par MapView juste avant de lancer le combat du dernier nœud de
# l'arbre (type END) : CombatManager pioche alors dans possible_boss_encounters
# au lieu de possible_encounters.
var is_boss_combat: bool = false
# Mis par MapView juste avant de lancer un nœud d'événement (type EVENT) :
# EventView lit cette donnée à son _ready() puis la remet à null.
var pending_event: EventData = null

# Un PlayerState par joueur de la partie. Vide tant que start_new_run() /
# start_multiplayer_run() n'a pas tourné — ne jamais appeler get_local_player()
# avant ça.
var players: Array[PlayerState] = []

# IDs des pairs (multiplayer.get_unique_id()) participant au run courant,
# dans un ordre identique et partagé par tous — transmis explicitement par
# l'hôte plutôt que recalculé côté client (en topologie étoile, un client ne
# voit que l'hôte dans ses propres pairs, pas les autres clients).
var run_peer_ids: Array[int] = []
# true une fois players[] construit pour ce run (deck/gemmes de départ) —
# distinct de map_generated car côté client, la carte arrive par réseau avant
# que ce pair ait construit ses propres PlayerState.
var players_ready: bool = false

# peer_id -> MapNode (hôte uniquement ; référence locale, jamais transmise
# telle quelle — seuls floor_index/position_in_floor voyagent par RPC).
var pending_node_picks: Dictionary = {}

# Hôte -> clients uniquement. -1 tant qu'aucun indice n'est arrivé pour le
# combat en cours ; remis à -1 par CombatManager juste après consommation
# pour ne pas laisser une valeur périmée fuiter vers le combat suivant.
var pending_encounter_index: int = -1
signal encounter_chosen(index: int)

signal node_choice_applied(map_node: MapNode)

# Message affiché par MainMenu à son prochain _ready() (pas encore chargé au
# moment de la déconnexion) — consommé puis remis à vide dès lecture.
var last_disconnect_message: String = ""

func _ready() -> void:
	NetworkManager.player_disconnected.connect(_on_peer_disconnected)
	NetworkManager.server_disconnected.connect(_on_host_disconnected)
	NetworkManager.connection_succeeded.connect(_on_connected_to_host)

func _on_peer_disconnected(peer_id: int) -> void:
	if not map_generated:
		return
	if not (peer_id in run_peer_ids):
		return
	ConnectionOverlay.show_peer_lost("Joueur déconnecté. En attente de reconnexion...")

func _on_host_disconnected() -> void:
	if not map_generated:
		return
	# Godot émet aussi peer_disconnected(1) pour l'hôte lui-même en plus de
	# server_disconnected() — _on_peer_disconnected() a donc pu déjà afficher
	# l'overlay avant qu'on arrive ici ; il faut le masquer explicitement,
	# rien d'autre ne le ferait sur ce chemin.
	ConnectionOverlay.hide_overlay()
	last_disconnect_message = "Hôte déconnecté."
	reset_run_state()
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")

# Remet à zéro tout l'état de run — nécessaire avant de revenir au menu
# (bouton "Abandonner" ou hôte parti) : sans ça, map_generated resterait à
# true et un Solo/nouvel hébergement ultérieur reprendrait silencieusement
# cette run abandonnée au lieu d'en démarrer une nouvelle.
func reset_run_state() -> void:
	floors = []
	current_floor_index = 0
	current_position_in_floor = 0
	map_generated = false
	is_boss_combat = false
	pending_event = null
	players.clear()
	players_ready = false
	run_peer_ids.clear()
	pending_node_picks.clear()
	pending_turn_ready.clear()
	pending_combat_finished.clear()
	pending_restart.clear()
	downed_peer_ids.clear()
	pending_encounter_index = -1
	pending_enemy_damage.clear()
	peer_client_tokens.clear()
	in_combat = false

# Hôte uniquement : peer_id -> token, alimenté par chaque handshake entrant.
var peer_client_tokens: Dictionary = {}
signal peer_reconnected(peer_id: int)

func _on_connected_to_host() -> void:
	if NetworkManager.is_host():
		return
	_submit_client_token.rpc_id(1, NetworkManager.local_client_token)

@rpc("any_peer", "call_remote", "reliable")
func _submit_client_token(token: String) -> void:
	if not NetworkManager.is_host():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	peer_client_tokens[sender_id] = token
	_try_reconnect_match(sender_id, token)

# Hôte uniquement. Cherche dans run_peer_ids un ANCIEN peer_id (déjà membre
# de la run, actuellement déconnecté) dont le token enregistré correspond —
# si trouvé, corrige son identité localement puis diffuse la correction à
# tous les pairs connectés (pas seulement run_peer_ids : chaque pair a aussi
# sa propre copie de players[] à corriger).
# Recherche via peer_client_tokens (toujours à jour dès qu'un handshake
# arrive) plutôt que via un champ PlayerState pré-rempli une seule fois :
# start_multiplayer_run() peut être appelé avant que le token du premier
# handshake n'ait eu le temps d'arriver (aucune synchronisation entre les
# deux), donc un PlayerState.client_token figé au moment du spawn pourrait
# rester vide indéfiniment — peer_client_tokens, lui, se met à jour dès que
# le RPC arrive, quel que soit le moment.
func _try_reconnect_match(new_peer_id: int, token: String) -> void:
	if token.is_empty():
		return
	for old_id in run_peer_ids:
		if old_id == new_peer_id:
			continue
		if peer_client_tokens.get(old_id, "") == token:
			var idx: int = run_peer_ids.find(old_id)
			if idx != -1:
				run_peer_ids[idx] = new_peer_id
			for p: PlayerState in players:
				if p.peer_id == old_id:
					p.peer_id = new_peer_id
					break
			_broadcast_peer_reconnect.rpc(old_id, new_peer_id)
			ConnectionOverlay.hide_overlay()
			peer_reconnected.emit(new_peer_id)
			if not in_combat:
				_send_full_resync(new_peer_id)
			return

@rpc("authority", "call_remote", "reliable")
func _broadcast_peer_reconnect(old_peer_id: int, new_peer_id: int) -> void:
	var idx: int = run_peer_ids.find(old_peer_id)
	if idx != -1:
		run_peer_ids[idx] = new_peer_id
	for p: PlayerState in players:
		if p.peer_id == old_peer_id:
			p.peer_id = new_peer_id
			break

# true pendant qu'un combat est en cours pour cette run — mis à jour par
# CombatManager. Sert à savoir si une reconnexion peut renvoyer le joueur
# directement sur la carte (_try_reconnect_match) : reconnecter en plein
# combat n'est pas encore géré (nécessite un instantané de combat séparé,
# pas construit ici), donc on ne tente pas la resynchronisation dans ce cas
# — le joueur reste sur MainMenu.tscn en attendant.
var in_combat: bool = false

func submit_card_picked(resource_path: String) -> void:
	if run_peer_ids.size() <= 1 or NetworkManager.is_host():
		return
	_receive_card_picked.rpc_id(1, resource_path)

@rpc("any_peer", "call_remote", "reliable")
func _receive_card_picked(resource_path: String) -> void:
	if not NetworkManager.is_host():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	for p: PlayerState in players:
		if p.peer_id == sender_id:
			var card: CardData = load(resource_path)
			var dup: CardData = card.duplicate(true)
			dup.template_path = resource_path
			p.deck.append(dup)
			return

func submit_gem_picked(resource_path: String) -> void:
	if run_peer_ids.size() <= 1 or NetworkManager.is_host():
		return
	_receive_gem_picked.rpc_id(1, resource_path)

@rpc("any_peer", "call_remote", "reliable")
func _receive_gem_picked(resource_path: String) -> void:
	if not NetworkManager.is_host():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	for p: PlayerState in players:
		if p.peer_id == sender_id:
			var gem: GemData = load(resource_path)
			var dup: GemData = gem.duplicate(true)
			dup.template_path = resource_path
			p.owned_gems.append(dup)
			return

# Index dans player.deck — sûr car les RPC fiables d'un même émetteur vers un
# même récepteur préservent l'ordre : tant que chaque ajout précédent a déjà
# été envoyé avant un retrait, les deux copies restent alignées par index.
func submit_card_removed(index: int) -> void:
	if run_peer_ids.size() <= 1 or NetworkManager.is_host():
		return
	_receive_card_removed.rpc_id(1, index)

@rpc("any_peer", "call_remote", "reliable")
func _receive_card_removed(index: int) -> void:
	if not NetworkManager.is_host():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	for p: PlayerState in players:
		if p.peer_id == sender_id:
			if index >= 0 and index < p.deck.size():
				p.deck.remove_at(index)
			return

# Hôte uniquement. Envoie un instantané complet de la run à un pair qui vient
# de se reconnecter, pour qu'il retrouve MapView.tscn pleinement fonctionnel
# au lieu de rester bloqué sur MainMenu.tscn (limite de la tranche
# précédente). N'est appelé que si !in_combat (cf. commentaire sur ce champ).
func _send_full_resync(target_peer_id: int) -> void:
	_receive_full_resync.rpc_id(
		target_peer_id,
		_serialize_floors(),
		current_floor_index,
		current_position_in_floor,
		is_boss_combat,
		run_peer_ids,
		_serialize_players(),
	)

func _serialize_players() -> Array:
	var out: Array = []
	for p: PlayerState in players:
		var deck_paths: Array = []
		for c: CardData in p.deck:
			deck_paths.append(c.template_path)
		var gem_paths: Array = []
		for g: GemData in p.owned_gems:
			gem_paths.append(g.template_path)
		out.append({
			"peer_id": p.peer_id,
			"current_hp": p.current_hp,
			"max_hp": p.max_hp,
			"deck": deck_paths,
			"owned_gems": gem_paths,
			"starting_event_resolved": p.starting_event_resolved,
		})
	return out

# Ne reçu que par le pair qui vient de se reconnecter (rpc_id ciblé, jamais
# diffusé). gems_locked n'est volontairement pas transmis : MapView._ready()
# le remet de toute façon inconditionnellement à false juste après.
@rpc("authority", "call_remote", "reliable")
func _receive_full_resync(serialized_floors: Array, f_idx: int, pos_idx: int, boss: bool, peer_ids: Array, serialized_players: Array) -> void:
	floors = _deserialize_floors(serialized_floors)
	current_floor_index = f_idx
	current_position_in_floor = pos_idx
	is_boss_combat = boss
	run_peer_ids = []
	for id in peer_ids:
		run_peer_ids.append(id)
	players = _deserialize_players(serialized_players)
	map_generated = true
	players_ready = true
	get_tree().change_scene_to_file("res://scenes/map/MapView.tscn")

func _deserialize_players(data: Array) -> Array[PlayerState]:
	var out: Array[PlayerState] = []
	for d: Dictionary in data:
		var state := PlayerState.new()
		state.peer_id = d["peer_id"]
		state.current_hp = d["current_hp"]
		state.max_hp = d["max_hp"]
		for path in d["deck"]:
			var card: CardData = load(path).duplicate(true)
			card.template_path = path
			state.deck.append(card)
		for path in d["owned_gems"]:
			var gem: GemData = load(path).duplicate(true)
			gem.template_path = path
			state.owned_gems.append(gem)
		state.starting_event_resolved = d["starting_event_resolved"]
		out.append(state)
	return out

func _generate_map(floor_count: int) -> void:
	var generator := MapGenerator.new()
	floors = generator.generate_map(floor_count)
	current_floor_index = 0
	current_position_in_floor = 0
	map_generated = true
	players_ready = false

func start_new_run(floor_count: int = 8) -> void:
	_generate_map(floor_count)
	run_peer_ids = [multiplayer.get_unique_id()]

# Hôte uniquement : génère la carte (le RNG n'est pas seedé, chaque pair
# obtiendrait une carte différente s'il générait la sienne) et la diffuse.
func start_multiplayer_run(floor_count: int = 8) -> void:
	if not NetworkManager.is_host():
		push_error("start_multiplayer_run() doit être appelé uniquement par l'hôte.")
		return
	_generate_map(floor_count)
	run_peer_ids = [1]
	for id in multiplayer.get_peers():
		run_peer_ids.append(id)
	_receive_map.rpc(_serialize_floors(), run_peer_ids, current_floor_index, current_position_in_floor)

@rpc("authority", "call_remote", "reliable")
func _receive_map(serialized_floors: Array, peer_ids: Array, starting_floor_index: int, starting_position_in_floor: int) -> void:
	floors = _deserialize_floors(serialized_floors)
	current_floor_index = starting_floor_index
	current_position_in_floor = starting_position_in_floor
	map_generated = true
	players_ready = false
	run_peer_ids = []
	for id in peer_ids:
		run_peer_ids.append(id)
	get_tree().change_scene_to_file("res://scenes/map/MapView.tscn")

func _serialize_floors() -> Array:
	var out: Array = []
	for floor_nodes in floors:
		var floor_out: Array = []
		for node: MapNode in floor_nodes:
			floor_out.append({
				"type": node.type,
				"floor_index": node.floor_index,
				"position_in_floor": node.position_in_floor,
				"connections": node.connections.duplicate(),
				"visual_offset": node.visual_offset,
			})
		out.append(floor_out)
	return out

func _deserialize_floors(data: Array) -> Array[Array]:
	var out: Array[Array] = []
	for floor_data in data:
		var floor_nodes: Array[MapNode] = []
		for node_data: Dictionary in floor_data:
			var node := MapNode.new()
			node.type = node_data["type"]
			node.floor_index = node_data["floor_index"]
			node.position_in_floor = node_data["position_in_floor"]
			var conns: Array[int] = []
			for c in node_data["connections"]:
				conns.append(c)
			node.connections = conns
			node.visual_offset = node_data["visual_offset"]
			floor_nodes.append(node)
		out.append(floor_nodes)
	return out

# Construit players[] pour ce pair à partir de son propre contenu de départ
# local (deck/gemmes — fichiers identiques chez tous les pairs, donc jamais
# transmis par le réseau). Appelé depuis MapView._ready() car starting_deck/
# starting_gems sont des @export qui n'existent que sur cette instance de
# scène ; RunManager (autoload) n'y a pas accès directement.
func build_players_from_starting_content(starting_deck: Array[CardData], starting_gems: Array[GemData]) -> void:
	players.clear()
	for id in run_peer_ids:
		var state := PlayerState.new()
		state.peer_id = id
		for card in starting_deck:
			var card_dup: CardData = card.duplicate(true)
			card_dup.template_path = card.resource_path
			state.deck.append(card_dup)
		for gem in starting_gems:
			var gem_dup: GemData = gem.duplicate(true)
			gem_dup.template_path = gem.resource_path
			state.owned_gems.append(gem_dup)
		players.append(state)
	players_ready = true

func get_local_player() -> PlayerState:
	var my_id: int = multiplayer.get_unique_id()
	for p in players:
		if p.peer_id == my_id:
			return p
	push_error("get_local_player(): aucun PlayerState pour peer_id %d" % my_id)
	return null

func get_current_node() -> MapNode:
	return floors[current_floor_index][current_position_in_floor]

# Point d'entrée appelé par MapView sur chaque pair quand un joueur clique une
# case (hors START). En solo, résout tout de suite et de façon synchrone —
# aucun round-trip réseau, comportement inchangé par rapport à avant.
func submit_node_pick(map_node: MapNode) -> void:
	if run_peer_ids.size() <= 1:
		_apply_node_choice(map_node)
		return
	if NetworkManager.is_host():
		_register_pick(multiplayer.get_unique_id(), map_node.floor_index, map_node.position_in_floor)
	else:
		_submit_pick_to_host.rpc_id(1, map_node.floor_index, map_node.position_in_floor)

@rpc("any_peer", "call_remote", "reliable")
func _submit_pick_to_host(floor_index: int, position_in_floor: int) -> void:
	if not NetworkManager.is_host():
		return
	_register_pick(multiplayer.get_remote_sender_id(), floor_index, position_in_floor)

# Hôte uniquement. Le paramètre peer_id est explicite plutôt que de rappeler
# get_remote_sender_id() ici, car cette fonction est aussi appelée directement
# (hors RPC) pour le propre choix de l'hôte — get_remote_sender_id() n'a de
# sens que pendant l'exécution d'un appel RPC entrant.
func _register_pick(peer_id: int, floor_index: int, position_in_floor: int) -> void:
	if floor_index < 0 or floor_index >= floors.size():
		return
	var floor_nodes: Array = floors[floor_index]
	if position_in_floor < 0 or position_in_floor >= floor_nodes.size():
		return
	pending_node_picks[peer_id] = floor_nodes[position_in_floor]
	if pending_node_picks.size() >= run_peer_ids.size():
		_resolve_votes()

# Hôte uniquement. pick_random() sur les valeurs brutes (PAS dédupliquées par
# case) : une case choisie par 2 joueurs a deux fois plus de chances de sortir.
func _resolve_votes() -> void:
	var winner: MapNode = pending_node_picks.values().pick_random()
	pending_node_picks.clear()
	_apply_node_choice(winner)
	_broadcast_node_choice.rpc(winner.floor_index, winner.position_in_floor)

@rpc("authority", "call_remote", "reliable")
func _broadcast_node_choice(floor_index: int, position_in_floor: int) -> void:
	_apply_node_choice(floors[floor_index][position_in_floor])

# Hôte uniquement. Tire l'indice dans le pool (pool_size = taille de
# possible_encounters/possible_boss_encounters, identique chez tous les
# pairs) et le diffuse. randi() % pool_size plutôt que pick_random() sur le
# tableau lui-même : RunManager n'a pas accès à encounter_pool (@export sur
# CombatManager), seul l'indice a besoin de voyager.
func choose_combat_encounter(pool_size: int) -> int:
	var index: int = randi() % pool_size
	if run_peer_ids.size() > 1:
		_receive_encounter_index.rpc(index)
	return index

@rpc("authority", "call_remote", "reliable")
func _receive_encounter_index(index: int) -> void:
	pending_encounter_index = index
	encounter_chosen.emit(index)

# Hôte uniquement : peer_id -> true une fois son tour local terminé pour ce
# combat. Remis à vide après résolution (même limite acceptée que
# pending_node_picks : si un pair quitte le combat après avoir voté mais
# avant que le tally se termine, son entrée traîne — pas géré, comme pour le
# vote de carte).
var pending_turn_ready: Dictionary = {}
signal enemy_phase_started

func submit_end_turn() -> void:
	if run_peer_ids.size() <= 1:
		enemy_phase_started.emit()
		return
	if NetworkManager.is_host():
		_register_turn_ready(multiplayer.get_unique_id())
	else:
		_submit_end_turn_to_host.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _submit_end_turn_to_host() -> void:
	if not NetworkManager.is_host():
		return
	_register_turn_ready(multiplayer.get_remote_sender_id())

func _register_turn_ready(peer_id: int) -> void:
	pending_turn_ready[peer_id] = true
	_check_turn_ready_complete()

# Le nombre de pairs actifs peut baisser en cours de tally (un pair meurt
# après avoir déjà soumis son tour, ou meurt avant de le soumettre) — appelé
# à la fois par _register_turn_ready() et _register_peer_down() pour que le
# tally se complète dès que le seuil est atteint, peu importe lequel des
# deux événements arrive en dernier.
func _check_turn_ready_complete() -> void:
	var active_count: int = run_peer_ids.size() - downed_peer_ids.size()
	if active_count <= 0:
		return
	if pending_turn_ready.size() >= active_count:
		pending_turn_ready.clear()
		enemy_phase_started.emit()
		_broadcast_enemy_phase.rpc()

@rpc("authority", "call_remote", "reliable")
func _broadcast_enemy_phase() -> void:
	enemy_phase_started.emit()

# Pair -> true une fois son popup de récompense fermé pour ce combat. Remis à
# vide après résolution. Contrairement à pending_turn_ready, n'a jamais besoin
# de soustraire downed_peer_ids : par construction (cf. CombatManager._on_
# enemy_died), personne n'est plus "à terre" au moment où un pair atteint ce
# tally.
var pending_combat_finished: Dictionary = {}
signal combat_finished

func submit_combat_finished() -> void:
	if run_peer_ids.size() <= 1:
		combat_finished.emit()
		return
	if NetworkManager.is_host():
		_register_combat_finished(multiplayer.get_unique_id())
	else:
		_submit_combat_finished_to_host.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _submit_combat_finished_to_host() -> void:
	if not NetworkManager.is_host():
		return
	_register_combat_finished(multiplayer.get_remote_sender_id())

func _register_combat_finished(peer_id: int) -> void:
	pending_combat_finished[peer_id] = true
	if pending_combat_finished.size() >= run_peer_ids.size():
		pending_combat_finished.clear()
		combat_finished.emit()
		_broadcast_combat_finished.rpc()

@rpc("authority", "call_remote", "reliable")
func _broadcast_combat_finished() -> void:
	combat_finished.emit()

# Même schéma que pending_combat_finished : une défaite d'équipe implique que
# tout le monde est déjà à terre/spectateur, pas besoin de soustraire
# downed_peer_ids ici non plus.
var pending_restart: Dictionary = {}
signal restart_ready

func submit_restart() -> void:
	if run_peer_ids.size() <= 1:
		restart_ready.emit()
		return
	if NetworkManager.is_host():
		_register_restart(multiplayer.get_unique_id())
	else:
		_submit_restart_to_host.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _submit_restart_to_host() -> void:
	if not NetworkManager.is_host():
		return
	_register_restart(multiplayer.get_remote_sender_id())

func _register_restart(peer_id: int) -> void:
	pending_restart[peer_id] = true
	if pending_restart.size() >= run_peer_ids.size():
		pending_restart.clear()
		restart_ready.emit()
		_broadcast_restart.rpc()

@rpc("authority", "call_remote", "reliable")
func _broadcast_restart() -> void:
	restart_ready.emit()

# Hôte -> tous (y compris l'auteur, qui n'a jamais touché downed_peer_ids
# localement lui-même — c'est la seule façon dont son propre downed_peer_ids
# se peuple). Pas de file d'attente pending_* nécessaire ici contrairement à
# enemy_damage_received : une mort ne peut survenir que pendant ENEMY_TURN,
# qui n'est atteint qu'une fois que TOUS les pairs ont déjà soumis leur tour
# au moins une fois — donc _ready() (et son .connect() sur team_wiped) a
# forcément déjà fini de tourner partout avant qu'une mort soit possible.
var downed_peer_ids: Array[int] = []
signal peer_downed(peer_id: int)
signal team_wiped

func submit_player_down() -> void:
	if run_peer_ids.size() <= 1:
		team_wiped.emit()
		return
	if NetworkManager.is_host():
		_register_peer_down(multiplayer.get_unique_id())
	else:
		_submit_player_down_to_host.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _submit_player_down_to_host() -> void:
	if not NetworkManager.is_host():
		return
	_register_peer_down(multiplayer.get_remote_sender_id())

func _register_peer_down(peer_id: int) -> void:
	if peer_id in downed_peer_ids:
		return
	downed_peer_ids.append(peer_id)
	_broadcast_peer_down.rpc(peer_id)
	peer_downed.emit(peer_id)
	if downed_peer_ids.size() >= run_peer_ids.size():
		_broadcast_team_wipe.rpc()
		team_wiped.emit()
		return
	_check_turn_ready_complete()

@rpc("authority", "call_remote", "reliable")
func _broadcast_peer_down(peer_id: int) -> void:
	if peer_id in downed_peer_ids:
		return
	downed_peer_ids.append(peer_id)
	peer_downed.emit(peer_id)

@rpc("authority", "call_remote", "reliable")
func _broadcast_team_wipe() -> void:
	team_wiped.emit()

# Pas de file d'attente pending_* ici (contrairement à enemy_damage_received) :
# la seule source possible d'un changement de PV joueur est une attaque
# ennemie pendant ENEMY_TURN, qui ne peut être atteint qu'une fois que TOUS
# les pairs actifs ont déjà soumis leur tour au moins une fois — donc
# _ready() (et son .connect() sur player_hp_updated) a forcément déjà fini de
# tourner partout avant qu'un tel événement soit possible.
signal player_hp_updated(peer_id: int, current_hp: int)

func submit_player_hp(current_hp: int) -> void:
	if run_peer_ids.size() <= 1:
		return
	if NetworkManager.is_host():
		_relay_player_hp(1, current_hp)
	else:
		_submit_player_hp_to_host.rpc_id(1, current_hp)

@rpc("any_peer", "call_remote", "reliable")
func _submit_player_hp_to_host(current_hp: int) -> void:
	if not NetworkManager.is_host():
		return
	_relay_player_hp(multiplayer.get_remote_sender_id(), current_hp)

func _relay_player_hp(origin_peer_id: int, current_hp: int) -> void:
	if origin_peer_id != 1:
		player_hp_updated.emit(origin_peer_id, current_hp)
	for id in run_peer_ids:
		if id != origin_peer_id and id != 1:
			_receive_player_hp.rpc_id(id, origin_peer_id, current_hp)

@rpc("authority", "call_remote", "reliable")
func _receive_player_hp(origin_peer_id: int, current_hp: int) -> void:
	player_hp_updated.emit(origin_peer_id, current_hp)

signal enemy_damage_received(spawn_id: int, amount: int)

# Dégâts reçus par le réseau avant que le CombatManager de CE pair n'ait fini
# de connecter enemy_damage_received (même risque de course que
# pending_encounter_index, généralisé en file car plusieurs dégâts peuvent
# s'accumuler avant que quiconque écoute). Vidée par CombatManager juste
# après avoir connecté le signal.
var pending_enemy_damage: Array[Dictionary] = []

func _emit_or_queue_enemy_damage(spawn_id: int, amount: int) -> void:
	if enemy_damage_received.get_connections().is_empty():
		pending_enemy_damage.append({"spawn_id": spawn_id, "amount": amount})
	else:
		enemy_damage_received.emit(spawn_id, amount)

# Appelé par CombatManager sur le pair qui vient d'appliquer les dégâts en
# local, de façon optimiste — prévient les autres pairs du même combat.
func submit_enemy_damage(spawn_id: int, amount: int) -> void:
	if run_peer_ids.size() <= 1:
		return
	if NetworkManager.is_host():
		_relay_enemy_damage(1, spawn_id, amount)
	else:
		_submit_enemy_damage_to_host.rpc_id(1, spawn_id, amount)

@rpc("any_peer", "call_remote", "reliable")
func _submit_enemy_damage_to_host(spawn_id: int, amount: int) -> void:
	if not NetworkManager.is_host():
		return
	_relay_enemy_damage(multiplayer.get_remote_sender_id(), spawn_id, amount)

# Hôte uniquement. Applique en local chez l'hôte si l'auteur n'est pas
# l'hôte lui-même (l'auteur a déjà appliqué en optimiste, ne jamais lui
# renvoyer sa propre action), puis relaie individuellement (rpc_id, pas de
# primitive Godot pour "broadcast sauf X") à tous les AUTRES pairs, en
# excluant systématiquement l'auteur.
func _relay_enemy_damage(origin_peer_id: int, spawn_id: int, amount: int) -> void:
	if origin_peer_id != 1:
		_emit_or_queue_enemy_damage(spawn_id, amount)
	for id in run_peer_ids:
		if id != origin_peer_id and id != 1:
			_receive_enemy_damage.rpc_id(id, spawn_id, amount)

@rpc("authority", "call_remote", "reliable")
func _receive_enemy_damage(spawn_id: int, amount: int) -> void:
	_emit_or_queue_enemy_damage(spawn_id, amount)

# Tourne à l'identique sur chaque pair : en direct depuis _resolve_votes() côté
# hôte, depuis le récepteur RPC côté client, et depuis le chemin rapide solo.
# is_boss_combat est fonction pure de map_node.type (déterministe, aucun RNG)
# donc safe à définir ici sans RPC dédié. pending_event N'EST PAS touché ici —
# ça reste le job de MapView._start_event() (RNG indépendant par pair, même
# précédent déjà accepté que CombatManager.encounter_pool.pick_random()).
func _apply_node_choice(map_node: MapNode) -> void:
	current_floor_index = map_node.floor_index
	current_position_in_floor = map_node.position_in_floor
	if map_node.type == MapNode.NodeType.END:
		is_boss_combat = true
	elif map_node.type == MapNode.NodeType.COMBAT:
		is_boss_combat = false
	node_choice_applied.emit(map_node)
