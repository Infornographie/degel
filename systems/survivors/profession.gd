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

@export_group("Traits")
## Traits NATURE posés automatiquement au réveil.
## Vide = pas de trait initial (le survivant sera juste `normal`).
@export var initial_traits: Array[TraitConfig] = []

func weight() -> int:
	return RARITY_WEIGHTS.get(rarity, 0)
