extends TextureRect
class_name SurvivorSpriteWidget
## Sprite d'un survivant avec tooltip riche BBCode, badge d'état (fatigue),
## et optionnellement une action au clic. Centralise le rendu partagé entre
## SurvivorsView, MapView, ColonyView (bâtiments), CryoView, TileAssignmentPopup.
##
## Contrat : `setup()` à appeler UNE fois après `new()`. Pour rafraîchir,
## queue_free + recréer (pattern rebuild-on-signal du reste du codebase).
##
## Usage minimal :
##   var w := SurvivorSpriteWidget.new()
##   w.setup(survivor)
##   parent.add_child(w)
##
## Usage cliquable (ex: désassigner d'un bâtiment) :
##   w.setup(s, 4, true, "TOOLTIP_CLICK_TO_UNASSIGN")
##   w.clicked.connect(func(sid): GameState.unassign_from_building(sid))

signal clicked(survivor_id: int)

const SURVIVOR_SPRITE_PATH := "res://assets/survivors/generic%d.png"
## Taille du badge d'état relative à la taille du sprite rendu.
const BADGE_RATIO: float = 0.35

## Mapping color_hint sémantique → couleur BBCode.
const TRAIT_COLORS := {
	"neutral": "#dddddd",
	"positive": "#7dd68f",
	"negative": "#e08a7a",
	"story": "#c9a3ea",
}

# État interne rempli par setup()
var _survivor: Survivor
var _header_text: String = ""
var _trait_lines: Array = []    # [{name, description, color}]
var _click_hint_key: String = ""


## Configure et rend le widget.
##
## - `s` : survivant à afficher
## - `sprite_scale` : facteur d'échelle du pixel art. Défaut 4 (colony, roster,
##   cryo). MapView et TileAssignmentPopup utilisent 3.
## - `capture_clicks` : `true` → mouse_filter STOP, curseur pointeur, émet
##   `clicked` au clic gauche. `false` (défaut) → PASS, tooltip actif mais
##   le clic file au parent (cas MapView, TileAssignmentPopup).
## - `click_hint_key` : clé i18n ajoutée en bas du tooltip pour indiquer
##   l'action au clic. Décoratif — la connexion à `clicked` reste au caller.
func setup(
	s: Survivor,
	sprite_scale: int = 4,
	capture_clicks: bool = false,
	click_hint_key: String = "",
) -> void:
	_survivor = s
	_click_hint_key = click_hint_key

	# 1) Sprite (profession si dispo, fallback générique via sprite_variant)
	texture = _load_survivor_texture(s)
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tex_size: Vector2 = (texture as Texture2D).get_size()
	custom_minimum_size = tex_size * sprite_scale

	# 2) Mouse handling
	if capture_clicks:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		gui_input.connect(_on_gui_input)
	else:
		mouse_filter = Control.MOUSE_FILTER_PASS

	# 3) Tooltip riche (pré-calculé une fois — le survivant ne mute pas
	# pendant la durée de vie du widget, on rebuild via signal si besoin).
	# Godot n'appelle _make_custom_tooltip que si tooltip_text est non-vide.
	_header_text = _build_header_text(s)
	_trait_lines = _build_trait_lines(s)
	tooltip_text = " "

	# 4) Badge d'état (fatigue pour l'instant, extensible)
	if s.has_trait(&"tired"):
		_add_state_badge(s.get_trait(&"tired"), custom_minimum_size)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(_survivor.id)


## Charge le sprite : profession spécifique si dispo, fallback générique.
func _load_survivor_texture(s: Survivor) -> Texture2D:
	var prof := Roster.get_profession(s.profession)
	if prof != null and prof.sprite != null:
		return prof.sprite
	return load(SURVIVOR_SPRITE_PATH % s.sprite_variant)


## Header BBCode : nom, profession, rôle, location, prod si non nulle.
## Pour un colon endormi (cryo), on ne garde que nom + profession.
func _build_header_text(s: Survivor) -> String:
	if not s.awake:
		return "[b]%s[/b] (%s)" % [s.name, Roster.display_name(s.profession)]
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


## Ligne compacte de production, ex : "+4 food, +1 wood".
func _format_output(s: Survivor) -> String:
	var out: Dictionary = GameState.get_survivor_output(s)
	if out.is_empty():
		return ""
	var parts: Array[String] = []
	for resource_name in out:
		parts.append("+%.0f %s" % [out[resource_name], resource_name])
	return ", ".join(parts)


## Trait lines pour le tooltip. Ordre STATE → NATURE → EVENT, coloré par
## color_hint sémantique.
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


## Ajoute un badge d'état en coin haut-droit du sprite. Icône du trait si
## définie, sinon fallback ColorRect coloré selon color_hint (cohérent avec
## le pattern production_icon d'UiPresentation).
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
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE  # ne pas voler le hover parent
	badge.tooltip_text = tr(t.name_key)  # petit tooltip système sur le badge (nom du trait)
	add_child(badge)


## Godot appelle ceci quand le tooltip est déclenché (tooltip_text non-vide).
## On renvoie un RichTextLabel BBCode à la place du tooltip système simple.
func _make_custom_tooltip(_for_text: String) -> Control:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.custom_minimum_size = Vector2(320, 0)
	var content: String = _header_text
	for line in _trait_lines:
		var name_bb := "[color=%s]%s[/color]" % [line.color, line.name]
		if line.description != "":
			content += "\n%s [color=#888888]— %s[/color]" % [name_bb, line.description]
		else:
			content += "\n" + name_bb
	if _click_hint_key != "":
		content += "\n\n[color=#888888]" + tr(_click_hint_key) + "[/color]"
	rtl.text = content
	return rtl
