extends Resource
class_name TileConfig
## Configuration des tuiles : ratios de génération et rendements par job.

@export_group("Generation ratios")
## Proportion de plaines parmi les tuiles non-bunker.
@export var plains_ratio: float = 0.40
## Proportion de forêts parmi les tuiles non-bunker.
@export var forest_ratio: float = 0.40
# Le reste devient montagne.

@export_group("Plains yields per job")
@export var plains_food: float = 4.0
@export var plains_wood: float = 1.0
@export var plains_ore: float = 0.0

@export_group("Forest yields per job")
@export var forest_food: float = 2.0
@export var forest_wood: float = 4.0
@export var forest_ore: float = 1.0

@export_group("Mountain yields per job")
@export var mountain_food: float = 1.0
@export var mountain_wood: float = 1.0
@export var mountain_ore: float = 4.0
