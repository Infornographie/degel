extends RefCounted
class_name BuildingRegistry
## Registry des BuildingConfig. Charge depuis le manifest central GameRegistry.

var configs: Dictionary = {}

func _init() -> void:
	_load_all()

func _load_all() -> void:
	var manifest: GameRegistry = GameRegistry.load_default()
	if manifest == null:
		push_error("BuildingRegistry: game_registry.tres introuvable")
		return
	for config in manifest.buildings:
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
		if config.is_starter:
			continue
		if not config.available:
			continue
		result.append(config)
	return result
