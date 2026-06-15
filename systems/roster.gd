extends RefCounted
class_name Roster
## Gère la liste des survivants : génération, accès, manipulations.
## Détenu par GameState, qui lui délègue tout ce qui touche aux survivants.

# Pools de tirage. Plus tard : extraits dans une Resource SurvivorRoster.tres.
const NAMES: Array[String] = [
	"Mara", "Yann", "Lina", "Otto", "Sève", "Théo", "Anouk", "Rémi",
	"Iris", "Bastien", "Nora", "Eliott", "Camille", "Soren", "Maï", "Jonas",
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
