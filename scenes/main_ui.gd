extends Control
## UI placeholder — 4c. Carte interactive, jobs territorialisés.


const BUNKER_BUILDING_IDS: Array[String] = ["computer", "cryo_room", "synthesizer"]

var _map_container: Control
var _tile_popup: PopupMenu
var _popup_tile_key: String = ""
# id dans le sous-menu (encodé : survivor_id * 100 + job_id) → (survivor_id, job_id)
var _popup_submenus: Array[PopupMenu] = []
var _colony_grid: GridContainer
const COLONY_SLOTS: int = 12
var _placement_mode_type_id: String = ""  # si non vide, on est en mode placement d'un type donné


func _ready() -> void:
	_build_ui()
	GameState.turn_advanced.connect(_refresh)
	GameState.resources_changed.connect(_refresh)
	GameState.survivor_woken.connect(_refresh)
	GameState.survivor_assigned.connect(_refresh)
	GameState.candidates_changed.connect(_refresh)
	GameState.tile_assignment_changed.connect(_refresh)
	GameState.run_ended.connect(_on_run_ended)
	GameState.nightly_deaths.connect(_on_nightly_deaths)
	GameState.building_assignment_changed.connect(_refresh)
	GameState.construction_started.connect(_refresh)
	GameState.construction_progressed.connect(_refresh)
	GameState.construction_completed.connect(_refresh)
	# On cache l'UI le temps que le layout se calcule
	modulate.a = 0.0
	await get_tree().process_frame
	_refresh()
	modulate.a = 1.0

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 8)
	add_child(main_vbox)

	# Rang du haut : settlement à gauche, map+prod à droite
	var top_row := HBoxContainer.new()
	top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_row.size_flags_stretch_ratio = 0.70
	top_row.add_theme_constant_override("separation", 12)
	main_vbox.add_child(top_row)

	var settlement_panel := VBoxContainer.new()
	settlement_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settlement_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settlement_panel.size_flags_stretch_ratio = 0.65
	top_row.add_child(settlement_panel)
	_build_colony_panel(settlement_panel)

	var right_column := VBoxContainer.new()
	right_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_column.size_flags_stretch_ratio = 0.35
	right_column.add_theme_constant_override("separation", 8)
	top_row.add_child(right_column)

	var map_panel := VBoxContainer.new()
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_stretch_ratio = 0.55
	right_column.add_child(map_panel)
	_build_map_panel(map_panel)

	var production_view: ProductionView = preload("res://scenes/ui/production_view.tscn").instantiate()
	production_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	production_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	production_view.size_flags_stretch_ratio = 0.45
	right_column.add_child(production_view)

	# Rang du milieu : infos + awakened + buttons
	var middle_row := HBoxContainer.new()
	middle_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle_row.size_flags_stretch_ratio = 0.18
	middle_row.add_theme_constant_override("separation", 16)
	main_vbox.add_child(middle_row)

	var infos_section: InfosSection = preload("res://scenes/ui/infos_section.tscn").instantiate()
	infos_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	infos_section.size_flags_stretch_ratio = 0.20
	infos_section.clip_contents = true
	middle_row.add_child(infos_section)

	# Awakened : scrollable et clippé pour ne pas pousser les autres
	var awake_scroll := ScrollContainer.new()
	awake_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	awake_scroll.size_flags_stretch_ratio = 0.55
	awake_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	middle_row.add_child(awake_scroll)
	var awake_panel := VBoxContainer.new()
	awake_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	awake_scroll.add_child(awake_panel)
	var survivors_view: SurvivorsView = preload("res://scenes/ui/survivors_view.tscn").instantiate()
	awake_panel.add_child(survivors_view)

	var buttons_panel := VBoxContainer.new()
	buttons_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons_panel.size_flags_stretch_ratio = 0.25
	middle_row.add_child(buttons_panel)
	var buttons_section: ButtonsSection = preload("res://scenes/ui/buttons_section.tscn").instantiate()
	buttons_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	buttons_section.language_toggled.connect(_rebuild_ui)
	buttons_panel.add_child(buttons_section)

	# Rang du bas : resources bar
	var resources_row := HBoxContainer.new()
	resources_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resources_row.custom_minimum_size = Vector2(0, 50)
	main_vbox.add_child(resources_row)
	var resources_bar: ResourcesBar = preload("res://scenes/ui/resources_bar.tscn").instantiate()
	resources_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resources_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	resources_row.add_child(resources_bar)

