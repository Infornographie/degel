extends Object
class_name UiPresentation
## Helpers de présentation : transforment une donnée du modèle en string,
## couleur, ou widget visuel d'affichage. Toutes les fonctions sont statiques —
## aucune logique d'état. Centralise ce qui est partagé entre les vues.
##
## Note : on utilise TranslationServer.translate() au lieu de tr() parce que
## tr() est une méthode de Object, inaccessible depuis static func.

const RESOURCE_SPRITE_SIZE: int = 32
const OVERLAY_PATH := "res://assets/resources/%s.png"
const SURVIVOR_SPRITE_PATH := "res://assets/survivors/generic%d.png"
const SURVIVOR_SPRITE_SCALE: int = 4
const SLOT_BUNKER_COLOR := Color("#2a2e3a")
const SLOT_COLONY_COLOR := Color("#3a322a")
const SLOT_MIN_SIZE := Vector2(140, 100)

## Nom affichable d'une ressource (via le registry, fallback brut).
static func resource(resource_name: String) -> String:
	var type: ResourceType = ResourceRegistry.get_type(resource_name)
	if type != null:
		return TranslationServer.translate(type.name_key)
	return resource_name

## Couleur de fond utilisée quand le sprite d'une ressource n'est pas chargé.
static func placeholder_color(resource_name: String) -> Color:
	match resource_name:
		"food": return Color("#c4a13a")
		"wood": return Color("#7b4f2c")
		"ore": return Color("#5a5a6b")
		"electricity": return Color("#e8c441")
		"heat": return Color("#c25a3a")
		_: return Color.GRAY

## Étiquette d'une tuile depuis sa clé : "Forêt (-2,0)".
static func tile_label(key: String) -> String:
	var tile: HexTile = GameState.hex_map.get_tile_by_key(key)
	if tile == null:
		return key
	var type_key: String = "TILE_TYPE_" + HexTile.Type.keys()[tile.type]
	return "%s (%d,%d)" % [TranslationServer.translate(type_key), tile.q, tile.r]

## Rôle d'un survivant assigné à un bâtiment.
static func activity_for_building(building_id: String) -> String:
	match building_id:
		"construction_zone": return TranslationServer.translate("ROLE_BUILDER")
		"synthesizer": return TranslationServer.translate("ROLE_SYNTH_OPERATOR")
		"campfire": return TranslationServer.translate("ROLE_FIRE_KEEPER")
		"kitchen": return TranslationServer.translate("ROLE_COOK")
		"tool_workshop": return TranslationServer.translate("ROLE_TOOLMAKER")
		_: return TranslationServer.translate("ROLE_BUILDING_WORKER")

## Activité courante d'un survivant : bâtiment, tuile, ou idle.
static func activity(s: Survivor) -> String:
	if s.building_id != "":
		var b: Building = GameState._find_building_by_type(s.building_id)
		if b != null:
			return activity_for_building(b.config.id)
	if s.activity_id != "":
		var act: Activity = GameState.activity_registry.get_activity(s.activity_id)
		if act != null:
			return TranslationServer.translate(act.name_key)
	return TranslationServer.translate("ROLE_IDLE")

## Icône d'une ressource (depuis le registry, fallback ColorRect si pas d'icône).
## Taille paramétrable pour permettre les usages variés (barres, lignes de prod, etc).
static func resource_icon(resource_name: String, icon_size: int) -> Control:
	var type: ResourceType = ResourceRegistry.get_type(resource_name)
	if type != null and type.icon != null:
		var icon := TextureRect.new()
		icon.texture = type.icon
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size = Vector2(icon_size, icon_size)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return icon
	var placeholder := ColorRect.new()
	placeholder.color = placeholder_color(resource_name)
	placeholder.custom_minimum_size = Vector2(icon_size, icon_size)
	return placeholder

## Icône composée pour la vue de production : sprite de la ressource + overlay
## éventuel ("surplus", "deficit", "crossed"...). L'overlay essaie d'abord un
## asset image, puis tombe sur un ColorRect teinté en fallback.
static func production_icon(resource_name: String, overlay: String) -> Control:
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(RESOURCE_SPRITE_SIZE, RESOURCE_SPRITE_SIZE)
	var base := resource_icon(resource_name, RESOURCE_SPRITE_SIZE)
	base.position = Vector2.ZERO
	stack.add_child(base)
	if overlay != "":
		var overlay_path := OVERLAY_PATH % overlay
		if ResourceLoader.exists(overlay_path):
			var ov := TextureRect.new()
			ov.texture = load(overlay_path)
			ov.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			ov.custom_minimum_size = Vector2(RESOURCE_SPRITE_SIZE, RESOURCE_SPRITE_SIZE)
			ov.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ov.position = Vector2.ZERO
			stack.add_child(ov)
		else:
			var ph := ColorRect.new()
			ph.custom_minimum_size = Vector2(RESOURCE_SPRITE_SIZE, RESOURCE_SPRITE_SIZE)
			match overlay:
				"surplus": ph.color = Color(0.4, 1.0, 0.4, 0.5)   # vert
				"deficit": ph.color = Color(1.0, 0.7, 0.2, 0.5)   # orange (puisé sur réserve)
				_: ph.color = Color(1.0, 0.3, 0.3, 0.6)            # rouge (manquant)
			ph.position = Vector2.ZERO
			stack.add_child(ph)
	return stack

