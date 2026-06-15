extends RefCounted
class_name HexMap
## Carte hexagonale autour du bunker. Génère un disque de tuiles en cube coords.

# Les six directions cube standard (Red Blob Games convention).
const DIRECTIONS: Array = [
	Vector2i(+1, 0), Vector2i(+1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, +1), Vector2i(0, +1),
]

# Cibles de génération pour les tuiles non-bunker (sur 18 tuiles : ~7 plaines, ~7 forêts, ~4 montagnes).
const PLAINS_RATIO: float = 0.40
const FOREST_RATIO: float = 0.40
# Le reste devient montagne.

var radius: int
var tiles: Dictionary = {}   # clé "q,r" → HexTile

func _init(p_radius: int = 2) -> void:
	radius = p_radius
	_generate()

## Génère un disque hexagonal de rayon `radius`.
## La tuile centrale (0,0) est le bunker. Les autres ont un type tiré au hasard
## selon les ratios cibles.
func _generate() -> void:
	# Collecte d'abord toutes les positions
	var positions: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		var r_min: int = max(-radius, -q - radius)
		var r_max: int = min(radius, -q + radius)
		for r in range(r_min, r_max + 1):
			positions.append(Vector2i(q, r))

	# Crée les tuiles
	for pos in positions:
		var tile := HexTile.new(pos.x, pos.y)
		tiles[tile.key()] = tile

	# Assigne les types : bunker au centre, le reste tiré au hasard avec les ratios
	tiles[HexTile.make_key(0, 0)].type = HexTile.Type.BUNKER

	var non_bunker_tiles: Array[HexTile] = []
	for tile in tiles.values():
		if tile.q != 0 or tile.r != 0:
			non_bunker_tiles.append(tile)

	# Calcul du nombre cible de chaque type
	var total: int = non_bunker_tiles.size()
	var plains_count: int = roundi(total * PLAINS_RATIO)
	var forest_count: int = roundi(total * FOREST_RATIO)
	var mountain_count: int = total - plains_count - forest_count

	# Construction d'un bag de types à distribuer
	var bag: Array[int] = []
	for i in plains_count:
		bag.append(HexTile.Type.PLAINS)
	for i in forest_count:
		bag.append(HexTile.Type.FOREST)
	for i in mountain_count:
		bag.append(HexTile.Type.MOUNTAIN)
	bag.shuffle()

	# Distribution
	for i in non_bunker_tiles.size():
		non_bunker_tiles[i].type = bag[i]

## Renvoie la tuile aux coordonnées données, ou null si hors carte.
func get_tile(q: int, r: int) -> HexTile:
	return tiles.get(HexTile.make_key(q, r))

## Renvoie les voisins immédiats d'une tuile (jusqu'à 6).
func neighbors(tile: HexTile) -> Array[HexTile]:
	var result: Array[HexTile] = []
	for dir in DIRECTIONS:
		var n := get_tile(tile.q + dir.x, tile.r + dir.y)
		if n != null:
			result.append(n)
	return result

## Toutes les tuiles travaillables (tout sauf bunker).
func workable_tiles() -> Array[HexTile]:
	var result: Array[HexTile] = []
	for tile in tiles.values():
		if tile.type != HexTile.Type.BUNKER:
			result.append(tile)
	return result

## Toutes les tuiles d'un type donné.
func tiles_of_type(type: int) -> Array[HexTile]:
	var result: Array[HexTile] = []
	for tile in tiles.values():
		if tile.type == type:
			result.append(tile)
	return result
