extends RefCounted
class_name Building
## Instance d'un bâtiment dans la colonie. Référence une BuildingConfig (type)
## et porte son état courant : niveau, colons affectés, progression de construction.

enum State {
	## En cours de construction. Pas opérationnel.
	UNDER_CONSTRUCTION,
	## Opérationnel.
	OPERATIONAL,
}

var config: BuildingConfig
var state: int = State.UNDER_CONSTRUCTION
var level: int = 1

## IDs des colons assignés à ce bâtiment. Vide = personne.
var worker_ids: Array[int] = []

## Progression de la construction, en unités de travail.
## Quand >= config.build_work, le bâtiment passe en OPERATIONAL.
var build_progress: float = 0.0

## Ressources déjà consommées pour la construction. { "wood": 3.0 }.
## Sert à savoir quand on a tout ce qu'il faut pour avancer.
var build_resources_consumed: Dictionary = {}

func _init(p_config: BuildingConfig) -> void:
	config = p_config

## Si vrai, le bâtiment a tout ce qu'il faut pour fonctionner ce tour.
func can_operate() -> bool:
	if state != State.OPERATIONAL:
		return false
	if worker_ids.size() >= config.workers_required:
		return true
	if config.can_run_on_electricity:
		return true
	return false

## Capacité maximale de colons selon le niveau actuel.
func workers_max() -> int:
	return config.workers_max + (level - 1) * config.workers_max_increase_per_level

## Multiplicateur d'output selon le niveau actuel.
func level_multiplier() -> float:
	return 1.0 + (level - 1) * config.output_multiplier_per_level

## Marque le bâtiment comme construit. Appelé par le système de construction.
func complete_construction() -> void:
	state = State.OPERATIONAL
	build_progress = 0.0
	build_resources_consumed.clear()
