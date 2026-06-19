extends Control
## UI placeholder — 4c. Carte interactive, jobs territorialisés.

const HEX_SIZE: float = 32.0

const TILE_LABELS := {
	HexTile.Type.BUNKER: "B",
	HexTile.Type.PLAINS: "P",
	HexTile.Type.FOREST: "F",
	HexTile.Type.MOUNTAIN: "M",
}

const TILE_COLORS := {
	HexTile.Type.BUNKER: Color("#2c2c2c"),
	HexTile.Type.PLAINS: Color("#a8c25a"),
	HexTile.Type.FOREST: Color("#3a6b35"),
	HexTile.Type.MOUNTAIN: Color("#7a5a3a"),
}

var _resources_section: VBoxContainer
var _famine_label: Label
var _awake_header: Label
var _awake_list: HBoxContainer
var _advance_button: Button
var _status_label: Label
var _map_container: Control
var _tile_popup: PopupMenu
var _popup_tile_key: String = ""
# id dans le sous-menu (encodé : survivor_id * 100 + job_id) → (survivor_id, job_id)
var _popup_submenus: Array[PopupMenu] = []
var _colony_grid: GridContainer
const COLONY_SLOTS: int = 8

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
	# On cache l'UI le temps que le layout se calcule
	modulate.a = 0.0
	await get_tree().process_frame
	_refresh()
	modulate.a = 1.0

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Split vertical principal : top (colony + map) / bottom (data & buttons)
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 12)
	add_child(main_vbox)

	# --- Rang du haut : colony + map ---
	var top_row := HBoxContainer.new()
	top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_row.size_flags_stretch_ratio = 0.70
	top_row.add_theme_constant_override("separation", 12)
	main_vbox.add_child(top_row)

	# Colony à gauche du rang du haut
	var colony_panel := VBoxContainer.new()
	colony_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	colony_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	colony_panel.size_flags_stretch_ratio = 0.60
	top_row.add_child(colony_panel)
	_build_colony_panel(colony_panel)

	# Map à droite du rang du haut
	var map_panel := VBoxContainer.new()
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_stretch_ratio = 0.40
	top_row.add_child(map_panel)
	_build_map_panel(map_panel)

	# --- Rang du bas : data & buttons ---
	var bottom_row := HBoxContainer.new()
	bottom_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_row.size_flags_stretch_ratio = 0.30
	bottom_row.add_theme_constant_override("separation", 16)
	main_vbox.add_child(bottom_row)

	# Zone ressources
	var resources_scroll := ScrollContainer.new()
	resources_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resources_scroll.size_flags_stretch_ratio = 0.30
	resources_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bottom_row.add_child(resources_scroll)
	var resources_vbox := VBoxContainer.new()
	resources_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resources_scroll.add_child(resources_vbox)
	_build_resources_section(resources_vbox)

	# Zone survivants
	var survivors_scroll := ScrollContainer.new()
	survivors_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	survivors_scroll.size_flags_stretch_ratio = 0.50
	survivors_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bottom_row.add_child(survivors_scroll)
	var survivors_vbox := VBoxContainer.new()
	survivors_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	survivors_vbox.add_theme_constant_override("separation", 8)
	survivors_scroll.add_child(survivors_vbox)
	_build_survivors_section(survivors_vbox)

	# Zone boutons (advance, necrology, quit)
	var buttons_vbox := VBoxContainer.new()
	buttons_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons_vbox.size_flags_stretch_ratio = 0.20
	buttons_vbox.add_theme_constant_override("separation", 8)
	bottom_row.add_child(buttons_vbox)
	_build_buttons_section(buttons_vbox)

func _build_resources_section(parent: VBoxContainer) -> void:
	_resources_section = VBoxContainer.new()
	parent.add_child(_resources_section)
	_famine_label = _add_label(parent, "")

func _build_survivors_section(parent: VBoxContainer) -> void:
	_awake_header = _add_label(parent, tr("LABEL_AWAKE") % 0)
	_awake_list = HBoxContainer.new()
	_awake_list.add_theme_constant_override("separation", 8)
	parent.add_child(_awake_list)

