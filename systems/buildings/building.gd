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

## Ressources déjà consommées pour la construction. { "wood": 3.0 }.
## La complétion = tout le build_cost consommé (voir TurnResolver._resolve_construction).
var build_resources_consumed: Dictionary = {}

## Pour la zone de construction : id du bâtiment à construire (vide si rien à faire).
var construction_target: String = ""

## Identifiant unique d'instance (différent de config.id qui est le type).
var instance_id: int = -1

## Slot où le bâtiment est placé dans la grille colonie. -1 = non placé.
var slot_index: int = -1

## Si false, le bâtiment opérationnel ne tourne pas (mais existe).
var active: bool = true

## Intensité courante du bâtiment. Initialisée à max(1, max_intensity / 2).
## Modifie inputs ET outputs au prorata à la résolution.
var current_intensity: int = 1

func _init(p_config: BuildingConfig) -> void:
	config = p_config
	@warning_ignore("integer_division")
	current_intensity = max(1, p_config.max_intensity / 2)

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

## Report fractionnaire de production par output. { "meal": 0.4 }.
## Les stocks restent entiers : la fraction non produite ce tour se reporte
## au tour suivant (2.4/tour = 2, 2, 3, 2, 3...).
var output_carry: Dictionary = {}

## Marque le bâtiment comme construit. Appelé par le système de construction.
func complete_construction() -> void:
	state = State.OPERATIONAL
	build_resources_consumed.clear()
