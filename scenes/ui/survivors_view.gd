extends Control
class_name SurvivorsView
## Liste des survivants éveillés : un sprite par survivant (via
## SurvivorSpriteWidget), triés par ordre de réveil chronologique.
##
## Lecture seule, pas d'input. S'abonne directement aux signals qui peuvent
## affecter le contenu ou les tooltips.

var _header: Label
var _list: HBoxContainer

func _ready() -> void:
	_build()
	GameState.turn_advanced.connect(_rebuild)
	GameState.survivor_woken.connect(_rebuild)
	GameState.survivor_assigned.connect(_rebuild)
	GameState.tile_assignment_changed.connect(_rebuild)
	GameState.building_assignment_changed.connect(_rebuild)
	GameState.nightly_deaths.connect(_rebuild)
	_rebuild()

func _build() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	_header = Label.new()
	_header.text = tr("LABEL_AWAKE") % 0
	vbox.add_child(_header)

	_list = HBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	vbox.add_child(_list)

## Signature tolérante pour absorber les divers payloads des signals branchés.
func _rebuild(_a = null, _b = null, _c = null, _d = null) -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	var awake_sorted: Array[Survivor] = []
	for s in GameState.survivors():
		if s.awake:
			awake_sorted.append(s)
	awake_sorted.sort_custom(func(a, b): return a.wake_order < b.wake_order)
	for s in awake_sorted:
		_add_row(s)
	_header.text = tr("LABEL_AWAKE") % awake_sorted.size()
	if awake_sorted.is_empty():
		var empty := Label.new()
		empty.text = tr("LABEL_NOBODY_AWAKE")
		_list.add_child(empty)

func _add_row(s: Survivor) -> void:
	var widget := SurvivorSpriteWidget.new()
	widget.setup(s)
	_list.add_child(widget)