func _build_buttons_section(parent: VBoxContainer) -> void:
	_advance_button = Button.new()
	_advance_button.text = tr("BTN_ADVANCE")
	_advance_button.pressed.connect(_on_advance_pressed)
	parent.add_child(_advance_button)
	var necro_btn := Button.new()
	necro_btn.text = tr("BTN_NECROLOGY")
	necro_btn.pressed.connect(_on_necrology_pressed)
	parent.add_child(necro_btn)
	var lang_btn := Button.new()
	lang_btn.text = tr("BTN_TOGGLE_LANG")
	lang_btn.pressed.connect(_on_toggle_lang_pressed)
	parent.add_child(lang_btn)
	var quit_btn := Button.new()
	quit_btn.text = tr("BTN_QUIT")
	quit_btn.pressed.connect(get_tree().quit)
	parent.add_child(quit_btn)
	_status_label = _add_label(parent, "")

func _on_toggle_lang_pressed() -> void:
	var current := TranslationServer.get_locale()
	var new_locale := "en" if current.begins_with("fr") else "fr"
	TranslationServer.set_locale(new_locale)
	_rebuild_ui()

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
		child.queue_free()
	var computer: Building = _find_starter("computer")
	var synth: Building = _find_starter("synthesizer")
	var cryo: Building = _find_starter("cryo_room")
	# Slots 0-3 : ligne du haut, tous vides
	for i in 4:
		_add_empty_slot()
	# Slots 4-7 : computer, vide, vide, vide
	if computer != null: _add_computer_slot(computer)
	else: _add_empty_slot()
	_add_empty_slot()
	_add_empty_slot()
	_add_empty_slot()
	# Slots 8-11 : cryo, synth, vide, vide
	if cryo != null: _add_cryo_slot(cryo)
	else: _add_empty_slot()
	if synth != null: _add_synth_slot(synth)
	else: _add_empty_slot()
	for i in 2:
		_add_empty_slot()

func _find_starter(id: String) -> Building:
	for b in GameState.buildings:
		if b.config.id == id:
			return b
	return null

func _add_computer_slot(b: Building) -> void:
	var panel := _new_slot_panel()
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
	var panel := _new_slot_panel()
	_colony_grid.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	vbox.add_child(_slot_title(tr(b.config.name_key)))
	var checkbox := CheckBox.new()
	checkbox.text = tr("LABEL_SYNTH_RUNNING")
	checkbox.set_pressed_no_signal(GameState.synth_on)
	checkbox.toggled.connect(_on_synth_toggled)
	vbox.add_child(checkbox)
	var info := Label.new()
	info.text = tr("LABEL_SYNTH_INFO")
	info.add_theme_font_size_override("font_size", 9)
	info.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(info)

func _add_cryo_slot(b: Building) -> void:
	var panel := _new_slot_panel()
	_colony_grid.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	vbox.add_child(_slot_title(tr(b.config.name_key)))
	var sprites_row := HBoxContainer.new()
	sprites_row.add_theme_constant_override("separation", 4)
	sprites_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(sprites_row)
	for cid in GameState.candidates:
		var s: Survivor = GameState.roster.get_by_id(cid)
		if s == null:
			continue
		sprites_row.add_child(_make_candidate_card(s))
	# Compteur des endormis restants
	var count_label := Label.new()
	count_label.text = tr("LABEL_STILL_IN_CRYO") % GameState.roster.sleeping_count()
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", 12)
	count_label.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(count_label)

func _new_slot_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(140, 100)
	return panel

func _slot_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	return label

func _draw_colony_slots() -> void:
	for child in _colony_grid.get_children():
		child.queue_free()
	# Bâtiments non-starter à afficher dans la grille libre
	var non_starter: Array[Building] = []
	for b in GameState.buildings:
		if not b.config.is_starter:
			non_starter.append(b)
	for i in COLONY_SLOTS:
		if i < non_starter.size():
			_add_building_slot(non_starter[i])
		else:
			_add_empty_slot()

