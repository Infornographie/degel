extends Node
## GameState — cœur de la simulation (autoload).

var production_system: ProductionSystem
var activity_registry: ActivityRegistry
var turn_resolver: TurnResolver

enum EndCause { REACTOR_DEAD, COLONY_LOST }

const CONFIG_PATH := "res://resources/game_config_default.tres"
const TILE_CONFIG_PATH := "res://resources/tile_config_default.tres"

signal turn_advanced(turn: int)
signal resources_changed(resources: Dictionary)
signal survivor_woken(survivor: Survivor)
signal survivor_assigned(survivor: Survivor, activity_id: String)
signal nightly_deaths(events: Array)   # liste de { name, profession, cause }
signal famine_started
signal famine_ended
signal candidates_changed
signal targeted_wake_failed(profession: StringName)
signal tile_assignment_changed(tile: HexTile)
signal run_ended(cause: EndCause)
signal building_assignment_changed(building: Building)
signal construction_started(building: Building)
@warning_ignore("unused_signal")
signal construction_progressed(building: Building)
@warning_ignore("unused_signal")
signal construction_completed(building: Building)

var config: GameConfig
var tile_config: TileConfig

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

# ── Journal d'événements ──
signal event_logged(event: GameEvent)
var event_log: Array[GameEvent] = []

## Ajoute un événement au journal. Émet event_logged pour les vues qui
## écoutent en streaming (journal UI). Les news de fin de tour filtrent
## event_log par turn via events_for_turn().
func log_event(category: String, key: String, params: Array = []) -> void:
	var ev := GameEvent.new(turn, category, key, params)
	event_log.append(ev)
	event_logged.emit(ev)

## Retourne tous les events loggés à un tour donné.
func events_for_turn(t: int) -> Array[GameEvent]:
	var result: Array[GameEvent] = []
	for ev in event_log:
		if ev.turn == t:
			result.append(ev)
	return result

# --- Nécrologie (pour 5f) ---
var _deaths_this_turn: Array = []
var necrology: Array = []  # entrées { name, profession, cause, turn }

# --- Réveils ---
var _wakes_done_this_turn: int = 0
var _next_wake_order: int = 0

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
		"meal":0.0,
		"electricity": 0.0,
		"heat": 0.0,
	}

	building_registry = BuildingRegistry.new()
	activity_registry = ActivityRegistry.new()
	roster = Roster.new(config.roster_size)
	hex_map = HexMap.new(2, tile_config)
	production_system = ProductionSystem.new(hex_map, roster, activity_registry)
	turn_resolver = TurnResolver.new(self)

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

## Production attendue si ce survivant faisait cette activité sur cette tuile.
## Helper d'UI — passe par TurnResolver pour le calcul unique (famine + bonus prof).
func expected_activity_yield(s: Survivor, tile: HexTile, activity: Activity) -> int:
	if s == null or tile == null or activity == null:
		return 0
	var raw: float = tile.yields.get(activity.id, 0.0)
	return int(turn_resolver.compute_activity_yield(raw, s, activity.produced_resource))

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
	_apply_initial_traits(s)
	s.wake_order = _next_wake_order
	_next_wake_order += 1
	survivor_woken.emit(s)
	log_event("colony", "EVENT_WAKE", [s.name, "tr:" + Roster.name_key(s.profession)])
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

