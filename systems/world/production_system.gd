extends RefCounted
class_name ProductionSystem
## Système de production des tuiles. Résout combien chaque tuile occupée
## génère selon l'activité du colon, en appliquant la probabilité d'échec
## et le multiplicateur global (famine, etc.).

var hex_map: HexMap
var roster: Roster
var activity_registry: ActivityRegistry

func _init(p_hex_map: HexMap, p_roster: Roster, p_activity_registry: ActivityRegistry) -> void:
	hex_map = p_hex_map
	roster = p_roster
	activity_registry = p_activity_registry

## Calcule la production *projetée* d'un colon (espérance, pour l'affichage).
## Renvoie { "resource_name": amount } ou {} si pas de prod.
## Pour les activités risquées : produit × success_rate (valeur attendue).
func get_survivor_output(s: Survivor, multiplier: float) -> Dictionary:
	if s.tile_key == "" or s.activity_id == "":
		return {}
	var tile := hex_map.get_tile_by_key(s.tile_key)
	if tile == null:
		return {}
	var activity := activity_registry.get_activity(s.activity_id)
	if activity == null or activity.produced_resource == "":
		return {}
	var raw: float = tile.yields.get(s.activity_id, 0.0)
	if raw <= 0.0:
		return {}
	var expected: float = raw * activity.success_rate
	var produced: float = _apply_multiplier(expected, multiplier)
	return { activity.produced_resource: produced }

## Résout la production réelle de ce tour, avec tirage pour les activités risquées.
## Renvoie une liste d'événements pour la news (chasses échouées, etc.).
func resolve(resources: Dictionary, multiplier: float) -> Array:
	var events: Array = []
	for tile in hex_map.tiles.values():
		if tile.worker_id == -1:
			continue
		var s: Survivor = roster.get_by_id(tile.worker_id)
		if s == null or not s.awake or s.activity_id == "":
			continue
		var activity := activity_registry.get_activity(s.activity_id)
		if activity == null:
			continue
		# Vérifier qu'on a les inputs nécessaires
		var has_inputs := true
		for input_name in activity.inputs:
			var needed: float = activity.inputs[input_name]
			if resources.get(input_name, 0.0) < needed:
				has_inputs = false
				break
		if not has_inputs:
			events.append({
				"type": "activity_no_inputs",
				"name": s.name,
				"profession": s.profession,
				"activity_key": activity.name_key,
			})
			continue
		# Consommer les inputs
		for input_name in activity.inputs:
			resources[input_name] = resources.get(input_name, 0.0) - activity.inputs[input_name]
		# Tirage de succès
		var success := true
		if activity.success_rate < 1.0:
			success = randf() < activity.success_rate
		if not success:
			events.append({
				"type": "activity_failed",
				"name": s.name,
				"profession": s.profession,
				"activity_key": activity.name_key,
			})
			continue
		# Effet sur la tuile (dégradation / restauration)
		if activity.tile_health_delta != 0:
			tile.health = max(0, tile.health + activity.tile_health_delta)
		# Production
		if activity.produced_resource == "":
			continue
		var raw: float = tile.yields.get(s.activity_id, 0.0)
		if raw <= 0.0:
			continue
		var produced: float = _apply_multiplier(raw, multiplier)
		resources[activity.produced_resource] = resources.get(activity.produced_resource, 0.0) + produced
	for tile in hex_map.tiles.values():
		if tile.type == HexTile.Type.FOREST and tile.health >= 5:
			_mutate_to_plains(tile)
			events.append({
				"type": "tile_mutated",
				"from": "forest",
				"to": "plains",
				"tile_key": tile.key(),
			})
	return events

func _mutate_to_plains(tile: HexTile) -> void:
	hex_map.mutate_tile(tile, HexTile.Type.PLAINS)

func _apply_multiplier(raw: float, multiplier: float) -> float:
	if multiplier >= 1.0:
		return raw
	var result: float = floor(raw * multiplier)
	if raw >= 1.0 and result < 1.0:
		result = 1.0
	return result
