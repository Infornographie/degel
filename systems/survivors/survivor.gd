extends RefCounted
class_name Survivor
## Un survivant : une petite personne identifiée, avec un métier de l'ancien monde.

var id: int
var name: String
var profession: StringName  # id de la profession (cf. Profession.id)
var awake: bool = false
var wake_order: int = -1   # ordre de réveil, -1 = pas encore éveillé
var activity_id: String = ""   # vide = pas d'activité (IDLE)
var tile_key: String = ""   # tuile où il travaille, "" si au bunker
var building_id: String = ""   # bâtiment où il travaille, "" si pas en bâtiment
var sprite_variant: int = 0
var work_force: float = 3.0

# --- Traits ---
## Traits actuellement actifs. Un seul par id (pas de stacking).
## Un seul STATE à la fois (unicité garantie par add_trait).
var traits: Array[TraitConfig] = []
## Durées restantes pour les traits temporaires (id → tours restants).
## Absent = permanent.
var trait_durations: Dictionary = {}

# --- Fatigue (mécanique de pose du trait `tired`) ---
## Nombre de tours consécutifs sur la même activité.
var fatigue_streak: int = 0
## Dernière activité travaillée, pour détecter le changement.
var last_activity_id: StringName = &""


func _init(p_id: int, p_name: String, p_profession: StringName) -> void:
	id = p_id
	name = p_name
	profession = p_profession


# ──────────────────────────────────────────────────────────────────────────
#  TRAITS
# ──────────────────────────────────────────────────────────────────────────

## Ajoute un trait. Si déjà présent, reset sa durée. Si STATE, retire les autres
## STATE (unicité). Ne fait rien si t est null.
func add_trait(t: TraitConfig) -> void:
	if t == null:
		return
	# STATE : on retire les autres STATE (unicité)
	if t.category == TraitConfig.Category.STATE:
		var to_remove: Array[StringName] = []
		for existing in traits:
			if existing.category == TraitConfig.Category.STATE and existing.id != t.id:
				to_remove.append(existing.id)
		for id in to_remove:
			remove_trait(id)
	# Déjà présent : reset la durée uniquement
	if has_trait(t.id):
		if t.duration_turns > 0:
			trait_durations[t.id] = t.duration_turns
		return
	# Ajout neuf
	traits.append(t)
	if t.duration_turns > 0:
		trait_durations[t.id] = t.duration_turns

## Retire un trait par id. Silencieux si absent.
func remove_trait(id: StringName) -> void:
	for i in range(traits.size() - 1, -1, -1):
		if traits[i].id == id:
			traits.remove_at(i)
			break
	trait_durations.erase(id)

func has_trait(id: StringName) -> bool:
	for t in traits:
		if t.id == id:
			return true
	return false

func get_trait(id: StringName) -> TraitConfig:
	for t in traits:
		if t.id == id:
			return t
	return null