func _rebuild_ui() -> void:
	for child in get_children():
		child.queue_free()
	modulate.a = 0.0
	_build_ui()
	await get_tree().process_frame
	_refresh()
	modulate.a = 1.0

func _build_map_panel(parent: VBoxContainer) -> void:
	var title := _add_label(parent, tr("LABEL_MAP_TITLE"))
	title.add_theme_font_size_override("font_size", 16)
	_map_container = Control.new()
	_map_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_container.custom_minimum_size = Vector2(320, 320)
	parent.add_child(_map_container)
	parent.add_child(HSeparator.new())
	_add_label(parent, tr("LABEL_LEGEND_1"))
	_add_label(parent, tr("LABEL_LEGEND_2"))

func _build_colony_panel(parent: VBoxContainer) -> void:
	var title := _add_label(parent, tr("LABEL_COLONY_TITLE"))
	title.add_theme_font_size_override("font_size", 16)
	_colony_grid = GridContainer.new()
	_colony_grid.columns = 4
	_colony_grid.add_theme_constant_override("h_separation", 8)
	_colony_grid.add_theme_constant_override("v_separation", 8)
	_colony_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_colony_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(_colony_grid)

func _draw_colony() -> void:
	if _colony_grid == null:
		return
	for child in _colony_grid.get_children():
		_colony_grid.remove_child(child)  # synchrone
		child.queue_free()
	# Map slot_index → Building
	var slot_to_building := {}
	var computer: Building = _find_starter("computer")
	var synth: Building = _find_starter("synthesizer")
	var cryo: Building = _find_starter("cryo_room")
	var zone: Building = _find_starter("construction_zone")
	if computer != null:
		computer.slot_index = 4
		slot_to_building[4] = computer
	if zone != null:
		zone.slot_index = 5
		slot_to_building[5] = zone
	if cryo != null:
		cryo.slot_index = 8
		slot_to_building[8] = cryo
	if synth != null:
		synth.slot_index = 9
		slot_to_building[9] = synth
	for b in GameState.buildings:
		if not b.config.is_starter and b.slot_index >= 0:
			slot_to_building[b.slot_index] = b
	for i in COLONY_SLOTS:
		if slot_to_building.has(i):
			_render_building_in_slot(slot_to_building[i])
		else:
			_add_empty_slot(i)

func _render_building_in_slot(b: Building) -> void:
	match b.config.id:
		"computer": _add_computer_slot(b)
		"synthesizer": _add_synth_slot(b)
		"cryo_room": _add_cryo_slot(b)
		"construction_zone": _add_construction_zone_slot(b)
		_: _add_generic_building_slot(b)