## Affecte une activité à un colon. Renvoie true si succès.
func assign_activity(survivor_id: int, new_activity_id: String) -> bool:
	if is_over:
		return false
	var s: Survivor = roster.get_by_id(survivor_id)
	if s == null or not s.awake:
		return false
	s.activity_id = new_activity_id
	survivor_assigned.emit(s, new_activity_id)
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

	# 1) Résolution déterministe + aléatoire (production, construction, bâtiments, mutations)
	turn_resolver.execute_turn()

	# 2) Repas + famine.
	#    Les meals sont consommés en priorité (1 meal = 1 survivant nourri),
	#    la food brute couvre le reste à raison de food_per_survivor par tête.
	var awake: int = awake_count()
	var meals_available: float = resources.get("meal", 0.0)
	var meals_consumed: float = min(meals_available, float(awake))
	resources["meal"] = meals_available - meals_consumed
	var food_needed: float = (float(awake) - meals_consumed) * config.food_per_survivor
	var was_in_famine := famine_turns > 0
	if resources["food"] >= food_needed:
		resources["food"] -= food_needed
		if was_in_famine:
			famine_turns = 0
			_deaths_triggered = false
			production_multiplier = 1.0
			famine_ended.emit()
			log_event("system", "EVENT_FAMINE_ENDED", [])
	else:
		resources["food"] = 0.0
		famine_turns += 1
		production_multiplier = FAMINE_PROD_MULTIPLIER
		if not was_in_famine:
			famine_started.emit()
			log_event("system", "EVENT_FAMINE_STARTED", [])
		_resolve_famine_deaths()

	# 3) Extinction des cryos si élec négative
	_resolve_extinctions()

	# 4) Érosion du réacteur
	if turn % config.reactor_decay_interval == 0:
		reactor_output -= 1.0
		log_event("system", "EVENT_REACTOR_DECAY", [reactor_output])
		if reactor_output <= 0.0:
			reactor_output = 0.0
			is_over = true
			resources_changed.emit(resources)
			turn_advanced.emit(turn)
			run_ended.emit(EndCause.REACTOR_DEAD)
			return

	# 5) Fin éventuelle par colonie vide
	if roster.is_empty():
		is_over = true
		resources_changed.emit(resources)
		turn_advanced.emit(turn)
		run_ended.emit(EndCause.COLONY_LOST)
		return

	_begin_turn()
	# News : tous les events de ce tour, vus à travers le log.
	var news: Array[GameEvent] = events_for_turn(turn)
	if not news.is_empty():
		nightly_deaths.emit(news)
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
	log_event("loss", "EVENT_DEATH_SWITCHED_OFF", [victim.name, "tr:" + Roster.name_key(victim.profession)])

func _sleeping_survivors() -> Array[Survivor]:
	var result: Array[Survivor] = []
	for s in roster.survivors:
		if not s.awake:
			result.append(s)
	return result

# ── PRODUCTION ──

func get_survivor_output(s: Survivor) -> Dictionary:
	if s == null or not s.awake or s.tile_key == "" or s.activity_id == "":
		return {}
	var tile: HexTile = hex_map.get_tile_by_key(s.tile_key)
	if tile == null:
		return {}
	var activity: Activity = activity_registry.get_activity(s.activity_id)
	if activity == null or activity.success_rate < 1.0:
		return {}  # risky : géré séparément par l'overlay
	var produced: int = expected_activity_yield(s, tile, activity)
	if produced <= 0:
		return {}
	return { activity.produced_resource: produced }

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
			log_event("loss", "EVENT_DEATH_STARVED", [victim.name, "tr:" + Roster.name_key(victim.profession)])

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
func targeted_wake(prof_id: StringName) -> bool:
	if is_over:
		return false
	if _wakes_done_this_turn >= config.wakes_per_turn:
		return false
	resources["electricity"] -= config.wake_cost_targeted
	_wakes_done_this_turn += 1
	var s: Survivor = roster.find_sleeping_by_profession_id(prof_id)
	if s == null:
		targeted_wake_failed.emit(prof_id)
		candidates_changed.emit()
		resources_changed.emit(resources)
		return false
	s.awake = true
	_apply_initial_traits(s)
	survivor_woken.emit(s)
	candidates.erase(s.id)
	_clean_candidates()
	log_event("colony", "EVENT_TARGETED_WAKE_SUCCESS", [s.name, "tr:" + Roster.name_key(s.profession)])
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
	log_event("colony", "EVENT_CONSTRUCTION_STARTED", ["tr:" + target_config.name_key])
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

## Pose le trait `normal` puis les initial_traits de la profession.
func _apply_initial_traits(s: Survivor) -> void:
	var normal_trait: TraitConfig = _find_trait(&"normal")
	if normal_trait != null:
		s.add_trait(normal_trait)
	var prof: Profession = Roster.get_profession(s.profession)
	if prof == null:
		return
	for t in prof.initial_traits:
		if t != null:
			s.add_trait(t)

## Lookup trait par id via le registry. Duplication temporaire — voir dette
## `TraitRegistry` dans la roadmap.
func _find_trait(id: StringName) -> TraitConfig:
	for t in GameRegistry.load_default().traits:
		if t.id == id:
			return t
	return null
