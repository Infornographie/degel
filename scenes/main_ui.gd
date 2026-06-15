extends Control
## UI placeholder — 4b. Layout horizontal : panneau gauche + carte droite.

const JOB_ORDER: Array[int] = [
	GameState.Job.IDLE,
	GameState.Job.FARM,
	GameState.Job.LOG,
]

const JOB_BASE_LABELS := {
	GameState.Job.IDLE: "Idle",
	GameState.Job.FARM: "Farm",
	GameState.Job.LOG: "Chop wood",
}

# --- Hex rendering ---
# Taille d'un hex pointe-en-haut (rayon du cercle circonscrit).
const HEX_SIZE: float = 32.0

const TILE_LABELS := {
	HexTile.Type.BUNKER: "B",
	HexTile.Type.PLAINS: "P",
	HexTile.Type.FOREST: "F",
	HexTile.Type.MOUNTAIN: "M",
}

const TILE_COLORS := {
	HexTile.Type.BUNKER: Color("#2c2c2c"),       # noir/charbon
	HexTile.Type.PLAINS: Color("#a8c25a"),       # vert clair / herbe
	HexTile.Type.FOREST: Color("#3a6b35"),       # vert foncé / sapinière
	HexTile.Type.MOUNTAIN: Color("#7a5a3a"),     # marron / pierre
}

# --- UI refs ---
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

func _ready() -> void:
	_build_ui()
	GameState.turn_advanced.connect(_refresh)
	GameState.resources_changed.connect(_refresh)
	GameState.survivor_woken.connect(_refresh)
	GameState.survivor_assigned.connect(_refresh)
	GameState.survivor_died.connect(_refresh)
	GameState.candidates_changed.connect(_refresh)
	GameState.targeted_wake_failed.connect(_on_targeted_wake_failed)
	GameState.run_ended.connect(_on_run_ended)
	_refresh()

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Split horizontal : panneau gauche (scroll) + carte droite
	var split := HBoxContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", 16)
	add_child(split)

	# --- Panneau gauche scrollable ---
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

	# --- Panneau droite : carte ---
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.4
	split.add_child(right)
	_build_map_panel(right)

func _build_left_panel(parent: VBoxContainer) -> void:
	_resources_section = VBoxContainer.new()
	parent.add_child(_resources_section)
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
	_advance_button.text = "Advance one turn"
	_advance_button.pressed.connect(_on_advance_pressed)
	parent.add_child(_advance_button)
	_status_label = _add_label(parent, "")

func _build_map_panel(parent: VBoxContainer) -> void:
	_add_label(parent, "Surface map")
	# Conteneur libre : on positionne les hex à l'absolu dedans.
	_map_container = Control.new()
	_map_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_container.custom_minimum_size = Vector2(320, 320)
	parent.add_child(_map_container)
	_draw_map()
	# Petite légende sous la carte
	parent.add_child(HSeparator.new())
	_add_label(parent, "Legend:  B = Bunker   P = Plains   F = Forest   M = Mountain")

func _add_label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label

# --- Map rendering ---

func _draw_map() -> void:
	for child in _map_container.get_children():
		child.queue_free()

	# Centre du conteneur, comme origine du repère hex
	var origin := _map_container.size * 0.5
	if origin.x == 0:
		# Au tout premier _ready, la taille n'est pas encore résolue ; on tape une valeur safe.
		origin = Vector2(160, 160)

	for tile in GameState.hex_map.tiles.values():
		var pixel := _hex_to_pixel(tile.q, tile.r) + origin
		_add_hex_label(tile, pixel)

## Conversion cube → pixel pour hexagones pointe-en-haut.
## Convention Red Blob Games : x = size * sqrt(3) * (q + r/2), y = size * 3/2 * r
func _hex_to_pixel(q: int, r: int) -> Vector2:
	var x: float = HEX_SIZE * sqrt(3.0) * (q + r / 2.0)
	var y: float = HEX_SIZE * 1.5 * r
	return Vector2(x, y)

func _add_hex_label(tile: HexTile, center: Vector2) -> void:
	# Fond coloré : un PanelContainer ou directement un ColorRect en arrière-plan.
	var bg := ColorRect.new()
	var box_size := Vector2(HEX_SIZE, HEX_SIZE)
	bg.size = box_size
	bg.position = center - box_size * 0.5
	bg.color = TILE_COLORS.get(tile.type, Color.GRAY)
	_map_container.add_child(bg)

	# La lettre par-dessus, en blanc pour le contraste.
	var label := Label.new()
	label.text = TILE_LABELS.get(tile.type, "?")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = box_size
	label.position = center - box_size * 0.5
	label.add_theme_color_override("font_color", Color.WHITE)
	_map_container.add_child(label)

# --- Resources (inchangé) ---

func _refresh(_a = null, _b = null, _c = null, _d = null) -> void:
	_rebuild_resources()
	_famine_label.text = "⚠ Famine — turn %d" % GameState.famine_turns if GameState.famine_turns > 0 else ""
	_rebuild_lists()
	_draw_map()