func _add_generic_building_slot(b: Building) -> void:
	var panel := _new_slot_panel(false)
	_colony_grid.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	vbox.add_child(_slot_title(tr(b.config.name_key)))
	if b.state == Building.State.UNDER_CONSTRUCTION:
		# Affichage progression
		var status := Label.new()
		status.text = tr("LABEL_UNDER_CONSTRUCTION")
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status.add_theme_font_size_override("font_size", 10)
		status.modulate = Color(0.7, 0.7, 0.7)
		vbox.add_child(status)
		# Icônes des ressources restantes — une ligne par ressource, resserrement si trop
		var order: Array[String] = b.config.build_order
		if order.is_empty():
			order = b.config.build_cost.keys()
		for resource_name in order:
			var needed: float = b.config.build_cost.get(resource_name, 0.0)
			var consumed: float = b.build_resources_consumed.get(resource_name, 0.0)
			var remaining: int = int(needed - consumed)
			if remaining <= 0:
				continue
			var row := HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# Resserrement
			var separation: int = 2
			if remaining > 6:
				var icon_size: int = 16
				var target_width: float = 6.0 * (icon_size + 2)
				var needed_width: float = remaining * icon_size
				var overlap: float = (needed_width - target_width) / max(1, remaining - 1)
				separation = int(-overlap)
			row.add_theme_constant_override("separation", separation)
			for i in remaining:
				row.add_child(UiPresentation.resource_icon(resource_name, 16))
			vbox.add_child(row)
		# Indique si c'est la cible active
		var zone: Building = GameState._find_building("construction_zone")
		var is_active: bool = (zone != null and zone.construction_target == str(b.instance_id))
		# Clic = définir comme cible active OU annuler si déjà actif
		var bid := b.instance_id
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if is_active:
			panel.modulate = Color(1.2, 1.2, 0.9)  # léger jaune pour l'active
		panel.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				GameState.set_active_construction(bid))
	else:
		# Bâtiment opérationnel
		# Affichage des colons assignés
		var workers_row := HBoxContainer.new()
		workers_row.add_theme_constant_override("separation", 4)
		workers_row.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(workers_row)
		if b.worker_ids.is_empty():
			var info := Label.new()
			info.text = tr("LABEL_NO_WORKER")
			info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			info.add_theme_font_size_override("font_size", 10)
			info.modulate = Color(0.7, 0.7, 0.7)
			vbox.add_child(info)
		else:
			for wid in b.worker_ids:
				var s: Survivor = GameState.roster.get_by_id(wid)
				if s != null:
					workers_row.add_child(_make_assigned_worker_sprite(s))
		# Bouton pour ouvrir le popup d'affectation
		var assign_btn := Button.new()
		assign_btn.text = tr("BTN_ASSIGN_WORKER")
		assign_btn.add_theme_font_size_override("font_size", 10)
		assign_btn.pressed.connect(func():
			_open_building_popup(b, get_global_mouse_position()))
		vbox.add_child(assign_btn)
		# Affichage des inputs/outputs en icônes
		if not b.config.inputs.is_empty() or not b.config.outputs.is_empty():
			var io_row := HBoxContainer.new()
			io_row.add_theme_constant_override("separation", 2)
			io_row.alignment = BoxContainer.ALIGNMENT_CENTER
			vbox.add_child(io_row)
			# Inputs
			for resource_name in b.config.inputs:
				var amt: int = int(b.config.inputs[resource_name])
				for i in amt:
					var icon := UiPresentation.resource_icon(resource_name, 14)
					io_row.add_child(icon)
			# Flèche séparatrice si on a les deux
			if not b.config.inputs.is_empty() and not b.config.outputs.is_empty():
				var arrow := Label.new()
				arrow.text = "→"
				arrow.add_theme_font_size_override("font_size", 12)
				io_row.add_child(arrow)
			# Outputs
			for resource_name in b.config.outputs:
				var amt: int = int(b.config.outputs[resource_name])
				for i in amt:
					var icon := UiPresentation.resource_icon(resource_name, 14)
					io_row.add_child(icon)

func _find_starter(id: String) -> Building:
	for b in GameState.buildings:
		if b.config.id == id:
			return b
	return null

func _add_computer_slot(b: Building) -> void:
	var panel := _new_slot_panel(true)
	_colony_grid.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	vbox.add_child(_slot_title(tr(b.config.name_key)))
	var btn := Button.new()
	btn.text = tr("BTN_COMPUTER_INTERACT")
	btn.pressed.connect(_on_computer_pressed)
	vbox.add_child(btn)

func _add_synth_slot(b: Building) -> void:
	var panel := _new_slot_panel(true)
	_colony_grid.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	vbox.add_child(_slot_title(tr(b.config.name_key)))
	var checkbox := CheckBox.new()
	checkbox.text = tr("LABEL_SYNTH_RUNNING")
	checkbox.set_pressed_no_signal(b.active)
	var bid := b.instance_id
	checkbox.toggled.connect(func(pressed: bool):
		var building := GameState._find_building_by_instance(bid)
		if building != null:
			building.active = pressed
			_refresh())
	vbox.add_child(checkbox)
	var info := Label.new()
	info.text = tr("LABEL_SYNTH_INFO")
	info.add_theme_font_size_override("font_size", 9)
	info.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(info)

func _add_cryo_slot(_b: Building) -> void:
	var panel := _new_slot_panel(true)
	_colony_grid.add_child(panel)
	var view: CryoView = preload("res://scenes/ui/buildings/cryo_view.tscn").instantiate()
	panel.add_child(view)

