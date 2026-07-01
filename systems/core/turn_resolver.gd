extends RefCounted
class_name TurnResolver
## Source unique de vérité pour la résolution d'un tour.
##
## Deux usages :
##  - compute_flow() : calcule le bilan DÉTERMINISTE du tour (production, conso,
##    impossible) sans rien modifier. Utilisé par l'UI (prévision) ET comme base
##    du commit. C'est ce partage qui garantit que l'affichage ne ment jamais.
##  - execute_turn() : applique réellement le tour, dans l'ordre canonique, en
##    incluant l'aléatoire (chasse, morts) qui n'a pas sa place en prévision.
##
## L'aléatoire et les morts ne sont JAMAIS calculés en prévision.

var gs  # GameState (autoload). Typé dynamiquement pour éviter la dépendance circulaire.

func _init(game_state) -> void:
	gs = game_state

# ──────────────────────────────────────────────────────────────────────────
#  FLUX DÉTERMINISTE (prévision = commit)
# ──────────────────────────────────────────────────────────────────────────

## Calcule le bilan déterministe du tour sur une COPIE du stock, sans rien
## modifier. Reproduit fidèlement la séquence d'exécution (tile → construction
## → bâtiments) pour que la prévision corresponde exactement au commit.
##
## Retourne, par ressource :
##   { "production": float, "consumption": float, "impossible": float }
## où :
##   production  = ce qui est réellement produit ce tour (inputs disponibles)
##   impossible  = ce qui aurait été produit mais bloqué faute d'inputs
##   consumption = tout ce qui est consommé (colons, activités, construction, bâtiments)
##
## NB : la chasse (risky) est exclue. Elle est affichée à part et résolue
## séparément en commit.
func compute_flow() -> Dictionary:
	# Copie de travail du stock — on n'altère jamais le vrai.
	var stock: Dictionary = gs.resources.duplicate()
	# Accumulateurs par ressource.
	var production: Dictionary = {}
	var consumption: Dictionary = {}
	var impossible: Dictionary = {}

	# 1) Production des tuiles (activités sûres uniquement)
	for tile in gs.hex_map.tiles.values():
		if tile.worker_id == -1:
			continue
		var s: Survivor = gs.roster.get_by_id(tile.worker_id)
		if s == null or not s.awake or s.activity_id == "":
			continue
		var activity: Activity = gs.activity_registry.get_activity(s.activity_id)
		if activity == null:
			continue
		if activity.success_rate < 1.0:
			continue  # risky : hors flux déterministe
		# Inputs de l'activité (ex : outils du bûcheron)
		var has_inputs := _has_inputs(stock, activity.inputs, 1.0)
		var raw: float = tile.yields.get(s.activity_id, 0.0)
		var produced: float = compute_activity_yield(raw, s, activity.produced_resource)
		if produced > 0.0:
			stock[activity.produced_resource] = stock.get(activity.produced_resource, 0.0) + produced
		if has_inputs:
			# Consommer les inputs, produire l'output
			for input_name in activity.inputs:
				_add(consumption, input_name, activity.inputs[input_name])
				stock[input_name] = stock.get(input_name, 0.0) - activity.inputs[input_name]
			if activity.produced_resource != "" and produced > 0.0:
				_add(production, activity.produced_resource, produced)
				stock[activity.produced_resource] = stock.get(activity.produced_resource, 0.0) + produced
		else:
			# Inputs manquants : l'output devient impossible
			if activity.produced_resource != "" and produced > 0.0:
				_add(impossible, activity.produced_resource, produced)

	# 2) Construction (consomme dans l'ordre build_order, bornée par le stock)
	_simulate_construction(stock, consumption)

	# 3) Bâtiments opérationnels (séquentiel, sur la copie)
	for b in gs.buildings:
		if not _building_operates(b):
			continue
		var bmult: float = _building_multiplier(b)
		var factor: float = _operation_factor(b, stock, bmult)
		# Inputs consommés au prorata
		for input_name in b.config.inputs:
			var needed_full: float = b.config.inputs[input_name] * bmult
			var needed: float = needed_full * factor
			_add(consumption, input_name, needed)
			stock[input_name] = stock.get(input_name, 0.0) - needed
		# Outputs produits au prorata ; le reste (1 - factor) est impossible
		var build_mod: float = _building_output_modifier(b)
		for output_name in b.config.outputs:
			var output_full: float = round(b.config.outputs[output_name] * bmult * build_mod)
			var produced: float = output_full * factor
			if produced > 0.0:
				_add(production, output_name, produced)
				stock[output_name] = stock.get(output_name, 0.0) + produced
			var blocked: float = output_full - produced
			if blocked > 0.0:
				_add(impossible, output_name, blocked)

	# 4) Synthétiseur — traité comme bâtiment SI c'est un Building actif.
	#    (Le synthé est déjà dans gs.buildings, donc géré par la boucle ci-dessus.
	#     Ce bloc ne fait rien de plus ; conservé pour lisibilité.)

	# 5) Réacteur : production d'électricité (flux pur, pas de multiplicateur famine)
	_add(production, "electricity", gs.reactor_output)

	# 6) Consommation : repas des colons.
	#    Les meals sont consommés en priorité (1 meal = 1 survivant nourri),
	#    la food brute couvre le reste à raison de food_per_survivor par tête.
	var awake_count: int = gs.awake_count()
	var meals_available: float = stock.get("meal", 0.0)
	var meals_consumed: float = min(meals_available, float(awake_count))
	if meals_consumed > 0.0:
		_add(consumption, "meal", meals_consumed)
		stock["meal"] = meals_available - meals_consumed
	var food_needed: float = (float(awake_count) - meals_consumed) * gs.config.food_per_survivor
	_add(consumption, "food", food_needed)

	# 7) Consommation : électricité déjà dépensée ce tour (réveils)
	_add(consumption, "electricity", gs.electricity_consumed_this_turn())

	# Assemble le résultat par ressource.
	var result: Dictionary = {}
	var all_resources: Array = []
	for k in production.keys():
		if k not in all_resources: all_resources.append(k)
	for k in consumption.keys():
		if k not in all_resources: all_resources.append(k)
	for k in impossible.keys():
		if k not in all_resources: all_resources.append(k)
	for r in all_resources:
		result[r] = {
			"production": production.get(r, 0.0),
			"consumption": consumption.get(r, 0.0),
			"impossible": impossible.get(r, 0.0),
		}
	return result

