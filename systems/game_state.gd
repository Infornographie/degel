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
var reserve: float = 50.0
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
# Nombre de tours consécutifs où on n'a pas pu nourrir tout le monde.
var famine_turns: int = 0
# Une fois les morts amorcées par le tirage, elles continuent tant que la famine dure.
var _deaths_triggered: bool = false
# Multiplicateur de production sous famine. Sera appliqué quand la prod existera,
# AVEC arrondi-plancher à 1 unité produite (pour éviter la spirale).
var production_multiplier: float = 1.0
const FAMINE_PROD_MULTIPLIER: float = 0.8

var survivors: Array[Survivor] = []

func _ready() -> void:
	survivors = [
		Survivor.new("Mara", "Ingénieure"),
		Survivor.new("Yann", "Fermier"),
		Survivor.new("Lina", "Médecin"),
		Survivor.new("Otto", "Mécanicien"),
		Survivor.new("Sève", "Botaniste"),
	]
	_begin_turn()
	turn_advanced.emit(turn, energy_available, reserve, food_stock)

func wake(index: int) -> bool:
	if is_over:
		return false
	if index < 0 or index >= survivors.size():
		return false
	var s: Survivor = survivors[index]
	if s.awake:
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

func awake_survivors() -> Array[Survivor]:
	var result: Array[Survivor] = []
	for s in survivors:
		if s.awake:
			result.append(s)
	return result

func awake_count() -> int:
	return awake_survivors().size()

## Bilan de tour : 1) synthé, 2) repas + famine, 3) bilan énergie, 4) fin éventuelle.
func advance_turn() -> void:
	if is_over:
		return

	# On incrémente le tour D'ABORD : tout ce qui suit (synthé, repas, famine, bilan)
	# appartient au nouveau tour. C'est ce qui rend l'ordre des signaux lisible.
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
	if survivors.is_empty():
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

## Gère le tirage et l'application des morts de famine pour ce tour.
## Tirage de déclenchement : 25 % au tour 2 de famine, +25 % par tour, 100 % au tour 5.
## Une fois déclenché : un mort par tour, et ça reste déclenché jusqu'au reset.
func _resolve_famine_deaths() -> void:
	if not _deaths_triggered:
		if famine_turns >= 2:
			var chance: int = min(100, (famine_turns - 1) * 25)
			if randi() % 100 < chance:
				_deaths_triggered = true
	if _deaths_triggered:
		_kill_random_awake()

func _kill_random_awake() -> void:
	var pool: Array[Survivor] = awake_survivors()
	if pool.is_empty():
		# Plus personne d'éveillé : la conso retombe à 0 au tour suivant,
		# la famine se résoudra d'elle-même. Pas de mort à infliger.
		return
	var victim: Survivor = pool[randi() % pool.size()]
	survivors.erase(victim)
	survivor_died.emit(victim)

func _begin_turn() -> void:
	_wakes_done_this_turn = 0
	energy_available = bunker_production + surface_production

func compute_score() -> Dictionary:
	return {
		"survivors_saved": awake_count(),
		"survivors_total": survivors.size(),
	}
