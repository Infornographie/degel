extends TextureRect
class_name SurvivorSpriteWidget
## Sprite d'un survivant avec tooltip riche BBCode, badge d'état (fatigue),
## et optionnellement une action au clic. Centralise le rendu partagé entre
## SurvivorsView, MapView, ColonyView (bâtiments), CryoView, TileAssignmentPopup.
##
## Contrat : `setup()` à appeler UNE fois après `new()`. Pour rafraîchir,
## queue_free + recréer.
##
## La fonction statique `build_rich_tooltip(s, click_hint_key)` peut aussi
## être appelée par d'autres Controls (ex: slot hexagonal du popup
## d'affectation) qui veulent le même tooltip sur une zone plus large que
## le sprite. Une seule logique de tooltip pour tous les callers.

signal clicked(survivor_id: int)

const SURVIVOR_SPRITE_PATH := "res://assets/survivors/generic%d.png"
const BADGE_RATIO: float = 0.35

const TRAIT_COLORS := {
	"neutral": "#dddddd",
	"positive": "#7dd68f",
	"negative": "#e08a7a",
	"story": "#c9a3ea",
}

var _survivor: Survivor
var _click_hint_key: String = ""


func setup(
	s: Survivor,
	sprite_scale: int = 4,
	capture_clicks: bool = false,
	click_hint_key: String = "",
) -> void:
	_survivor = s
	_click_hint_key = click_hint_key

	texture = _load_survivor_texture(s)
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tex_size: Vector2 = (texture as Texture2D).get_size()
	custom_minimum_size = tex_size * sprite_scale

	if capture_clicks:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		gui_input.connect(_on_gui_input)
	else:
		mouse_filter = Control.MOUSE_FILTER_PASS

	tooltip_text = " "  # nécessaire pour déclencher _make_custom_tooltip

	if s.has_trait(&"tired"):
		_add_state_badge(s.get_trait(&"tired"), custom_minimum_size)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(_survivor.id)


static func _load_survivor_texture(s: Survivor) -> Texture2D:
	var prof := Roster.get_profession(s.profession)
	if prof != null and prof.sprite != null:
		return prof.sprite
	return load(SURVIVOR_SPRITE_PATH % s.sprite_variant)


## Construit un RichTextLabel BBCode prêt à servir de tooltip Godot.
## Statique — utilisée par le widget dans `_make_custom_tooltip`, mais aussi
## par d'autres Controls qui veulent le même tooltip sur une zone plus large.
static func build_rich_tooltip(s: Survivor, click_hint_key: String = "") -> Control:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.custom_minimum_size = Vector2(320, 0)
	var content: String = _build_header_text(s)
	for line in _build_trait_lines(s):
		var name_bb := "[color=%s]%s[/color]" % [line.color, line.name]
		if line.description != "":
			content += "\n%s [color=#888888]— %s[/color]" % [name_bb, line.description]
		else:
			content += "\n" + name_bb
	if click_hint_key != "":
		content += "\n\n[color=#888888]" + TranslationServer.translate(click_hint_key) + "[/color]"
	rtl.text = content
	return rtl


## Header BBCode. Dégradé à nom+profession seul si colon endormi (cryo).
static func _build_header_text(s: Survivor) -> String:
	if not s.awake:
		return "[b]%s[/b] (%s)" % [s.name, Roster.display_name(s.profession)]
	var location: String
	if s.tile_key != "":
		location = TranslationServer.translate("LABEL_AT_TILE") + UiPresentation.tile_label(s.tile_key)
	elif s.building_id != "":
		var b: Building = GameState._find_building_by_type(s.building_id)
		if b != null:
			location = TranslationServer.translate("LABEL_AT_TILE") + TranslationServer.translate(b.config.name_key) + " " + TranslationServer.translate("LABEL_IN_SETTLEMENT_BRACKETS")
		else:
			location = TranslationServer.translate("LABEL_IN_SETTLEMENT")
	else:
		location = TranslationServer.translate("LABEL_IDLE_IN_SETTLEMENT")

	var role: String = UiPresentation.activity(s)
	var header := "[b]%s[/b] (%s)\n%s — %s" % [
		s.name,
		Roster.display_name(s.profession),
		role,
		location,
	]
	var prod := _format_output(s)
	if prod != "":
		header += "\n\n→ " + prod
	return header


static func _format_output(s: Survivor) -> String:
	var out: Dictionary = GameState.get_survivor_output(s)
	if out.is_empty():
		return ""
	var parts: Array[String] = []
	for resource_name in out:
		parts.append("+%.0f %s" % [out[resource_name], resource_name])
	return ", ".join(parts)


static func _build_trait_lines(s: Survivor) -> Array:
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
			var desc: String = ""
			if t.description_key != "":
				desc = TranslationServer.translate(t.description_key)
			lines.append({
				"name": TranslationServer.translate(t.name_key),
				"description": desc,
				"color": color,
			})
	return lines


func _add_state_badge(t: TraitConfig, widget_size: Vector2) -> void:
	var badge_size: float = widget_size.x * BADGE_RATIO
	var badge: Control
	if t.icon != null:
		var icon := TextureRect.new()
		icon.texture = t.icon
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge = icon
	else:
		var placeholder := ColorRect.new()
		match t.color_hint:
			"positive": placeholder.color = Color(0.4, 1.0, 0.4, 0.7)
			"negative": placeholder.color = Color(1.0, 0.7, 0.2, 0.75)
			"story":    placeholder.color = Color(0.79, 0.63, 0.92, 0.7)
			_:          placeholder.color = Color(1.0, 1.0, 1.0, 0.55)
		badge = placeholder
	badge.custom_minimum_size = Vector2(badge_size, badge_size)
	badge.size = Vector2(badge_size, badge_size)
	badge.position = Vector2(widget_size.x - badge_size, 0)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.tooltip_text = tr(t.name_key)
	add_child(badge)


func _make_custom_tooltip(_for_text: String) -> Control:
	return build_rich_tooltip(_survivor, _click_hint_key)
