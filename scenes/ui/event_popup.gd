extends PopupPanel
class_name EventPopup
## Popup de présentation d'un événement narratif. Affiche le titre, le texte
## narratif et les choix. Le joueur peut fermer sans résoudre (il reviendra
## via le bouton event). Résoudre un choix applique les effets et ferme.

const MIN_WIDTH := 500
const MAX_WIDTH := 700
const MARGIN := 20

var _config: EventConfig

## Point d'entrée statique — crée le popup et l'affiche.
static func show_event(parent: Node, config: EventConfig) -> void:
	var instance := EventPopup.new()
	instance._config = config
	parent.add_child(instance)
	instance._build()
	instance.popup_centered()

func _build() -> void:
	# Conteneur principal avec marge
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", MARGIN)
	margin.add_theme_constant_override("margin_right", MARGIN)
	margin.add_theme_constant_override("margin_top", MARGIN)
	margin.add_theme_constant_override("margin_bottom", MARGIN)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Titre
	var title_label := Label.new()
	title_label.text = tr(_config.title_key)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title_label)

	# Séparateur
	vbox.add_child(HSeparator.new())

	# Corps narratif — RichTextLabel pour le BBCode futur
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.text = tr(_config.body_key)
	body.fit_content = true
	body.scroll_active = false
	body.custom_minimum_size.x = MIN_WIDTH
	vbox.add_child(body)

	# Séparateur avant les choix
	vbox.add_child(HSeparator.new())

	# Boutons de choix
	for i in _config.choices.size():
		var choice: EventChoice = _config.choices[i]
		var btn := Button.new()
		btn.text = tr(choice.label_key)
		btn.pressed.connect(_on_choice_pressed.bind(i))
		vbox.add_child(btn)

	# Dimensionnement
	min_size.x = MIN_WIDTH + MARGIN * 2
	max_size.x = MAX_WIDTH

func _on_choice_pressed(index: int) -> void:
	GameState.event_manager.resolve(index)
	queue_free()

func _input(event: InputEvent) -> void:
	# Échap ferme le popup sans résoudre (le joueur reviendra)
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		queue_free()
		get_viewport().set_input_as_handled()
