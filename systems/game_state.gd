extends Node
## GameState — cœur de la simulation (autoload).

enum EndCause { RESERVE_DEPLETED, AUTONOMY_REACHED, COLONY_LOST }
enum Job { IDLE, FARM, LOG }

const CONFIG_PATH := "res://systems/default_config.tres"

signal turn_advanced(turn: int, energy_available: float, reserve: float)
signal resources_changed(resources: Dictionary)
signal survivor_woken(survivor: Survivor)
signal survivor_assigned(survivor: Survivor, job: int)
signal survivor_died(survivor: Survivor)
signal synth_skipped
signal famine_started
signal famine_ended
signal run_ended(cause: EndCause)

var config: GameConfig
var job_outputs: Dictionary = {}

var turn: int = 0
var is_over: bool = false

# --- Énergie ---
var reserve: float
var energy_available: float = 0.0
var surface_production: float = 0.0

# --- Ressources ---
var resources: Dictionary = {}

# --- Combustion ---
const WOOD_BURN_RATIO: float = 1.0

# --- Synthétiseur ---
var synth_on: bool = false
const SYNTH_ENERGY_COST: float = 3.0
const SYNTH_FOOD_OUTPUT: float = 1.0

# --- Réveils ---
var _wakes_done_this_turn: int = 0

# --- Famine ---
var famine_turns: int = 0
var _deaths_triggered: bool = false
var production_multiplier: float = 1.0
const FAMINE_PROD_MULTIPLIER: float = 0.8

# --- Roster ---
var roster: Roster

func _ready() -> void:
	config = load(CONFIG_PATH) as GameConfig
	# Initialisation depuis le config
	reserve = config.reserve_initial
	resources = {"food": config.food_initial, "wood": 0.0}
	job_outputs = {
		Job.IDLE: {},
		Job.FARM: {"food": config.farm_food_output},
		Job.LOG: {"wood": config.log_wood_output},
	}
	roster = Roster.new(config.roster_size)
	_begin_turn()
	turn_advanced.emit(turn, energy_available, reserve)
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
	if reserve <= 0.0:
		reserve = 0.0
		is_over = true
		run_ended.emit(EndCause.RESERVE_DEPLETED)
	return true

func assign_job(id: int, job: int) -> bool:
	if is_over:
		return false
	var s: Survivor = roster.get_by_id(id)
	if s == null or not s.awake:
		return false
	if not job_outputs.has(job):
		return false
	s.job = job
	survivor_assigned.emit(s, job)
	return true

func burn_wood(amount: float) -> bool:
	if is_over or amount <= 0.0:
		return false
	if resources["wood"] < amount:
		return false
	resources["wood"] -= amount
	energy_available += amount * WOOD_BURN_RATIO
	resources_changed.emit(resources)
	return true

func set_synth(on: bool) -> void:
	synth_on = on

func advance_turn() -> void:
	if is_over:
		return

	turn += 1
	_resolve_job_production()

	if synth_on:
		if energy_available >= SYNTH_ENERGY_COST:
			energy_available -= SYNTH_ENERGY_COST
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

	reserve += energy_available
	reserve -= config.core_upkeep

	if roster.is_empty():
		is_over = true
		turn_advanced.emit(turn, energy_available, max(reserve, 0.0))
		run_ended.emit(EndCause.COLONY_LOST)
		return
	if reserve <= 0.0:
		reserve = 0.0
		is_over = true
		turn_advanced.emit(turn, 0.0, reserve)
		run_ended.emit(EndCause.RESERVE_DEPLETED)
		return

	_begin_turn()
	turn_advanced.emit(turn, energy_available, reserve)

func _resolve_job_production() -> void:
	for s in roster.awake_survivors():
		var outputs: Dictionary = job_outputs.get(s.job, {})
		for resource_name in outputs:
			var raw: float = outputs[resource_name]
			var produced: float = raw
			if production_multiplier < 1.0:
				produced = floor(raw * production_multiplier)
				if raw >= 1.0 and produced < 1.0:
					produced = 1.0
			resources[resource_name] = resources.get(resource_name, 0.0) + produced

func _resolve_famine_deaths() -> void:
	if not _deaths_triggered:
		if famine_turns >= 2:
			var chance: int = min(100, (famine_turns - 1) * 25)
			if randi() % 100 < chance:
				_deaths_triggered = true
	if _deaths_triggered:
		var victim: Survivor = roster.pick_random_awake()
		if victim != null:
			roster.remove(victim)
			survivor_died.emit(victim)

func _begin_turn() -> void:
	_wakes_done_this_turn = 0
	energy_available = config.bunker_production + surface_production

func compute_score() -> Dictionary:
	return {
		"survivors_saved": awake_count(),
		"survivors_total": roster.initial_size,
	}
