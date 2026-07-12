extends Control
class_name MapView
## Vue de la carte hexagonale : tuiles colorées par type, sprites des workers
## assignés, icônes de production en arrière-plan. Clic sur tuile → popup
## d'assignation par activité.
##
## Layout : pointy-top hexagones, deux passes de rendu (backgrounds d'abord
## pour que les sprites/icônes des workers passent par-dessus).
##
## Popups : un seul popup ouvert à la fois, l'ancien est freed à l'ouverture
## du nouveau. Sous-menus stockés dans _popup_submenus pour cleanup.

const HEX_RADIUS: float = 36.0
const TILE_PROD_ICON_SIZE: int = 14
const WORKER_SPRITE_SCALE: int = 3
const DEFAULT_MAP_ORIGIN := Vector2(160, 160)

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

var _map_container: Control

func _ready() -> void:
	_build()
	GameState.turn_advanced.connect(_rebuild)
	GameState.resources_changed.connect(_rebuild)
	GameState.survivor_woken.connect(_rebuild)
	GameState.survivor_assigned.connect(_rebuild)
	GameState.tile_assignment_changed.connect(_rebuild)
	GameState.building_assignment_changed.connect(_rebuild)
	GameState.construction_completed.connect(_rebuild)
	GameState.nightly_deaths.connect(_rebuild)
	_rebuild()
	await get_tree().process_frame
	_rebuild()

func _build() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	var title := Label.new()
	title.text = tr("LABEL_MAP_TITLE")
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	_map_container = Control.new()
	_map_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_container.custom_minimum_size = Vector2(320, 320)
	vbox.add_child(_map_container)

	vbox.add_child(HSeparator.new())
	var legend_1 := Label.new()
	legend_1.text = tr("LABEL_LEGEND_1")
	vbox.add_child(legend_1)
	var legend_2 := Label.new()
	legend_2.text = tr("LABEL_LEGEND_2")
	vbox.add_child(legend_2)

## Signature tolérante pour absorber les divers payloads des signals branchés.
func _rebuild(_a = null, _b = null, _c = null, _d = null) -> void:
	if _map_container == null:
		return
	for child in _map_container.get_children():
		_map_container.remove_child(child)
		child.queue_free()
	var origin := _map_container.size * 0.5
	if origin.x == 0:
		origin = DEFAULT_MAP_ORIGIN
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
			risky_amount = GameState.expected_activity_yield(s, tile, activity)
			risky_resource = activity.produced_resource
			risky_rate = activity.success_rate
	var out: Dictionary = GameState.get_survivor_output(s)
	# Icônes de production EN FOND
	if is_risky and risky_amount > 0:
		var total: int = risky_amount
		var separation: int = 0
		if total > 3:
			var target_width: float = 3.0 * TILE_PROD_ICON_SIZE
			var needed_width: float = total * TILE_PROD_ICON_SIZE
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
			var target_width: float = 3.0 * TILE_PROD_ICON_SIZE
			var needed_width: float = total * TILE_PROD_ICON_SIZE
			separation = int(-((needed_width - target_width) / max(1, total - 1)))
		icons_row.add_theme_constant_override("separation", separation)
		for resource_name in out:
			var amount: int = int(out[resource_name])
			for i in amount:
				icons_row.add_child(UiPresentation.resource_icon(resource_name, TILE_PROD_ICON_SIZE))
		icons_row.size = Vector2(HEX_RADIUS * 2.0, TILE_PROD_ICON_SIZE)
		icons_row.position = center - Vector2(HEX_RADIUS, HEX_RADIUS * 0.7)
		_map_container.add_child(icons_row)
	# Sprite du worker PAR-DESSUS, centré
	var sprite := TextureRect.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var prof := Roster.get_profession(s.profession)
	if prof != null and prof.sprite != null:
		sprite.texture = prof.sprite
	else:
		sprite.texture = load(UiPresentation.SURVIVOR_SPRITE_PATH % s.sprite_variant)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex_size: Vector2 = (sprite.texture as Texture2D).get_size()
	var sprite_size: Vector2 = tex_size * WORKER_SPRITE_SCALE
	sprite.size = sprite_size
	sprite.position = center - sprite_size * 0.5 + Vector2(0, HEX_RADIUS * 0.15)
	_map_container.add_child(sprite)

func _hex_to_pixel(q: int, r: int) -> Vector2:
	# Pointy-top hex layout
	var x: float = HEX_RADIUS * sqrt(3.0) * (q + r / 2.0)
	var y: float = HEX_RADIUS * 1.5 * r
	return Vector2(x, y)

func _hex_polygon_points() -> PackedVector2Array:
	# 6 sommets d'un hexagone pointy-top, centré sur (0,0)
	var points := PackedVector2Array()
	for i in 6:
		var angle: float = deg_to_rad(60.0 * i - 30.0)
		points.append(Vector2(cos(angle), sin(angle)) * HEX_RADIUS)
	return points

# ── Popups ──

func _open_tile_popup(tile_key: String, popup_position: Vector2) -> void:
	var tile: HexTile = GameState.hex_map.get_tile_by_key(tile_key)
	if tile == null:
		return
	TileAssignmentPopup.open(self, tile, popup_position)
