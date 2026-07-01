extends Resource
class_name TraitConfig
## Trait porté par un survivant : modifie sa production, raconte qui il est ou
## comment il va. Un seul modèle pour STATE (état temporaire), NATURE (qui il
## est devenu) et EVENT (son histoire). La résolution les agrège indistinctement ;
## c'est l'UI qui les sépare par catégorie.

enum Category { STATE, NATURE, EVENT }

@export_group("Identity")
@export var id: StringName
@export var name_key: String
@export var description_key: String
@export var category: Category = Category.NATURE

@export_group("Display")
## Icône pour les STATE (affichée à côté du nom). Optionnelle pour les autres.
@export var icon: Texture2D
## Indication de couleur sémantique. L'UI choisit la couleur finale.
@export_enum("neutral", "positive", "negative", "story") var color_hint: String = "neutral"

@export_group("Modifiers")
## Multiplicateur sur la production d'une activité (tuile).
@export var activity_modifier: float = 1.0
## Multiplicateur sur la progression de chantier de ce survivant.
@export var construction_modifier: float = 1.0
## Multiplicateur sur l'output d'opération de bâtiment.
@export var building_modifier: float = 1.0
## Liste de ressources qui activent les modifiers activity et building.
## Vide = s'applique partout. Côté bâtiment, matche sur input OU output.
@export var modifier_resource_filter: Array[StringName] = []

@export_group("Lifecycle")
## -1 = permanent ; sinon nombre de tours avant retrait automatique.
@export var duration_turns: int = -1

## Modifier d'activité pour une ressource donnée.
func activity_modifier_for(res: StringName) -> float:
	if modifier_resource_filter.is_empty():
		return activity_modifier
	if res in modifier_resource_filter:
		return activity_modifier
	return 1.0

## Modifier de bâtiment : matche si une des ressources I/O est dans le filtre.
func building_modifier_for(resources_in_play: Array) -> float:
	if modifier_resource_filter.is_empty():
		return building_modifier
	for r in resources_in_play:
		if r in modifier_resource_filter:
			return building_modifier
	return 1.0
