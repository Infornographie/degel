extends Control
## UI placeholder — 4c. Carte interactive, jobs territorialisés.


var _map_container: Control
var _tile_popup: PopupMenu
var _popup_tile_key: String = ""
# id dans le sous-menu (encodé : survivor_id * 100 + job_id) → (survivor_id, job_id)
var _popup_submenus: Array[PopupMenu] = []
var _colony_view: ColonyView


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