func _new_slot_panel(is_bunker: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(140, 100)
	var style := StyleBoxFlat.new()
	if is_bunker:
		style.bg_color = Color("#2a2e3a")  # bleu-gris froid : bunker, technologique
	else:
		style.bg_color = Color("#3a322a")  # brun chaud : colonie, terre
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _slot_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	return label

func _add_empty_slot(slot_idx: int) -> void:
	var panel := _new_slot_panel(false)
	panel.modulate = Color(1, 1, 1, 0.3)
	_colony_grid.add_child(panel)
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
				_refresh())
	else:
		label.text = tr("LABEL_EMPTY_SLOT")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)

func _add_label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label

# --- Map ---

func _draw_map() -> void:
	for child in _map_container.get_children():
		_map_container.remove_child(child)
		child.queue_free()
	var origin := _map_container.size * 0.5
	if origin.x == 0:
		origin = Vector2(160, 160)
	# Première passe : les hexagones de fond
	for tile in GameState.hex_map.tiles.values():
		var pixel := _hex_to_pixel(tile.q, tile.r) + origin
		_draw_hex_background(tile, pixel)
	# Deuxième passe : les workers et leurs productions, par-dessus
	for tile in GameState.hex_map.tiles.values():
		var pixel := _hex_to_pixel(tile.q, tile.r) + origin
		if tile.worker_id != -1:
			_render_tile_worker(tile, pixel)

func _draw_hex_background(tile: HexTile, center: Vector2) -> void:
	var hex := Polygon2D.new()
	hex.polygon = _hex_polygon_points()
	hex.color = TILE_COLORS.get(tile.type, Color.GRAY)
	hex.position = center
	var click_area := Control.new()
	var bbox: float = HEX_RADIUS * 2.0
	click_area.size = Vector2(bbox, bbox)
	click_area.position = center - Vector2(HEX_RADIUS, HEX_RADIUS)
	click_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_container.add_child(hex)
	_map_container.add_child(click_area)
	if tile.type != HexTile.Type.BUNKER:
		var tkey := tile.key()
		click_area.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed:
				if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
					_open_tile_popup(tkey, event.global_position))
	if tile.worker_id == -1:
		var label := Label.new()
		label.text = tr(TILE_LABEL_KEYS.get(tile.type, "")).substr(0, 1)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size = Vector2(bbox, bbox)
		label.position = center - Vector2(HEX_RADIUS, HEX_RADIUS)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
		_map_container.add_child(label)

func _hex_to_pixel(q: int, r: int) -> Vector2:
	# Pointy-top hex layout
	var x: float = HEX_RADIUS * sqrt(3.0) * (q + r / 2.0)
	var y: float = HEX_RADIUS * 1.5 * r
	return Vector2(x, y)

const HEX_RADIUS: float = 36.0  # taille = rayon du hex (du centre au sommet)

const TILE_COLORS := {
	HexTile.Type.BUNKER: Color("#2c2c2c"),
	HexTile.Type.PLAINS: Color("#d4c47a"),    # jaune paille
	HexTile.Type.FOREST: Color("#3a6b35"),
	HexTile.Type.MOUNTAIN: Color("#7a5a3a"),
}

const TILE_LABEL_KEYS := {
	HexTile.Type.BUNKER: "TILE_TYPE_SETTLEMENT",
	HexTile.Type.PLAINS: "TILE_TYPE_PLAINS",
	HexTile.Type.FOREST: "TILE_TYPE_FOREST",
	HexTile.Type.MOUNTAIN: "TILE_TYPE_MOUNTAIN",
}

func _hex_polygon_points() -> PackedVector2Array:
	# 6 sommets d'un hexagone pointy-top, centré sur (0,0)
	var points := PackedVector2Array()
	for i in 6:
		var angle: float = deg_to_rad(60.0 * i - 30.0)
		points.append(Vector2(cos(angle), sin(angle)) * HEX_RADIUS)
	return points

const TILE_PROD_ICON_SIZE: int = 14

