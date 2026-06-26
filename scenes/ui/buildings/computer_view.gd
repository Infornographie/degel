extends Control
class_name ComputerView
## Vue du bâtiment Ordinateur central : bouton "Interagir" qui ouvre un popup
## avec la recherche ciblée par profession et un bouton "discuter" placeholder.
## Évolution prévue : tutoriel narratif via voix du bunker computer.

var _building: Building

func setup(b: Building) -> void:
	_building = b
	_build()

func _build() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)
	vbox.add_child(UiPresentation.slot_title(tr(_building.config.name_key)))

	var btn := Button.new()
	btn.text = tr("BTN_COMPUTER_INTERACT")
	btn.pressed.connect(_on_interact_pressed)
	vbox.add_child(btn)

func _on_interact_pressed() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = tr("POPUP_COMPUTER_TITLE")
	add_child(dialog)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	dialog.add_child(vbox)
	# Recherche ciblée
	var search_row := HBoxContainer.new()
	vbox.add_child(search_row)
	var search_label := Label.new()
	search_label.text = tr("LABEL_SEARCH_FOR")
	search_row.add_child(search_label)
	var selector := OptionButton.new()
	for prof in GameState.roster.all_professions():
		selector.add_item(tr(prof))
		selector.set_item_metadata(selector.item_count - 1, prof)
	search_row.add_child(selector)
	var search_btn := Button.new()
	search_btn.text = tr("BTN_SEARCH") % GameState.config.wake_cost_targeted
	search_btn.disabled = not GameState.can_targeted_wake()
	search_btn.pressed.connect(func():
		var idx := selector.selected
		if idx < 0: return
		var profession: String = selector.get_item_metadata(idx)
		GameState.targeted_wake(profession)
		dialog.queue_free())
	search_row.add_child(search_btn)
	# Bouton "discuter" en placeholder
	var chat_btn := Button.new()
	chat_btn.text = tr("BTN_COMPUTER_CHAT")
	chat_btn.disabled = true
	vbox.add_child(chat_btn)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
