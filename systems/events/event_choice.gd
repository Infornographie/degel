extends Resource
class_name EventChoice
## Un choix proposé au joueur dans un événement narratif.
## Phase 1 : effets globaux (ressources + traits sur tous les éveillés).
## Phase 2 : targeting par survivant (triggering_survivor, random, etc.).

@export var label_key: String
@export var resource_effects: Dictionary[String, float] = {}
@export var traits_to_add: Array[TraitConfig] = []
