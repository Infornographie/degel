extends RefCounted
class_name ActivityRegistry
## Registry des Activity. Charge depuis le manifest central GameRegistry.

var activities: Dictionary = {}

func _init() -> void:
	_load_all()

func _load_all() -> void:
	var manifest: GameRegistry = GameRegistry.load_default()
	if manifest == null:
		push_error("ActivityRegistry: game_registry.tres introuvable")
		return
	for activity in manifest.activities:
		if activity != null and activity.id != "":
			activities[activity.id] = activity

func get_activity(id: String) -> Activity:
	return activities.get(id)

func available_for_tile(tile_type: int) -> Array[Activity]:
	var result: Array[Activity] = []
	for activity in activities.values():
		if not activity.available:
			continue
		if tile_type in activity.allowed_tile_types:
			result.append(activity)
	return result
