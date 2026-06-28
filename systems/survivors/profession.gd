extends Resource
class_name Profession
## Une profession d'avant-monde. Identité narrative + paramètres de tirage.

enum Rarity { ABSENT, ELITE, RARE, UNCOMMON, COMMON }

## Poids de tirage par rareté. Modifiable ici si l'équilibrage doit bouger.
const RARITY_WEIGHTS := {
	Rarity.ABSENT: 0,
	Rarity.ELITE: 1,
	Rarity.RARE: 3,
	Rarity.UNCOMMON: 10,
	Rarity.COMMON: 30,
}

## Identifiant interne (anglais, lowercase). Stocké sur Survivor.profession.
@export var id: StringName
## Clé de localisation du nom affiché (ex: PROF_CEO).
@export var name_key: String
## Tribu d'appartenance. Une seule.
@export var tribe: Tribe
## Rareté dans le roster initial et le pool d'éveil.
@export var rarity: Rarity = Rarity.COMMON
## Garantie de présence minimum dans le roster initial.
## 0 = pas de garantie, tirage normal selon rarity.
@export var min_count: int = 0
## Sprite associé. Laissé vide pour l'instant — plusieurs professions
## pourront partager le même sprite plus tard, avec pool de variantes
## pour la représentativité.
@export var sprite: Texture2D

@export_group("Modifiers")
## Multiplicateur sur la production d'une activité (tuile).
@export var activity_modifier: float = 1.0
## Multiplicateur sur la progression de chantier de ce survivant.
@export var construction_modifier: float = 1.0
## Multiplicateur sur l'output d'opération de bâtiment.
@export var building_modifier: float = 1.0
## Liste de ressources qui activent les modifiers activity et building.
## Vide = s'applique partout. Pour le bâtiment, matche sur input OU output.
## Ex : cuistot = [&"food", &"meal"] s'applique à la cueillette (output food)
## et à la canteen (input food, output meal).
@export var modifier_resource_filter: Array[StringName] = []

func weight() -> int:
	return RARITY_WEIGHTS.get(rarity, 0)

## Modifier d'activité pour une ressource donnée.
## Si le filtre est vide ou contient la ressource produite, applique le modifier.
func activity_modifier_for(res: StringName) -> float:
	if modifier_resource_filter.is_empty():
		return activity_modifier
	if res in modifier_resource_filter:
		return activity_modifier
	return 1.0

## Modifier de construction (pas de filtre — l'effort, c'est l'effort).
func construction_modifier_value() -> float:
	return construction_modifier

## Modifier de bâtiment : matche si une des ressources I/O est dans le filtre.
## resources_in_play = union des inputs et outputs du bâtiment (en StringName).
func building_modifier_for(resources_in_play: Array) -> float:
	if modifier_resource_filter.is_empty():
		return building_modifier
	for r in resources_in_play:
		if r in modifier_resource_filter:
			return building_modifier
	return 1.0
