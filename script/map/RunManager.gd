extends Node

const SOLO_SAVE_PATH: String = "user://solo_save.dat"
const SAVE_FORMAT_VERSION: int = 1
const MULTI_SAVE_PATH: String = "user://multi_save.dat"
const MULTI_SAVE_FORMAT_VERSION: int = 1
const DEFAULT_CHARACTER_PATH: String = "res://ressourcesCharacters/personnage_de_base.tres"

# RNG unique de la run en cours — tout ce qui détermine réellement son
# déroulement (carte, rencontres, événements, récompenses, mélange du deck)
# pioche ici plutôt que dans le RNG global de Godot, pour qu'une seed donnée
# reproduise toujours la même run. Le tremblement d'écran, le décalage
# cosmétique des nœuds de carte et le départage de vote simultané restent
# volontairement sur le RNG global (purement visuels ou liés au timing des
# joueurs, pas à la génération de contenu).
var run_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var run_seed: int = 0

func _init_run_rng(seed_value: int) -> void:
	run_seed = seed_value
	run_rng.seed = seed_value

var floors: Array[Array] = []
var current_floor_index: int = 0
var current_position_in_floor: int = 0
# true tant que le nœud courant (COMBAT/END/EVENT) n'a pas été résolu — posé
# par _apply_node_choice(), remis à faux par
# CombatManager._on_combat_finished() / EventView._on_continue_pressed().
# Sert uniquement à la sauvegarde solo : recharger une sauvegarde relance ce
# nœud à neuf plutôt que de tenter de restaurer son état interne.
#
# La sauvegarde elle-même ne s'écrit sur disque QU'à ces moments précis
# (jamais au clic sur "Sauvegarder et quitter", qui se contente de relire
# le fichier déjà à jour) : entrée dans le nœud (_apply_node_choice),
# victoire juste avant le choix des récompenses (CombatManager._on_enemy_died),
# et sortie du nœud d'ÉVÉNEMENT (EventView._on_continue_pressed()). Sortie de
# COMBAT (_on_combat_finished()) ne sauvegarde volontairement plus rien
# (demande explicite) : le dernier point de contrôle d'un combat reste celui
# pris juste avant les récompenses, pas celui d'après — recharger entre la
# fin du combat et le prochain nœud choisi rejoue donc le choix des
# récompenses plutôt que de reprendre sur la carte. Ainsi le fichier reflète
# toujours un point de progression réellement acquis — jamais un dégât ou un
# tour de combat en cours — sans avoir besoin de retenir/restaurer un
# instantané séparé pour chaque champ concerné.
var current_node_pending: bool = false
# true entre la mort du dernier ennemi et la fermeture du popup de
# récompenses : au chargement, ce nœud ne doit pas être rejoué (l'ennemi est
# déjà vaincu), juste réafficher le choix de récompenses.
var current_node_awaiting_rewards: bool = false
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

# true entre load_multi_run_from_disk() et resume_multiplayer_run() : salon de
# reprise en cours, pas encore en jeu. Distinct de map_generated (qui pilote
# le bouton engrenage de SettingsOverlay et la pause de _on_peer_disconnected)
# pour que ni l'un ni l'autre ne s'active pendant l'attente en salon.
var resume_mode: bool = false
# Un booléen par emplacement de joueurs[] d'une sauvegarde multi chargée :
# true si ce joueur d'origine s'est reconnecté cette session. Reconstruit par
# _lobby_roster_flags() à chaque reconnexion, lu par MainMenu pour afficher le
# statut du salon et n'activer le bouton de reprise qu'une fois tout le monde
# revenu.
var lobby_roster_flags: Array[bool] = []
# Émis côté client quand l'hôte a rejeté sa tentative de rejoindre un salon de
# reprise (token absent de la sauvegarde) — MainMenu affiche le message.
signal join_rejected(reason: String)

# peer_id -> resource_path du CharacterData choisi par ce joueur, alimenté
# pendant l'attente en salon (submit_character_pick), figé au moment de
# start_multiplayer_run()/start_new_run() et diffusé aux clients via
# _receive_map — jamais modifié après le début du run. Lu par
# build_players_from_starting_content() via _resolve_character().
var character_picks: Dictionary = {}

