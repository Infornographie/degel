extends Control
class_name ButtonsSection
## Boutons d'action globaux : tour suivant, nécrologie, switch langue, quitter.
## Inclut aussi le label de statut affiché en fin de run.
##
## Émet `language_toggled` quand on change de langue, parce que le rebuild
## complet de l'UI est de la responsabilité de MainUi (mécanisme global).

signal language_toggled

var _advance_button: Button
var _event_button: Button
var _status_label: Label

func _ready() -> void:
	_build()
	GameState.run_ended.connect(_on_run_ended)
	GameState.event_queued.connect(_on_event_queue_changed.unbind(1))
	GameState.event_resolved.connect(_on_event_queue_changed.unbind(1))

func _build() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	_event_button = Button.new()
	_event_button.text = tr("BTN_EVENT")
	_event_button.pressed.connect(_on_event_pressed)
	_event_button.visible = false
	vbox.add_child(_event_button)

	_advance_button = Button.new()
	_advance_button.text = tr("BTN_ADVANCE")
	_advance_button.pressed.connect(_on_advance_pressed)
	vbox.add_child(_advance_button)

	var necro_btn := Button.new()
	necro_btn.text = tr("BTN_NECROLOGY")
	necro_btn.pressed.connect(_on_necrology_pressed)
	vbox.add_child(necro_btn)

	var stats_btn := Button.new()
	stats_btn.text = tr("BTN_STATS")
	stats_btn.pressed.connect(_on_stats_pressed)
	vbox.add_child(stats_btn)

	var lang_btn := Button.new()
	lang_btn.text = tr("BTN_TOGGLE_LANG")
	lang_btn.pressed.connect(_on_toggle_lang_pressed)
	vbox.add_child(lang_btn)

	var quit_btn := Button.new()
	quit_btn.text = tr("BTN_QUIT")
	quit_btn.pressed.connect(get_tree().quit)
	vbox.add_child(quit_btn)

	_status_label = Label.new()
	_status_label.text = ""
	vbox.add_child(_status_label)

func _on_advance_pressed() -> void:
	GameState.advance_turn()

func _on_stats_pressed() -> void:
	StatsPopup.show_stats(self)

func _on_event_pressed() -> void:
	var config: EventConfig = GameState.event_manager.peek()
	if config == null:
		return
	EventPopup.show_event(self, config)

func _on_event_queue_changed() -> void:
	var has_events: bool = GameState.event_manager.has_pending()
	_event_button.visible = has_events
	_advance_button.disabled = has_events or GameState.is_over

func _on_necrology_pressed() -> void:
	var lines: Array[String] = []
	for entry in GameState.necrology:
		var cause_label: String = entry.cause
		if entry.cause == "switched off":
			cause_label = tr("DEATH_SWITCHED_OFF")
		elif entry.cause == "starved":
			cause_label = tr("DEATH_STARVED")
		lines.append(tr("POPUP_NECROLOGY_LINE") % [
			entry.turn, entry.name, Roster.display_name(entry.profession), cause_label])
	var content := "\n".join(lines) if not lines.is_empty() else tr("POPUP_NECROLOGY_EMPTY")
	UiPresentation.show_popup(self, tr("BTN_NECROLOGY"), content)

func _on_toggle_lang_pressed() -> void:
	var current := TranslationServer.get_locale()
	var new_locale := "en" if current.begins_with("fr") else "fr"
	TranslationServer.set_locale(new_locale)
	language_toggled.emit()

func _on_run_ended(cause: GameState.EndCause) -> void:
	var label := ""
	match cause:
		GameState.EndCause.REACTOR_DEAD: label = tr("LABEL_REACTOR_DEAD")
		GameState.EndCause.COLONY_LOST: label = tr("LABEL_COLONY_LOST")
	_status_label.text = tr("LABEL_RUN_ENDED") % label
	_advance_button.disabled = true