## Liste les activités risquées en cours, pour l'affichage séparé.
## Retourne [{ "activity": Activity, "amount": float, "survivor": Survivor }].
func gather_risky() -> Array:
	var rows: Array = []
	for s in gs.awake_survivors():
		if s.activity_id == "" or s.tile_key == "":
			continue
		var activity: Activity = gs.activity_registry.get_activity(s.activity_id)
		if activity == null or activity.success_rate >= 1.0:
			continue
		var tile: HexTile = gs.hex_map.get_tile_by_key(s.tile_key)
		if tile == null:
			continue
		rows.append({
			"activity": activity,
			"amount": tile.yields.get(s.activity_id, 0.0),
			"survivor": s,
		})
	return rows

# ──────────────────────────────────────────────────────────────────────────
#  EXÉCUTION (commit) — ordre canonique avec aléatoire
# ──────────────────────────────────────────────────────────────────────────

## Exécute réellement le tour sur gs.resources. Les événements (chasses,
## mutations, constructions, morts...) sont enregistrés via gs.log_event().
func execute_turn() -> void:
	# 1) RISKY d'abord : le gain peut servir dès ce tour.
	_resolve_risky()
	# 2) Production des tuiles déterministe.
	_resolve_tile_production()
	# 3) Construction.
	_resolve_construction()
	# 4) Bâtiments opérationnels.
	_resolve_buildings_operation()
	# 5) Mutations de tuiles (forêt épuisée → plaine).
	_resolve_tile_mutations()
	# 6) Fatigue : détection de répétition d'activité, pose/retrait de `tired`.
	_resolve_fatigue()
	# 7) Décrément des durées de traits, retrait des expirés.
	_resolve_trait_durations()

# ── Étapes d'exécution ──

func _resolve_risky() -> void:
	for tile in gs.hex_map.tiles.values():
		if tile.worker_id == -1:
			continue
		var s: Survivor = gs.roster.get_by_id(tile.worker_id)
		if s == null or not s.awake or s.activity_id == "":
			continue
		var activity: Activity = gs.activity_registry.get_activity(s.activity_id)
		if activity == null or activity.success_rate >= 1.0:
			continue
		# Inputs (rare pour une activité risquée, mais on respecte le modèle)
		if not _has_inputs(gs.resources, activity.inputs, 1.0):
			gs.log_event("colony", "EVENT_HUNT_NO_INPUTS", [s.name, "tr:" + Roster.name_key(s.profession)])
			continue
		for input_name in activity.inputs:
			gs.resources[input_name] = gs.resources.get(input_name, 0.0) - activity.inputs[input_name]
		# Tirage
		if randf() < activity.success_rate:
			var raw: float = tile.yields.get(s.activity_id, 0.0)
			var produced: float = compute_activity_yield(raw, s, activity.produced_resource)
			if activity.produced_resource != "" and produced > 0.0:
				gs.resources[activity.produced_resource] = gs.resources.get(activity.produced_resource, 0.0) + produced
			gs.log_event("colony", "EVENT_HUNT_SUCCESS", [s.name, "tr:" + Roster.name_key(s.profession)])
			if activity.tile_health_delta != 0:
				tile.health = max(0, tile.health + activity.tile_health_delta)
		else:
			gs.log_event("colony", "EVENT_HUNT_FAIL", [s.name, "tr:" + Roster.name_key(s.profession)])

