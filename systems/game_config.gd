extends Resource
class_name GameConfig
## Configuration globale d'équilibrage. Édité via l'inspecteur sur un .tres.

# --- Énergie ---
@export var reserve_initial: float = 50.0
@export var core_upkeep: float = 10.0
@export var bunker_production: float = 6.0

# --- Réveils ---
@export var wake_cost: float = 10.0
@export var wakes_per_turn: int = 1

# --- Nourriture ---
@export var food_per_survivor: float = 2.0
@export var food_initial: float = 10.0

# --- Roster ---
@export var roster_size: int = 5

# --- Production des jobs (sortie nette par tour, hors famine) ---
@export var farm_food_output: float = 4.0
@export var log_wood_output: float = 4.0
