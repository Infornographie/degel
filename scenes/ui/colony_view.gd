extends Control
class_name ColonyView
## Grille 4×3 des bâtiments de la colonie : starters (computer, cryo, synth,
## zone de construction) à des emplacements fixes, autres bâtiments selon leur
## slot_index, slots vides ailleurs.
##
## Le rendu d'un slot occupé est délégué à MainUi via _render_slot_fn (le
## temps que les `_make_*_slot` deviennent leurs propres vues — séance 2).
## ColonyView reste responsable du grid layout, des slots vides, et du mode
## placement (le joueur a choisi un type à construire, attend qu'on clique
## un slot libre).
##
## Note layout : le nombre de slots et la disposition des starters sont
## hardcodés ici. À terme, déplacer dans une Resource configurable (dette).

const COLONY_SLOTS: int = 12
const BUNKER_BUILDING_IDS: Array[String] = ["computer", "cryo_room", "synthesizer"]

# Emplacements fixes des starters dans la grille (4 colonnes × 3 lignes)
const STARTER_SLOTS := {
	"computer": 4,
	"construction_zone": 5,
	"cryo_room": 8,
	"synthesizer": 9,
}

var _grid: GridContainer
var _placement_mode_type_id: String = ""
var _render_slot_fn: Callable

func _ready() -> void:
	_build()
	GameState.turn_advanced.connect(_rebuild)
	GameState.resources_changed.connect(_rebuild)
	GameState.survivor_woken.connect(_rebuild)
	GameState.survivor_assigned.connect(_rebuild)
	GameState.candidates_changed.connect(_rebuild)
	GameState.tile_assignment_changed.connect(_rebuild)
	GameState.building_assignment_changed.connect(_rebuild)
	GameState.construction_started.connect(_rebuild)
	GameState.construction_progressed.connect(_rebuild)
	GameState.construction_completed.connect(_rebuild)
	_rebuild()

## Branchement de la fonction de rendu des slots occupés. Appelée par MainUi
## à l'instanciation, avant que les signaux ne soient émis.
func set_render_slot_fn(fn: Callable) -> void:
	_render_slot_fn = fn

func _build() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	var title := Label.new()
	title.text = tr("LABEL_COLONY_TITLE")
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_grid)

## Signature tolérante pour absorber les divers payloads des signals branchés.
func _rebuild(_a = null, _b = null, _c = null, _d = null) -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	# Map slot_index → Building (starters fixes + autres bâtiments selon slot_index)
	var slot_to_building := {}
	for starter_id in STARTER_SLOTS:
		var starter := _find_starter(starter_id)
		if starter != null:
			starter.slot_index = STARTER_SLOTS[starter_id]
			slot_to_building[STARTER_SLOTS[starter_id]] = starter
	for b in GameState.buildings:
		if not b.config.is_starter and b.slot_index >= 0:
			slot_to_building[b.slot_index] = b
	# Render
	for i in COLONY_SLOTS:
		if slot_to_building.has(i):
			if _render_slot_fn.is_valid():
				var node: Control = _render_slot_fn.call(slot_to_building[i])
				_grid.add_child(node)
		else:
			_grid.add_child(_make_empty_slot(i))

## Active le mode placement : les slots vides deviennent cliquables pour
## démarrer la construction du type donné.
func enter_placement_mode(type_id: String) -> void:
	_placement_mode_type_id = type_id
	_rebuild()

func _find_starter(id: String) -> Building:
	for b in GameState.buildings:
		if b.config.id == id:
			return b
	return null

func _make_empty_slot(slot_idx: int) -> PanelContainer:
	var panel := UiPresentation.slot_panel(false)
	panel.modulate = Color(1, 1, 1, 0.3)
	var label := Label.new()
	if _placement_mode_type_id != "":
		label.text = tr("LABEL_PLACE_HERE")
		panel.modulate = Color(0.7, 1.0, 0.7, 0.6)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var type_id := _placement_mode_type_id
		panel.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				GameState.start_construction(type_id, slot_idx)
				_placement_mode_type_id = ""
				_rebuild())
	else:
		label.text = tr("LABEL_EMPTY_SLOT")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel
