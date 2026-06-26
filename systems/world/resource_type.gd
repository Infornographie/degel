extends Resource
class_name ResourceType
## Type de ressource : descripteur d'une réserve du jeu.
## Indexé par `id` (StringName) dans GameState.resources.

@export var id: StringName
## Clé de localisation pour le nom affiché.
@export var name_key: String
## Icône utilisée dans la barre de ressources et les vues de production.
@export var icon: Texture2D
## Si false, la ressource est un flux (réinitialisée chaque tour, ex: electricity, heat).
@export var stackable: bool = true
## Plafond de stockage. -1 = illimité. Pas encore appliqué dans GameState (dette consciente).
@export var max_stock: float = -1.0
## Ordre d'affichage dans la barre de ressources (croissant).
@export var display_order: int = 0
