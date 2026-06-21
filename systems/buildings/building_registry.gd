extends RefCounted
class_name BuildingRegistry

const CONFIGS_PATH := "res://resources/buildings/"
const BUILDING_FILES := [
	"computer.tres",
	"cryo_room.tres",
	"synthesizer.tres",
	"construction_zone.tres",
	"campfire.tres",
	"tool_workshop.tres",
]

var configs: Dictionary = {}

func _init() -> void:
	_load_all()

func _load_all() -> void:
	for file_name in BUILDING_FILES:
		var path: String = CONFIGS_PATH + file_name
		if not ResourceLoader.exists(path):
			push_warning("BuildingRegistry: %s introuvable" % path)
			continue
		var config: BuildingConfig = load(path) as BuildingConfig
		if config != null and config.id != "":
			configs[config.id] = config

func get_config(id: String) -> BuildingConfig:
	return configs.get(id)

func starters() -> Array[BuildingConfig]:
	var result: Array[BuildingConfig] = []
	for config in configs.values():
		if config.is_starter:
			result.append(config)
	return result

func constructibles() -> Array[BuildingConfig]:
	var result: Array[BuildingConfig] = []
	for config in configs.values():
		if not config.is_starter:
			result.append(config)
	return result
