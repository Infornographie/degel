extends RefCounted
class_name BuildingRegistry
## Registre des BuildingConfig disponibles dans le jeu.
## Charge tous les .tres d'un dossier au démarrage.

const CONFIGS_PATH := "res://resources/buildings/"

var configs: Dictionary = {}  # id -> BuildingConfig

func _init() -> void:
	_load_all()

func _load_all() -> void:
	var dir := DirAccess.open(CONFIGS_PATH)
	if dir == null:
		push_warning("BuildingRegistry: dossier %s introuvable" % CONFIGS_PATH)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var config: BuildingConfig = load(CONFIGS_PATH + file_name) as BuildingConfig
			if config != null and config.id != "":
				configs[config.id] = config
		file_name = dir.get_next()
	dir.list_dir_end()

func get_config(id: String) -> BuildingConfig:
	return configs.get(id)

## Tous les bâtiments marqués `is_starter`. Posés dès le début du jeu.
func starters() -> Array[BuildingConfig]:
	var result: Array[BuildingConfig] = []
	for config in configs.values():
		if config.is_starter:
			result.append(config)
	return result

## Tous les bâtiments non-starter (constructibles par le joueur).
func constructibles() -> Array[BuildingConfig]:
	var result: Array[BuildingConfig] = []
	for config in configs.values():
		if not config.is_starter:
			result.append(config)
	return result
