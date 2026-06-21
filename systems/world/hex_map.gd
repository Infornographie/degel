extends RefCounted
class_name HexMap
## Carte hexagonale autour du bunker.

const DIRECTIONS: Array = [
	Vector2i(+1, 0), Vector2i(+1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, +1), Vector2i(0, +1),
]

var radius: int
var tiles: Dictionary = {}
var config: TileConfig

func _init(p_radius: int, p_config: TileConfig) -> void:
	radius = p_radius
	config = p_config
	_generate()

func _generate() -> void:
	var positions: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		var r_min: int = max(-radius, -q - radius)
		var r_max: int = min(radius, -q + radius)
		for r in range(r_min, r_max + 1):
			positions.append(Vector2i(q, r))

	for pos in positions:
		var tile := HexTile.new(pos.x, pos.y)
		tiles[tile.key()] = tile

	tiles[HexTile.make_key(0, 0)].type = HexTile.Type.BUNKER

	var non_bunker_tiles: Array[HexTile] = []
	for tile in tiles.values():
		if tile.q != 0 or tile.r != 0:
			non_bunker_tiles.append(tile)

	var total: int = non_bunker_tiles.size()
	var plains_count: int = roundi(total * config.plains_ratio)
	var forest_count: int = roundi(total * config.forest_ratio)
	var mountain_count: int = total - plains_count - forest_count

	var bag: Array[int] = []
	for i in plains_count:
		bag.append(HexTile.Type.PLAINS)
	for i in forest_count:
		bag.append(HexTile.Type.FOREST)
	for i in mountain_count:
		bag.append(HexTile.Type.MOUNTAIN)
	bag.shuffle()

	for i in non_bunker_tiles.size():
		non_bunker_tiles[i].type = bag[i]

	# Remplit les yields de chaque tuile selon son type.
	for tile in tiles.values():
		_assign_yields(tile)

func _assign_yields(tile: HexTile) -> void:
	tile.yields = config.yields_for_tile(tile.type)

func get_tile(q: int, r: int) -> HexTile:
	return tiles.get(HexTile.make_key(q, r))

func get_tile_by_key(key: String) -> HexTile:
	return tiles.get(key)

func neighbors(tile: HexTile) -> Array[HexTile]:
	var result: Array[HexTile] = []
	for dir in DIRECTIONS:
		var n := get_tile(tile.q + dir.x, tile.r + dir.y)
		if n != null:
			result.append(n)
	return result

func workable_tiles() -> Array[HexTile]:
	var result: Array[HexTile] = []
	for tile in tiles.values():
		if tile.type != HexTile.Type.BUNKER:
			result.append(tile)
	return result
