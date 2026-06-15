extends RefCounted
class_name Survivor
## Un survivant : une petite personne identifiée, avec un métier de l'ancien monde.

var id: int
var name: String
var profession: String
var awake: bool = false

func _init(p_id: int, p_name: String, p_profession: String) -> void:
	id = p_id
	name = p_name
	profession = p_profession
