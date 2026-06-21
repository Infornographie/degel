extends Node
## GameState — cœur de la simulation (autoload).

var production_system: ProductionSystem

enum EndCause { REACTOR_DEAD, COLONY_LOST }
enum Job { IDLE, FARMER, LUMBERJACK, MINER }

const CONFIG_PATH := "res://resources/game_config_default.tres"
const TILE_CONFIG_PATH := "res://resources/tile_config_default.tres"

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
signal building_assignment_changed(building: Building)
signal construction_started(building: Building)
signal construction_progressed(building: Building)
signal construction_completed(building: Building)

var config: GameConfig
var tile_config: TileConfig
var job_outputs: Dictionary = {}

var turn: int = 0
var is_over: bool = false

# --- Réacteur (flux, pas de stock) ---
var reactor_output: float

# Consommations effectuées ce tour (pour l'affichage de production)
var _electricity_consumed_this_turn: float = 0.0

# --- Ressources : flux et stocks ---
var resources: Dictionary = {}

# --- Buildings ---
var building_registry: BuildingRegistry
var buildings: Array[Building] = []
var _next_building_instance_id: int = 0

# --- Nécrologie (pour 5f) ---
var _deaths_this_turn: Array = []
var necrology: Array = []  # entrées { name, profession, cause, turn }

# --- Synthétiseur ---
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

