extends Control
class_name SynthesizerView
## Vue du bâtiment Synthétiseur : checkbox on/off + info statique.
## Le sprite et l'évolution graphique du synthé arriveront avec les assets.

var _building: Building

func setup(b: Building) -> void:
	_building = b
	_build()
	GameState.building_assignment_changed.connect(_rebuild)
	GameState.resources_changed.connect(_rebuild)

func _build() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)
	vbox.add_child(UiPresentation.slot_title(tr(_building.config.name_key)))

	var checkbox := CheckBox.new()
	checkbox.text = tr("LABEL_SYNTH_RUNNING")
	checkbox.set_pressed_no_signal(_building.active)
	var bid := _building.instance_id
	checkbox.toggled.connect(func(pressed: bool):
		var b := GameState._find_building_by_instance(bid)
		if b != null:
			b.active = pressed
			GameState.building_assignment_changed.emit())
	vbox.add_child(checkbox)

	var info := Label.new()
	info.text = tr("LABEL_SYNTH_INFO")
	info.add_theme_font_size_override("font_size", 9)
	info.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(info)

## Signature tolérante. Pour l'instant, le rebuild est rare et la vue ne se
## reconstruit pas réellement — la checkbox est suivie via son state. À élargir
## quand la vue affichera plus (production en cours, etc.).
func _rebuild(_a = null, _b = null, _c = null, _d = null) -> void:
	pass