func submit_character_pick(character_path: String) -> void:
	if NetworkManager.is_host():
		character_picks[multiplayer.get_unique_id()] = character_path
	else:
		_submit_character_pick_to_host.rpc_id(1, character_path)

@rpc("any_peer", "call_remote", "reliable")
func _submit_character_pick_to_host(character_path: String) -> void:
	if not NetworkManager.is_host():
		return
	character_picks[multiplayer.get_remote_sender_id()] = character_path

# Hôte uniquement. Vrai une fois que l'hôte lui-même ET chaque pair
# actuellement connecté (multiplayer.get_peers()) ont soumis un choix — sert
# à activer "Démarrer la partie" côté MainMenu pour une partie fraîche.
func all_connected_peers_picked_character() -> bool:
	if not character_picks.has(1):
		return false
	for id in multiplayer.get_peers():
		if not character_picks.has(id):
			return false
	return true

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
	run_seed = 0
	current_floor_index = 0
	current_position_in_floor = 0
	current_node_pending = false
	current_node_awaiting_rewards = false
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
	pending_combat_reconnects.clear()
	downed_peer_ids.clear()
	pending_encounter_index = -1
	pending_enemy_damage.clear()
	peer_client_tokens.clear()
	in_combat = false
	active_combat_manager = null
	pending_combat_resync = {}
	resume_mode = false
	lobby_roster_flags.clear()
	character_picks.clear()

# Hôte uniquement : peer_id -> token, alimenté par chaque handshake entrant.
var peer_client_tokens: Dictionary = {}
signal peer_reconnected(peer_id: int)

# Hôte uniquement : new_peer_id -> old_id, pairs revenus pendant un tour
# ennemi (cf. _try_reconnect_match()/flush_pending_combat_reconnects()).
var pending_combat_reconnects: Dictionary = {}

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
	if resume_mode:
		_try_lobby_rejoin_match(sender_id, token)
	else:
		_try_reconnect_match(sender_id, token)

# Hôte uniquement, salon de reprise (resume_mode == true, cf. load_multi_run_
# from_disk()). Distinct de _try_reconnect_match() : ici run_peer_ids contient
# des sentinelles -1 (joueur d'origine pas encore revenu cette session), pas
# d'anciens peer_id périmés d'une session en cours — mécanisme structurellement
# différent, pas la peine de les unifier.
func _try_lobby_rejoin_match(new_peer_id: int, token: String) -> void:
	if token.is_empty():
		return
	for i in players.size():
		var p: PlayerState = players[i]
		if p.client_token == token and p.peer_id == -1:
			p.peer_id = new_peer_id
			run_peer_ids[i] = new_peer_id
			lobby_roster_flags = _lobby_roster_flags()
			_broadcast_lobby_roster.rpc(lobby_roster_flags)
			return
	var reason: String = "Cette sauvegarde ne vous inclut pas parmi les joueurs d'origine."
	for p: PlayerState in players:
		if p.client_token == token:
			reason = "Vous êtes déjà connecté depuis un autre appareil."
			break
	_receive_join_rejection.rpc_id(new_peer_id, reason)

func _lobby_roster_flags() -> Array[bool]:
	var out: Array[bool] = []
	for p: PlayerState in players:
		out.append(p.peer_id != -1)
	return out

@rpc("authority", "call_remote", "reliable")
func _broadcast_lobby_roster(flags: Array) -> void:
	resume_mode = true
	lobby_roster_flags = []
	for f in flags:
		lobby_roster_flags.append(f)

