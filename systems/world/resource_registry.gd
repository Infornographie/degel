extends RefCounted
class_name ResourceRegistry
## Registry des ResourceType. Charge depuis le manifest central GameRegistry.

static var _by_id: Dictionary = {}
static var _all_sorted: Array[ResourceType] = []
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var manifest: GameRegistry = GameRegistry.load_default()
	if manifest == null:
		push_error("ResourceRegistry: game_registry.tres introuvable")
		return
	for res in manifest.resource_types:
		if res == null or res.id == StringName(""):
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
