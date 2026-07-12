extends PopupPanel
class_name TileAssignmentPopup
## Popup fixe centré. Matrice activités × persos éveillés :
## - Colonne 1 = en-tête d'activité (nom · [inputs] → [output] · max N)
## - Colonnes suivantes = un slot par perso (dispo à gauche, séparateur, occupés à droite)
## - Cellule = slot MapView-like (sprite + icônes yield en fond)
## - ScrollContainer H+V si la matrice déborde
##
## Signature open() garde popup_position pour compat MapView, mais l'ignore.

const HEX_RADIUS: float = 36.0
const TILE_PROD_ICON_SIZE: int = 14
const WORKER_SPRITE_SCALE: int = 3
const MAX_VISIBLE_COLS: int = 4
const COL_HEADER_MIN_WIDTH: int = 220
const POPUP_HEIGHT_RATIO: float = 0.6

# Couleurs des tuiles copiées de MapView (dette : à unifier en task 2)
const TILE_COLORS := {
	HexTile.Type.BUNKER: Color("#2c2c2c"),
	HexTile.Type.PLAINS: Color("#d4c47a"),
	HexTile.Type.FOREST: Color("#3a6b35"),
	HexTile.Type.MOUNTAIN: Color("#7a5a3a"),
}

var _tile: HexTile

# ──────────────────────────────────────────────────────────────────────────
#  INNER CLASS : slot cliquable avec tooltip riche coloré
# ──────────────────────────────────────────────────────────────────────────
# DETTE : duplique le pattern SurvivorsView.SurvivorSprite (header + trait_lines
# + _make_custom_tooltip). À unifier en task 2 (factorisation SurvivorSprite).

class RichHoverSlot extends Control:
	var header_text: String = ""
	var trait_lines: Array = []

	func _make_custom_tooltip(_for_text):
		var rtl := RichTextLabel.new()
		rtl.bbcode_enabled = true
		rtl.fit_content = true
		rtl.custom_minimum_size = Vector2(320, 0)
		var content: String = header_text
		for line in trait_lines:
			var name_bb := "[color=%s]%s[/color]" % [line.color, line.name]
			if line.description != "":
				content += "\n%s [color=#888888]— %s[/color]" % [name_bb, line.description]
			else:
				content += "\n" + name_bb
		rtl.text = content
		return rtl


# Mapping color_hint → hex (copie SurvivorsView, même dette)
const TRAIT_COLORS := {
	"neutral": "#dddddd",
	"positive": "#7dd68f",
	"negative": "#e08a7a",
	"story": "#c9a3ea",
}

func _hex_polygon_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		var angle: float = deg_to_rad(60.0 * i - 30.0)
		points.append(Vector2(cos(angle), sin(angle)) * HEX_RADIUS)
	return points

static func open(parent: Node, tile: HexTile, _popup_position: Vector2 = Vector2.ZERO) -> TileAssignmentPopup:
	var popup := TileAssignmentPopup.new()
	parent.add_child(popup)
	popup._tile = tile
	popup._build()
	popup.popup_hide.connect(popup.queue_free)
	var target := popup._compute_target_size()
	popup.popup_centered(target)
	popup.size = target
	return popup

