extends RefCounted
class_name Survivor
## Un survivant : une petite personne identifiée, avec un rôle.

var name: String
var role: String
var awake: bool = false

func _init(p_name: String, p_role: String) -> void:
	name = p_name
	role = p_role