## Sprite d'un survivant à sa taille standard, avec tooltip et hover actif.
## Utilisé par la liste des éveillés, la carte de candidat cryo, la map et la
## colony view (via le helper assigned_worker_sprite encore dans main_ui).
static func survivor_sprite(s: Survivor, sprite_tooltip: String) -> TextureRect:
	var sprite := TextureRect.new()
	sprite.texture = load(SURVIVOR_SPRITE_PATH % s.sprite_variant)
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # pour pixel art net
	var tex_size: Vector2 = (sprite.texture as Texture2D).get_size()
	sprite.custom_minimum_size = tex_size * SURVIVOR_SPRITE_SCALE
	sprite.tooltip_text = sprite_tooltip
	sprite.mouse_filter = Control.MOUSE_FILTER_STOP  # pour que hover/clic marche
	return sprite

## Affiche un AcceptDialog modal centré. `parent` doit être un Node de la
## scène courante (typiquement la vue qui appelle, ou MainUi).
static func show_popup(parent: Node, title: String, message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	parent.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)

## Helpers pour les slots de la grille colony. Style "bunker" (bleu-gris froid)
## ou "colonie" (brun chaud) selon le bâtiment.

static func slot_panel(is_bunker: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = SLOT_MIN_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = SLOT_BUNKER_COLOR if is_bunker else SLOT_COLONY_COLOR
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)
	return panel

static func slot_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	return label

## Sprite d'un survivant assigné à un bâtiment, cliquable pour le désassigner.
static func assigned_worker_sprite(s: Survivor) -> Control:
	var tooltip := "%s\n%s\n\n%s" % [
		s.name,
		TranslationServer.translate(s.profession),
		TranslationServer.translate("TOOLTIP_CLICK_TO_UNASSIGN"),
	]
	var sprite := survivor_sprite(s, tooltip)
	sprite.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var sid := s.id
	sprite.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			GameState.unassign_from_building(sid))
	return sprite

## Popup d'affectation d'un worker à un bâtiment opérationnel. Liste les
## éveillés avec leur localisation actuelle. Auto-cleanup à la fermeture.
##
## Migré depuis MainUi (séance 8.3i). Chaque appel crée un popup local —
## on perd la propriété "un seul popup à la fois" mais on gagne en simplicité
## et en découplage.
## Popup d'affectation d'un worker à un bâtiment opérationnel.
static func open_building_popup(parent: Node, b: Building, popup_position: Vector2) -> void:
	var popup := PopupMenu.new()
	parent.add_child(popup)
	# Option Clear si le bâtiment a des workers
	if not b.worker_ids.is_empty():
		popup.add_item(TranslationServer.translate("LABEL_CLEAR_BUILDING"))
		popup.set_item_metadata(popup.item_count - 1, {"action": "clear_building", "building_id": b.config.id})
		popup.add_separator()
	# Liste des éveillés
	var any := false
	for s in GameState.awake_survivors():
		var location_hint := ""
		if s.tile_key != "":
			var current_tile: HexTile = GameState.hex_map.get_tile_by_key(s.tile_key)
			if current_tile != null:
				location_hint = "  ← " + activity(s) + " @ " + tile_label(s.tile_key)
		elif s.building_id != "" and s.building_id != b.config.id:
			var other: Building = GameState._find_building_by_type(s.building_id)
			if other != null:
				location_hint = "  ← " + activity_for_building(other.config.id) + " @ " + TranslationServer.translate(other.config.name_key)
		elif s.building_id == b.config.id:
			location_hint = "  " + TranslationServer.translate("LABEL_HERE")
		else:
			location_hint = "  (" + TranslationServer.translate("LABEL_IDLE") + ")"
		popup.add_item("%s (%s)%s" % [s.name, TranslationServer.translate(s.profession), location_hint])
		popup.set_item_metadata(popup.item_count - 1, {
			"action": "assign_to_building",
			"survivor_id": s.id,
			"building_id": b.config.id,
		})
		any = true
	if not any:
		popup.add_item(TranslationServer.translate("LABEL_NO_AVAILABLE_WORKER"))
		popup.set_item_disabled(popup.item_count - 1, true)
	var handler := func(index: int) -> void:
		var meta = popup.get_item_metadata(index)
		if meta == null:
			return
		var action: String = meta.get("action", "")
		if action == "clear_building":
			var bb: Building = GameState._find_building(meta["building_id"])
			if bb != null:
				for wid in bb.worker_ids.duplicate():
					GameState.unassign_from_building(wid)
		elif action == "assign_to_building":
			var sid: int = meta["survivor_id"]
			var bid: String = meta["building_id"]
			var sv: Survivor = GameState.roster.get_by_id(sid)
			if sv != null and sv.building_id == bid:
				GameState.unassign_from_building(sid)
			else:
				GameState.assign_to_building(sid, bid)
	popup.id_pressed.connect(handler)
	popup.popup_hide.connect(popup.queue_free)
	popup.position = Vector2i(popup_position)
	popup.popup()
