extends RefCounted
class_name Roster
## Gère la liste des survivants : génération pondérée, accès, manipulations.
## Détenu par GameState, qui lui délègue tout ce qui touche aux survivants.
## Les noms et professions sont lus depuis GameRegistry (data-driven).

var survivors: Array[Survivor] = []
var initial_size: int = 0   # immuable, pour le score

func _init(initial_count: int) -> void:
	_generate(initial_count)
	initial_size = survivors.size()

# ─── Génération ──────────────────────────────────────────────────────

## Tire `count` survivants.
##
## Étape 1 : honore les min_count des professions (garantis présents).
## Étape 2 : remplit le reste avec un tirage pondéré par rarity.
## Les noms sont piochés sans remise (pas de doublon dans le bunker),
## les professions avec remise (deux CEO dans un bunker, c'est plausible).
func _generate(count: int) -> void:
	var manifest: GameRegistry = GameRegistry.load_default()
	if manifest == null:
		push_error("Roster: game_registry.tres introuvable")
		return

	# Préparation du pool de noms (sans remise).
	var available_names: Array[String] = manifest.names.duplicate()
	available_names.shuffle()
	var name_index: int = 0

	# Étape 1 : minimums obligatoires.
	var picked_professions: Array[Profession] = []
	for prof in manifest.professions:
		if prof == null:
			continue
		if prof.min_count > 0 and prof.rarity == Profession.Rarity.ABSENT:
			push_warning("Roster: %s a min_count=%d mais rarity=ABSENT — min_count gagne." % [prof.id, prof.min_count])
		for i in prof.min_count:
			picked_professions.append(prof)

	# Étape 2 : tirage pondéré pour combler.
	var pool: Array[Profession] = manifest.professions.filter(
		func(p: Profession): return p != null and p.weight() > 0
	)
	var total_weight: int = 0
	for p in pool:
		total_weight += p.weight()

	while picked_professions.size() < count:
		if pool.is_empty() or total_weight <= 0:
			break
		picked_professions.append(_pick_weighted(pool, total_weight))

	# Tronque si on a dépassé (cas où sum(min_count) > count).
	if picked_professions.size() > count:
		picked_professions.resize(count)

	# Mélange pour que les forcés ne soient pas tous au début.
	picked_professions.shuffle()

	# Création des Survivors.
	for i in picked_professions.size():
		if name_index >= available_names.size():
			push_warning("Roster: plus de noms disponibles (%d demandés, %d dispo)." % [count, available_names.size()])
			break
		var s_name: String = available_names[name_index]
		name_index += 1
		var s_prof: StringName = picked_professions[i].id
		survivors.append(Survivor.new(i, s_name, s_prof))

func _pick_weighted(pool: Array[Profession], total_weight: int) -> Profession:
	var pick: int = randi() % total_weight
	var cursor: int = 0
	for p in pool:
		cursor += p.weight()
		if pick < cursor:
			return p
	return pool.back()  # fallback (ne devrait jamais arriver)

# ─── Accès ──────────────────────────────────────────────────────────

func awake_survivors() -> Array[Survivor]:
	var result: Array[Survivor] = []
	for s in survivors:
		if s.awake:
			result.append(s)
	return result

func awake_count() -> int:
	return awake_survivors().size()

func size() -> int:
	return survivors.size()

func is_empty() -> bool:
	return survivors.is_empty()

func get_by_id(id: int) -> Survivor:
	for s in survivors:
		if s.id == id:
			return s
	return null

func remove(survivor: Survivor) -> void:
	survivors.erase(survivor)

func pick_random_awake() -> Survivor:
	var pool := awake_survivors()
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]

func sleeping_count() -> int:
	var n := 0
	for s in survivors:
		if not s.awake:
			n += 1
	return n

# ─── Professions : helpers ──────────────────────────────────────────

# ─── Cache statique des Professions ─────────────────────────────────
# Indexation O(1) par id. Construit au premier appel, conservé pour
# toute la durée de vie du programme. ResourceRegistry suit le même pattern.
static var _professions_by_id: Dictionary = {}
static var _professions_loaded: bool = false

static func _ensure_professions_loaded() -> void:
	if _professions_loaded:
		return
	_professions_loaded = true
	var manifest: GameRegistry = GameRegistry.load_default()
	if manifest == null:
		push_error("Roster: game_registry.tres introuvable")
		return
	for p in manifest.professions:
		if p != null and p.id != StringName(""):
			_professions_by_id[p.id] = p

static func get_profession(prof_id: StringName) -> Profession:
	_ensure_professions_loaded()
	return _professions_by_id.get(prof_id)

## Nom affichable d'une profession (localisé). Helper de transition
## pour les anciens callers qui interpolaient Survivor.profession directement.
static func display_name(prof_id: StringName) -> String:
	var p := get_profession(prof_id)
	if p == null:
		return String(prof_id)
	return TranslationServer.translate(p.name_key)

## Clé de localisation d'une profession (pour log d'événement avec "tr:").
## Permet la traduction différée au moment de l'affichage.
static func name_key(prof_id: StringName) -> String:
	var p := get_profession(prof_id)
	if p == null:
		return String(prof_id)
	return p.name_key

## Ids des professions présentes parmi les endormis.
func sleeping_profession_ids() -> Array[StringName]:
	var seen: Dictionary = {}
	var result: Array[StringName] = []
	for s in survivors:
		if not s.awake and not seen.has(s.profession):
			seen[s.profession] = true
			result.append(s.profession)
	return result

## Ids de toutes les professions présentes dans le manifest.
## Pour exposer le choix complet de recherche ciblée, indépendamment
## de qui dort encore.
func all_profession_ids() -> Array[StringName]:
	var manifest: GameRegistry = GameRegistry.load_default()
	if manifest == null:
		return []
	var result: Array[StringName] = []
	for p in manifest.professions:
		if p != null and p.rarity != Profession.Rarity.ABSENT:
			result.append(p.id)
	return result

## Premier endormi d'une profession donnée, ou null.
func find_sleeping_by_profession_id(prof_id: StringName) -> Survivor:
	for s in survivors:
		if not s.awake and s.profession == prof_id:
			return s
	return null

# ─── Candidats (pool de réveil) ─────────────────────────────────────

## Tire jusqu'à `count` candidats endormis. Renvoie les ids des survivants.
func draw_candidates(count: int, exclude_ids: Array = []) -> Array[int]:
	var pool: Array[Survivor] = []
	for s in survivors:
		if not s.awake and not exclude_ids.has(s.id):
			pool.append(s)
	pool.shuffle()
	var result: Array[int] = []
	var n: int = min(count, pool.size())
	for i in n:
		result.append(pool[i].id)
	return result
