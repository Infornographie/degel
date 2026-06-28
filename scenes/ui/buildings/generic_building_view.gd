extends Control
class_name GenericBuildingView
## Vue fallback pour les bâtiments sans vue spécifique : campfire, kitchen,
## tool_workshop, et tous les futurs bâtiments génériques.
##
## Deux états visuels selon le bâtiment :
## - UNDER_CONSTRUCTION : status + icônes des ressources restantes + clic pour
##   le rendre cible active
## - OPERATIONAL : workers assignés + bouton d'affectation + icônes inputs/outputs
##
## Se reconstruit sur les signals qui peuvent affecter l'affichage. setup(b)
## stocke le building et déclenche le premier build.

const ICON_SIZE: int = 16
const IO_ICON_SIZE: int = 14
const COMPRESSION_THRESHOLD: int = 6

var _building: Building

func setup(b: Building) -> void:
	_building = b
	_rebuild()
	GameState.turn_advanced.connect(_rebuild)
	GameState.building_assignment_changed.connect(_rebuild)
	GameState.construction_progressed.connect(_rebuild)
	GameState.construction_started.connect(_rebuild)

func _rebuild(_a = null, _b = null, _c = null, _d = null) -> void:
	if _building == null:
		return
	# Reset modulate (peut avoir été teinté en jaune si cible active)
	modulate = Color.WHITE
	# Vider le contenu précédent
	for child in get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)
	vbox.add_child(UiPresentation.slot_title(tr(_building.config.name_key)))

	if _building.state == Building.State.UNDER_CONSTRUCTION:
		_build_under_construction(vbox)
	else:
		_build_operational(vbox)

func _build_under_construction(vbox: VBoxContainer) -> void:
	var status := Label.new()
	status.text = tr("LABEL_UNDER_CONSTRUCTION")
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 10)
	status.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(status)
	# Icônes des ressources restantes
	var order: Array[String] = _building.config.build_order
	if order.is_empty():
		order = _building.config.build_cost.keys()
	for resource_name in order:
		var needed: float = _building.config.build_cost.get(resource_name, 0.0)
		var consumed: float = _building.build_resources_consumed.get(resource_name, 0.0)
		var remaining: int = int(needed - consumed)
		if remaining <= 0:
			continue
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Resserrement si trop d'icônes
		var separation: int = 2
		if remaining > COMPRESSION_THRESHOLD:
			var target_width: float = COMPRESSION_THRESHOLD * (ICON_SIZE + 2)
			var needed_width: float = remaining * ICON_SIZE
			var overlap: float = (needed_width - target_width) / max(1, remaining - 1)
			separation = int(-overlap)
		row.add_theme_constant_override("separation", separation)
		for i in remaining:
			row.add_child(UiPresentation.resource_icon(resource_name, ICON_SIZE))
		vbox.add_child(row)
	# Mise en évidence si c'est la cible active
	var zone: Building = GameState._find_building("construction_zone")
	var is_active: bool = (zone != null and zone.construction_target == str(_building.instance_id))
	if is_active:
		modulate = Color(1.2, 1.2, 0.9)  # léger jaune pour l'active
	# Clic = définir comme cible active OU annuler si déjà actif
	var bid := _building.instance_id
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			GameState.set_active_construction(bid))

func _build_operational(vbox: VBoxContainer) -> void:
	# Workers assignés
	var workers_row := HBoxContainer.new()
	workers_row.add_theme_constant_override("separation", 4)
	workers_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(workers_row)
	if _building.worker_ids.is_empty():
		var info := Label.new()
		info.text = tr("LABEL_NO_WORKER")
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.add_theme_font_size_override("font_size", 10)
		info.modulate = Color(0.7, 0.7, 0.7)
		vbox.add_child(info)
	else:
		for wid in _building.worker_ids:
			var s: Survivor = GameState.roster.get_by_id(wid)
			if s != null:
				workers_row.add_child(UiPresentation.assigned_worker_sprite(s))
	# Bouton pour ouvrir le popup d'affectation
	var assign_btn := Button.new()
	assign_btn.text = tr("BTN_ASSIGN_WORKER")
	assign_btn.add_theme_font_size_override("font_size", 10)
	assign_btn.pressed.connect(func():
		UiPresentation.open_building_popup(self, _building, get_global_mouse_position()))
	vbox.add_child(assign_btn)
	# Slider d'intensité si le bâtiment en a un
	if _building.config.max_intensity > 1:
		var intensity_box := VBoxContainer.new()
		intensity_box.add_theme_constant_override("separation", 2)
		vbox.add_child(intensity_box)
		var intensity_label := Label.new()
		intensity_label.text = tr("LABEL_INTENSITY") + ": %d / %d" % [
			_building.current_intensity, _building.config.max_intensity]
		intensity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		intensity_label.add_theme_font_size_override("font_size", 10)
		intensity_box.add_child(intensity_label)
		var slider := HSlider.new()
		slider.min_value = 1
		slider.max_value = _building.config.max_intensity
		slider.step = 1
		slider.value = _building.current_intensity
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bid := _building.instance_id
		slider.value_changed.connect(func(v: float):
			var b := GameState._find_building_by_instance(bid)
			if b != null:
				b.current_intensity = int(v)
				GameState.building_assignment_changed.emit())
		intensity_box.add_child(slider)
	# Inputs / outputs
	if not _building.config.inputs.is_empty() or not _building.config.outputs.is_empty():
		var io_row := HBoxContainer.new()
		io_row.add_theme_constant_override("separation", 2)
		io_row.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(io_row)
		var intensity: int = _building.current_intensity
		for resource_name in _building.config.inputs:
			var amt: int = int(_building.config.inputs[resource_name] * intensity)
			for i in amt:
				io_row.add_child(UiPresentation.resource_icon(resource_name, IO_ICON_SIZE))
		if not _building.config.inputs.is_empty() and not _building.config.outputs.is_empty():
			var arrow := Label.new()
			arrow.text = "→"
			arrow.add_theme_font_size_override("font_size", 12)
			io_row.add_child(arrow)
		for resource_name in _building.config.outputs:
			var amt: int = int(_building.config.outputs[resource_name] * intensity)
			for i in amt:
				io_row.add_child(UiPresentation.resource_icon(resource_name, IO_ICON_SIZE))
