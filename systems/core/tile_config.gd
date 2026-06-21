extends Resource
class_name TileConfig
## Configuration des tuiles : ratios de génération et rendements par activité.

@export_group("Generation ratios")
@export var plains_ratio: float = 0.40
@export var forest_ratio: float = 0.40

@export_group("Yields by activity")
@export var plains_yields: Dictionary[String, float] = {}
@export var forest_yields: Dictionary[String, float] = {}
@export var mountain_yields: Dictionary[String, float] = {}

func yields_for_tile(tile_type: int) -> Dictionary:
	match tile_type:
		HexTile.Type.PLAINS: return plains_yields
		HexTile.Type.FOREST: return forest_yields
		HexTile.Type.MOUNTAIN: return mountain_yields
		_: return {}