# Le rejet ne force jamais la déconnexion côté hôte (ordre RPC-avant-
# disconnect_peer() non garanti) : c'est le pair rejeté qui se déconnecte
# lui-même en recevant ce RPC fiable.
@rpc("authority", "call_remote", "reliable")
func _receive_join_rejection(reason: String) -> void:
	join_rejected.emit(reason)
	NetworkManager.close_connection()

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
			# Renomme l'entrée sous le nouvel id plutôt que de la perdre : si le
			# joueur avait déjà soumis son tour avant de se déconnecter, ce
			# statut doit survivre au changement de peer_id, sans quoi son
			# client réaffiche un bouton "Fin de tour" cliquable qui ne devrait
			# plus l'être. Pas besoin de _check_turn_ready_complete() ici : tant
			# que l'hôte est en pause, lui-même ne peut pas avoir déjà soumis
			# son propre tour, donc le tally ne peut pas être déjà complet.
			var already_ended_turn: bool = pending_turn_ready.has(old_id)
			if already_ended_turn:
				pending_turn_ready.erase(old_id)
				pending_turn_ready[new_peer_id] = true
			_broadcast_peer_reconnect.rpc(old_id, new_peer_id)
			# Capture/envoie l'instantané AVANT de dépausser (hide_overlay()
			# relance juste après les Tweens/timers de l'hôte) : évite toute
			# dépendance fragile à l'ordre d'exécution entre unpause et lecture
			# de l'état des ennemis.
			if in_combat and is_instance_valid(active_combat_manager) and not active_combat_manager.combat_over:
				if active_combat_manager.current_state == CombatManager.TurnState.PLAYER_TURN:
					_send_combat_resync(new_peer_id, old_id, already_ended_turn)
				elif active_combat_manager.current_state == CombatManager.TurnState.ENEMY_TURN:
					# Reco en plein tour ennemi : dépauser va laisser ce tour ennemi
					# (déjà en cours au moment de la coupure) se terminer normalement
					# chez l'hôte et les pairs déjà connectés (lockstep), mais rien
					# de sûr à envoyer au pair revenu tant que current_state n'est
					# pas retombé à PLAYER_TURN (cf. commentaire sur
					# _send_combat_resync) — mis en attente,
					# flush_pending_combat_reconnects() le rattrapera dès que ce
					# sera le cas (turn_started côté CombatManager), y compris après
					# un Recommencer suite à une défaite d'équipe survenue pendant
					# ce même tour ennemi.
					pending_combat_reconnects[new_peer_id] = old_id
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
# directement sur la carte (_try_reconnect_match), ou sur le combat en cours
# via active_combat_manager/_send_combat_resync si les conditions le
# permettent (cf. commentaires sur ces deux éléments).
var in_combat: bool = false

# Pointeur local (hôte ET client) vers le CombatManager du combat en cours,
# posé/retiré par CombatManager lui-même en même temps que in_combat.
var active_combat_manager: CombatManager = null

# Client uniquement : instantané de combat mis en attente par
# _receive_combat_resync(), consommé une seule fois par CombatManager._ready().
var pending_combat_resync: Dictionary = {}

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

func has_solo_save() -> bool:
	return FileAccess.file_exists(SOLO_SAVE_PATH)

func delete_solo_save() -> void:
	if FileAccess.file_exists(SOLO_SAVE_PATH):
		DirAccess.remove_absolute(SOLO_SAVE_PATH)

func has_multi_save() -> bool:
	return FileAccess.file_exists(MULTI_SAVE_PATH)

func delete_multi_save() -> void:
	if FileAccess.file_exists(MULTI_SAVE_PATH):
		DirAccess.remove_absolute(MULTI_SAVE_PATH)

# Un token par joueur de players[], dans le même ordre — jamais transmis par
# RPC (cf. commentaire sur PlayerState.client_token), collecté ici uniquement
# pour l'écriture sur disque. peer_id == 1 est toujours l'hôte lui-même
# (garanti par la topologie en étoile) : son token vient directement de
# NetworkManager, les autres de peer_client_tokens (alimenté à chaque
# handshake entrant, cf. _submit_client_token).
func _collect_player_tokens() -> Array:
	var out: Array = []
	for p: PlayerState in players:
		out.append(NetworkManager.local_client_token if p.peer_id == 1 else peer_client_tokens.get(p.peer_id, ""))
	return out

