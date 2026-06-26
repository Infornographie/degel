extends Control
## UI placeholder — 4c. Carte interactive, jobs territorialisés.


var _colony_view: ColonyView


func _ready() -> void:
	_build_ui()
	# On cache l'UI le temps que le layout se calcule
	modulate.a = 0.0
	await get_tree().process_frame
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
	_colony_view = preload("res://scenes/ui/colony_view.tscn").instantiate()
	_colony_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_colony_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settlement_panel.add_child(_colony_view)

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
	var map_view: MapView = preload("res://scenes/ui/map_view.tscn").instantiate()
	map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_panel.add_child(map_view)

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
	modulate.a = 1.0

func _on_run_ended(_cause: GameState.EndCause) -> void:
	var score = GameState.compute_score()
	var message := tr("POPUP_FINAL_SCORE") % [
		score.survivors_saved, score.survivors_total]
	UiPresentation.show_popup(self, tr("POPUP_RUN_ENDED"), message)

func _on_nightly_deaths(events: Array) -> void:
	if events.is_empty():
		return
	var lines: Array[String] = []
	for ev in events:
		lines.append(ev.format())
	UiPresentation.show_popup(self, tr("NEWS_TITLE"), tr("NEWS_INTRO") + "\n\n" + "\n".join(lines))