func _render_tile_worker(tile: HexTile, center: Vector2) -> void:
	var s: Survivor = GameState.roster.get_by_id(tile.worker_id)
	if s == null:
		return
	# Détecte si activité risquée
	var is_risky := false
	var risky_amount: int = 0
	var risky_resource: String = ""
	var risky_rate: float = 1.0
	if s.activity_id != "":
		var activity: Activity = GameState.activity_registry.get_activity(s.activity_id)
		if activity != null and activity.success_rate < 1.0:
			is_risky = true
			risky_amount = int(tile.yields.get(s.activity_id, 0.0))
			risky_resource = activity.produced_resource
			risky_rate = activity.success_rate
	var out: Dictionary = GameState.get_survivor_output(s)
	# Icônes de production EN FOND
	if is_risky and risky_amount > 0:
		# Calcule la séparation
		var total: int = risky_amount
		var separation: int = 0
		if total > 3:
			var icon_size: int = TILE_PROD_ICON_SIZE
			var target_width: float = 3.0 * icon_size
			var needed_width: float = total * icon_size
			separation = int(-((needed_width - target_width) / max(1, total - 1)))
		var icons_row := HBoxContainer.new()
		icons_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icons_row.add_theme_constant_override("separation", separation)
		for i in risky_amount:
			icons_row.add_child(UiPresentation.resource_icon(risky_resource, TILE_PROD_ICON_SIZE))
		var pct := Label.new()
		pct.text = " %d%%" % int(risky_rate * 100)
		pct.add_theme_font_size_override("font_size", 9)
		pct.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		pct.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icons_row.add_child(pct)
		# Calcule la largeur effective et centre manuellement
		var effective_icon_width: int = TILE_PROD_ICON_SIZE + separation
		var total_width: float = risky_amount * effective_icon_width + 20  # +20 pour le label %
		icons_row.position = center - Vector2(total_width * 0.5, HEX_RADIUS * 0.7)
		_map_container.add_child(icons_row)
	elif not out.is_empty():
		var icons_row := HBoxContainer.new()
		icons_row.alignment = BoxContainer.ALIGNMENT_CENTER
		icons_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var total: int = 0
		for r in out:
			total += int(out[r])
		var separation: int = 0
		if total > 3:
			var icon_size: int = TILE_PROD_ICON_SIZE
			var target_width: float = 3.0 * (icon_size)
			var needed_width: float = total * icon_size
			separation = int(-((needed_width - target_width) / max(1, total - 1)))
		icons_row.add_theme_constant_override("separation", separation)
		for resource_name in out:
			var amount: int = int(out[resource_name])
			for i in amount:
				var icon := UiPresentation.resource_icon(resource_name, TILE_PROD_ICON_SIZE)
				icons_row.add_child(icon)
		# Positionne le row centré sur la tuile, légèrement décalé vers le bas
		icons_row.size = Vector2(HEX_RADIUS * 2.0, TILE_PROD_ICON_SIZE)
		icons_row.position = center - Vector2(HEX_RADIUS, HEX_RADIUS * 0.7)
		_map_container.add_child(icons_row)
	# Sprite du worker PAR-DESSUS, centré
	var sprite := TextureRect.new()
	sprite.texture = load(UiPresentation.SURVIVOR_SPRITE_PATH % s.sprite_variant)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex_size: Vector2 = (sprite.texture as Texture2D).get_size()
	var sprite_size: Vector2 = tex_size * 3
	sprite.size = sprite_size
	sprite.position = center - sprite_size * 0.5 + Vector2(0, HEX_RADIUS * 0.15)
	_map_container.add_child(sprite)

func _on_tile_clicked(event: InputEvent, tile_key: String) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			_open_tile_popup(tile_key, event.global_position)

