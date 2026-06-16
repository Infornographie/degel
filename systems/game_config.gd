extends Resource
class_name GameConfig
## Configuration globale d'équilibrage. Édité via l'inspecteur sur un .tres.

@export_group("Reactor")
## Production d'électricité du réacteur, par tour, au début de la run.
@export var reactor_initial_output: float = 10.0
## Nombre de tours entre chaque baisse de 1 de la production réacteur.
@export var reactor_decay_interval: int = 10

@export_group("Wake")
## Coût d'un réveil normal, prélevé sur l'électricité du tour.
@export var wake_cost: float = 10.0
## Coût d'une recherche ciblée, plus élevée, échec possible.
@export var wake_cost_targeted: float = 25.0
## Nombre maximum de réveils par tour. Upgradable plus tard.
@export var wakes_per_turn: int = 1
## Nombre de candidats visibles dans le pool d'éveil.
@export var candidate_pool_size: int = 3

@export_group("Food")
## Nourriture consommée par survivant éveillé, chaque tour.
@export var food_per_survivor: float = 2.0
## Stock de nourriture au début de la run (garde-manger du bunker).
@export var food_initial: float = 10.0

@export_group("Roster")
## Nombre de survivants tirés au début de la run.
@export var roster_size: int = 50

@export_group("Extinction")
## Pourcentage de chance d'éteindre un cryo par point d'élec négatif (au-dessus du dernier multiple de 10).
## Ex : 10.0 = 10% par point.
@export var extinction_chance_per_point: float = 10.0
