extends Control
class_name CryoView
## Vue du slot cryogénique : présente le pool de candidats à réveiller (sprites
## inclinés représentant les chambres) et le compteur de cryogénisés restants.
## Le panel et le style "slot bunker" sont créés par MainUi qui instancie
## cette vue dedans.
##
## NB : la recherche ciblée vit ailleurs (popup du Computer), pas ici.
## Évolution prévue : sprites de chambres en arrière-plan, overlay sur les
## personnages — le Control racine est volontairement laissé libre pour
## accueillir des layers visuels supplémentaires.

const CANDIDATE_SPRITE_ROTATION_DEG: float = -75.0

var _sprites_row: HBoxContainer
var _count_label: Label

var _building: Building

func setup(b: Building) -> void:
	_building = b
	# Pas d'usage spécifique du building pour l'instant (CryoView lit GameState
	# pour le pool de candidats), mais on stocke pour cohérence future.

func _ready() -> void:
	_build()
	GameState.candidates_changed.connect(_rebuild)
	GameState.turn_advanced.connect(_rebuild)
	GameState.resources_changed.connect(_rebuild)
	GameState.survivor_woken.connect(_rebuild)
	GameState.nightly_deaths.connect(_rebuild)
	_rebuild()

func _build() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	var title := Label.new()
	title.text = tr("BUILDING_CRYO_ROOM")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	vbox.add_child(title)

	_sprites_row = HBoxContainer.new()
	_sprites_row.add_theme_constant_override("separation", 4)
	_sprites_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_sprites_row)

	_count_label = Label.new()
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.add_theme_font_size_override("font_size", 12)
	_count_label.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(_count_label)

## Signature tolérante pour absorber les divers payloads des signals branchés.
func _rebuild(_a = null, _b = null, _c = null, _d = null) -> void:
	if _sprites_row == null:
		return
	for child in _sprites_row.get_children():
		child.queue_free()
	for cid in GameState.candidates:
		var s: Survivor = GameState.roster.get_by_id(cid)
		if s == null:
			continue
		_sprites_row.add_child(_make_candidate_card(s))
	_count_label.text = tr("LABEL_STILL_IN_CRYO") % GameState.roster.sleeping_count()

func _make_candidate_card(s: Survivor) -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	# Sprite couché (rotation pour évoquer la chambre cryo)
	var sprite := SurvivorSpriteWidget.new()
	sprite.setup(s)
	sprite.pivot_offset = sprite.custom_minimum_size * 0.5
	sprite.rotation = deg_to_rad(CANDIDATE_SPRITE_ROTATION_DEG)
	var sprite_wrap := Control.new()
	sprite_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sprite_wrap.custom_minimum_size = sprite.custom_minimum_size
	sprite_wrap.add_child(sprite)
	vbox.add_child(sprite_wrap)
	# Bouton wake dessous
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.text = tr("BTN_WAKE_SHORT")
	btn.disabled = not GameState.can_wake(s.id)
	var sid := s.id
	btn.pressed.connect(func(): GameState.wake(sid))
	vbox.add_child(btn)
	return vbox
