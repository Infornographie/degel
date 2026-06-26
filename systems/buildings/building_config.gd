extends Resource
class_name BuildingConfig
## Description d'un type de bâtiment. Stocké en .tres, éditable dans l'inspecteur.

enum Family {
	## Transformation : consomme des ressources, produit des ressources.
	TRANSFORMATION,
	## Fonction : débloque une possibilité ou une action.
	FUNCTION,
}

@export_group("Identity")
## Identifiant unique du type. Sert de clé dans le registre. Ex : "sawmill".
@export var id: String = ""
## Clé de localisation pour le nom affiché. Ex : "BUILDING_SAWMILL".
@export var name_key: String = ""
## Clé de localisation pour la description.
@export var description_key: String = ""
## Famille du bâtiment.
@export var family: Family = Family.TRANSFORMATION

@export_group("Construction")
## Coût en ressources pour construire. { "wood": 5.0, "ore": 2.0 }.
@export var build_cost: Dictionary[String, float] = {}
## Ordre de consommation des ressources pour la construction.
## Si vide, on prend les clés du Dictionary dans leur ordre.
@export var build_order: Array[String] = []
## Coût en unités de travail pour construire. 1 unité = 1 tour-colon par défaut.
@export var build_work: float = 5.0
## Si vrai, le bâtiment est posé dès la création du jeu (bunker initial).
@export var is_starter: bool = false

@export_group("Operation")
## Inputs consommés par tour quand le bâtiment fonctionne. { "wood": 2.0 }.
@export var inputs: Dictionary[String, float] = {}
## Outputs produits par tour. { "planks": 1.0 }.
@export var outputs: Dictionary[String, float] = {}
## Nombre de colons requis pour que le bâtiment tourne (au niveau 1).
@export var workers_required: int = 1
## Nombre maximum de colons assignables au niveau 1.
@export var workers_max: int = 1
## Si vrai, le bâtiment peut tourner sans colon en consommant de l'électricité.
@export var can_run_on_electricity: bool = false
## Coût en électricité par tour si tourne sans colon (ou en plus).
@export var electricity_cost: float = 0.0

@export_group("Upgrades")
## Niveau maximum atteignable. 1 = pas d'amélioration possible.
@export var max_level: int = 1
## Multiplicateur d'output appliqué par niveau au-dessus de 1.
## Ex : 0.5 = +50% par niveau (niveau 2 = 150%, niveau 3 = 200%).
@export var output_multiplier_per_level: float = 0.5
## +N colons assignables par niveau au-dessus de 1.
@export var workers_max_increase_per_level: int = 1

@export_group("Availability")
## Est-ce que le bâtiment n'est constructible qu'en un seul exemplaire ?
@export var unique: bool = true
## Est-ce que le bâtiment est accessible à la construction ?
@export var available: bool = true

@export_group("UI")
## Vue UI à instancier dans le slot colony. Si null, fallback vers un Label
## d'erreur ; tu peux pointer vers generic_building_view.tscn pour les
## bâtiments génériques sans UI dédiée.
@export var view_scene: PackedScene
## Si vrai, le bâtiment est affiché avec le style "bunker" (bleu froid),
## sinon avec le style "colonie" (brun chaud). Indépendant de is_starter :
## conceptuellement, le bunker est l'héritage pré-apocalypse, la colonie
## est ce qu'on construit dehors.
@export var is_bunker_building: bool = false
## Clé de localisation du rôle affiché pour les workers assignés (ex : ROLE_COOK).
## Si vide, fallback générique ROLE_BUILDING_WORKER.
@export var worker_role_key: String = ""