# Hôte uniquement. Mêmes points de contrôle que save_run_to_disk() (jamais
# d'instantané de combat en cours), format séparé car run_peer_ids/peer_id
# n'ont aucun sens après un redémarrage du process — l'identité de chaque
# joueur d'origine est portée par son token, pas par son peer_id ENet.
func save_multi_run_to_disk() -> bool:
	if not NetworkManager.is_host():
		push_error("save_multi_run_to_disk() ne doit être appelé que par l'hôte.")
		return false
	var data: Dictionary = {
		"version": MULTI_SAVE_FORMAT_VERSION,
		"floors": _serialize_floors(),
		"current_floor_index": current_floor_index,
		"current_position_in_floor": current_position_in_floor,
		"current_node_pending": current_node_pending,
		"current_node_awaiting_rewards": current_node_awaiting_rewards,
		"is_boss_combat": is_boss_combat,
		"players": _serialize_players(),
		"tokens": _collect_player_tokens(),
		"seed": run_seed,
		"rng_state": run_rng.state,
	}
	var f: FileAccess = FileAccess.open(MULTI_SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("save_multi_run_to_disk(): écriture impossible (code %d)" % FileAccess.get_open_error())
		return false
	f.store_var(data)
	f.close()
	return true

# Repeuple floors/players/etc depuis le disque, comme load_run_from_disk(),
# mais laisse map_generated à false et pose resume_mode = true à la place :
# le run n'est pas encore "en jeu", il attend en salon que les joueurs
# d'origine se reconnectent (cf. _try_lobby_rejoin_match()). C'est
# resume_multiplayer_run() qui bascule effectivement vers la partie.
func load_multi_run_from_disk() -> bool:
	if not FileAccess.file_exists(MULTI_SAVE_PATH):
		return false
	var f: FileAccess = FileAccess.open(MULTI_SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var data = f.get_var()
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return false
	floors = _deserialize_floors(data["floors"])
	current_floor_index = data["current_floor_index"]
	current_position_in_floor = data["current_position_in_floor"]
	current_node_pending = data.get("current_node_pending", false)
	current_node_awaiting_rewards = data.get("current_node_awaiting_rewards", false)
	is_boss_combat = data["is_boss_combat"]
	players = _deserialize_players(data["players"])
	var tokens: Array = data.get("tokens", [])
	for i in players.size():
		players[i].client_token = tokens[i] if i < tokens.size() else ""
		if players[i].peer_id != 1:
			players[i].peer_id = -1
	run_peer_ids = []
	for p: PlayerState in players:
		run_peer_ids.append(p.peer_id)
	players_ready = true
	resume_mode = true
	lobby_roster_flags = _lobby_roster_flags()
	if data.has("seed") and data.has("rng_state"):
		run_rng.seed = data["seed"]
		run_rng.state = data["rng_state"]
		run_seed = data["seed"]
	else:
		_init_run_rng(randi())
	return true

# N'est appelée que par _apply_node_choice() / CombatManager._on_enemy_died()
# (victoire) / CombatManager._on_combat_finished() / EventView._on_continue_pressed()
# — jamais depuis le bouton "Sauvegarder et quitter" lui-même. Ainsi l'état
# capturé correspond toujours à un point de progression réellement acquis
# (avant tout dégât/tour de combat, ou juste après une victoire/résolution),
# jamais à un instant arbitraire choisi par le joueur en pleine bagarre.
func save_run_to_disk() -> bool:
	if run_peer_ids.size() > 1:
		push_error("save_run_to_disk() ne doit être appelé qu'en solo.")
		return false
	var data: Dictionary = {
		"version": SAVE_FORMAT_VERSION,
		"floors": _serialize_floors(),
		"current_floor_index": current_floor_index,
		"current_position_in_floor": current_position_in_floor,
		"current_node_pending": current_node_pending,
		"current_node_awaiting_rewards": current_node_awaiting_rewards,
		"is_boss_combat": is_boss_combat,
		"players": _serialize_players(),
		"seed": run_seed,
		"rng_state": run_rng.state,
	}
	var f: FileAccess = FileAccess.open(SOLO_SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("save_run_to_disk(): écriture impossible (code %d)" % FileAccess.get_open_error())
		return false
	f.store_var(data)
	f.close()
	return true

# Repeuple floors/players/etc depuis le disque, exactement comme
# _receive_full_resync() le fait depuis le réseau. N'effectue aucun
# changement de scène : le caller change vers MapView.tscn, et
# MapView._ready() relance lui-même le nœud en cours si current_node_pending.
func load_run_from_disk() -> bool:
	if not FileAccess.file_exists(SOLO_SAVE_PATH):
		return false
	var f: FileAccess = FileAccess.open(SOLO_SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var data = f.get_var()
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return false
	floors = _deserialize_floors(data["floors"])
	current_floor_index = data["current_floor_index"]
	current_position_in_floor = data["current_position_in_floor"]
	current_node_pending = data.get("current_node_pending", false)
	current_node_awaiting_rewards = data.get("current_node_awaiting_rewards", false)
	is_boss_combat = data["is_boss_combat"]
	players = _deserialize_players(data["players"])
	map_generated = true
	players_ready = true
	run_peer_ids = [1]
	# Sauvegarde antérieure à la fonctionnalité seed : pas de champ "seed"/
	# "rng_state" -> reprise sur une seed aléatoire, comme avant. Sinon,
	# seed DOIT être assignée avant state : assigner .seed réinitialise
	# aussi l'état interne (confirmé empiriquement), donc l'ordre inverse
	# écraserait l'état restauré avec celui dérivé de la seed seule.
	if data.has("seed") and data.has("rng_state"):
		run_rng.seed = data["seed"]
		run_rng.state = data["rng_state"]
		run_seed = data["seed"]
	else:
		_init_run_rng(randi())
	return true

# Instantané pur du combat en cours, sans effet de bord réseau — utilisé par
# _send_combat_resync (reconnexion réseau en plein combat, tranche 3b-ii ;
# la sauvegarde solo ne s'en sert plus, cf. save_run_to_disk()). Retourne {}
# si le capturer maintenant serait incorrect :
# hors combat, combat déjà terminé, ou pendant ENEMY_TURN. Ce dernier cas
# n'est pas qu'un problème de lockstep entre pairs : la restauration
# (CombatManager._ready()) reprend TOUJOURS à PLAYER_TURN sans rejouer
# enemy_play_turn() — capturer pendant ENEMY_TURN ferait donc sauter
# silencieusement les attaques pas encore exécutées ce tour-ci, y compris
# en solo.
func _capture_combat_snapshot(is_down_for: bool, already_ended_turn: bool) -> Dictionary:
	if not in_combat or not is_instance_valid(active_combat_manager):
		return {}
	var cm: CombatManager = active_combat_manager
	if cm.combat_over or cm.current_state != CombatManager.TurnState.PLAYER_TURN:
		return {}
	var enemies_snapshot: Array = []
	for e: Enemy in cm.enemies:
		if is_instance_valid(e):
			enemies_snapshot.append({
				"spawn_id": e.combat_spawn_id,
				"current_hp": e.current_hp,
				"current_block": e.current_block,
				"current_intention": e.current_intention,
				"sequence_index": e.sequence_index,
			})
	return {
		"encounter_path": cm.current_encounter.resource_path,
		"enemies": enemies_snapshot,
		"is_down": is_down_for,
		"already_ended_turn": already_ended_turn,
	}

# Hôte uniquement. N'est appelée que si active_combat_manager.current_state
# == PLAYER_TURN, soit tout de suite depuis _try_reconnect_match(), soit plus
# tard depuis flush_pending_combat_reconnects() : une reconnexion pendant
# ENEMY_TURN casserait le lockstep de séquence d'intentions des ennemis, qui
# ne repose QUE sur le fait qu'enemy_play_turn() tourne à l'identique sur
# chaque pair — resynchroniser un ennemi déjà à mi-séquence sans rejouer les
# attaques manquées le désynchroniserait définitivement. Le cas combat_over
# déjà vrai (victoire, récompenses pas encore refermées) reste hors scope.
func _send_combat_resync(target_peer_id: int, old_id: int, already_ended_turn: bool) -> void:
	var snap: Dictionary = _capture_combat_snapshot(downed_peer_ids.has(old_id), already_ended_turn)
	_receive_combat_resync.rpc_id(
		target_peer_id,
		_serialize_floors(),
		current_floor_index,
		current_position_in_floor,
		is_boss_combat,
		run_peer_ids,
		_serialize_players(),
		snap.get("encounter_path", ""),
		snap.get("enemies", []),
		snap.get("is_down", false),
		snap.get("already_ended_turn", false),
	)

# Ne reçue que par le pair qui vient de se reconnecter en plein combat
# (rpc_id ciblé). Contrairement à _receive_full_resync, atterrit sur
# Combat.tscn : les champs combat-spécifiques sont consommés une seule fois
# par CombatManager._ready() via pending_combat_resync.
@rpc("authority", "call_remote", "reliable")
func _receive_combat_resync(serialized_floors: Array, f_idx: int, pos_idx: int, boss: bool, peer_ids: Array, serialized_players: Array, encounter_path: String, enemies_snapshot: Array, was_down: bool, already_ended_turn: bool) -> void:
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
	pending_combat_resync = {
		"encounter_path": encounter_path,
		"enemies": enemies_snapshot,
		"is_down": was_down,
		"already_ended_turn": already_ended_turn,
	}
	get_tree().change_scene_to_file("res://scenes/combat/Combat.tscn")

# Hôte uniquement. Rattrape les pairs mis en attente par _try_reconnect_match()
# pendant un tour ennemi, dès que current_state redevient sûr (PLAYER_TURN) :
# appelée par CombatManager._on_turn_started(). already_ended_turn est
# recalculé ici plutôt que réutilisé depuis la mise en attente — si une
# défaite d'équipe est survenue entre-temps et que le combat a été relancé
# via "Recommencer", pending_turn_ready a été vidé pour ce nouveau tour et il
# faut refléter cet état à jour, pas celui d'avant la coupure. Ignore un pair
# qui se serait redéconnecté entre-temps (plus dans multiplayer.get_peers()) :
# il devra simplement retenter sa reconnexion.
func flush_pending_combat_reconnects() -> void:
	if pending_combat_reconnects.is_empty():
		return
	var reconnects: Dictionary = pending_combat_reconnects
	pending_combat_reconnects = {}
	for new_peer_id: int in reconnects:
		if not multiplayer.get_peers().has(new_peer_id):
			continue
		_send_combat_resync(new_peer_id, reconnects[new_peer_id], pending_turn_ready.has(new_peer_id))

func _serialize_players() -> Array:
	var out: Array = []
	for p: PlayerState in players:
		var deck_data: Array = []
		for c: CardData in p.deck:
			deck_data.append(_serialize_card(c))
		var gem_paths: Array = []
		for g: GemData in p.owned_gems:
			gem_paths.append(g.template_path)
		out.append({
			"peer_id": p.peer_id,
			"current_hp": p.current_hp,
			"max_hp": p.max_hp,
			"max_mana": p.max_mana,
			"deck": deck_data,
			"owned_gems": gem_paths,
			"starting_event_resolved": p.starting_event_resolved,
		})
	return out

# equipped_gem est référencé par template_path plutôt que dupliqué à part :
# à la désérialisation, il DOIT pointer vers la même instance que celle
# stockée dans owned_gems, sinon la gemme apparaîtrait à la fois équipée et
# dans la besace.
func _serialize_card(c: CardData) -> Dictionary:
	var torn: Array = []
	for mark: Dictionary in c.torn_marks:
		var icon: Texture2D = mark.get("icon")
		torn.append({
			"icon_path": icon.resource_path if icon else "",
			"position": mark["position"],
		})
	return {
		"template_path": c.template_path,
		"equipped_gem_template_path": c.equipped_gem.template_path if c.equipped_gem else "",
		"equipped_gem_position": c.equipped_gem_position,
		"torn_marks": torn,
	}

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
		state.max_mana = d.get("max_mana", state.max_mana)
		for path in d["owned_gems"]:
			var gem: GemData = load(path).duplicate(true)
			gem.template_path = path
			state.owned_gems.append(gem)
		for card_d: Dictionary in d["deck"]:
			state.deck.append(_deserialize_card(card_d, state.owned_gems))
		state.starting_event_resolved = d["starting_event_resolved"]
		out.append(state)
	return out

func _deserialize_card(d: Dictionary, owned_gems: Array[GemData]) -> CardData:
	var path: String = d["template_path"]
	var card: CardData = load(path).duplicate(true)
	card.template_path = path
	card.equipped_gem_position = d.get("equipped_gem_position", Vector2.ZERO)
	var gem_path: String = d.get("equipped_gem_template_path", "")
	if not gem_path.is_empty():
		for g: GemData in owned_gems:
			if g.template_path == gem_path:
				card.equipped_gem = g
				break
	for mark: Dictionary in d.get("torn_marks", []):
		var icon_path: String = mark["icon_path"]
		card.torn_marks.append({
			"icon": load(icon_path) if not icon_path.is_empty() else null,
			"position": mark["position"],
		})
	return card

func _generate_map(floor_count: int) -> void:
	var generator := MapGenerator.new()
	floors = generator.generate_map(floor_count, run_rng)
	current_floor_index = 0
	current_position_in_floor = 0
	map_generated = true
	players_ready = false

# seed_value/has_explicit_seed plutôt qu'une valeur sentinelle (ex: -1) : un
# champ de saisie numérique pur pourrait légitimement contenir un nombre
# négatif, une sentinelle serait ambiguë. character_path vide (ex: MapView.
# tscn ouverte directement dans l'éditeur, sans passer par le menu) laisse
# character_picks vide — _resolve_character() repliera sur DEFAULT_CHARACTER_PATH.
func start_new_run(floor_count: int = 8, seed_value: int = 0, has_explicit_seed: bool = false, character_path: String = "") -> void:
	_init_run_rng(seed_value if has_explicit_seed else randi())
	_generate_map(floor_count)
	run_peer_ids = [multiplayer.get_unique_id()]
	character_picks = {run_peer_ids[0]: character_path} if not character_path.is_empty() else {}

# Hôte uniquement : génère la carte à partir de run_rng (seedée ci-dessous)
# et la diffuse — la seed elle-même voyage aussi par ce RPC pour que chaque
# client aligne son propre run_rng sur le même point de départ.
# character_picks voyage dans le même RPC (déjà entièrement rempli à ce
# stade : le salon multi n'active "Démarrer la partie" qu'une fois que tous
# les pairs connectés ont soumis leur choix, cf. MainMenu._process()) — pas
# de round-trip réseau séparé nécessaire pour ça.
func start_multiplayer_run(floor_count: int = 8, seed_value: int = 0, has_explicit_seed: bool = false) -> void:
	if not NetworkManager.is_host():
		push_error("start_multiplayer_run() doit être appelé uniquement par l'hôte.")
		return
	_init_run_rng(seed_value if has_explicit_seed else randi())
	_generate_map(floor_count)
	run_peer_ids = [1]
	for id in multiplayer.get_peers():
		run_peer_ids.append(id)
	_receive_map.rpc(_serialize_floors(), run_peer_ids, current_floor_index, current_position_in_floor, run_seed, character_picks)

@rpc("authority", "call_remote", "reliable")
func _receive_map(serialized_floors: Array, peer_ids: Array, starting_floor_index: int, starting_position_in_floor: int, seed_value: int, picks: Dictionary) -> void:
	_init_run_rng(seed_value)
	floors = _deserialize_floors(serialized_floors)
	current_floor_index = starting_floor_index
	current_position_in_floor = starting_position_in_floor
	map_generated = true
	players_ready = false
	run_peer_ids = []
	for id in peer_ids:
		run_peer_ids.append(id)
	character_picks = picks
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

# Construit players[] à partir du personnage choisi par chaque pair
# (character_picks, rempli avant le lancement via submit_character_pick() /
# diffusé aux clients par _receive_map()). Chaque pair reconstruit
# indépendamment tout players[] (pas seulement son propre PlayerState) à
# partir des MÊMES données déjà connues de tous — aucun round-trip réseau
# supplémentaire nécessaire ici, comme c'était déjà le cas avant l'ajout des
# personnages.
func build_players_from_starting_content() -> void:
	players.clear()
	for id in run_peer_ids:
		var character: CharacterData = _resolve_character(id)
		var state := PlayerState.new()
		state.peer_id = id
		for card in character.starting_deck:
			var card_dup: CardData = card.duplicate(true)
			card_dup.template_path = card.resource_path
			state.deck.append(card_dup)
		for gem in character.starting_gems:
			var gem_dup: GemData = gem.duplicate(true)
			gem_dup.template_path = gem.resource_path
			state.owned_gems.append(gem_dup)
		players.append(state)
	players_ready = true

# Repli sur DEFAULT_CHARACTER_PATH si ce pair n'a pas de choix enregistré —
# couvre notamment l'ouverture de MapView.tscn directement dans l'éditeur
# (start_new_run(8) sans personnage, cf. MapView._ready()).
func _resolve_character(peer_id: int) -> CharacterData:
	var path: String = character_picks.get(peer_id, "")
	return load(path if not path.is_empty() else DEFAULT_CHARACTER_PATH)

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
# pairs) et le diffuse. Un indice sur run_rng plutôt que pick_random() sur le
# tableau lui-même : RunManager n'a pas accès à encounter_pool (@export sur
# CombatManager), seul l'indice a besoin de voyager.
func choose_combat_encounter(pool_size: int) -> int:
	var index: int = run_rng.randi_range(0, pool_size - 1)
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
	# N'est appelée que côté hôte (cf. les deux call sites ci-dessus). Sans ça,
	# players[] côté hôte pour un pair distant ne serait jamais mis à jour —
	# player_hp_updated ne fait que rafraîchir le Character miroir affiché
	# dans CombatManager (cosmétique), jamais PlayerState.current_hp lui-même
	# — et _serialize_players()/_send_full_resync()/_send_combat_resync()
	# enverraient alors ses PV d'avant le dernier combat/événement à ce même
	# pair lors d'une reconnexion.
	for p: PlayerState in players:
		if p.peer_id == origin_peer_id:
			p.current_hp = current_hp
			break
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
	# COMBAT/END/EVENT sont tous "en cours de résolution" dès ce choix
	# appliqué — remis à faux uniquement quand ce nœud est effectivement
	# résolu (CombatManager._on_combat_finished()/EventView._on_continue_pressed()).
	# Sert uniquement à la sauvegarde solo : recommencer un nœud non résolu
	# plutôt que d'essayer de capturer son état interne (combat/événement).
	current_node_pending = true
	current_node_awaiting_rewards = false
	if run_peer_ids.size() <= 1:
		save_run_to_disk()
	elif NetworkManager.is_host():
		save_multi_run_to_disk()
	node_choice_applied.emit(map_node)

# Hôte uniquement. Bascule le salon de reprise (resume_mode) vers la partie
# effective — n'est appelée par MainMenu qu'une fois lobby_roster_flags ne
# contient plus aucun false (tous les joueurs d'origine reconnectés, décision
# utilisateur : pas de reprise partielle). Diffuse un instantané complet,
# comme start_multiplayer_run()/_receive_map, mais transporte en plus
# current_node_pending/current_node_awaiting_rewards/seed+état RNG puisque,
# contrairement à _send_full_resync() (qui ne part jamais en cours de nœud),
# une reprise peut redémarrer en plein milieu d'un nœud non résolu.
func resume_multiplayer_run() -> void:
	if not NetworkManager.is_host():
		push_error("resume_multiplayer_run() ne doit être appelé que par l'hôte.")
		return
	resume_mode = false
	map_generated = true
	_receive_resumed_run.rpc(
		_serialize_floors(),
		run_peer_ids,
		current_floor_index,
		current_position_in_floor,
		current_node_pending,
		current_node_awaiting_rewards,
		is_boss_combat,
		_serialize_players(),
		run_seed,
		run_rng.state,
	)

@rpc("authority", "call_remote", "reliable")
func _receive_resumed_run(serialized_floors: Array, peer_ids: Array, f_idx: int, pos_idx: int, node_pending: bool, awaiting_rewards: bool, boss: bool, serialized_players: Array, seed_value: int, rng_state: int) -> void:
	floors = _deserialize_floors(serialized_floors)
	current_floor_index = f_idx
	current_position_in_floor = pos_idx
	current_node_pending = node_pending
	current_node_awaiting_rewards = awaiting_rewards
	is_boss_combat = boss
	run_peer_ids = []
	for id in peer_ids:
		run_peer_ids.append(id)
	players = _deserialize_players(serialized_players)
	map_generated = true
	players_ready = true
	resume_mode = false
	run_rng.seed = seed_value
	run_rng.state = rng_state
	run_seed = seed_value
	get_tree().change_scene_to_file("res://scenes/map/MapView.tscn")
