extends Control
class_name InfosSection
## Petit panneau d'infos en haut à gauche : tour courant, état de l'électricité
## (réacteur, conso synthé, usable), label de famine si en cours.
##
## Lecture seule, pas d'input. S'abonne directement aux signals de GameState
## qui peuvent affecter ce qui est affiché.

var _infos: VBoxContainer
var _famine_label: Label

func _ready() -> void:
	_build()
	GameState.turn_advanced.connect(_rebuild)
	GameState.resources_changed.connect(_rebuild)
	GameState.famine_started.connect(_rebuild)
	GameState.famine_ended.connect(_rebuild)
	GameState.building_assignment_changed.connect(_rebuild)
	_rebuild()

func _build() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	_infos = VBoxContainer.new()
	vbox.add_child(_infos)

	_famine_label = Label.new()
	_famine_label.text = ""
	vbox.add_child(_famine_label)

## Signature tolérante pour absorber les divers payloads des signals branchés.
func _rebuild(_a = null, _b = null, _c = null, _d = null) -> void:
	if _infos == null:
		return
	for child in _infos.get_children():
		child.queue_free()
	# Tour
	var turn_label := Label.new()
	turn_label.text = tr("LABEL_TURN") % GameState.turn
	_infos.add_child(turn_label)
	# Bloc électricité
	var elec_value: float = GameState.resources["electricity"]
	var elec_parts: Array[String] = []
	elec_parts.append(tr("LABEL_REACTOR") % GameState.reactor_output)
	var synth: Building = GameState._find_building_by_type("synthesizer")
	if synth != null and synth.active:
		elec_parts.append(tr("LABEL_SYNTH_COST") % GameState.SYNTH_ELECTRICITY_COST)
	elec_parts.append(tr("LABEL_USABLE") % elec_value)
	var elec_label := Label.new()
	elec_label.text = tr("LABEL_ELEC_HEADER") + " | ".join(elec_parts)
	_infos.add_child(elec_label)
	# Label famine (vide si pas en famine)
	if GameState.famine_turns > 0:
		_famine_label.text = tr("LABEL_FAMINE") % GameState.famine_turns
	else:
		_famine_label.text = ""
