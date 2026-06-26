extends Control
class_name ResourcesBar
## Barre des stocks de ressources en bas d'écran : food / wood / ore / tools.
## Scrollable horizontalement pour accueillir d'autres ressources plus tard.
## Lecture seule. Affiche les ressources stockables uniquement — l'électricité
## et la heat (flux par tour, pas stocks) vivent dans InfosSection.

const RESOURCE_ORDER: Array[String] = ["food", "wood", "ore", "tools"]

var _bar: HBoxContainer

func _ready() -> void:
	_build()
	GameState.resources_changed.connect(_rebuild)
	_rebuild()

func _build() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_bar = HBoxContainer.new()
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.add_theme_constant_override("separation", 24)
	scroll.add_child(_bar)

## Signature tolérante pour absorber le payload de resources_changed.
func _rebuild(_a = null, _b = null, _c = null, _d = null) -> void:
	if _bar == null:
		return
	for child in _bar.get_children():
		child.queue_free()
	for resource_name in RESOURCE_ORDER:
		_bar.add_child(_make_pill(resource_name))

func _make_pill(resource_name: String) -> HBoxContainer:
	var pill := HBoxContainer.new()
	pill.add_theme_constant_override("separation", 6)
	pill.tooltip_text = UiPresentation.resource(resource_name)
	pill.add_child(UiPresentation.resource_icon(resource_name, UiPresentation.RESOURCE_SPRITE_SIZE))
	# Valeur
	var value: float = GameState.resources.get(resource_name, 0.0)
	var label := Label.new()
	label.text = "%.0f" % value
	label.add_theme_font_size_override("font_size", 16)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pill.add_child(label)
	return pill
