extends Node
## GameState — cœur de la simulation (autoload).

enum EndCause { RESERVE_DEPLETED, AUTONOMY_REACHED, COLONY_LOST }
enum Job { IDLE, FARM, LOG }

const CONFIG_PATH := "res://systems/default_config.tres"

signal turn_advanced(turn: int, reserve: float)
signal resources_changed(resources: Dictionary)
signal survivor_woken(survivor: Survivor)
signal survivor_assigned(survivor: Survivor, job: int)
signal survivor_died(survivor: Survivor)
signal synth_skipped
signal famine_started
signal famine_ended
signal run_ended(cause: EndCause)
signal candidates_changed
signal targeted_wake_failed(profession: String)

var config: GameConfig
var job_outputs: Dictionary = {}

var turn: int = 0
var is_over: bool = false

# --- Réserve (horloge pure) ---
# Quantité finie qui maintient le bunker en vie. Non rechargeable.
# Drainée chaque tour par les systèmes vitaux + les actions du bunker (réveils).
var reserve: float

# --- Ressources flux (réinitialisées à chaque tour) ---
# Toutes les ressources, stocks ET flux, dans un seul dictionnaire.
# food/wood = stocks. electricity/heat = flux non stockables.
var resources: Dictionary = {}

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

# --- Roster ---
var roster: Roster
var candidates: Array[int] = []

# --- Map ---
var hex_map: HexMap

func _ready() -> void:
	config = load(CONFIG_PATH) as GameConfig
	reserve = config.reserve_initial
	resources = {
		"food": config.food_initial,
		"wood": 0.0,
		"electricity": 0.0,
		"heat": 0.0,
	}
	job_outputs = {
		Job.IDLE: {},
		Job.FARM: {"food": config.farm_food_output},
		Job.LOG: {"wood": config.log_wood_output},
	}
	roster = Roster.new(config.roster_size)
	_refill_candidates()
	hex_map = HexMap.new(2)   # rayon 2 = 19 tuiles
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
	if reserve <= 0.0:
		reserve = 0.0
		is_over = true
		run_ended.emit(EndCause.RESERVE_DEPLETED)
	candidates.erase(s.id)
	_clean_candidates()
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
	if not job_outputs.has(job):
		return false
	s.job = job
	survivor_assigned.emit(s, job)
	return true

func set_synth(on: bool) -> void:
	synth_on = on

## Bilan de tour. Ordre : production des jobs → synthé → repas + famine →
## ponction de la réserve par le bunker → fin éventuelle.
func advance_turn() -> void:
	if is_over:
		return

	turn += 1
	_resolve_job_production()

	# Synthé : consomme de l'électricité produite ce tour, produit de la food
	if synth_on:
		if resources["electricity"] >= SYNTH_ELECTRICITY_COST:
			resources["electricity"] -= SYNTH_ELECTRICITY_COST
			resources["food"] += SYNTH_FOOD_OUTPUT
		else:
			synth_skipped.emit()

	# Repas + famine
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

	# La réserve descend chaque tour : c'est l'horloge.
	# Rien ne la recharge ; les flux d'énergie ne la touchent pas.
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

func get_effective_output(job: int) -> Dictionary:
	var result: Dictionary = {}
	var outputs: Dictionary = job_outputs.get(job, {})
	for resource_name in outputs:
		var raw: float = outputs[resource_name]
		var produced: float = raw
		if production_multiplier < 1.0:
			produced = floor(raw * production_multiplier)
			if raw >= 1.0 and produced < 1.0:
				produced = 1.0
		result[resource_name] = produced
	return result

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

## Réinitialise les flux non-stockables et remplit avec les productions
## "passives" du tour (réacteur). Les flux non consommés sont perdus en fin de tour.
func _begin_turn() -> void:
	_wakes_done_this_turn = 0
	resources["electricity"] = 0.0
	resources["heat"] = 0.0
	resources["electricity"] += config.bunker_production
	_refill_candidates()
	resources_changed.emit(resources)

func compute_score() -> Dictionary:
	return {
		"survivors_saved": awake_count(),
		"survivors_total": roster.initial_size,
	}

## Retire les candidats qui ne sont plus valides (éveillés, morts).
## Ne complète pas le pool — c'est _begin_turn qui s'en charge en début de tour.
func _clean_candidates() -> void:
	var clean: Array[int] = []
	for id in candidates:
		var s: Survivor = roster.get_by_id(id)
		if s != null and not s.awake:
			clean.append(id)
	candidates = clean
	candidates_changed.emit()

## Nettoie puis complète jusqu'à candidate_pool_size.
## Appelé uniquement en début de tour.
func _refill_candidates() -> void:
	_clean_candidates()
	var needed: int = config.candidate_pool_size - candidates.size()
	if needed > 0:
		var new_ids: Array[int] = roster.draw_candidates(needed, candidates)
		for id in new_ids:
			candidates.append(id)
		candidates_changed.emit()

## Recherche ciblée d'une profession. Coût plus élevé, échec possible.
## - Si quelqu'un de cette profession est endormi : il est réveillé, ajouté aux candidats si pas déjà là.
## - Sinon : coût payé, signal d'échec, personne réveillé.
## Le réveil ciblé consomme aussi le quota wakes_per_turn comme un réveil normal.
func targeted_wake(profession: String) -> bool:
	if is_over:
		return false
	if _wakes_done_this_turn >= config.wakes_per_turn:
		return false
	if reserve < config.wake_cost_targeted:
		return false

	# Coût payé dans tous les cas
	reserve -= config.wake_cost_targeted
	_wakes_done_this_turn += 1

	var s: Survivor = roster.find_sleeping_by_profession(profession)
	if s == null:
		targeted_wake_failed.emit(profession)
		candidates_changed.emit()  # force le refresh UI même sur échec
		# Vérifier l'effondrement éventuel du coup
		if reserve <= 0.0:
			reserve = 0.0
			is_over = true
			run_ended.emit(EndCause.RESERVE_DEPLETED)
		return false

	s.awake = true
	survivor_woken.emit(s)
	# Retirer des candidats s'il y était
	candidates.erase(s.id)
	_clean_candidates()
	if reserve <= 0.0:
		reserve = 0.0
		is_over = true
		run_ended.emit(EndCause.RESERVE_DEPLETED)
	return true

## Indique si une recherche ciblée est actuellement possible.
func can_targeted_wake() -> bool:
	if is_over:
		return false
	if _wakes_done_this_turn >= config.wakes_per_turn:
		return false
	if reserve < config.wake_cost_targeted:
		return false
	return true