func _add_building_slot(b: Building) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(140, 100)
	_colony_grid.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	var name_label := Label.new()
	name_label.text = tr(b.config.name_key)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(name_label)
	var family_label := Label.new()
	match b.config.family:
		BuildingConfig.Family.TRANSFORMATION: family_label.text = tr("BUILDING_FAMILY_TRANSFORMATION")
		BuildingConfig.Family.FUNCTION: family_label.text = tr("BUILDING_FAMILY_FUNCTION")
	family_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	family_label.add_theme_font_size_override("font_size", 10)
	family_label.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(family_label)

func _add_empty_slot() -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(140, 100)
	panel.modulate = Color(1, 1, 1, 0.3)
	_colony_grid.add_child(panel)
	var label := Label.new()
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
		child.queue_free()
	var origin := _map_container.size * 0.5
	if origin.x == 0:
		origin = Vector2(160, 160)
	for tile in GameState.hex_map.tiles.values():
		var pixel := _hex_to_pixel(tile.q, tile.r) + origin
		_add_hex(tile, pixel)

func _hex_to_pixel(q: int, r: int) -> Vector2:
	var x: float = HEX_SIZE * sqrt(3.0) * (q + r / 2.0)
	var y: float = HEX_SIZE * 1.5 * r
	return Vector2(x, y)

func _add_hex(tile: HexTile, center: Vector2) -> void:
	var box_size := Vector2(HEX_SIZE, HEX_SIZE)
	var bg := ColorRect.new()
	bg.size = box_size
	bg.position = center - box_size * 0.5
	bg.color = TILE_COLORS.get(tile.type, Color.GRAY)
	if tile.type != HexTile.Type.BUNKER:
		bg.mouse_filter = Control.MOUSE_FILTER_STOP
		var tkey := tile.key()
		bg.gui_input.connect(func(event: InputEvent): _on_tile_clicked(event, tkey))
	_map_container.add_child(bg)

	# Lettre du type, + astérisque si la tuile est occupée
	var letter: String = TILE_LABELS.get(tile.type, "?")
	if tile.worker_id != -1:
		letter += "*"

	var label := Label.new()
	label.text = letter
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = box_size
	label.position = center - box_size * 0.5
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color.WHITE)
	_map_container.add_child(label)

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

		var jobs: Array[int] = [GameState.Job.FARMER, GameState.Job.LUMBERJACK, GameState.Job.MINER]
		for job_id in jobs:
			var yield_val: float = tile.yields.get(job_id, 0.0)
			var resource_name: String = ProductionSystem.JOB_RESOURCE.get(job_id, "")
			var label_text := "%s  (+%.0f %s)" % [_job_label(job_id), yield_val, _resource_label(resource_name)]
			sub.add_item(label_text)
			sub.set_item_metadata(sub.item_count - 1, {"survivor_id": s.id, "job": job_id})

		sub.id_pressed.connect(_on_submenu_selected.bind(sub))

		# Indication d'emplacement courant du colon
		var location_hint := ""
		if s.tile_key != "" and s.tile_key != tile_key:
			location_hint = tr("LABEL_CURRENTLY_AT") + _format_tile_label(s.tile_key)
		elif s.tile_key == tile_key:
			location_hint = tr("LABEL_HERE")
		else:
			location_hint = "  (" + tr("LABEL_IN_BUNKER") + ")"

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
	var job: int = meta["job"]
	# On assigne le job ET la tuile
	GameState.assign_job(survivor_id, job)
	GameState.assign_to_tile(survivor_id, _popup_tile_key)
	_popup_tile_key = ""

func _on_tile_popup_selected(id: int) -> void:
	if _popup_tile_key == "":
		return
	if id == -1:
		# Clear : on retire l'occupant courant
		var tile: HexTile = GameState.hex_map.get_tile_by_key(_popup_tile_key)
		if tile != null and tile.worker_id != -1:
			GameState.unassign_from_tile(tile.worker_id)
	elif id == -2:
		pass   # no-op
	else:
		GameState.assign_to_tile(id, _popup_tile_key)
	_popup_tile_key = ""

# --- Refresh ---