func _rebuild_resources() -> void:
	for child in _resources_section.get_children():
		child.queue_free()
	_add_label(_resources_section, "Turn %d" % GameState.turn)
	_add_label(_resources_section, "Reserve: %.1f   (-%.1f / turn)" % [
		GameState.reserve, GameState.config.core_upkeep])
	var food_income := _aggregate_production("food")
	var food_outcome: float = GameState.awake_count() * GameState.config.food_per_survivor
	_add_label(_resources_section, "Food: %.1f   (+%.1f / -%.1f)" % [
		GameState.resources["food"], food_income, food_outcome])
	var wood_income := _aggregate_production("wood")
	_add_label(_resources_section, "Wood: %.1f   (+%.1f)" % [
		GameState.resources["wood"], wood_income])
	_add_label(_resources_section, "Electricity (this turn): %.1f" % GameState.resources["electricity"])
	_add_label(_resources_section, "Heat (this turn): %.1f" % GameState.resources["heat"])

func _aggregate_production(resource_name: String) -> float:
	var total: float = 0.0
	for s in GameState.awake_survivors():
		var out: Dictionary = GameState.get_effective_output(s.job)
		total += out.get(resource_name, 0.0)
	return total

# --- Survivor lists (inchangé) ---

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
	_awake_header.text = "Awake (%d)" % awake_count
	if awake_count == 0:
		_add_label(_awake_list, "  (nobody awake yet)")

	var sleeping_count := GameState.roster.sleeping_count()
	_asleep_header.text = "Awakening pool — Still in cryo: %d" % sleeping_count
	if sleeping_count == 0:
		_add_label(_asleep_list, "  (cryo bay is empty)")
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

	var label := Label.new()
	label.text = "  %s (%s)" % [s.name, s.profession]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var selector := OptionButton.new()
	for job_id in JOB_ORDER:
		selector.add_item(_job_item_label(job_id), job_id)
	var idx := JOB_ORDER.find(s.job)
	if idx >= 0:
		selector.select(idx)
	var sid := s.id
	selector.item_selected.connect(
		func(index: int): GameState.assign_job(sid, JOB_ORDER[index])
	)
	row.add_child(selector)

	var out_label := Label.new()
	out_label.text = _format_output(s.job)
	out_label.custom_minimum_size = Vector2(140, 0)
	row.add_child(out_label)

func _job_item_label(job_id: int) -> String:
	var base: String = JOB_BASE_LABELS[job_id]
	var outputs: Dictionary = GameState.job_outputs.get(job_id, {})
	if outputs.is_empty():
		return base
	var parts: Array[String] = []
	for resource_name in outputs:
		parts.append("+%.0f %s" % [outputs[resource_name], resource_name])
	return "%s (%s)" % [base, ", ".join(parts)]

func _format_output(job: int) -> String:
	var out: Dictionary = GameState.get_effective_output(job)
	if out.is_empty():
		return ""
	var parts: Array[String] = []
	for resource_name in out:
		parts.append("+%.0f %s" % [out[resource_name], resource_name])
	return ", ".join(parts)

func _add_candidate_row(s: Survivor) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_asleep_list.add_child(row)

	var label := Label.new()
	label.text = "  %s (%s)" % [s.name, s.profession]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var btn := Button.new()
	btn.text = "Wake (-%.0f reserve)" % GameState.config.wake_cost
	btn.disabled = not GameState.can_wake(s.id)
	var sid := s.id
	btn.pressed.connect(func(): GameState.wake(sid))
	row.add_child(btn)

func _add_targeted_search_row() -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_asleep_list.add_child(row)

	var label := Label.new()
	label.text = "  Search for:"
	row.add_child(label)

	_targeted_selector = OptionButton.new()
	for prof in GameState.roster.all_professions():
		_targeted_selector.add_item(prof)
	_targeted_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_targeted_selector)

	var btn := Button.new()
	btn.text = "Search (-%.0f reserve)" % GameState.config.wake_cost_targeted
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
	var profession := _targeted_selector.get_item_text(idx)
	GameState.targeted_wake(profession)

# --- Misc ---

func _on_advance_pressed() -> void:
	GameState.advance_turn()

func _on_targeted_wake_failed(profession: String) -> void:
	if _targeted_status != null:
		_targeted_status.text = "  No %s found in cryo. Reserve spent." % profession

func _on_run_ended(cause: GameState.EndCause) -> void:
	var label := ""
	match cause:
		GameState.EndCause.RESERVE_DEPLETED: label = "Reserve depleted"
		GameState.EndCause.AUTONOMY_REACHED: label = "Autonomy reached"
		GameState.EndCause.COLONY_LOST: label = "Colony lost"
	var score = GameState.compute_score()
	_status_label.text = "Run ended: %s — Score: %d / %d survivors" % [
		label, score.survivors_saved, score.survivors_total]
	_advance_button.disabled = true
