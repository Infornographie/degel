extends Node
## GameState — cœur de la simulation (autoload).

enum EndCause { RESERVE_DEPLETED, AUTONOMY_REACHED, COLONY_LOST }
enum Job { IDLE, FARM, LOG }

# Table de production des jobs. Ajouter un job = une ligne ici.
const JOB_OUTPUTS := {
	Job.IDLE: {},
	Job.FARM: {"food": 2.0},
	Job.LOG: {"wood": 2.0},
}

signal turn_advanced(turn: int, energy_available: float, reserve: float)
signal resources_changed(resources: Dictionary)
signal survivor_woken(survivor: Survivor)
signal survivor_assigned(survivor: Survivor, job: int)
signal survivor_died(survivor: Survivor)
signal synth_skipped
signal famine_started
signal famine_ended
signal run_ended(cause: EndCause)

var turn: int = 0
var is_over: bool = false

# --- Énergie ---
var reserve: float = 50.0
var core_upkeep: float = 10.0
var bunker_production: float = 6.0
var surface_production: float = 0.0
var energy_available: float = 0.0

# --- Ressources (stocks) ---
var resources: Dictionary = {"food": 10.0, "wood": 0.0}
const FOOD_PER_SURVIVOR: float = 2.0

# --- Combustion ---
const WOOD_BURN_RATIO: float = 1.0   # 1 bois -> 1 énergie (mauvais rendement, à équilibrer)

# --- Synthétiseur ---
var synth_on: bool = false
const SYNTH_ENERGY_COST: float = 3.0
const SYNTH_FOOD_OUTPUT: float = 1.0

# --- Réveils ---
var wake_cost: float = 10.0
var wakes_per_turn: int = 1
var _wakes_done_this_turn: int = 0

# --- Famine ---
var famine_turns: int = 0
var _deaths_triggered: bool = false
var production_multiplier: float = 1.0
const FAMINE_PROD_MULTIPLIER: float = 0.8

# --- Roster ---
var roster_size: int = 5
var roster: Roster

func _ready() -> void:
	roster = Roster.new(roster_size)
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
	if _wakes_done_this_turn >= wakes_per_turn:
		return false
	if reserve < wake_cost:
		return false
	reserve -= wake_cost
	_wakes_done_this_turn += 1
	s.awake = true
	survivor_woken.emit(s)
	if reserve <= 0.0:
		reserve = 0.0
		is_over = true
		run_ended.emit(EndCause.RESERVE_DEPLETED)
	return true

## Affecte un job à un survivant éveillé. Renvoie true si réussi.
func assign_job(id: int, job: int) -> bool:
	if is_over:
		return false
	var s: Survivor = roster.get_by_id(id)
	if s == null or not s.awake:
		return false
	if not JOB_OUTPUTS.has(job):
		return false
	s.job = job
	survivor_assigned.emit(s, job)
	return true

## Brûle du bois pour de l'énergie immédiate ce tour.
## Énergie ajoutée au budget courant (non stockable au-delà du tour, comme la prod bunker).
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

	# 1) Production des jobs (modulée par la famine en cours, si déjà installée)
	_resolve_job_production()

	# 2) Synthé
	if synth_on:
		if energy_available >= SYNTH_ENERGY_COST:
			energy_available -= SYNTH_ENERGY_COST
			resources["food"] += SYNTH_FOOD_OUTPUT
		else:
			synth_skipped.emit()

	# 3) Repas + famine
	var needed: float = awake_count() * FOOD_PER_SURVIVOR
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

	# 4) Bilan énergie
	reserve += energy_available
	reserve -= core_upkeep

	# 5) Fin éventuelle
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

## Pour chaque éveillé avec un job, ajoute sa production aux ressources.
## Application de la famine : floor(prod * mult), plancher 1 si la prod brute était >= 1.
func _resolve_job_production() -> void:
	for s in roster.awake_survivors():
		var outputs: Dictionary = JOB_OUTPUTS.get(s.job, {})
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
	energy_available = bunker_production + surface_production

func compute_score() -> Dictionary:
	return {
		"survivors_saved": awake_count(),
		"survivors_total": roster.initial_size,
	}