func _build() -> void:
	# Fond opaque
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.13, 0.98)
	bg_style.corner_radius_top_left = 6
	bg_style.corner_radius_top_right = 6
	bg_style.corner_radius_bottom_left = 6
	bg_style.corner_radius_bottom_right = 6
	bg_style.content_margin_left = 12
	bg_style.content_margin_right = 12
	bg_style.content_margin_top = 8
	bg_style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", bg_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(vbox)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Header : titre + bouton clear
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = tr("POPUP_TILE_ASSIGN_TITLE") + " — " + UiPresentation.tile_label(_tile.key())
	title.add_theme_font_size_override("font_size", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	if _tile.worker_id != -1:
		var clear_btn := Button.new()
		clear_btn.text = tr("LABEL_CLEAR_TILE")
		clear_btn.pressed.connect(_on_clear_pressed)
		header.add_child(clear_btn)
	vbox.add_child(header)

	var activities: Array = GameState.activity_registry.available_for_tile(_tile.type)
	if activities.is_empty():
		var empty := Label.new()
		empty.text = tr("LABEL_NO_ACTIVITY")
		vbox.add_child(empty)
		return

	# Répartition dispo / occupés (fixe pour tout le popup)
	var available: Array = []
	var occupied: Array = []
	for s in GameState.awake_survivors():
		if _is_available(s):
			available.append(s)
		else:
			occupied.append(s)
	available.sort_custom(func(a, b): return a.name < b.name)
	occupied.sort_custom(func(a, b): return a.name < b.name)

	# Une row par activité, chacune scroll horizontal indépendant.
	for activity in activities:
		vbox.add_child(_activity_row(activity, available, occupied))

func _activity_row(activity: Activity, available: Array, occupied: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Header fixe à gauche (largeur contrainte pour aligner les scrolls entre rows)
	row.add_child(_activity_header(activity))

	# ScrollContainer H uniquement, contenant les slots persos
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var slot_size: int = int(HEX_RADIUS * 2.0)
	scroll.custom_minimum_size = Vector2(0, slot_size + 20)  # +20 pour la scrollbar H
	row.add_child(scroll)

	var slots_hbox := HBoxContainer.new()
	slots_hbox.add_theme_constant_override("separation", 6)
	scroll.add_child(slots_hbox)

	# Meilleur dispo (fond vert)
	var best_yield: int = -1
	var best_id: int = -1
	var yields := {}
	for s in available:
		var y: int = int(GameState.expected_activity_yield(s, _tile, activity))
		yields[s.id] = y
		if y > best_yield:
			best_yield = y
			best_id = s.id
	for s in available:
		var y: int = yields[s.id]
		slots_hbox.add_child(_survivor_slot(s, y, activity, false, s.id == best_id and best_yield > 0))

	# Filtre : masquer les occupés qui font DÉJÀ cette activité ailleurs
	# (les déplacer ne fait qu'annuler leur prod actuelle pour la re-poser ici)
	var relevant_occupied: Array = []
	for s in occupied:
		if s.activity_id != activity.id:
			relevant_occupied.append(s)

	if not relevant_occupied.is_empty() and not available.is_empty():
		slots_hbox.add_child(_vsep_narrow())

	for s in relevant_occupied:
		var y: int = int(GameState.expected_activity_yield(s, _tile, activity))
		slots_hbox.add_child(_survivor_slot(s, y, activity, true, false))
	return row

## Taille cible : largeur pour MAX_VISIBLE_COLS slots + en-tête activité,
## hauteur adaptée au nombre d'activités de la tuile (une row par activité).
## Cap à 90% de l'écran comme filet de sécurité.
func _compute_target_size() -> Vector2i:
	var slot_size: int = int(HEX_RADIUS * 2.0)
	var slot_actual: int = slot_size
	var h_sep: int = 6
	var margins_and_scrollbar: int = 48
	var width: int = COL_HEADER_MIN_WIDTH + MAX_VISIBLE_COLS * slot_actual + (MAX_VISIBLE_COLS - 1) * h_sep + margins_and_scrollbar

	var activities: Array = GameState.activity_registry.available_for_tile(_tile.type)
	var n_rows: int = max(1, activities.size())
	var row_height: int = slot_size + 20  # +20 scrollbar H
	var v_sep: int = 8
	var header_and_margins_v: int = 60
	var height: int = header_and_margins_v + n_rows * row_height + (n_rows - 1) * v_sep

	return Vector2i(width, height)

func _vsep_narrow() -> Control:
	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(4, 20)
	return sep

func _activity_header(activity: Activity) -> Control:
	var m: int = GameState.best_yield_all_survivors(activity)
	var risky_suffix := ""
	if activity.success_rate < 1.0:
		risky_suffix = ", %d%%" % int(activity.success_rate * 100)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = tr(activity.name_key)
	name_label.add_theme_font_size_override("font_size", 13)
	row.add_child(name_label)

	row.add_child(_muted_label("·"))
	if not activity.inputs.is_empty():
		for res_name in activity.inputs:
			var qty: int = int(activity.inputs[res_name])
			for i in qty:
				row.add_child(UiPresentation.resource_icon(res_name, TILE_PROD_ICON_SIZE))
		row.add_child(_muted_label("→"))
	row.add_child(UiPresentation.resource_icon(activity.produced_resource, TILE_PROD_ICON_SIZE))

	var meta := Label.new()
	meta.text = "  (%s %d%s)" % [tr("LABEL_MAX"), m, risky_suffix]
	meta.add_theme_font_size_override("font_size", 11)
	meta.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	row.add_child(meta)
	row.custom_minimum_size = Vector2(COL_HEADER_MIN_WIDTH, 0)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return row

func _survivor_slot(s: Survivor, y: int, activity: Activity, is_occupied: bool, is_best: bool) -> Control:
	var tile_bbox: float = HEX_RADIUS * 2.0
	var slot := RichHoverSlot.new()
	slot.custom_minimum_size = Vector2(tile_bbox, tile_bbox)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slot.header_text = _survivor_header_text(s)
	slot.trait_lines = _build_trait_lines(s)
	slot.tooltip_text = " "  # hack Godot : nécessite un texte non-vide pour activer _make_custom_tooltip

	var center: Vector2 = Vector2(tile_bbox * 0.5, tile_bbox * 0.5)

	# Hex de fond, couleur de la tuile (teinté vert pour meilleur candidat)
	var hex := Polygon2D.new()
	hex.polygon = _hex_polygon_points()
	hex.color = TILE_COLORS.get(_tile.type, Color.GRAY)
	hex.position = center
	if is_best and not is_occupied:
		hex.modulate = Color(1.3, 1.7, 1.3)  # teinte verte
	slot.add_child(hex)

	# Icônes de prod (copie fidèle MapView non-risky)
	var icons_row := HBoxContainer.new()
	icons_row.alignment = BoxContainer.ALIGNMENT_CENTER
	icons_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var separation: int = 0
	if y > 3:
		var target_width: float = 3.0 * TILE_PROD_ICON_SIZE
		var needed_width: float = y * TILE_PROD_ICON_SIZE
		separation = int(-((needed_width - target_width) / max(1, y - 1)))
	icons_row.add_theme_constant_override("separation", separation)
	for i in max(0, y):
		icons_row.add_child(UiPresentation.resource_icon(activity.produced_resource, TILE_PROD_ICON_SIZE))
	icons_row.size = Vector2(HEX_RADIUS * 2.0, TILE_PROD_ICON_SIZE)
	icons_row.position = center - Vector2(HEX_RADIUS, HEX_RADIUS * 0.7)
	slot.add_child(icons_row)

	# Sprite par-dessus
	var sprite := TextureRect.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var prof := Roster.get_profession(s.profession)
	if prof != null and prof.sprite != null:
		sprite.texture = prof.sprite
	else:
		sprite.texture = load(UiPresentation.SURVIVOR_SPRITE_PATH % s.sprite_variant)
	var tex_size: Vector2 = (sprite.texture as Texture2D).get_size()
	var sprite_size: Vector2 = tex_size * WORKER_SPRITE_SCALE
	sprite.size = sprite_size
	sprite.position = center - sprite_size * 0.5 + Vector2(0, HEX_RADIUS * 0.15)
	slot.add_child(sprite)

	if is_occupied:
		slot.modulate = Color(1, 1, 1, 0.55)

	var sid := s.id
	var aid := activity.id
	slot.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_activity_selected(sid, aid))
	return slot

## Copie du header text de SurvivorsView._add_row (pattern BBCode).
func _survivor_header_text(s: Survivor) -> String:
	var location: String
	if s.tile_key != "":
		location = tr("LABEL_AT_TILE") + UiPresentation.tile_label(s.tile_key)
	elif s.building_id != "":
		var b: Building = GameState._find_building_by_type(s.building_id)
		if b != null:
			location = tr("LABEL_AT_TILE") + tr(b.config.name_key) + " " + tr("LABEL_IN_SETTLEMENT_BRACKETS")
		else:
			location = tr("LABEL_IN_SETTLEMENT")
	else:
		location = tr("LABEL_IDLE_IN_SETTLEMENT")

	var role: String = UiPresentation.activity(s)
	var prod := _format_output(s)

	var header := "[b]%s[/b] (%s)\n%s — %s" % [
		s.name,
		Roster.display_name(s.profession),
		role,
		location,
	]
	if prod != "":
		header += "\n\n→ " + prod
	return header

func _build_trait_lines(s: Survivor) -> Array:
	var ordered_categories := [
		TraitConfig.Category.STATE,
		TraitConfig.Category.NATURE,
		TraitConfig.Category.EVENT,
	]
	var lines: Array = []
	for cat in ordered_categories:
		for t in s.traits:
			if t.category != cat:
				continue
			var color: String = TRAIT_COLORS.get(t.color_hint, "#dddddd")
			var desc: String = tr(t.description_key) if t.description_key != "" else ""
			lines.append({
				"name": tr(t.name_key),
				"description": desc,
				"color": color,
			})
	return lines

func _format_output(s: Survivor) -> String:
	var out: Dictionary = GameState.get_survivor_output(s)
	if out.is_empty():
		return ""
	var parts: Array[String] = []
	for resource_name in out:
		parts.append("+%.0f %s" % [out[resource_name], resource_name])
	return ", ".join(parts)

func _muted_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	return l

func _is_available(s: Survivor) -> bool:
	if s.tile_key == _tile.key():
		return true
	return s.tile_key == "" and s.building_id == ""

func _current_activity_context(s: Survivor) -> String:
	if s.tile_key != "":
		return UiPresentation.activity(s) + " @ " + UiPresentation.tile_label(s.tile_key)
	if s.building_id != "":
		var b: Building = GameState._find_building_by_type(s.building_id)
		if b != null:
			return UiPresentation.activity_for_building(b.config.id) + " @ " + tr(b.config.name_key)
	return tr("LABEL_IDLE")

func _on_clear_pressed() -> void:
	if _tile.worker_id != -1:
		GameState.unassign_from_tile(_tile.worker_id)
	hide()

func _on_activity_selected(survivor_id: int, activity_id: String) -> void:
	GameState.assign_activity(survivor_id, activity_id)
	GameState.assign_to_tile(survivor_id, _tile.key())
	hide()