func _refresh(_a = null, _b = null, _c = null, _d = null) -> void:
	_rebuild_resources()
	_famine_label.text = tr("LABEL_FAMINE") % GameState.famine_turns if GameState.famine_turns > 0 else ""
	_rebuild_lists()
	_draw_map()
	_draw_colony()

func _rebuild_resources() -> void:
	for child in _resources_section.get_children():
		child.queue_free()
	_add_label(_resources_section, tr("LABEL_TURN") % GameState.turn)
		
	# Bloc énergie : tout sur une vue compacte
	var elec_value: float = GameState.resources["electricity"]
	var elec_parts: Array[String] = []
	elec_parts.append(tr("LABEL_REACTOR") % GameState.reactor_output)
	if GameState.synth_on:
		elec_parts.append(tr("LABEL_SYNTH_COST") % GameState.SYNTH_ELECTRICITY_COST)
	elec_parts.append(tr("LABEL_USABLE") % elec_value)
	_add_label(_resources_section, tr("LABEL_ELEC_HEADER") + " | ".join(elec_parts))
	if GameState.resources["heat"] > 0.0:
		_add_label(_resources_section, tr("LABEL_HEAT") % GameState.resources["heat"])

	var food_income := _aggregate_production("food")
	var food_outcome: float = GameState.awake_count() * GameState.config.food_per_survivor
	_add_label(_resources_section, tr("LABEL_FOOD") % [
		GameState.resources["food"], food_income, food_outcome])
	var wood_income := _aggregate_production("wood")
	_add_label(_resources_section, tr("LABEL_WOOD") % [
		GameState.resources["wood"], wood_income])
	var ore_income := _aggregate_production("ore")
	_add_label(_resources_section, tr("LABEL_ORE") % [
		GameState.resources["ore"], ore_income])

func _aggregate_production(resource_name: String) -> float:
	var total: float = 0.0
	for s in GameState.awake_survivors():
		var out: Dictionary = GameState.get_survivor_output(s)
		total += out.get(resource_name, 0.0)
	return total

# --- Listes survivants ---

func _rebuild_lists() -> void:
	for child in _awake_list.get_children():
		child.queue_free()
	var awake_count := 0
	for s in GameState.survivors():
		if s.awake:
			_add_awake_row(s)
			awake_count += 1
	_awake_header.text = tr("LABEL_AWAKE") % awake_count
	if awake_count == 0:
		_add_label(_awake_list, tr("LABEL_NOBODY_AWAKE"))

func _add_awake_row(s: Survivor) -> void:
	var location := tr("LABEL_IN_BUNKER") if s.tile_key == "" else tr("LABEL_AT_TILE") + _format_tile_label(s.tile_key)
	var prod := _format_output(s)
	var tooltip := "%s\n%s\n%s — %s" % [
		s.name,
		tr(s.profession),
		_job_label(s.job),
		location,
	]
	if prod != "":
		tooltip += "\n\n→ " + prod
	var sprite := _make_survivor_sprite(s, tooltip)
	_awake_list.add_child(sprite)

func _format_output(s: Survivor) -> String:
	var out: Dictionary = GameState.get_survivor_output(s)
	if out.is_empty():
		return ""
	var parts: Array[String] = []
	for resource_name in out:
		parts.append("+%.0f %s" % [out[resource_name], resource_name])
	return ", ".join(parts)

func _format_tile_label(key: String) -> String:
	var tile: HexTile = GameState.hex_map.get_tile_by_key(key)
	if tile == null:
		return key
	var type_key: String = "TILE_TYPE_" + HexTile.Type.keys()[tile.type]
	return "%s (%d,%d)" % [tr(type_key), tile.q, tile.r]

func _on_advance_pressed() -> void:
	GameState.advance_turn()

func _on_run_ended(cause: GameState.EndCause) -> void:
	var label := ""
	match cause:
		GameState.EndCause.REACTOR_DEAD: label = tr("LABEL_REACTOR_DEAD")
		GameState.EndCause.COLONY_LOST: label = tr("LABEL_COLONY_LOST")
	var score = GameState.compute_score()
	var message := tr("POPUP_FINAL_SCORE") % [
		score.survivors_saved, score.survivors_total]
	_show_popup(tr("POPUP_RUN_ENDED"), message)
	_status_label.text = tr("LABEL_RUN_ENDED") % label
	_advance_button.disabled = true

