extends Control
class_name ConstructionZoneView
## Vue du bâtiment Zone de construction : workers assignés, cible courante,
## bouton "Choisir une cible" (ouvre un popup avec les bâtiments constructibles),
## bouton "Affecter un travailleur".
##
## Émet `placement_mode_requested(type_id)` quand le joueur choisit une cible.
## ColonyView écoute ce signal et bascule sa grille en mode placement.

signal placement_mode_requested(type_id: String)

var _building: Building

func setup(b: Building) -> void:
	_building = b
	_rebuild()
	GameState.turn_advanced.connect(_rebuild)
	GameState.building_assignment_changed.connect(_rebuild)
	GameState.construction_started.connect(_rebuild)
	GameState.construction_progressed.connect(_rebuild)
	GameState.construction_completed.connect(_rebuild)

func _rebuild(_a = null, _b = null, _c = null, _d = null) -> void:
	if _building == null:
		return
	for child in get_children():
		child.queue_free()
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)
	vbox.add_child(UiPresentation.slot_title(tr(_building.config.name_key)))

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

	# Cible courante + icônes de ce qui sera consommé ce tour
	if _building.construction_target != "":
		var target: Building = GameState._find_building_by_instance(int(_building.construction_target))
		if target != null:
			var target_label := Label.new()
			target_label.text = tr("LABEL_BUILDING_TARGET") % tr(target.config.name_key)
			target_label.add_theme_font_size_override("font_size", 10)
			target_label.modulate = Color(0.7, 0.7, 0.7)
			target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vbox.add_child(target_label)
			var icons_row := HBoxContainer.new()
			icons_row.add_theme_constant_override("separation", 2)
			icons_row.alignment = BoxContainer.ALIGNMENT_CENTER
			vbox.add_child(icons_row)
			var work: float = 0.0
			for wid in _building.worker_ids:
				var s: Survivor = GameState.roster.get_by_id(wid)
				if s != null and s.awake:
					work += s.work_force
			if work > 0.0:
				var order: Array[String] = target.config.build_order
				if order.is_empty():
					order = target.config.build_cost.keys()
				var work_left: float = work
				for resource_name in order:
					if work_left <= 0.0:
						break
					var needed: float = target.config.build_cost.get(resource_name, 0.0) - target.build_resources_consumed.get(resource_name, 0.0)
					if needed <= 0.0:
						continue
					var to_consume: int = int(min(work_left, needed))
					for i in to_consume:
						icons_row.add_child(UiPresentation.production_icon(resource_name, "crossed"))
					work_left -= to_consume
	else:
		var no_target := Label.new()
		no_target.text = tr("LABEL_NO_TARGET")
		no_target.add_theme_font_size_override("font_size", 10)
		no_target.modulate = Color(0.7, 0.7, 0.7)
		no_target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(no_target)

	# Bouton "Choisir une cible"
	var choose_btn := Button.new()
	choose_btn.text = tr("BTN_CHOOSE_TARGET")
	choose_btn.add_theme_font_size_override("font_size", 10)
	choose_btn.pressed.connect(_on_choose_target_pressed)
	vbox.add_child(choose_btn)

	# Bouton "Affecter un travailleur"
	var assign_btn := Button.new()
	assign_btn.text = tr("BTN_ASSIGN_WORKER")
	assign_btn.add_theme_font_size_override("font_size", 10)
	assign_btn.pressed.connect(func():
		UiPresentation.open_building_popup(self, _building, get_global_mouse_position()))
	vbox.add_child(assign_btn)

func _on_choose_target_pressed() -> void:
	var popup := PopupMenu.new()
	add_child(popup)
	# Option "rien à construire" si une cible est définie
	if _building.construction_target != "":
		popup.add_item(tr("LABEL_CLEAR_TARGET"))
		popup.set_item_metadata(popup.item_count - 1, {"action": "clear_target"})
		popup.add_separator()
	# Lister les bâtiments constructibles disponibles
	for config in GameState.building_registry.constructibles():
		if config.unique:
			var already_exists := false
			for existing in GameState.buildings:
				if existing.config.id == config.id and not existing.config.is_starter:
					already_exists = true
					break
			if already_exists:
				continue
		var cost_parts: Array[String] = []
		for resource_name in config.build_cost:
			cost_parts.append("%d %s" % [int(config.build_cost[resource_name]), UiPresentation.resource(resource_name)])
		var cost_str: String = " (" + ", ".join(cost_parts) + ")" if not cost_parts.is_empty() else ""
		popup.add_item(tr(config.name_key) + cost_str)
		popup.set_item_metadata(popup.item_count - 1, {
			"action": "set_target",
			"target_id": config.id,
		})
	var handler := func(index: int) -> void:
		var meta = popup.get_item_metadata(index)
		if meta == null:
			return
		var action: String = meta.get("action", "")
		if action == "set_target":
			placement_mode_requested.emit(meta["target_id"])
	popup.id_pressed.connect(handler)
	popup.popup_hide.connect(popup.queue_free)
	popup.position = Vector2i(get_global_mouse_position())
	popup.popup()
