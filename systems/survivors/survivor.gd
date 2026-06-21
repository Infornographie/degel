extends RefCounted
class_name Survivor
## Un survivant : une petite personne identifiée, avec un métier de l'ancien monde.

var id: int
var name: String
var profession: String
var awake: bool = false
var job: int = 0   # GameState.Job.IDLE par défaut
var tile_key: String = ""   # tuile où il travaille, "" si au bunker
var building_id: String = ""   # bâtiment où il travaille, "" si pas en bâtiment
var sprite_variant: int = 0
var work_force: float = 3.0


func _init(p_id: int, p_name: String, p_profession: String) -> void:
	id = p_id
	name = p_name
	profession = p_profession
	sprite_variant = randi() % 5 # indiquer le nombre de variantes
