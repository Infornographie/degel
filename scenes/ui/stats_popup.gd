extends PopupPanel
class_name StatsPopup
## Écran de statistiques de la partie, construit à partir du Chronicle.
## Lecture seule — agrège les faits et snapshots pour l'affichage.
## Sert aussi de vue de contrôle du journal (on voit ce qui s'enregistre).

const MIN_WIDTH := 450
const MARGIN := 20

static func show_stats(parent: Node) -> void:
	var instance := StatsPopup.new()
	parent.add_child(instance)
	instance._build()
	instance.popup_centered()

func _build() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", MARGIN)
	margin.add_theme_constant_override("margin_right", MARGIN)
	margin.add_theme_constant_override("margin_top", MARGIN)
	margin.add_theme_constant_override("margin_bottom", MARGIN)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title_label := Label.new()
	title_label.text = tr("STATS_TITLE")
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title_label)

	vbox.add_child(HSeparator.new())

	# Courbes de stocks (Chronicle)
	var chart_header := Label.new()
	chart_header.text = tr("STATS_SECTION_CHART")
	chart_header.add_theme_font_size_override("font_size", 14)
	vbox.add_child(chart_header)
	vbox.add_child(ResourceChart.new())

	vbox.add_child(HSeparator.new())

	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.text = _compose_stats()
	body.fit_content = true
	body.scroll_active = false
	body.custom_minimum_size.x = MIN_WIDTH
	vbox.add_child(body)

	var close_btn := Button.new()
	close_btn.text = tr("BTN_CLOSE")
	close_btn.pressed.connect(queue_free)
	vbox.add_child(close_btn)

func _compose_stats() -> String:
	var c: Chronicle = GameState.chronicle
	var sections: Array[String] = []

	# ── Réveils ──
	var wakes: int = c.count_of(&"wake")
	var targeted: int = c.count_of(&"targeted_wake")
	var targeted_failed: int = c.count_of(&"targeted_wake_failed")
	var lines: Array[String] = []
	lines.append(tr("STATS_WAKES") % (wakes + targeted))
	if targeted + targeted_failed > 0:
		lines.append(tr("STATS_TARGETED_WAKES") % [targeted, targeted_failed])
	sections.append(_section(tr("STATS_SECTION_WAKES"), lines))

	# ── Pertes ──
	var starved: int = 0
	var switched_off: int = 0
	for f in c.facts_of(&"death"):
		if f.data.get("cause", "") == "starved":
			starved += 1
		else:
			switched_off += 1
	var famines: int = c.count_of(&"famine_started")
	lines = []
	lines.append(tr("STATS_DEATHS_STARVED") % starved)
	lines.append(tr("STATS_DEATHS_SWITCHED_OFF") % switched_off)
	lines.append(tr("STATS_FAMINES") % famines)
	sections.append(_section(tr("STATS_SECTION_LOSSES"), lines))

	# ── Chantiers ──
	lines = []
	lines.append(tr("STATS_CONSTRUCTIONS") % [
		c.count_of(&"construction_completed"), c.count_of(&"construction_started")])
	sections.append(_section(tr("STATS_SECTION_CONSTRUCTION"), lines))

	# ── Écologie ──
	var defo_facts: Array[Dictionary] = c.facts_of(&"deforestation")
	lines = []
	lines.append(tr("STATS_DEFORESTATIONS") % defo_facts.size())
	# Regroupement par acteur
	var by_actor: Dictionary = {}
	for f in defo_facts:
		by_actor[f.actor_id] = by_actor.get(f.actor_id, 0) + 1
	for actor_id in by_actor:
		lines.append("    %s : %d" % [_survivor_name(actor_id), by_actor[actor_id]])
	sections.append(_section(tr("STATS_SECTION_ECOLOGY"), lines))

	# ── Activités (tours travaillés) ──
	var totals: Dictionary = c.activity_totals()
	lines = []
	if totals.is_empty():
		lines.append(tr("STATS_NO_ACTIVITY"))
	else:
		for activity_id in totals:
			lines.append("%s : %d" % [_activity_label(activity_id), totals[activity_id]])
		# Détail par survivant
		var by_survivor: Dictionary = c.activity_totals_by_survivor()
		for survivor_id in by_survivor:
			var per: Dictionary = by_survivor[survivor_id]
			var parts: Array[String] = []
			for activity_id in per:
				parts.append("%s %d" % [_activity_label(activity_id), per[activity_id]])
			lines.append("    %s : %s" % [_survivor_name(survivor_id), ", ".join(parts)])
	sections.append(_section(tr("STATS_SECTION_ACTIVITIES"), lines))

	# ── Événements ──
	var resolved_facts: Array[Dictionary] = c.facts_of(&"event_resolved")
	var pending: Array[EventConfig] = GameState.event_manager.pending_events()
	lines = []
	if resolved_facts.is_empty() and pending.is_empty():
		lines.append(tr("STATS_NO_EVENT"))
	for f in resolved_facts:
		lines.append(tr("STATS_EVENT_RESOLVED_LINE") % [f.turn, _event_title(f.target)])
	for config in pending:
		lines.append(tr("STATS_EVENT_PENDING_LINE") % tr(config.title_key))
	sections.append(_section(tr("STATS_SECTION_EVENTS"), lines))

	return "\n\n".join(sections)

func _section(header: String, lines: Array[String]) -> String:
	return "[b]%s[/b]\n%s" % [header, "\n".join(lines)]

## Libellé traduit d'une activité, avec fallback sur l'id brut.
func _activity_label(activity_id: String) -> String:
	var activity: Activity = GameState.activity_registry.get_activity(activity_id)
	return tr(activity.name_key) if activity != null else activity_id

## Titre traduit d'un event par son id, via le registry.
func _event_title(event_id: String) -> String:
	for config in GameRegistry.load_default().events:
		if String(config.id) == event_id:
			return tr(config.title_key)
	return event_id

## Nom d'un survivant par id. Les morts ne sont plus dans le roster —
## fallback sur un label générique.
func _survivor_name(id: int) -> String:
	if id == -1:
		return tr("STATS_NOBODY")
	var s: Survivor = GameState.roster.get_by_id(id)
	if s != null:
		return s.name
	return tr("STATS_DEPARTED")
