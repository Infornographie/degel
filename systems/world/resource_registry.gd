extends RefCounted
class_name ResourceRegistry
## Registry des ResourceType, chargés depuis une liste explicite.
## Pattern aligné sur ActivityRegistry / BuildingRegistry (build Windows : pas de DirAccess).

const PATHS: Array[String] = [
	"res://resources/resource_types/food.tres",
	"res://resources/resource_types/wood.tres",
	"res://resources/resource_types/ore.tres",
	"res://resources/resource_types/tools.tres",
	"res://resources/resource_types/electricity.tres",
	"res://resources/resource_types/heat.tres",
]

static var _by_id: Dictionary = {}
static var _all_sorted: Array[ResourceType] = []
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path in PATHS:
		var res: ResourceType = load(path) as ResourceType
		if res == null:
			push_error("ResourceRegistry: impossible de charger %s" % path)
			continue
		_by_id[res.id] = res
	var sorted: Array[ResourceType] = []
	for res in _by_id.values():
		sorted.append(res)
	sorted.sort_custom(func(a, b): return a.display_order < b.display_order)
	_all_sorted = sorted

static func get_type(id: StringName) -> ResourceType:
	_ensure_loaded()
	return _by_id.get(id)

static func all() -> Array[ResourceType]:
	_ensure_loaded()
	return _all_sorted

static func ids() -> Array[StringName]:
	_ensure_loaded()
	var result: Array[StringName] = []
	for res in _all_sorted:
		result.append(res.id)
	return result