func _resolve_tile_production() -> void:
	# Production sûre + effets de santé. (Les risky sont déjà résolues.)
	for tile in gs.hex_map.tiles.values():
		if tile.worker_id == -1:
			continue
		var s: Survivor = gs.roster.get_by_id(tile.worker_id)
		if s == null or not s.awake or s.activity_id == "":
			continue
		var activity: Activity = gs.activity_registry.get_activity(s.activity_id)
		if activity == null or activity.success_rate < 1.0:
			continue  # risky déjà traité
		# Inputs
		if not _has_inputs(gs.resources, activity.inputs, 1.0):
			continue
		for input_name in activity.inputs:
			gs.resources[input_name] = gs.resources.get(input_name, 0.0) - activity.inputs[input_name]
		# Effet santé
		if activity.tile_health_delta != 0:
			tile.health = max(0, tile.health + activity.tile_health_delta)
		# Production
		if activity.produced_resource == "":
			continue
		var raw: float = tile.yields.get(s.activity_id, 0.0)
		var produced: float = compute_activity_yield(raw, s, activity.produced_resource)
		if produced > 0.0:
			gs.resources[activity.produced_resource] = gs.resources.get(activity.produced_resource, 0.0) + produced
	
func _resolve_construction() -> void:
	var zone: Building = gs._find_building_by_type("construction_zone")
	if zone == null or zone.construction_target == "":
		return
	var target: Building = gs._find_building_by_instance(int(zone.construction_target))
	if target == null or target.state != Building.State.UNDER_CONSTRUCTION:
		return
	var total_work: float = 0.0
	for wid in zone.worker_ids:
		var s: Survivor = gs.roster.get_by_id(wid)
		if s != null and s.awake:
			total_work += s.work_force * _construction_modifier(s)
	if total_work <= 0.0:
		return
	var work_left: float = total_work
	var order: Array = _build_order(target)
	for resource_name in order:
		if work_left <= 0.0:
			break
		var needed: float = target.config.build_cost.get(resource_name, 0.0) - target.build_resources_consumed.get(resource_name, 0.0)
		if needed <= 0.0:
			continue
		var available: float = gs.resources.get(resource_name, 0.0)
		if available < 1.0:
			continue
		var to_consume: float = min(min(work_left, needed), available)
		gs.resources[resource_name] = available - to_consume
		target.build_resources_consumed[resource_name] = target.build_resources_consumed.get(resource_name, 0.0) + to_consume
		work_left -= to_consume
	gs.construction_progressed.emit(target)
	# Complétion ?
	var done := true
	for resource_name in target.config.build_cost:
		if target.build_resources_consumed.get(resource_name, 0.0) < target.config.build_cost[resource_name]:
			done = false
			break
	if done:
		target.complete_construction()
		gs.log_event("colony", "EVENT_CONSTRUCTION_COMPLETED", ["tr:" + target.config.name_key])
		if zone.construction_target == str(target.instance_id):
			zone.construction_target = ""
			# Bascule auto sur un autre chantier en cours, s'il y en a.
			for other in gs.buildings:
				if other.state == Building.State.UNDER_CONSTRUCTION:
					zone.construction_target = str(other.instance_id)
					break
		gs.construction_completed.emit(target)

func _resolve_buildings_operation() -> void:
	for b in gs.buildings:
		if not _building_operates(b):
			continue
		var bmult: float = _building_multiplier(b)
		var factor: float = _operation_factor(b, gs.resources, bmult)
		if factor <= 0.0:
			continue
		for input_name in b.config.inputs:
			var needed: float = b.config.inputs[input_name] * bmult * factor
			gs.resources[input_name] = gs.resources.get(input_name, 0.0) - needed
		var build_mod: float = _building_output_modifier(b)
		for output_name in b.config.outputs:
			var produced: float = round(b.config.outputs[output_name] * bmult * build_mod) * factor
			gs.resources[output_name] = gs.resources.get(output_name, 0.0) + produced