# ── INITIALISATION ──
func _ready() -> void:
	config = load(CONFIG_PATH) as GameConfig
	tile_config = load(TILE_CONFIG_PATH) as TileConfig
	reactor_output = config.reactor_initial_output
	resources = {
		"food": config.food_initial,
		"wood": 0.0,
		"ore": 0.0,
		"tools": 0.0,
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
	production_system = ProductionSystem.new(hex_map, roster)
	building_registry = BuildingRegistry.new()
	_init_starter_buildings()
	_refill_candidates()
	_begin_turn()
	turn_advanced.emit(turn)
	resources_changed.emit(resources)

# ── ACCÈS SURVIVANTS ──
func awake_count() -> int:
	return roster.awake_count()

func awake_survivors() -> Array[Survivor]:
	return roster.awake_survivors()

func survivors() -> Array[Survivor]:
	return roster.survivors

# ── ACTIONS JOUEUR ──
func wake(id: int) -> bool:
	if is_over:
		return false
	var s: Survivor = roster.get_by_id(id)
	if s == null or s.awake:
		return false
	if _wakes_done_this_turn >= config.wakes_per_turn:
		return false
	resources["electricity"] -= config.wake_cost
	_electricity_consumed_this_turn += config.wake_cost
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
	# Libérer l'ancien occupant de la tuile, s'il y en a un
	if tile.worker_id != -1 and tile.worker_id != survivor_id:
		var previous: Survivor = roster.get_by_id(tile.worker_id)
		if previous != null:
			previous.tile_key = ""
	# Le colon quitte son emplacement actuel
	_remove_survivor_from_assignments(s)
	# Affectation
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

## Affecte un colon éveillé à un bâtiment. Renvoie true si succès.
## Le colon quitte sa tuile s'il en occupait une, ou son ancien bâtiment.
func assign_to_building(survivor_id: int, building_id: String) -> bool:
	if is_over:
		return false
	var s: Survivor = roster.get_by_id(survivor_id)
	if s == null or not s.awake:
		return false
	var target: Building = _find_building(building_id)
	if target == null or target.state != Building.State.OPERATIONAL:
		return false
	if target.worker_ids.size() >= target.workers_max():
		return false
	# Le colon quitte son emplacement actuel
	_remove_survivor_from_assignments(s)
	# On l'affecte au nouveau bâtiment
	target.worker_ids.append(survivor_id)
	s.building_id = building_id
	building_assignment_changed.emit(target)
	return true

## Retire un colon d'un bâtiment.
func unassign_from_building(survivor_id: int) -> bool:
	var s: Survivor = roster.get_by_id(survivor_id)
	if s == null or s.building_id == "":
		return false
	var b: Building = _find_building(s.building_id)
	if b != null:
		b.worker_ids.erase(survivor_id)
		building_assignment_changed.emit(b)
	s.building_id = ""
	return true

func _find_building(id: String) -> Building:
	for b in buildings:
		if b.config.id == id:
			return b
	return null

## Helper : retire un colon de partout où il est assigné (tuile ou bâtiment).
func _remove_survivor_from_assignments(s: Survivor) -> void:
	if s.tile_key != "":
		var t: HexTile = hex_map.get_tile_by_key(s.tile_key)
		if t != null:
			t.worker_id = -1
			tile_assignment_changed.emit(t)
		s.tile_key = ""
	if s.building_id != "":
		var b: Building = _find_building(s.building_id)
		if b != null:
			b.worker_ids.erase(s.id)
			building_assignment_changed.emit(b)
		s.building_id = ""

# ── BOUCLE DE TOUR ──
func advance_turn() -> void:
	if is_over:
		return
	turn += 1
	_deaths_this_turn.clear()

	# 2) Production des tuiles
	_resolve_tile_production()
	_resolve_construction()
	_resolve_buildings_operation()

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

func electricity_consumed_this_turn() -> float:
	return _electricity_consumed_this_turn

# ── ÉNERGIE & EXTINCTION ──
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

# ── PRODUCTION ──
func _resolve_tile_production() -> void:
	production_system.resolve(resources, production_multiplier)

func get_survivor_output(s: Survivor) -> Dictionary:
	return production_system.get_survivor_output(s, production_multiplier)

# ── FAMINE ──
func _resolve_famine_deaths() -> void:
	if not _deaths_triggered:
		if famine_turns >= 2:
			var chance: int = min(100, (famine_turns - 1) * 25)
			if randi() % 100 < chance:
				_deaths_triggered = true
	if _deaths_triggered:
		var victim: Survivor = roster.pick_random_awake()
		if victim != null:
			_remove_survivor_from_assignments(victim)
			roster.remove(victim)
			var entry := {
				"name": victim.name,
				"profession": victim.profession,
				"cause": "starved",
				"turn": turn,
			}
			necrology.append(entry)
			_deaths_this_turn.append(entry)

# ── HELPERS INTERNES ──
func _begin_turn() -> void:
	_wakes_done_this_turn = 0
	_electricity_consumed_this_turn = 0.0
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

# ── RECHERCHE CIBLÉE ──
func targeted_wake(profession: String) -> bool:
	if is_over:
		return false
	if _wakes_done_this_turn >= config.wakes_per_turn:
		return false
	resources["electricity"] -= config.wake_cost_targeted
	_electricity_consumed_this_turn += config.wake_cost_targeted
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

# ── SCORE ──
func compute_score() -> Dictionary:
	return {
		"survivors_saved": awake_count(),
		"survivors_total": roster.initial_size,
	}

#
func _init_starter_buildings() -> void:
	for building_config in building_registry.starters():
		var b := Building.new(building_config)
		b.instance_id = _next_building_instance_id
		_next_building_instance_id += 1
		b.complete_construction()
		buildings.append(b)

## Démarre un nouveau chantier sur un slot vide.
## Crée le Building en UNDER_CONSTRUCTION, le place, et le rend cible active.
func start_construction(target_type_id: String, slot_index: int) -> bool:
	if is_over:
		return false
	var target_config: BuildingConfig = building_registry.get_config(target_type_id)
	if target_config == null or target_config.is_starter:
		return false
	if not _is_slot_available(slot_index):
		return false
	var b := Building.new(target_config)
	b.instance_id = _next_building_instance_id
	_next_building_instance_id += 1
	b.slot_index = slot_index
	b.state = Building.State.UNDER_CONSTRUCTION
	buildings.append(b)
	# Devient la cible active de la zone de construction
	var zone: Building = _find_building_by_type("construction_zone")
	if zone != null:
		zone.construction_target = str(b.instance_id)
	construction_started.emit(b)
	return true

## Change la cible active de la zone de construction (par instance_id).
func set_active_construction(instance_id: int) -> bool:
	var zone: Building = _find_building_by_type("construction_zone")
	if zone == null:
		return false
	var target := _find_building_by_instance(instance_id)
	if target == null or target.state != Building.State.UNDER_CONSTRUCTION:
		return false
	zone.construction_target = str(instance_id)
	construction_started.emit(target)  # réutilise le signal pour rafraîchir
	return true

## Annule un chantier (seulement si rien n'a encore été consommé).
func cancel_construction(instance_id: int) -> bool:
	var b := _find_building_by_instance(instance_id)
	if b == null or b.state != Building.State.UNDER_CONSTRUCTION:
		return false
	if not b.build_resources_consumed.is_empty():
		return false  # déjà commencé, plus annulable
	buildings.erase(b)
	var zone: Building = _find_building_by_type("construction_zone")
	if zone != null and zone.construction_target == str(instance_id):
		zone.construction_target = ""
	construction_started.emit(b)  # rafraîchir
	return true

func _is_slot_available(slot_index: int) -> bool:
	for b in buildings:
		if b.slot_index == slot_index:
			return false
	return true

func _find_building_by_type(type_id: String) -> Building:
	for b in buildings:
		if b.config.id == type_id:
			return b
	return null

func _find_building_by_instance(instance_id: int) -> Building:
	for b in buildings:
		if b.instance_id == instance_id:
			return b
	return null

func _resolve_construction() -> void:
	var zone: Building = _find_building_by_type("construction_zone")
	if zone == null or zone.construction_target == "":
		return
	var target := _find_building_by_instance(int(zone.construction_target))
	if target == null or target.state != Building.State.UNDER_CONSTRUCTION:
		return
	# Force de travail totale = somme des forces de travail des colons assignés à la zone
	var total_work: float = 0.0
	for wid in zone.worker_ids:
		var s: Survivor = roster.get_by_id(wid)
		if s != null and s.awake:
			total_work += s.work_force
	if total_work <= 0.0:
		return
	# Consomme dans l'ordre les ressources requises, jusqu'à épuiser la force de travail
	var work_left: float = total_work
	var order: Array[String] = target.config.build_order
	if order.is_empty():
		order = target.config.build_cost.keys()
	for resource_name in order:
		if work_left <= 0.0:
			break
		var needed: float = target.config.build_cost.get(resource_name, 0.0) - target.build_resources_consumed.get(resource_name, 0.0)
		if needed <= 0.0:
			continue
		var to_consume: float = min(work_left, needed)
		# Vérifier qu'on a la ressource en stock
		var available: float = resources.get(resource_name, 0.0)
		if available < 1.0:
			continue  # pas assez en stock, on saute (on pourrait s'arrêter aussi)
		to_consume = min(to_consume, available)
		resources[resource_name] = available - to_consume
		target.build_resources_consumed[resource_name] = target.build_resources_consumed.get(resource_name, 0.0) + to_consume
		work_left -= to_consume
	construction_progressed.emit(target)
	# Vérifier si la construction est terminée
	var done := true
	for resource_name in target.config.build_cost:
		var consumed: float = target.build_resources_consumed.get(resource_name, 0.0)
		if consumed < target.config.build_cost[resource_name]:
			done = false
			break
	if done:
		target.complete_construction()
		# Libérer la zone de construction
		if zone.construction_target == str(target.instance_id):
			zone.construction_target = ""
		construction_completed.emit(target)

func _resolve_buildings_operation() -> void:
	for b in buildings:
		if b.state != Building.State.OPERATIONAL:
			continue
		if not b.active:
			continue
		if b.config.id == "construction_zone":
			continue
		if not b.can_operate():
			continue
		print("Operating: ", b.config.id, " active=", b.active, " workers=", b.worker_ids.size())
		var mult: float = b.level_multiplier()
		var has_all_inputs := true
		for resource_name in b.config.inputs:
			var needed: float = b.config.inputs[resource_name] * mult
			print("  needs ", needed, " of ", resource_name, " (has ", resources.get(resource_name, 0.0), ")")
			if resources.get(resource_name, 0.0) < needed:
				has_all_inputs = false
				break
		if not has_all_inputs:
			print("  -> skipped (not enough inputs)")
			continue
		for resource_name in b.config.inputs:
			var needed: float = b.config.inputs[resource_name] * mult
			resources[resource_name] = resources.get(resource_name, 0.0) - needed
		for resource_name in b.config.outputs:
			var produced: float = b.config.outputs[resource_name] * mult
			resources[resource_name] = resources.get(resource_name, 0.0) + produced
			print("  produced ", produced, " of ", resource_name)