func _open_tile_popup(tile_key: String, popup_position: Vector2) -> void:
	_popup_tile_key = tile_key
	var tile: HexTile = GameState.hex_map.get_tile_by_key(tile_key)
	if tile == null:
		return

	# Nettoyage de l'ancien popup et de ses sous-menus
	if _tile_popup != null:
		_tile_popup.queue_free()
	for sub in _popup_submenus:
		if sub != null:
			sub.queue_free()
	_popup_submenus.clear()

	_tile_popup = PopupMenu.new()
	add_child(_tile_popup)

	# Option Clear
	if tile.worker_id != -1:
		_tile_popup.add_item(tr("LABEL_CLEAR_TILE"))
		_tile_popup.set_item_metadata(_tile_popup.item_count - 1, {"action": "clear"})
		_tile_popup.add_separator()

	# Pour chaque éveillé : un sous-menu avec les jobs et leurs rendements sur cette tuile
	var any_available := false
	for s in GameState.awake_survivors():
		var sub := PopupMenu.new()
		sub.name = "sub_" + str(s.id)
		_tile_popup.add_child(sub)
		_popup_submenus.append(sub)

		for activity in GameState.activity_registry.available_for_tile(tile.type):
			var yield_val: float = tile.yields.get(activity.id, 0.0)
			# On ne propose que les activités qui produisent quelque chose sur cette tuile.
			# (Forester n'a pas de yield, mais on le proposera explicitement — voir plus bas.)
			var label_text: String
			if activity.success_rate < 1.0:
				label_text = "%s  (+%.0f, %d%%)" % [tr(activity.name_key), yield_val, int(activity.success_rate * 100)]
			else:
				label_text = "%s  (+%.0f)" % [tr(activity.name_key), yield_val]
			sub.add_item(label_text)
			sub.set_item_metadata(sub.item_count - 1, {"survivor_id": s.id, "activity_id": activity.id})

		sub.id_pressed.connect(_on_submenu_selected.bind(sub))

		# Indication d'emplacement courant du colon
		var location_hint := ""
		if s.tile_key != "" and s.tile_key != tile_key:
			var current_tile: HexTile = GameState.hex_map.get_tile_by_key(s.tile_key)
			if current_tile != null:
				location_hint = "  ← " + UiPresentation.activity(s) + " @ " + UiPresentation.tile_label(s.tile_key)
		elif s.building_id != "":
			var b: Building = GameState._find_building_by_type(s.building_id)
			if b != null:
				location_hint = "  ← " + UiPresentation.activity_for_building(b.config.id) + " @ " + tr(b.config.name_key)
		elif s.tile_key == tile_key:
			location_hint = "  " + tr("LABEL_HERE")
		else:
			location_hint = "  (" + tr("LABEL_IDLE") + ")"
		_tile_popup.add_submenu_item("%s (%s)%s" % [s.name, tr(s.profession), location_hint], sub.name)
		any_available = true

	if not any_available and tile.worker_id == -1:
		_tile_popup.add_item(tr("LABEL_NO_WORKER"))
		_tile_popup.set_item_disabled(_tile_popup.item_count - 1, true)

	_tile_popup.id_pressed.connect(_on_main_popup_selected)
	_tile_popup.position = Vector2i(popup_position)
	_tile_popup.popup()

func _on_main_popup_selected(index: int) -> void:
	var meta = _tile_popup.get_item_metadata(index)
	if meta == null:
		return
	if meta.has("action") and meta["action"] == "clear":
		var tile: HexTile = GameState.hex_map.get_tile_by_key(_popup_tile_key)
		if tile != null and tile.worker_id != -1:
			GameState.unassign_from_tile(tile.worker_id)
	_popup_tile_key = ""

func _on_submenu_selected(index: int, sub: PopupMenu) -> void:
	var meta = sub.get_item_metadata(index)
	if meta == null:
		return
	var survivor_id: int = meta["survivor_id"]
	var act_id: String = meta["activity_id"]
	GameState.assign_activity(survivor_id, act_id)
	GameState.assign_to_tile(survivor_id, _popup_tile_key)
	_popup_tile_key = ""

# --- Refresh ---

func _refresh(_a = null, _b = null, _c = null, _d = null) -> void:
	_draw_map()
	_draw_colony()

func _on_run_ended(_cause: GameState.EndCause) -> void:
	var score = GameState.compute_score()
	var message := tr("POPUP_FINAL_SCORE") % [
		score.survivors_saved, score.survivors_total]
	UiPresentation.show_popup(self, tr("POPUP_RUN_ENDED"), message)

func _on_synth_toggled(pressed: bool) -> void:
	GameState.set_synth(pressed)
	_refresh()