func _on_synth_toggled(pressed: bool) -> void:
	GameState.set_synth(pressed)
	_refresh()

func _on_necrology_pressed() -> void:
	var lines: Array[String] = []
	for entry in GameState.necrology:
		var cause_label: String = entry.cause
		if entry.cause == "switched off":
			cause_label = tr("DEATH_SWITCHED_OFF")
		elif entry.cause == "starved":
			cause_label = tr("DEATH_STARVED")
		lines.append(tr("POPUP_NECROLOGY_LINE") % [
			entry.turn, entry.name, tr(entry.profession), cause_label])
	var content := "\n".join(lines) if not lines.is_empty() else tr("POPUP_NECROLOGY_EMPTY")
	_show_popup(tr("BTN_NECROLOGY"), content)

func _show_popup(title: String, message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)

func _on_nightly_deaths(events: Array) -> void:
	var lines: Array[String] = []
	for entry in events:
		if entry.cause == "switched off":
			lines.append(tr("DEATH_LINE_SWITCHED") % [entry.name, tr(entry.profession)])
		elif entry.cause == "starved":
			lines.append(tr("DEATH_LINE_STARVED") % [entry.name, tr(entry.profession)])
		else:
			lines.append("%s (%s) — %s." % [entry.name, tr(entry.profession), entry.cause])
	_show_popup(tr("POPUP_NEWS_TITLE"), tr("POPUP_NEWS_PREFIX") + "\n".join(lines))

func _job_label(job: int) -> String:
	match job:
		GameState.Job.IDLE: return tr("JOB_IDLE")
		GameState.Job.FARMER: return tr("JOB_FARMER")
		GameState.Job.LUMBERJACK: return tr("JOB_LUMBERJACK")
		GameState.Job.MINER: return tr("JOB_MINER")
		_: return "?"

func _resource_label(resource_name: String) -> String:
	match resource_name:
		"food": return tr("RESOURCE_FOOD")
		"wood": return tr("RESOURCE_WOOD")
		"ore": return tr("RESOURCE_ORE")
		_: return resource_name

func _make_candidate_card(s: Survivor) -> Control:
	var tooltip := "%s\n%s\n\n%s" % [
		s.name,
		tr(s.profession),
		tr("BTN_WAKE") % GameState.config.wake_cost,
	]
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	# Sprite couché (rotation -45°)
	var sprite := _make_survivor_sprite(s, tooltip)
	sprite.pivot_offset = sprite.custom_minimum_size * 0.5
	sprite.rotation = deg_to_rad(-75)
	var sprite_wrap := Control.new()
	sprite_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sprite_wrap.custom_minimum_size = sprite.custom_minimum_size
	sprite_wrap.add_child(sprite)
	vbox.add_child(sprite_wrap)
	# Bouton wake dessous
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.text = tr("BTN_WAKE_SHORT")
	btn.disabled = not GameState.can_wake(s.id)
	var sid := s.id
	btn.pressed.connect(func(): GameState.wake(sid))
	vbox.add_child(btn)
	return vbox

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

const SURVIVOR_SPRITE_PATH := "res://assets/survivors/generic.png"
const SURVIVOR_SPRITE_SCALE := 4

func _make_survivor_sprite(s: Survivor, sprite_tooltip: String) -> TextureRect:
	var sprite := TextureRect.new()
	sprite.texture = load("res://assets/survivors/generic%d.png" % s.sprite_variant)
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # pour pixel art net
	var tex_size: Vector2 = (sprite.texture as Texture2D).get_size()
	sprite.custom_minimum_size = tex_size * SURVIVOR_SPRITE_SCALE
	sprite.tooltip_text = sprite_tooltip
	sprite.mouse_filter = Control.MOUSE_FILTER_STOP  # pour que le hover/clic marche
	return sprite