func _resolve_tile_mutations() -> void:
	for tile in gs.hex_map.tiles.values():
		if tile.type == HexTile.Type.FOREST and tile.health >= 5:
			gs.hex_map.mutate_tile(tile, HexTile.Type.PLAINS)
			gs.log_event("system", "EVENT_FOREST_DEPLETED", [])

# ──────────────────────────────────────────────────────────────────────────
#  HELPERS PARTAGÉS (utilisés par flux ET exécution)
# ──────────────────────────────────────────────────────────────────────────

## Un bâtiment produit-il ce tour ? (opérationnel, actif, hors zone de construction,
## peut opérer selon ses workers/élec).
func _building_operates(b: Building) -> bool:
	if b.state != Building.State.OPERATIONAL:
		return false
	if not b.active:
		return false
	if b.config.id == "construction_zone":
		return false
	if not b.can_operate():
		return false
	return true

## Multiplicateur effectif d'un bâtiment : niveau × intensité.
## Helper partagé pour éviter de l'oublier à un des call sites.
func _building_multiplier(b: Building) -> float:
	return b.level_multiplier() * float(b.current_intensity)

## Facteur d'opération d'un bâtiment : fraction de cycle réalisable selon les
## inputs disponibles dans `stock`. 1.0 = plein régime, 0.0 = rien.
func _operation_factor(b: Building, stock: Dictionary, bmult: float) -> float:
	var factor: float = 1.0
	for input_name in b.config.inputs:
		var needed: float = b.config.inputs[input_name] * bmult
		if needed <= 0.0:
			continue
		var available: float = stock.get(input_name, 0.0)
		factor = min(factor, available / needed)
	return max(0.0, factor)

## Vérifie que `stock` couvre tous les `inputs` (chacun × scale).
func _has_inputs(stock: Dictionary, inputs: Dictionary, scale: float) -> bool:
	for input_name in inputs:
		if stock.get(input_name, 0.0) < inputs[input_name] * scale:
			return false
	return true

## Simule la consommation de construction sur la copie de stock (pour compute_flow).
func _simulate_construction(stock: Dictionary, consumption: Dictionary) -> void:
	var zone: Building = gs._find_building_by_type("construction_zone")
	if zone == null or zone.construction_target == "":
		return
	var target: Building = gs._find_building_by_instance(int(zone.construction_target))
	if target == null or target.state != Building.State.UNDER_CONSTRUCTION:
		return
	var work: float = 0.0
	for wid in zone.worker_ids:
		var s: Survivor = gs.roster.get_by_id(wid)
		if s != null and s.awake:
			work += s.work_force * _construction_modifier(s)
	if work <= 0.0:
		return
	var work_left: float = work
	for resource_name in _build_order(target):
		if work_left <= 0.0:
			break
		var needed: float = target.config.build_cost.get(resource_name, 0.0) - target.build_resources_consumed.get(resource_name, 0.0)
		if needed <= 0.0:
			continue
		var available: float = stock.get(resource_name, 0.0)
		if available < 1.0:
			continue
		var to_consume: float = min(min(work_left, needed), available)
		stock[resource_name] = available - to_consume
		_add(consumption, resource_name, to_consume)
		work_left -= to_consume

func _build_order(target: Building) -> Array:
	var order: Array = target.config.build_order
	if order.is_empty():
		order = target.config.build_cost.keys()
	return order

## Applique le multiplicateur de famine en préservant "au moins 1 si raw ≥ 1".
func _apply_multiplier(raw: float, mult: float) -> float:
	if mult >= 1.0:
		return raw
	var result: float = floor(raw * mult)
	if raw >= 1.0 and result < 1.0:
		result = 1.0
	return result

## Calcul unique de la production d'un survivant pour une activité donnée.
## Combine famine + modifier profession. N'applique PAS le success_rate.
## Tous les call sites (résolution, prévisualisation, affichage carte) passent ici.
func compute_activity_yield(raw: float, s: Survivor, produced_resource: String) -> float:
	var produced: float = _apply_multiplier(raw, gs.production_multiplier)
	produced = round(produced * _activity_modifier(s, produced_resource))
	return produced

# ──────────────────────────────────────────────────────────────────────────
#  MODIFIERS TRAITS (helpers centralisés — une logique, un endroit)
# ──────────────────────────────────────────────────────────────────────────

