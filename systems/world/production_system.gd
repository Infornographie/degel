extends RefCounted
class_name ProductionSystem
## Système de production des tuiles. Résout combien chaque tuile occupée
## génère selon le job du colon affecté, en appliquant le multiplicateur global.

# Mapping job → nom de la ressource produite.
const JOB_RESOURCE := {
	1: "food",      # FARMER
	2: "wood",      # LUMBERJACK
	3: "ore",       # MINER
}

var hex_map: HexMap
var roster: Roster

func _init(p_hex_map: HexMap, p_roster: Roster) -> void:
	hex_map = p_hex_map
	roster = p_roster

## Calcule la production effective d'un colon sur sa tuile.
## Renvoie { "resource_name": amount } ou {} si pas de prod.
func get_survivor_output(s: Survivor, multiplier: float) -> Dictionary:
	if s.tile_key == "":
		return {}
	var tile := hex_map.get_tile_by_key(s.tile_key)
	if tile == null:
		return {}
	var raw: float = tile.yields.get(s.job, 0.0)
	var resource_name: String = JOB_RESOURCE.get(s.job, "")
	if resource_name == "":
		return {}
	var produced: float = _apply_multiplier(raw, multiplier)
	return { resource_name: produced }

## Résout la production de toutes les tuiles occupées, écrit dans `resources`.
func resolve(resources: Dictionary, multiplier: float) -> void:
	for tile in hex_map.tiles.values():
		if tile.worker_id == -1:
			continue
		var s: Survivor = roster.get_by_id(tile.worker_id)
		if s == null or not s.awake:
			continue
		var raw: float = tile.yields.get(s.job, 0.0)
		if raw <= 0.0:
			continue
		var resource_name: String = JOB_RESOURCE.get(s.job, "")
		if resource_name == "":
			continue
		var produced: float = _apply_multiplier(raw, multiplier)
		resources[resource_name] = resources.get(resource_name, 0.0) + produced

## Applique le multiplicateur en préservant la règle "au moins 1 si raw ≥ 1".
func _apply_multiplier(raw: float, multiplier: float) -> float:
	if multiplier >= 1.0:
		return raw
	var result: float = floor(raw * multiplier)
	if raw >= 1.0 and result < 1.0:
		result = 1.0
	return result
