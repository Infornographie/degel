extends RefCounted
class_name Survivor
## Un survivant : une petite personne identifiée, avec un métier de l'ancien monde.

var id: int
var name: String
var profession: String
var awake: bool = false
var wake_order: int = -1   # ordre de réveil, -1 = pas encore éveillé
var activity_id: String = ""   # vide = pas d'activité (IDLE)
var tile_key: String = ""   # tuile où il travaille, "" si au bunker
var building_id: String = ""   # bâtiment où il travaille, "" si pas en bâtiment
var sprite_variant: int = 0
var work_force: float = 3.0


func _init(p_id: int, p_name: String, p_profession: String) -> void:
	id = p_id
	name = p_name
	profession = p_profession
	sprite_variant = randi() % 10 # indiquer le nombre de variantes
