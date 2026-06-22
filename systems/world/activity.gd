extends Resource
class_name Activity
## Une activité réalisable par un colon sur une tuile.

@export_group("Identity")
@export var id: String = ""
@export var name_key: String = ""

@export_group("Availability")
@export var available: bool = true
## Types de tuiles où cette activité est réalisable.
## Stocké en int car HexTile.Type est une enum (qui se résout en int).
@export var allowed_tile_types: Array[int] = []

@export_group("Production")
@export var inputs: Dictionary[String, float] = {}
## Ressource produite par cette activité.
@export var produced_resource: String = ""

@export_group("Success / Failure")
## Probabilité de succès, entre 0.0 et 1.0. À 1.0, l'activité est sûre.
@export_range(0.0, 1.0, 0.05) var success_rate: float = 1.0

@export_group("Tile effect")
## Effet sur la santé de la tuile. +1 = dégrade, -1 = restaure.
@export var tile_health_delta: int = 0
