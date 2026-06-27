extends Control
class_name InfosSection
## Panneau d'infos en haut à gauche :
## - Bloc état : tour courant, électricité, label famine si en cours
## - Journal d'événements scrollable, alimenté en streaming via event_logged
##
## Le journal affiche tout l'historique. Auto-scroll vers le bas à chaque
## nouvel événement (pattern chat). L'utilisateur peut scroller vers le haut
## pour consulter le passé.

const TURN_PREFIX_KEY := "LABEL_EVENT_TURN_PREFIX"

# Teinte légère par catégorie pour aider la lecture.
const CATEGORY_COLOR := {
	"loss": Color(1.0, 0.55, 0.55),
	"system": Color(0.75, 0.75, 0.75),
	"colony": Color.WHITE,
}

var _infos: VBoxContainer
var _famine_label: Label
var _journal_scroll: ScrollContainer
var _journal_lines: VBoxContainer

func _ready() -> void:
	_build()
	GameState.turn_advanced.connect(_rebuild)
	GameState.resources_changed.connect(_rebuild)
	GameState.famine_started.connect(_rebuild)
	GameState.famine_ended.connect(_rebuild)
	GameState.building_assignment_changed.connect(_rebuild)
	GameState.event_logged.connect(_on_event_logged)
	_rebuild()
	_load_journal_history()

func _build() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	# Bloc état (tour + élec)
	_infos = VBoxContainer.new()
	vbox.add_child(_infos)

	# Famine (vide si pas en famine)
	_famine_label = Label.new()
	_famine_label.text = ""
	vbox.add_child(_famine_label)

	vbox.add_child(HSeparator.new())

	# Titre journal
	var journal_title := Label.new()
	journal_title.text = tr("LABEL_EVENT_LOG_TITLE")
	journal_title.add_theme_font_size_override("font_size", 13)
	vbox.add_child(journal_title)

	# Zone scrollable : prend tout le reste de l'espace
	_journal_scroll = ScrollContainer.new()
	_journal_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_journal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_journal_scroll)

	_journal_lines = VBoxContainer.new()
	_journal_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal_scroll.add_child(_journal_lines)

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
		var synth_elec_cost: float = synth.config.inputs.get("electricity", 0.0)
		elec_parts.append(tr("LABEL_SYNTH_COST") % synth_elec_cost)
	elec_parts.append(tr("LABEL_USABLE") % elec_value)
	var elec_label := Label.new()
	elec_label.text = tr("LABEL_ELEC_HEADER") + " | ".join(elec_parts)
	_infos.add_child(elec_label)
	# Label famine
	if GameState.famine_turns > 0:
		_famine_label.text = tr("LABEL_FAMINE") % GameState.famine_turns
	else:
		_famine_label.text = ""

# ── Journal ──

## Charge l'historique présent dans GameState.event_log au moment du build.
## Au démarrage normal, log vide. En cas de reload de scène en cours de partie,
## récupère ce qui a déjà été loggé.
func _load_journal_history() -> void:
	for ev in GameState.event_log:
		_append_line(ev)
	_scroll_to_bottom()

func _on_event_logged(ev: GameEvent) -> void:
	_append_line(ev)
	_scroll_to_bottom()

func _append_line(ev: GameEvent) -> void:
	var label := Label.new()
	label.text = "%s %s" % [tr(TURN_PREFIX_KEY) % ev.turn, ev.format()]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 11)
	if CATEGORY_COLOR.has(ev.category):
		label.modulate = CATEGORY_COLOR[ev.category]
	_journal_lines.add_child(label)

## Le max_value de la scrollbar n'est mis à jour qu'au frame suivant l'ajout
## d'un enfant. D'où l'attente d'un frame avant de descendre.
func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	var sb := _journal_scroll.get_v_scroll_bar()
	_journal_scroll.scroll_vertical = int(sb.max_value)
