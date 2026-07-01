extends Control
class_name SurvivorsView
## Liste des survivants éveillés : un sprite par survivant, triés par ordre
## de réveil chronologique. Tooltip riche sur hover : rôle, location, prod, traits.
##
## Lecture seule, pas d'input. S'abonne directement aux signals qui peuvent
## affecter le contenu ou les tooltips.

# ──────────────────────────────────────────────────────────────────────────
#  INNER CLASS : sprite avec tooltip riche coloré
# ──────────────────────────────────────────────────────────────────────────
# DETTE : duplique la logique de chargement de sprite avec UiPresentation.
# À factoriser au moment du chantier UI Colonization (survivor_sprite doit
# accepter un mode "rich tooltip" en paramètre).

class SurvivorSprite extends TextureRect:
	var header_text: String = ""
	var trait_lines: Array = []  # [{text: String, color: String}]

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


const SURVIVOR_SPRITE_PATH := "res://assets/survivors/generic%d.png"
const SPRITE_SCALE: int = 4

# Mapping color_hint sémantique → couleur RichText
const TRAIT_COLORS := {
	"neutral": "#dddddd",
	"positive": "#7dd68f",
	"negative": "#e08a7a",
	"story": "#c9a3ea",
}

var _header: Label
var _list: HBoxContainer

func _ready() -> void:
	_build()
	GameState.turn_advanced.connect(_rebuild)
	GameState.survivor_woken.connect(_rebuild)
	GameState.survivor_assigned.connect(_rebuild)
	GameState.tile_assignment_changed.connect(_rebuild)
	GameState.building_assignment_changed.connect(_rebuild)
	GameState.nightly_deaths.connect(_rebuild)
	_rebuild()

func _build() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	_header = Label.new()
	_header.text = tr("LABEL_AWAKE") % 0
	vbox.add_child(_header)

	_list = HBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	vbox.add_child(_list)

## Signature tolérante pour absorber les divers payloads des signals branchés.
func _rebuild(_a = null, _b = null, _c = null, _d = null) -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	var awake_sorted: Array[Survivor] = []
	for s in GameState.survivors():
		if s.awake:
			awake_sorted.append(s)
	awake_sorted.sort_custom(func(a, b): return a.wake_order < b.wake_order)
	for s in awake_sorted:
		_add_row(s)
	_header.text = tr("LABEL_AWAKE") % awake_sorted.size()
	if awake_sorted.is_empty():
		var empty := Label.new()
		empty.text = tr("LABEL_NOBODY_AWAKE")
		_list.add_child(empty)

func _add_row(s: Survivor) -> void:
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

	# Sprite avec tooltip riche
	var sprite := SurvivorSprite.new()
	sprite.texture = _load_survivor_texture(s)
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tex_size: Vector2 = (sprite.texture as Texture2D).get_size()
	sprite.custom_minimum_size = tex_size * SPRITE_SCALE
	sprite.mouse_filter = Control.MOUSE_FILTER_STOP
	sprite.header_text = header
	sprite.trait_lines = _build_trait_lines(s)
	sprite.tooltip_text = " "
	_list.add_child(sprite)

func _load_survivor_texture(s: Survivor) -> Texture2D:
	var prof := Roster.get_profession(s.profession)
	if prof != null and prof.sprite != null:
		return prof.sprite
	return load(SURVIVOR_SPRITE_PATH % s.sprite_variant)

## Construit la liste des lignes de traits pour le tooltip.
## Ordre : STATE d'abord, puis NATURE, puis EVENT.
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

## Texte compact de l'output du survivant pour le tooltip.
func _format_output(s: Survivor) -> String:
	var out: Dictionary = GameState.get_survivor_output(s)
	if out.is_empty():
		return ""
	var parts: Array[String] = []
	for resource_name in out:
		parts.append("+%.0f %s" % [out[resource_name], resource_name])
	return ", ".join(parts)
