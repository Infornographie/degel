extends Control
## UI placeholder — 3a. Colonization-style readout.

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

var _resources_section: VBoxContainer
var _famine_label: Label
var _awake_header: Label
var _awake_list: VBoxContainer
var _asleep_header: Label
var _asleep_list: VBoxContainer
var _advance_button: Button
var _status_label: Label

func _ready() -> void:
	_build_ui()
	GameState.turn_advanced.connect(_refresh)
	GameState.resources_changed.connect(_refresh)
	GameState.survivor_woken.connect(_refresh)
	GameState.survivor_assigned.connect(_refresh)
	GameState.survivor_died.connect(_refresh)
	GameState.run_ended.connect(_on_run_ended)
	GameState.candidates_changed.connect(_refresh)
	GameState.targeted_wake_failed.connect(_on_targeted_wake_failed)
	_refresh()

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Scroll global : tout le contenu peut dépasser la fenêtre et rester accessible.
	var outer_scroll := ScrollContainer.new()
	outer_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(outer_scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	outer_scroll.add_child(root)

	# --- Resources ---
	_resources_section = VBoxContainer.new()
	root.add_child(_resources_section)
	_famine_label = _add_label(root, "")

	root.add_child(HSeparator.new())

	# --- Awake ---
	_awake_header = _add_label(root, "Awake (0)")
	_awake_list = VBoxContainer.new()
	_awake_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_awake_list)

	root.add_child(HSeparator.new())

	# --- Asleep ---
	_asleep_header = _add_label(root, "Asleep (0)")
	_asleep_list = VBoxContainer.new()
	_asleep_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_asleep_list)

	root.add_child(HSeparator.new())

	# --- Advance + status ---
	_advance_button = Button.new()
	_advance_button.text = "Advance one turn"
	_advance_button.pressed.connect(_on_advance_pressed)
	root.add_child(_advance_button)
	_status_label = _add_label(root, "")

	var dump_btn := Button.new()
	dump_btn.text = "[DEBUG] Dump map"
	dump_btn.pressed.connect(_on_dump_map)
	root.add_child(dump_btn)

func _on_dump_map() -> void:
	print("\n=== Carte (rayon %d, %d tuiles) ===" % [GameState.hex_map.radius, GameState.hex_map.tiles.size()])
	# Groupe par type pour résumer
	var counts: Dictionary = {}
	for tile in GameState.hex_map.tiles.values():
		var type_name: String = HexTile.Type.keys()[tile.type]
		counts[type_name] = counts.get(type_name, 0) + 1
	for type_name in counts:
		print("  %s: %d" % [type_name, counts[type_name]])
	# Liste détaillée
	print("Détail :")
	for tile in GameState.hex_map.tiles.values():
		var type_name: String = HexTile.Type.keys()[tile.type]
		print("  (q=%d, r=%d) %s" % [tile.q, tile.r, type_name])
	# Test des voisins du centre
	var center := GameState.hex_map.get_tile(0, 0)
	print("Voisins du bunker (devraient être 6) : %d" % GameState.hex_map.neighbors(center).size())

func _on_targeted_wake_failed(profession: String) -> void:
	if _targeted_status != null:
		_targeted_status.text = "  No %s found in cryo. Reserve spent." % profession

func _add_label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label

func _refresh(_a = null, _b = null, _c = null, _d = null) -> void:
	_rebuild_resources()
	_famine_label.text = "⚠ Famine — turn %d" % GameState.famine_turns if GameState.famine_turns > 0 else ""
	_rebuild_lists()

# --- Resources ---

func _rebuild_resources() -> void:
	for child in _resources_section.get_children():
		child.queue_free()
	_add_label(_resources_section, "Turn %d" % GameState.turn)

	# Reserve (l'horloge)
	_add_label(_resources_section, "Reserve: %.1f   (-%.1f / turn)" % [
		GameState.reserve, GameState.config.core_upkeep])

	# Food
	var food_income := _aggregate_production("food")
	var food_outcome: float = GameState.awake_count() * GameState.config.food_per_survivor
	_add_label(_resources_section, "Food: %.1f   (+%.1f / -%.1f)" % [
		GameState.resources["food"], food_income, food_outcome])

	# Wood
	var wood_income := _aggregate_production("wood")
	_add_label(_resources_section, "Wood: %.1f   (+%.1f)" % [
		GameState.resources["wood"], wood_income])

	# Electricity (flux du tour seulement)
	_add_label(_resources_section, "Electricity (this turn): %.1f" % GameState.resources["electricity"])

	# Heat (flux du tour seulement)
	_add_label(_resources_section, "Heat (this turn): %.1f" % GameState.resources["heat"])

func _aggregate_production(resource_name: String) -> float:
	var total: float = 0.0
	for s in GameState.awake_survivors():
		var out: Dictionary = GameState.get_effective_output(s.job)
		total += out.get(resource_name, 0.0)
	return total

# --- Survivor lists ---

func _rebuild_lists() -> void:
	for child in _awake_list.get_children():
		child.queue_free()
	for child in _asleep_list.get_children():
		child.queue_free()

	# Awake
	var awake_count := 0
	for s in GameState.survivors():
		if s.awake:
			_add_awake_row(s)
			awake_count += 1
	_awake_header.text = "Awake (%d)" % awake_count
	if awake_count == 0:
		_add_label(_awake_list, "  (nobody awake yet)")

	# Awakening pool : candidats visibles
	var sleeping_count := GameState.roster.sleeping_count()
	_asleep_header.text = "Awakening pool — Still in cryo: %d" % sleeping_count
	if sleeping_count == 0:
		_add_label(_asleep_list, "  (cryo bay is empty)")
	else:
		for id in GameState.candidates:
			var s: Survivor = GameState.roster.get_by_id(id)
			if s != null:
				_add_candidate_row(s)
		# Search bar
		_add_label(_asleep_list, "")  # spacer
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

var _targeted_selector: OptionButton
var _targeted_status: Label

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

	# Petit label de feedback (rempli par le signal failed)
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
