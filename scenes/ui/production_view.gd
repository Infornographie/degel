extends Control
class_name ProductionView
## Vue du panneau de production : tableau 4 colonnes (net, consommé, stock,
## impossible) + ligne séparée pour les activités risquées. Lit le bilan
## déterministe via TurnResolver.compute_flow, se reconstruit sur les signals
## qui peuvent l'affecter.

const COLUMN_GAP: int = 20

var _section: VBoxContainer

func _ready() -> void:
	_build()
	GameState.turn_advanced.connect(_rebuild)
	GameState.resources_changed.connect(_rebuild)
	GameState.survivor_assigned.connect(_rebuild)
	GameState.tile_assignment_changed.connect(_rebuild)
	GameState.building_assignment_changed.connect(_rebuild)
	GameState.construction_started.connect(_rebuild)
	GameState.construction_progressed.connect(_rebuild)
	GameState.construction_completed.connect(_rebuild)
	_rebuild()

func _build() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	var title := Label.new()
	title.text = tr("LABEL_PRODUCTION_TITLE")
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	_section = VBoxContainer.new()
	_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_section)

## Reconstruit le tableau. Signature tolérante pour pouvoir être branchée
## sur les divers signals (turn_advanced(int), resources_changed(Dict), etc).
func _rebuild(_a = null, _b = null, _c = null, _d = null) -> void:
	if _section == null:
		return
	for child in _section.get_children():
		child.queue_free()
	_section.add_child(_make_header())
	var flow: Dictionary = GameState.turn_resolver.compute_flow()
	for type in ResourceRegistry.all():
		var resource_name := String(type.id)
		if not flow.has(resource_name):
			continue
		var f: Dictionary = flow[resource_name]
		var production: float = f["production"]
		var consumption: float = f["consumption"]
		var impossible: float = f["impossible"]
		if production == 0.0 and consumption == 0.0 and impossible == 0.0:
			continue
		_section.add_child(_make_row(type, production, consumption, impossible))
	# Activités risquées
	var risky: Array = GameState.turn_resolver.gather_risky()
	if not risky.is_empty():
		_section.add_child(HSeparator.new())
		var risky_title := Label.new()
		risky_title.text = tr("PROD_RISKY_TITLE")
		risky_title.add_theme_font_size_override("font_size", 10)
		risky_title.modulate = Color(1, 1, 1, 0.7)
		_section.add_child(risky_title)
		for row_data in risky:
			_section.add_child(_make_risky_row(row_data))

func _make_header() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", COLUMN_GAP)
	row.modulate = Color(1, 1, 1, 0.6)
	var spacer := Label.new()
	spacer.text = ""
	spacer.custom_minimum_size = Vector2(40, 0)
	row.add_child(spacer)
	row.add_child(_make_header_label(tr("PROD_HEADER_CONSUMED")))
	row.add_child(_make_header_label(tr("PROD_HEADER_DELTA")))
	row.add_child(_make_header_label(tr("PROD_HEADER_IMPOSSIBLE")))
	return row

func _make_header_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 9)
	label.custom_minimum_size = Vector2(80, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _make_risky_row(row: Dictionary) -> HBoxContainer:
	var container := HBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var activity: Activity = row["activity"]
	var label := Label.new()
	label.text = "%s (%d%%)" % [tr(activity.name_key), int(activity.success_rate * 100)]
	label.add_theme_font_size_override("font_size", 12)
	label.custom_minimum_size = Vector2(140, 0)
	container.add_child(label)
	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 2)
	container.add_child(icons)
	var amount: int = int(row["amount"])
	for i in amount:
		icons.add_child(UiPresentation.resource_icon(activity.produced_resource, UiPresentation.RESOURCE_SPRITE_SIZE))
	return container

func _make_row(type: ResourceType, production: float, consumption: float, impossible: float) -> HBoxContainer:
	var resource_name := String(type.id)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", COLUMN_GAP)
	# Calcul des 3 catégories visibles
	var prod_int: int = int(production)
	var cons_int: int = int(consumption)
	var imp_int: int = int(impossible)
	var covered: int = min(prod_int, cons_int)
	var surplus: int = max(0, prod_int - cons_int)
	var deficit: int = max(0, cons_int - prod_int)
	# Colonne 1 : net chiffré
	var net: float = production - consumption
	var net_label := Label.new()
	net_label.text = "%+d" % int(net)
	net_label.add_theme_font_size_override("font_size", 14)
	net_label.custom_minimum_size = Vector2(40, 0)
	net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(net_label)
	# Colonne 2 : consommé couvert
	row.add_child(_make_icon_column(resource_name, covered, ""))
	# Colonne 3 : surplus OU déficit (stock)
	if surplus > 0:
		row.add_child(_make_icon_column(resource_name, surplus, "surplus"))
	elif deficit > 0 and type.stackable:
		row.add_child(_make_icon_column(resource_name, deficit, "deficit"))
	else:
		row.add_child(_make_empty_column())
	# Colonne 4 : impossible (faute d'inputs) + déficit non-stockable
	var total_impossible: int = imp_int
	if deficit > 0 and not type.stackable:
		total_impossible += deficit
	if total_impossible > 0:
		row.add_child(_make_icon_column(resource_name, total_impossible, "crossed"))
	else:
		row.add_child(_make_empty_column())
	return row

func _make_empty_column() -> Control:
	var ctl := Control.new()
	ctl.custom_minimum_size = Vector2(80, UiPresentation.RESOURCE_SPRITE_SIZE)
	return ctl

func _make_icon_column(resource_name: String, count: int, overlay: String) -> HBoxContainer:
	var col := HBoxContainer.new()
	col.custom_minimum_size = Vector2(80, UiPresentation.RESOURCE_SPRITE_SIZE)
	# Resserrement si trop d'icônes
	var separation: int = 2
	if count > 4:
		var target_width: float = 4.0 * (UiPresentation.RESOURCE_SPRITE_SIZE + 2)
		var needed_width: float = count * UiPresentation.RESOURCE_SPRITE_SIZE
		separation = int(-((needed_width - target_width) / max(1, count - 1)))
	col.add_theme_constant_override("separation", separation)
	for i in count:
		col.add_child(UiPresentation.production_icon(resource_name, overlay))
	return col
