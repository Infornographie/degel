extends Node
## GameState — cœur de la simulation (autoload).

enum EndCause { REACTOR_DEAD, COLONY_LOST }
enum Job { IDLE, FARMER, LUMBERJACK, MINER }

const CONFIG_PATH := "res://systems/game_config_default.tres"
const TILE_CONFIG_PATH := "res://systems/tile_config_default.tres"

const JOB_RESOURCE := {
	Job.FARMER: "food",
	Job.LUMBERJACK: "wood",
	Job.MINER: "ore",
}

signal turn_advanced(turn: int)
signal resources_changed(resources: Dictionary)
signal survivor_woken(survivor: Survivor)
signal survivor_assigned(survivor: Survivor, job: int)
signal nightly_deaths(events: Array)   # liste de { name, profession, cause }
signal famine_started
signal famine_ended
signal candidates_changed
signal targeted_wake_failed(profession: String)
signal tile_assignment_changed(tile: HexTile)
signal run_ended(cause: EndCause)

var config: GameConfig
var tile_config: TileConfig
var job_outputs: Dictionary = {}

var turn: int = 0
var is_over: bool = false

# --- Réacteur (flux, pas de stock) ---
var reactor_output: float

# --- Ressources : flux et stocks ---
var resources: Dictionary = {}

# --- Nécrologie (pour 5f) ---
var _deaths_this_turn: Array = []
var necrology: Array = []  # entrées { name, profession, cause, turn }

# --- Synthétiseur ---
var synth_on: bool = false
const SYNTH_ELECTRICITY_COST: float = 3.0
const SYNTH_FOOD_OUTPUT: float = 1.0

# --- Réveils ---
var _wakes_done_this_turn: int = 0

# --- Famine ---
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
	reactor_output = config.reactor_initial_output
	resources = {
		"food": config.food_initial,
		"wood": 0.0,
		"ore": 0.0,
		"electricity": 0.0,
		"heat": 0.0,
	}
	job_outputs = {
		Job.IDLE: {},
		Job.FARMER: {"food": 0.0},  # rempli par les tuiles
		Job.LUMBERJACK: {"wood": 0.0},
		Job.MINER: {"ore": 0.0},
	}
	roster = Roster.new(config.roster_size)
	hex_map = HexMap.new(2, tile_config)
	_refill_candidates()
	_begin_turn()
	turn_advanced.emit(turn)
	resources_changed.emit(resources)

func awake_count() -> int:
	return roster.awake_count()

func awake_survivors() -> Array[Survivor]:
	return roster.awake_survivors()

func survivors() -> Array[Survivor]:
	return roster.survivors

## Réveille un survivant. Le coût est prélevé sur l'élec du tour.
## Peut rendre l'élec négative — l'extinction se résoudra en fin de tour.
func wake(id: int) -> bool:
	if is_over:
		return false
	var s: Survivor = roster.get_by_id(id)
	if s == null or s.awake:
		return false
	if _wakes_done_this_turn >= config.wakes_per_turn:
		return false
	resources["electricity"] -= config.wake_cost
	_wakes_done_this_turn += 1
	s.awake = true
	survivor_woken.emit(s)
	candidates.erase(s.id)
	_clean_candidates()
	resources_changed.emit(resources)
	return true

func can_wake(id: int) -> bool:
	if is_over:
		return false
	var s: Survivor = roster.get_by_id(id)
	if s == null or s.awake:
		return false
	if _wakes_done_this_turn >= config.wakes_per_turn:
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

func assign_to_tile(survivor_id: int, tile_key: String) -> bool:
	if is_over:
		return false
	var s: Survivor = roster.get_by_id(survivor_id)
	if s == null or not s.awake:
		return false
	var tile := hex_map.get_tile_by_key(tile_key)
	if tile == null or tile.type == HexTile.Type.BUNKER:
		return false
	if tile.worker_id != -1 and tile.worker_id != survivor_id:
		var previous: Survivor = roster.get_by_id(tile.worker_id)
		if previous != null:
			previous.tile_key = ""
	if s.tile_key != "":
		var old_tile := hex_map.get_tile_by_key(s.tile_key)
		if old_tile != null:
			old_tile.worker_id = -1
			tile_assignment_changed.emit(old_tile)
	s.tile_key = tile_key
	tile.worker_id = survivor_id
	tile_assignment_changed.emit(tile)
	return true

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
	_deaths_this_turn.clear()

	# 1) Synthé (consomme l'élec du tour avant les productions de tuile)
	if synth_on:
		resources["electricity"] -= SYNTH_ELECTRICITY_COST
		resources["food"] += SYNTH_FOOD_OUTPUT

	# 2) Production des tuiles
	_resolve_tile_production()

	# 3) Repas + famine
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

	# 4) Extinction des cryos si élec négative
	_resolve_extinctions()

	# 5) Érosion du réacteur
	if turn % config.reactor_decay_interval == 0:
		reactor_output -= 1.0
		if reactor_output <= 0.0:
			reactor_output = 0.0
			is_over = true
			resources_changed.emit(resources)
			turn_advanced.emit(turn)
			run_ended.emit(EndCause.REACTOR_DEAD)
			return

	# 6) Fin éventuelle par colonie vide
	if roster.is_empty():
		is_over = true
		resources_changed.emit(resources)
		turn_advanced.emit(turn)
		run_ended.emit(EndCause.COLONY_LOST)
		return

	_begin_turn()
	if not _deaths_this_turn.is_empty():
		nightly_deaths.emit(_deaths_this_turn.duplicate())
	turn_advanced.emit(turn)
	resources_changed.emit(resources)

## Tant que l'élec est négative, on tente d'éteindre des cryos pour combler.
## 1 mort certain par tranche de 10, +X% par point partiel.
func _resolve_extinctions() -> void:
	while resources["electricity"] < 0.0:
		var deficit: float = -resources["electricity"]
		var sleepers := _sleeping_survivors()
		if sleepers.is_empty():
			break  # plus personne à éteindre, la colonie va se vider
		# Tranche complète : 1 mort certain
		if deficit >= 10.0:
			var victim: Survivor = sleepers[randi() % sleepers.size()]
			_extinguish(victim)
			resources["electricity"] += 10.0
			continue
		# Reste partiel : probabilité
		var chance: float = deficit * config.extinction_chance_per_point  # en %
		if randf() * 100.0 < chance:
			var victim: Survivor = sleepers[randi() % sleepers.size()]
			_extinguish(victim)
		# Qu'il y ait eu mort ou non, le partiel est résolu, on sort.
		resources["electricity"] = 0.0
		break

func _extinguish(victim: Survivor) -> void:
	roster.remove(victim)
	var entry := {
		"name": victim.name,
		"profession": victim.profession,
		"cause": "switched off",
		"turn": turn,
	}
	necrology.append(entry)
	_deaths_this_turn.append(entry)

func _sleeping_survivors() -> Array[Survivor]:
	var result: Array[Survivor] = []
	for s in roster.survivors:
		if not s.awake:
			result.append(s)
	return result

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
			if victim.tile_key != "":
				var t := hex_map.get_tile_by_key(victim.tile_key)
				if t != null:
					t.worker_id = -1
					tile_assignment_changed.emit(t)
			roster.remove(victim)
			var entry := {
				"name": victim.name,
				"profession": victim.profession,
				"cause": "starved",
				"turn": turn,
			}
			necrology.append(entry)
			_deaths_this_turn.append(entry)

func _begin_turn() -> void:
	_wakes_done_this_turn = 0
	resources["electricity"] = reactor_output
	resources["heat"] = 0.0
	_refill_candidates()

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
	resources["electricity"] -= config.wake_cost_targeted
	_wakes_done_this_turn += 1
	var s: Survivor = roster.find_sleeping_by_profession(profession)
	if s == null:
		targeted_wake_failed.emit(profession)
		candidates_changed.emit()
		resources_changed.emit(resources)
		return false
	s.awake = true
	survivor_woken.emit(s)
	candidates.erase(s.id)
	_clean_candidates()
	resources_changed.emit(resources)
	return true

func can_targeted_wake() -> bool:
	if is_over:
		return false
	if _wakes_done_this_turn >= config.wakes_per_turn:
		return false
	return true

func compute_score() -> Dictionary:
	return {
		"survivors_saved": awake_count(),
		"survivors_total": roster.initial_size,
	}
