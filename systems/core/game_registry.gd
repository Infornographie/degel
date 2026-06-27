extends Resource
class_name GameRegistry
## Manifest central de tout le contenu data-driven du jeu.
##
## Édité dans l'inspecteur Godot : drag-drop des .tres dans les arrays.
## Pour ajouter ou retirer un type (ressource, bâtiment, activité), aucun code
## à toucher — uniquement ce fichier .tres.
##
## Les trois registries (Resource, Building, Activity) chargent ce manifest
## au démarrage et indexent ce qu'il déclare.

const DEFAULT_PATH := "res://resources/game_registry.tres"

@export var resource_types: Array[ResourceType] = []
@export var buildings: Array[BuildingConfig] = []
@export var activities: Array[Activity] = []
@export var tribes: Array[Tribe] = []
@export var professions: Array[Profession] = []
@export var names: Array[String] = []

## Charge le manifest par défaut. Les Resources étant cachées par Godot,
## appeler plusieurs fois ne provoque pas de relecture disque.
static func load_default() -> GameRegistry:
	return load(DEFAULT_PATH) as GameRegistry