func _on_nightly_deaths(events: Array) -> void:
	if events.is_empty():
		return
	var lines: Array[String] = []
	for ev in events:
		lines.append(ev.format())
	UiPresentation.show_popup(self, tr("NEWS_TITLE"), tr("NEWS_INTRO") + "\n\n" + "\n".join(lines))

func _on_computer_pressed() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = tr("POPUP_COMPUTER_TITLE")
	add_child(dialog)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	dialog.add_child(vbox)
	# Recherche ciblée
	var search_row := HBoxContainer.new()
	vbox.add_child(search_row)
	search_row.add_child(_make_label(tr("LABEL_SEARCH_FOR")))
	var selector := OptionButton.new()
	for prof in GameState.roster.all_professions():
		selector.add_item(tr(prof))
		selector.set_item_metadata(selector.item_count - 1, prof)
	search_row.add_child(selector)
	var search_btn := Button.new()
	search_btn.text = tr("BTN_SEARCH") % GameState.config.wake_cost_targeted
	search_btn.disabled = not GameState.can_targeted_wake()
	search_btn.pressed.connect(func():
		var idx := selector.selected
		if idx < 0: return
		var profession: String = selector.get_item_metadata(idx)
		GameState.targeted_wake(profession)
		dialog.queue_free())
	search_row.add_child(search_btn)
	# Bouton "discuter" en placeholder
	var chat_btn := Button.new()
	chat_btn.text = tr("BTN_COMPUTER_CHAT")
	chat_btn.disabled = true
	vbox.add_child(chat_btn)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)

func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

func _add_construction_zone_slot(b: Building) -> void:
	var panel := _new_slot_panel(false)
	_colony_grid.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	vbox.add_child(_slot_title(tr(b.config.name_key)))
	# Affichage des colons assignés
	var workers_row := HBoxContainer.new()
	workers_row.add_theme_constant_override("separation", 4)
	workers_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(workers_row)
	if b.worker_ids.is_empty():
		var info := Label.new()
		info.text = tr("LABEL_NO_WORKER")
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.add_theme_font_size_override("font_size", 10)
		info.modulate = Color(0.7, 0.7, 0.7)
		vbox.add_child(info)
	else:
		for wid in b.worker_ids:
			var s: Survivor = GameState.roster.get_by_id(wid)
			if s != null:
				workers_row.add_child(_make_assigned_worker_sprite(s))
	# Label de la cible courante
	if b.construction_target != "":
		var target: Building = GameState._find_building_by_instance(int(b.construction_target))
		if target != null:
			var target_label := Label.new()
			target_label.text = tr("LABEL_BUILDING_TARGET") % tr(target.config.name_key)
			target_label.add_theme_font_size_override("font_size", 10)
			target_label.modulate = Color(0.7, 0.7, 0.7)
			target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vbox.add_child(target_label)
			# Icônes de ce qui sera consommé ce tour
			var icons_row := HBoxContainer.new()
			icons_row.add_theme_constant_override("separation", 2)
			icons_row.alignment = BoxContainer.ALIGNMENT_CENTER
			vbox.add_child(icons_row)
			var work: float = 0.0
			for wid in b.worker_ids:
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
	choose_btn.pressed.connect(_on_construction_target_pressed.bind(b))
	vbox.add_child(choose_btn)
	# Bouton "Affecter un travailleur"
	var assign_btn := Button.new()
	assign_btn.text = tr("BTN_ASSIGN_WORKER")
	assign_btn.add_theme_font_size_override("font_size", 10)
	assign_btn.pressed.connect(func():
		_open_building_popup(b, get_global_mouse_position()))
	vbox.add_child(assign_btn)

