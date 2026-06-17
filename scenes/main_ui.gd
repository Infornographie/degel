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
var _awake_list: VBoxContainer
var _asleep_header: Label
var _asleep_list: VBoxContainer
var _advance_button: Button
var _status_label: Label
var _map_container: Control
var _targeted_selector: OptionButton
var _targeted_status: Label
var _tile_popup: PopupMenu
var _popup_tile_key: String = ""
# id dans le sous-menu (encodé : survivor_id * 100 + job_id) → (survivor_id, job_id)
var _popup_submenus: Array[PopupMenu] = []
var _synth_checkbox: CheckBox

func _ready() -> void:
	_build_ui()
	GameState.turn_advanced.connect(_refresh)
	GameState.resources_changed.connect(_refresh)
	GameState.survivor_woken.connect(_refresh)
	GameState.survivor_assigned.connect(_refresh)
	GameState.candidates_changed.connect(_refresh)
	GameState.tile_assignment_changed.connect(_refresh)
	GameState.targeted_wake_failed.connect(_on_targeted_wake_failed)
	GameState.run_ended.connect(_on_run_ended)
	GameState.nightly_deaths.connect(_on_nightly_deaths)
	_refresh()

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var split := HBoxContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", 16)
	add_child(split)

	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_stretch_ratio = 0.6
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(left_scroll)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	left_scroll.add_child(left)
	_build_left_panel(left)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.4
	split.add_child(right)
	_build_map_panel(right)

func _build_left_panel(parent: VBoxContainer) -> void:
	_resources_section = VBoxContainer.new()
	parent.add_child(_resources_section)
	_synth_checkbox = CheckBox.new()
	_synth_checkbox.text = tr("LABEL_SYNTH_TOGGLE")
	_synth_checkbox.toggled.connect(_on_synth_toggled)
	parent.add_child(_synth_checkbox)
	_famine_label = _add_label(parent, "")
	parent.add_child(HSeparator.new())
	_awake_header = _add_label(parent, "Awake (0)")
	_awake_list = VBoxContainer.new()
	_awake_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(_awake_list)
	parent.add_child(HSeparator.new())
	_asleep_header = _add_label(parent, "Asleep (0)")
	_asleep_list = VBoxContainer.new()
	_asleep_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(_asleep_list)
	parent.add_child(HSeparator.new())
	_advance_button = Button.new()
	_advance_button.text = tr("BTN_ADVANCE")
	_advance_button.pressed.connect(_on_advance_pressed)
	parent.add_child(_advance_button)
	_status_label = _add_label(parent, "")
	var necro_btn := Button.new()
	necro_btn.text = tr("BTN_NECROLOGY")
	necro_btn.pressed.connect(_on_necrology_pressed)
	parent.add_child(necro_btn)

func _build_map_panel(parent: VBoxContainer) -> void:
	_add_label(parent, tr("LABEL_MAP_TITLE"))
	_map_container = Control.new()
	_map_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_container.custom_minimum_size = Vector2(320, 320)
	parent.add_child(_map_container)
	parent.add_child(HSeparator.new())
	_add_label(parent, tr("LABEL_LEGEND_1"))
	_add_label(parent, tr("LABEL_LEGEND_2"))

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
	var tile := GameState.hex_map.get_tile_by_key(tile_key)
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
			var resource_name: String = GameState.JOB_RESOURCE.get(job_id, "")
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
		var tile := GameState.hex_map.get_tile_by_key(_popup_tile_key)
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
		var tile := GameState.hex_map.get_tile_by_key(_popup_tile_key)
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

	if _synth_checkbox != null:
		_synth_checkbox.set_pressed_no_signal(GameState.synth_on)

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
	for child in _asleep_list.get_children():
		child.queue_free()

	var awake_count := 0
	for s in GameState.survivors():
		if s.awake:
			_add_awake_row(s)
			awake_count += 1
	_awake_header.text = tr("LABEL_AWAKE") % awake_count
	if awake_count == 0:
		_add_label(_awake_list, tr("LABEL_NOBODY_AWAKE"))

	var sleeping_count := GameState.roster.sleeping_count()
	_asleep_header.text = tr("LABEL_ASLEEP_HEADER") % sleeping_count
	if sleeping_count == 0:
		_add_label(_asleep_list, tr("LABEL_CRYO_EMPTY"))
	else:
		for id in GameState.candidates:
			var s: Survivor = GameState.roster.get_by_id(id)
			if s != null:
				_add_candidate_row(s)
		_add_label(_asleep_list, "")
		_add_targeted_search_row()

func _add_awake_row(s: Survivor) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_awake_list.add_child(row)

	var location := tr("LABEL_IN_BUNKER") if s.tile_key == "" else tr("LABEL_AT_TILE") + _format_tile_label(s.tile_key)
	var prod := _format_output(s)
	var prod_suffix := "  →  " + prod if prod != "" else ""
	var label := Label.new()
	label.text = "  %s (%s) — %s — %s%s" % [s.name, tr(s.profession), _job_label(s.job), location, prod_suffix]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

func _format_output(s: Survivor) -> String:
	var out: Dictionary = GameState.get_survivor_output(s)
	if out.is_empty():
		return ""
	var parts: Array[String] = []
	for resource_name in out:
		parts.append("+%.0f %s" % [out[resource_name], resource_name])
	return ", ".join(parts)

func _format_tile_label(key: String) -> String:
	var tile := GameState.hex_map.get_tile_by_key(key)
	if tile == null:
		return key
	var type_key: String = "TILE_TYPE_" + HexTile.Type.keys()[tile.type]
	return "%s (%d,%d)" % [tr(type_key), tile.q, tile.r]

func _add_candidate_row(s: Survivor) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_asleep_list.add_child(row)
	var label := Label.new()
	label.text = "  %s (%s)" % [s.name, tr(s.profession)]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var btn := Button.new()
	btn.text = tr("BTN_WAKE") % GameState.config.wake_cost
	btn.disabled = not GameState.can_wake(s.id)
	var sid := s.id
	btn.pressed.connect(func(): GameState.wake(sid))
	row.add_child(btn)

func _add_targeted_search_row() -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_asleep_list.add_child(row)
	var label := Label.new()
	label.text = tr("LABEL_SEARCH_FOR")
	row.add_child(label)
	_targeted_selector = OptionButton.new()
	for prof in GameState.roster.all_professions():
		_targeted_selector.add_item(tr(prof))
		_targeted_selector.set_item_metadata(_targeted_selector.item_count - 1, prof)
	_targeted_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_targeted_selector)
	var btn := Button.new()
	btn.text = tr("BTN_SEARCH") % GameState.config.wake_cost_targeted
	btn.disabled = not GameState.can_targeted_wake()
	btn.pressed.connect(_on_targeted_search_pressed)
	row.add_child(btn)
	_targeted_status = _add_label(_asleep_list, "")

func _on_targeted_search_pressed() -> void:
	if _targeted_selector == null:
		return
	var idx := _targeted_selector.selected
	if idx < 0:
		return
	var profession: String = _targeted_selector.get_item_metadata(idx)
	GameState.targeted_wake(profession)

func _on_advance_pressed() -> void:
	GameState.advance_turn()

func _on_targeted_wake_failed(profession: String) -> void:
	if _targeted_status != null:
		_targeted_status.text = tr("SEARCH_FAILED") % profession

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

func _resource_label(name: String) -> String:
	match name:
		"food": return tr("RESOURCE_FOOD")
		"wood": return tr("RESOURCE_WOOD")
		"ore": return tr("RESOURCE_ORE")
		_: return name
