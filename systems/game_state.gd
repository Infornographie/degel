extends Node
## GameState — cœur de la simulation (autoload).

enum EndCause { RESERVE_DEPLETED, AUTONOMY_REACHED, COLONY_LOST }
enum Job { IDLE, FARMER, LUMBERJACK, MINER }

const CONFIG_PATH := "res://systems/game_config_default.tres"
const TILE_CONFIG_PATH := "res://systems/tile_config_default.tres"

# Mapping job → nom de la ressource qu'il produit.
# La quantité vient de la tuile.
const JOB_RESOURCE := {
	Job.FARMER: "food",
	Job.LUMBERJACK: "wood",
	Job.MINER: "ore",
}

signal turn_advanced(turn: int, reserve: float)
signal resources_changed(resources: Dictionary)
signal survivor_woken(survivor: Survivor)
signal survivor_assigned(survivor: Survivor, job: int)
signal survivor_died(survivor: Survivor)
signal synth_skipped
signal famine_started
signal famine_ended
signal candidates_changed
signal targeted_wake_failed(profession: String)
signal tile_assignment_changed(tile: HexTile)
signal run_ended(cause: EndCause)

var config: GameConfig
var tile_config: TileConfig

var turn: int = 0
var is_over: bool = false

var reserve: float
var resources: Dictionary = {}

var synth_on: bool = false
const SYNTH_ELECTRICITY_COST: float = 3.0
const SYNTH_FOOD_OUTPUT: float = 1.0

var _wakes_done_this_turn: int = 0

var famine_turns: int = 0
var _deaths_triggered: bool = false
var production_multiplier: float = 1.0
const FAMINE_PROD_MULTIPLIER: float = 0.8

var roster: Roster
var hex_map: HexMap
var candidates: Array[int] = []

func _ready() -> void:
	config = load(CONFIG_PATH) as GameConfig
	tile_config = load(TILE_CONFIG_PATH) as TileConfig
	reserve = config.reserve_initial
	resources = {
		"food": config.food_initial,
		"wood": 0.0,
		"ore": 0.0,
		"electricity": 0.0,
		"heat": 0.0,
	}
	roster = Roster.new(config.roster_size)
	hex_map = HexMap.new(2, tile_config)
	_refill_candidates()
	_begin_turn()
	turn_advanced.emit(turn, reserve)
	resources_changed.emit(resources)

func awake_count() -> int:
	return roster.awake_count()

func awake_survivors() -> Array[Survivor]:
	return roster.awake_survivors()

func survivors() -> Array[Survivor]:
	return roster.survivors

func wake(id: int) -> bool:
	if is_over:
		return false
	var s: Survivor = roster.get_by_id(id)
	if s == null or s.awake:
		return false
	if _wakes_done_this_turn >= config.wakes_per_turn:
		return false
	if reserve < config.wake_cost:
		return false
	reserve -= config.wake_cost
	_wakes_done_this_turn += 1
	s.awake = true
	survivor_woken.emit(s)
	candidates.erase(s.id)
	_clean_candidates()
	if reserve <= 0.0:
		reserve = 0.0
		is_over = true
		run_ended.emit(EndCause.RESERVE_DEPLETED)
	return true

func can_wake(id: int) -> bool:
	if is_over:
		return false
	var s: Survivor = roster.get_by_id(id)
	if s == null or s.awake:
		return false
	if _wakes_done_this_turn >= config.wakes_per_turn:
		return false
	if reserve < config.wake_cost:
		return false
	return true

func assign_job(id: int, job: int) -> bool:
	if is_over:
		return false
	var s: Survivor = roster.get_by_id(id)
	if s == null or not s.awake:
		return false
	s.job = job
	survivor_assigned.emit(s, job)
	return true

## Affecte un colon éveillé à une tuile. Renvoie true si succès.
## Si la tuile était occupée par quelqu'un d'autre, ce dernier est désaffecté.
## Si le colon était déjà sur une autre tuile, il est désaffecté de l'ancienne.
func assign_to_tile(survivor_id: int, tile_key: String) -> bool:
	if is_over:
		return false
	var s: Survivor = roster.get_by_id(survivor_id)
	if s == null or not s.awake:
		return false
	var tile := hex_map.get_tile_by_key(tile_key)
	if tile == null or tile.type == HexTile.Type.BUNKER:
		return false
	# Libérer l'ancien occupant de la tuile, s'il y en a un
	if tile.worker_id != -1 and tile.worker_id != survivor_id:
		var previous: Survivor = roster.get_by_id(tile.worker_id)
		if previous != null:
			previous.tile_key = ""
	# Libérer l'ancienne tuile du colon
	if s.tile_key != "":
		var old_tile := hex_map.get_tile_by_key(s.tile_key)
		if old_tile != null:
			old_tile.worker_id = -1
			tile_assignment_changed.emit(old_tile)
	s.tile_key = tile_key
	tile.worker_id = survivor_id
	tile_assignment_changed.emit(tile)
	return true

## Retire un colon de sa tuile (s'il en a une).
func unassign_from_tile(survivor_id: int) -> bool:
	var s: Survivor = roster.get_by_id(survivor_id)
	if s == null or s.tile_key == "":
		return false
	var tile := hex_map.get_tile_by_key(s.tile_key)
	if tile != null:
		tile.worker_id = -1
		tile_assignment_changed.emit(tile)
	s.tile_key = ""
	return true

