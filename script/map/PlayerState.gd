extends Resource
class_name PlayerState

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