## Modifier d'activité : produit de tous les traits du survivant, pour la
## ressource produite par l'activité.
func _activity_modifier(s: Survivor, resource_name: String) -> float:
	if s == null:
		return 1.0
	var res: StringName = StringName(resource_name)
	var total: float = 1.0
	for t in s.traits:
		total *= t.activity_modifier_for(res)
	return total

## Modifier de construction : produit de tous les traits du survivant.
func _construction_modifier(s: Survivor) -> float:
	if s == null:
		return 1.0
	var total: float = 1.0
	for t in s.traits:
		total *= t.construction_modifier
	return total

## Modifier de bâtiment : lit le premier worker (1 worker/bâtiment pour l'instant),
## agrège ses traits. Le filtre trait matche sur input ∪ output du bâtiment.
func _building_output_modifier(b: Building) -> float:
	if b.worker_ids.is_empty():
		return 1.0
	var s: Survivor = gs.roster.get_by_id(b.worker_ids[0])
	if s == null:
		return 1.0
	var resources_in_play: Array = []
	for r in b.config.inputs.keys():
		resources_in_play.append(StringName(r))
	for r in b.config.outputs.keys():
		resources_in_play.append(StringName(r))
	var total: float = 1.0
	for t in s.traits:
		total *= t.building_modifier_for(resources_in_play)
	return total

func _add(dict: Dictionary, key: String, amount: float) -> void:
	if amount == 0.0:
		return
	dict[key] = dict.get(key, 0.0) + amount

# ──────────────────────────────────────────────────────────────────────────
#  FATIGUE (STATE `tired` posé sur répétition d'activité)
# ──────────────────────────────────────────────────────────────────────────

## Seuil de fatigue : après N tours consécutifs sur la même activité.
const FATIGUE_THRESHOLD: int = 3

## Met à jour le compteur de fatigue de chaque éveillé et pose/retire le trait
## `tired`. À appeler UNE fois par tour, après la résolution de production.
func _resolve_fatigue() -> void:
	var tired_trait: TraitConfig = _get_trait_by_id(&"tired")
	var normal_trait: TraitConfig = _get_trait_by_id(&"normal")
	if tired_trait == null or normal_trait == null:
		return  # traits pas encore créés, silencieux
	for s in gs.awake_survivors():
		var current: StringName = StringName(s.activity_id)
		if current == &"":
			# Pas d'activité ce tour : on remet à zéro
			s.fatigue_streak = 0
			s.last_activity_id = &""
			if s.has_trait(&"tired"):
				s.add_trait(normal_trait)
			continue
		if current == s.last_activity_id:
			s.fatigue_streak += 1
		else:
			s.fatigue_streak = 1
			# Changement d'activité : on repose normal si on était tired
			if s.has_trait(&"tired"):
				s.add_trait(normal_trait)
		s.last_activity_id = current
		# Pose du trait tired si seuil atteint
		if s.fatigue_streak >= FATIGUE_THRESHOLD and not s.has_trait(&"tired"):
			s.add_trait(tired_trait)


# ──────────────────────────────────────────────────────────────────────────
#  DÉCRÉMENT DES DURÉES DE TRAITS
# ──────────────────────────────────────────────────────────────────────────

## Décrémente `trait_durations` de chaque éveillé, retire les traits expirés.
## Si le trait retiré était un STATE, repose `normal` pour maintenir l'invariant
## "toujours un STATE actif".
func _resolve_trait_durations() -> void:
	var normal_trait: TraitConfig = _get_trait_by_id(&"normal")
	for s in gs.awake_survivors():
		if s.trait_durations.is_empty():
			continue
		var expired: Array[StringName] = []
		for id in s.trait_durations.keys():
			s.trait_durations[id] -= 1
			if s.trait_durations[id] <= 0:
				expired.append(id)
		for id in expired:
			var was_state: bool = false
			var t: TraitConfig = s.get_trait(id)
			if t != null and t.category == TraitConfig.Category.STATE:
				was_state = true
			s.remove_trait(id)
			if was_state and normal_trait != null:
				s.add_trait(normal_trait)


# ──────────────────────────────────────────────────────────────────────────
#  LOOKUP TRAITS (via game registry, cache local)
# ──────────────────────────────────────────────────────────────────────────

var _trait_cache: Dictionary = {}
var _registry: GameRegistry = null

func _get_trait_by_id(id: StringName) -> TraitConfig:
	if _trait_cache.has(id):
		return _trait_cache[id]
	if _registry == null:
		_registry = GameRegistry.load_default()
	for t in _registry.traits:
		if t.id == id:
			_trait_cache[id] = t
			return t
	return null
