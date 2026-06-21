extends RefCounted
class_name ActivityRegistry
## Charge et expose les activités du jeu.

const CONFIGS_PATH := "res://resources/activities/"
const ACTIVITY_FILES := [
	"gathering.tres",
	"hunting.tres",
	"wood_picker.tres",
	"lumberjack.tres",
	"forester.tres",
	"gardener.tres",
	"ore_picker.tres",
]

var activities: Dictionary = {}

func _init() -> void:
	_load_all()

func _load_all() -> void:
	for file_name in ACTIVITY_FILES:
		var path: String = CONFIGS_PATH + file_name
		if not ResourceLoader.exists(path):
			push_warning("ActivityRegistry: %s introuvable" % path)
			continue
		var activity: Activity = load(path) as Activity
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
