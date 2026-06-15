extends RefCounted
class_name Roster
## Gère la liste des survivants : génération, accès, manipulations.
## Détenu par GameState, qui lui délègue tout ce qui touche aux survivants.

# Pools de tirage. Plus tard : extraits dans une Resource SurvivorRoster.tres.
const NAMES: Array[String] = [
	"Mara", "Yann", "Lina", "Otto", "Sève", "Théo", "Anouk", "Rémi",
	"Iris", "Bastien", "Nora", "Eliott", "Camille", "Soren", "Maï", "Jonas",
	"Aïcha", "Diego", "Wei", "Priya", "Tomás", "Astrid", "Kenji", "Fatou",
	"Niko", "Esra", "Léo", "Zara", "Idris", "Mei", "Hugo", "Lucia",
	"Akira", "Naomi", "Pavel", "Yusra", "Bjorn", "Olga", "Mateo", "Sana",
	"Kai", "Inès", "Dimitri", "Chiara", "Hassan", "Liv", "Raphaël", "Yuki",
	"Tariq", "Elena", "Sven", "Amara", "Léon", "Noor", "Iván", "Hana",
	"Cyril", "Greta", "Malik", "Suki", "Rasmus", "Layla", "Bram", "Imani",
	"Alma", "Joon", "Cécile", "Omar", "Freya", "Sasha", "Petra", "Khalil",
	"Solène", "Igor", "Yara", "Felix", "Mira", "Aslan", "Talia", "Cosmin",
	"Anika", "Jules", "Rania", "Lars", "Eve", "Samir", "Beatriz", "Vlad",
	"Tina", "Magnus", "Aïsha", "Quentin", "Sora", "Milos", "Zoé", "Hiro",
	"Yael", "Bao", "Ingrid", "Marek"
]
const PROFESSIONS: Array[String] = [
	"CEO", "Trader", "Game designer", "AI specialist", "Lawyer",
	"Cosmetic surgeon", "Influencer", "Architect", "Lobbyist",
	"Private pilot", "Banker", "Michelin-starred chef",
]

var survivors: Array[Survivor] = []
var initial_size: int = 0   # immuable, pour le score

func _init(initial_count: int) -> void:
	_generate(initial_count)
	initial_size = survivors.size()

## Tire `size` survivants. Noms et professions piochés sans remise pour les noms
## (pas de doublon dans le bunker), avec remise pour les professions (deux CEO,
## c'est plausible et même savoureux).
func _generate(count: int) -> void:
	var available_names := NAMES.duplicate()
	available_names.shuffle()
	var n: int = min(count, available_names.size())
	for i in n:
		var name: String = available_names[i]
		var profession: String = PROFESSIONS[randi() % PROFESSIONS.size()]
		survivors.append(Survivor.new(i, name, profession))

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

## Renvoie la liste des professions distinctes présentes parmi les endormis.
## Utilisé par l'UI pour proposer la recherche ciblée.
func sleeping_professions() -> Array[String]:
	var seen: Dictionary = {}
	var result: Array[String] = []
	for s in survivors:
		if not s.awake and not seen.has(s.profession):
			seen[s.profession] = true
			result.append(s.profession)
	result.sort()
	return result

## Toutes les professions présentes dans le roster (éveillés + endormis + morts retirés).
## Pour exposer la liste complète des choix de recherche, indépendamment de qui est encore en cryo.
func all_professions() -> Array[String]:
	# On reconstruit depuis le pool de départ : c'est le bunker, pas l'état courant.
	var seen: Dictionary = {}
	var result: Array[String] = []
	for prof in PROFESSIONS:
		if not seen.has(prof):
			seen[prof] = true
			result.append(prof)
	return result

## Tire jusqu'à `count` candidats endormis. Renvoie les ids.
## Si `exclude_ids` est fourni, ces survivants sont exclus du tirage.
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

## Renvoie le premier endormi de la profession donnée, ou null.
func find_sleeping_by_profession(profession: String) -> Survivor:
	for s in survivors:
		if not s.awake and s.profession == profession:
			return s
	return null

## Compte les endormis restants.
func sleeping_count() -> int:
	var n := 0
	for s in survivors:
		if not s.awake:
			n += 1
	return n