func set_synth(on: bool) -> void:
	synth_on = on

func advance_turn() -> void:
	if is_over:
		return
	turn += 1
	_resolve_tile_production()

	if synth_on:
		if resources["electricity"] >= SYNTH_ELECTRICITY_COST:
			resources["electricity"] -= SYNTH_ELECTRICITY_COST
			resources["food"] += SYNTH_FOOD_OUTPUT
		else:
			synth_skipped.emit()

	var needed: float = awake_count() * config.food_per_survivor
	var was_in_famine := famine_turns > 0
	if resources["food"] >= needed:
		resources["food"] -= needed
		if was_in_famine:
			famine_turns = 0
			_deaths_triggered = false
			production_multiplier = 1.0
			famine_ended.emit()
	else:
		resources["food"] = 0.0
		famine_turns += 1
		production_multiplier = FAMINE_PROD_MULTIPLIER
		if not was_in_famine:
			famine_started.emit()
		_resolve_famine_deaths()

	resources_changed.emit(resources)

	reserve -= config.core_upkeep

	if roster.is_empty():
		is_over = true
		turn_advanced.emit(turn, max(reserve, 0.0))
		run_ended.emit(EndCause.COLONY_LOST)
		return
	if reserve <= 0.0:
		reserve = 0.0
		is_over = true
		turn_advanced.emit(turn, reserve)
		run_ended.emit(EndCause.RESERVE_DEPLETED)
		return

	_begin_turn()
	turn_advanced.emit(turn, reserve)

## Pour chaque tuile occupée, calcule la production selon le job du colon
## et le rendement de la tuile pour ce job.
func _resolve_tile_production() -> void:
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
		var produced: float = raw
		if production_multiplier < 1.0:
			produced = floor(raw * production_multiplier)
			if raw >= 1.0 and produced < 1.0:
				produced = 1.0
		resources[resource_name] = resources.get(resource_name, 0.0) + produced

## Rendement effectif d'un colon donné, ce tour, sur sa tuile actuelle.
## Renvoie { "resource_name": amount } pour l'UI. Vide si pas de tuile ou rendement nul.
func get_survivor_output(s: Survivor) -> Dictionary:
	if s.tile_key == "":
		return {}
	var tile := hex_map.get_tile_by_key(s.tile_key)
	if tile == null:
		return {}
	var raw: float = tile.yields.get(s.job, 0.0)
	var resource_name: String = JOB_RESOURCE.get(s.job, "")
	if resource_name == "":
		return {}
	var produced: float = raw
	if production_multiplier < 1.0:
		produced = floor(raw * production_multiplier)
		if raw >= 1.0 and produced < 1.0:
			produced = 1.0
	return { resource_name: produced }

func _resolve_famine_deaths() -> void:
	if not _deaths_triggered:
		if famine_turns >= 2:
			var chance: int = min(100, (famine_turns - 1) * 25)
			if randi() % 100 < chance:
				_deaths_triggered = true
	if _deaths_triggered:
		var victim: Survivor = roster.pick_random_awake()
		if victim != null:
			# Libérer sa tuile s'il en occupait une
			if victim.tile_key != "":
				var t := hex_map.get_tile_by_key(victim.tile_key)
				if t != null:
					t.worker_id = -1
					tile_assignment_changed.emit(t)
			roster.remove(victim)
			survivor_died.emit(victim)

func _begin_turn() -> void:
	_wakes_done_this_turn = 0
	resources["electricity"] = 0.0
	resources["heat"] = 0.0
	resources["electricity"] += config.bunker_production
	_refill_candidates()
	resources_changed.emit(resources)

func _clean_candidates() -> void:
	var clean: Array[int] = []
	for id in candidates:
		var s: Survivor = roster.get_by_id(id)
		if s != null and not s.awake:
			clean.append(id)
	candidates = clean
	candidates_changed.emit()

func _refill_candidates() -> void:
	_clean_candidates()
	var needed: int = config.candidate_pool_size - candidates.size()
	if needed > 0:
		var new_ids: Array[int] = roster.draw_candidates(needed, candidates)
		for id in new_ids:
			candidates.append(id)
		candidates_changed.emit()

func targeted_wake(profession: String) -> bool:
	if is_over:
		return false
	if _wakes_done_this_turn >= config.wakes_per_turn:
		return false
	if reserve < config.wake_cost_targeted:
		return false
	reserve -= config.wake_cost_targeted
	_wakes_done_this_turn += 1
	var s: Survivor = roster.find_sleeping_by_profession(profession)
	if s == null:
		targeted_wake_failed.emit(profession)
		candidates_changed.emit()
		if reserve <= 0.0:
			reserve = 0.0
			is_over = true
			run_ended.emit(EndCause.RESERVE_DEPLETED)
		return false
	s.awake = true
	survivor_woken.emit(s)
	candidates.erase(s.id)
	_clean_candidates()
	if reserve <= 0.0:
		reserve = 0.0
		is_over = true
		run_ended.emit(EndCause.RESERVE_DEPLETED)
	return true

func can_targeted_wake() -> bool:
	if is_over:
		return false
	if _wakes_done_this_turn >= config.wakes_per_turn:
		return false
	if reserve < config.wake_cost_targeted:
		return false
	return true

func compute_score() -> Dictionary:
	return {
		"survivors_saved": awake_count(),
		"survivors_total": roster.initial_size,
	}
