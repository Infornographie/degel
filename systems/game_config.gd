extends Resource
class_name GameConfig
## Configuration globale d'équilibrage. Édité via l'inspecteur sur un .tres.

@export_group("Energy")
## Réserve d'énergie au début de la run. Détermine la longueur de l'horloge globale.
@export var reserve_initial: float = 50.0
## Énergie consommée chaque tour par les systèmes vitaux (cryo, bunker).
## Prélevée sur la réserve à chaque fin de tour.
@export var core_upkeep: float = 10.0
## Énergie produite par le bunker chaque tour. Va dans le budget courant ;
## le reliquat non dépensé repart dans la réserve.
@export var bunker_production: float = 6.0

@export_group("Wake")
## Coût d'un réveil, ponctionné directement sur la réserve.
@export var wake_cost: float = 10.0
## Nombre maximum de réveils par tour. Augmentable plus tard via techno/bâtiment.
@export var wakes_per_turn: int = 1

@export_group("Food")
## Nourriture consommée par survivant éveillé, chaque tour.
@export var food_per_survivor: float = 2.0
## Stock de nourriture au début de la run (garde-manger du bunker).
@export var food_initial: float = 10.0

@export_group("Roster")
## Nombre de survivants tirés au début de la run.
## Limité par la taille du pool de noms (16 actuellement).
@export var roster_size: int = 5

@export_group("Job outputs")
## Nourriture produite par un farmer chaque tour (hors famine).
@export var farm_food_output: float = 2.0
## Bois produit par un bûcheron chaque tour (hors famine).
@export var log_wood_output: float = 2.0