func _on_construction_target_pressed(b: Building) -> void:
	# On ouvre un popup avec les bâtiments constructibles
	if _tile_popup != null:
		_tile_popup.queue_free()
	_tile_popup = PopupMenu.new()
	add_child(_tile_popup)
	# Option "rien à construire" si une cible est définie
	if b.construction_target != "":
		_tile_popup.add_item(tr("LABEL_CLEAR_TARGET"))
		_tile_popup.set_item_metadata(_tile_popup.item_count - 1, {"action": "clear_target"})
		_tile_popup.add_separator()
	for config in GameState.building_registry.constructibles():
		# Si unique, exclure ceux déjà construits ou en construction
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
		_tile_popup.add_item(tr(config.name_key) + cost_str)
		_tile_popup.set_item_metadata(_tile_popup.item_count - 1, {
			"action": "set_target",
			"target_id": config.id,
		})
	_tile_popup.id_pressed.connect(_on_construction_target_selected)
	# Positionne le popup à la souris
	_tile_popup.position = Vector2i(get_global_mouse_position())
	_tile_popup.popup()

func _on_construction_target_selected(index: int) -> void:
	var meta = _tile_popup.get_item_metadata(index)
	if meta == null:
		return
	match meta.get("action", ""):
		"set_target":
			_placement_mode_type_id = meta["target_id"]
			_refresh()

func _make_assigned_worker_sprite(s: Survivor) -> Control:
	var tooltip := "%s\n%s\n\n%s" % [
		s.name,
		tr(s.profession),
		tr("TOOLTIP_CLICK_TO_UNASSIGN"),
	]
	var sprite := UiPresentation.survivor_sprite(s, tooltip)
	sprite.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var sid := s.id
	sprite.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			GameState.unassign_from_building(sid))
	return sprite

func _open_building_popup(b: Building, popup_position: Vector2) -> void:
	if _tile_popup != null:
		_tile_popup.queue_free()
	for sub in _popup_submenus:
		if sub != null:
			sub.queue_free()
	_popup_submenus.clear()
	_tile_popup = PopupMenu.new()
	add_child(_tile_popup)
	# Si le bâtiment a déjà des workers : option Clear
	if not b.worker_ids.is_empty():
		_tile_popup.add_item(tr("LABEL_CLEAR_BUILDING"))
		_tile_popup.set_item_metadata(_tile_popup.item_count - 1, {"action": "clear_building", "building_id": b.config.id})
		_tile_popup.add_separator()
	# Liste des éveillés
	var any := false
	for s in GameState.awake_survivors():
		var location_hint := ""
		if s.tile_key != "":
			var current_tile: HexTile = GameState.hex_map.get_tile_by_key(s.tile_key)
			if current_tile != null:
				location_hint = "  ← " + UiPresentation.activity(s) + " @ " + UiPresentation.tile_label(s.tile_key)
		elif s.building_id != "" and s.building_id != b.config.id:
			var other: Building = GameState._find_building_by_type(s.building_id)
			if other != null:
				location_hint = "  ← " + UiPresentation.activity_for_building(other.config.id) + " @ " + tr(other.config.name_key)
		elif s.building_id == b.config.id:
			location_hint = "  " + tr("LABEL_HERE")
		else:
			location_hint = "  (" + tr("LABEL_IDLE") + ")"
		_tile_popup.add_item("%s (%s)%s" % [s.name, tr(s.profession), location_hint])
		_tile_popup.set_item_metadata(_tile_popup.item_count - 1, {
			"action": "assign_to_building",
			"survivor_id": s.id,
			"building_id": b.config.id,
		})
		any = true
	if not any:
		_tile_popup.add_item(tr("LABEL_NO_AVAILABLE_WORKER"))
		_tile_popup.set_item_disabled(_tile_popup.item_count - 1, true)
	_tile_popup.id_pressed.connect(_on_building_popup_selected)
	_tile_popup.position = Vector2i(popup_position)
	_tile_popup.popup()

func _on_building_popup_selected(index: int) -> void:
	var meta = _tile_popup.get_item_metadata(index)
	if meta == null:
		return
	match meta.get("action", ""):
		"clear_building":
			var b: Building = GameState._find_building(meta["building_id"])
			if b != null:
				# Retirer tous les workers
				for wid in b.worker_ids.duplicate():
					GameState.unassign_from_building(wid)
		"assign_to_building":
			var sid: int = meta["survivor_id"]
			var bid: String = meta["building_id"]
			var s: Survivor = GameState.roster.get_by_id(sid)
			# Si le colon est déjà ici → on le retire
			if s != null and s.building_id == bid:
				GameState.unassign_from_building(sid)
			else:
				GameState.assign_to_building(sid, bid)
