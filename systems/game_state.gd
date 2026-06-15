extends Node
## GameState — cœur de la simulation (autoload).

enum EndCause { RESERVE_DEPLETED, AUTONOMY_REACHED, COLONY_LOST }

signal turn_advanced(turn: int, energy_available: float, reserve: float, food_stock: float)
signal survivor_woken(survivor: Survivor)
signal survivor_died(survivor: Survivor)
signal synth_skipped
signal famine_started
signal famine_ended
signal run_ended(cause: EndCause)

var turn: int = 0
var is_over: bool = false

# --- Énergie ---
var reserve: float = 500.0
var core_upkeep: float = 10.0
var bunker_production: float = 6.0
var surface_production: float = 0.0
var energy_available: float = 0.0

# --- Nourriture ---
var food_stock: float = 10.0
const FOOD_PER_SURVIVOR: float = 2.0

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

# --- Roster (sous-système) ---
var roster_size: int = 100
var roster: Roster

func _ready() -> void:
	roster = Roster.new(roster_size)
	_begin_turn()
	turn_advanced.emit(turn, energy_available, reserve, food_stock)

# Raccourcis vers le roster, pour que l'extérieur n'ait pas à savoir.
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

func set_synth(on: bool) -> void:
	synth_on = on

func advance_turn() -> void:
	if is_over:
		return

	turn += 1

	# 1) Synthé
	if synth_on:
		if energy_available >= SYNTH_ENERGY_COST:
			energy_available -= SYNTH_ENERGY_COST
			food_stock += SYNTH_FOOD_OUTPUT
		else:
			synth_skipped.emit()

	# 2) Repas + famine
	var needed: float = awake_count() * FOOD_PER_SURVIVOR
	var was_in_famine := famine_turns > 0
	if food_stock >= needed:
		food_stock -= needed
		if was_in_famine:
			famine_turns = 0
			_deaths_triggered = false
			production_multiplier = 1.0
			famine_ended.emit()
	else:
		food_stock = 0.0
		famine_turns += 1
		production_multiplier = FAMINE_PROD_MULTIPLIER
		if not was_in_famine:
			famine_started.emit()
		_resolve_famine_deaths()

	# 3) Bilan énergie
	reserve += energy_available
	reserve -= core_upkeep

	# 4) Fin éventuelle
	if roster.is_empty():
		is_over = true
		turn_advanced.emit(turn, energy_available, max(reserve, 0.0), food_stock)
		run_ended.emit(EndCause.COLONY_LOST)
		return
	if reserve <= 0.0:
		reserve = 0.0
		is_over = true
		turn_advanced.emit(turn, 0.0, reserve, food_stock)
		run_ended.emit(EndCause.RESERVE_DEPLETED)
		return

	_begin_turn()
	turn_advanced.emit(turn, energy_available, reserve, food_stock)

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
