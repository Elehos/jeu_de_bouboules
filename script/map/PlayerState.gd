extends Resource
class_name PlayerState

# ID du pair (multiplayer.get_unique_id()) propriétaire de cet état. Vaut 1
# par défaut : c'est aussi l'ID renvoyé par multiplayer.get_unique_id() côté
# hôte ET en solo (aucun MultiplayerPeer actif) — get_local_player() retrouve
# donc toujours le bon joueur sans cas particulier à gérer en solo.
var peer_id: int = 1

# --- PV de combat ---
var current_hp: int = -1   # -1 = pas encore initialisé (première entrée en combat)
var max_hp: int = 50

# --- Deck ---
var deck: Array[CardData] = []          # deck complet, persiste hors combat
var draw_pile: Array[CardData] = []     # pioche courante (vide hors combat)
var discard_pile: Array[CardData] = []  # défausse courante (vide hors combat)

# --- Gemmes ---
var owned_gems: Array[GemData] = []
var gems_locked: bool = false

# --- Mana ---
var max_mana: int = 3
var current_mana: int = max_mana

# --- Progression du run ---
var starting_event_resolved: bool = false
