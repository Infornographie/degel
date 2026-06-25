extends Object
class_name UiPresentation
## Helpers de présentation : transforment une donnée du modèle en string,
## couleur, ou widget visuel d'affichage. Toutes les fonctions sont statiques —
## aucune logique d'état. Centralise ce qui est partagé entre les vues.
##
## Note : on utilise TranslationServer.translate() au lieu de tr() parce que
## tr() est une méthode de Object, inaccessible depuis static func.

const RESOURCE_SPRITE_PATH := "res://assets/resources/%s.png"
const RESOURCE_SPRITE_SIZE: int = 32
const OVERLAY_PATH := "res://assets/resources/%s.png"
const SURVIVOR_SPRITE_PATH := "res://assets/survivors/generic%d.png"
const SURVIVOR_SPRITE_SCALE: int = 4

## Nom affichable d'une ressource (clé i18n si connue, sinon brut).
static func resource(resource_name: String) -> String:
	match resource_name:
		"food": return TranslationServer.translate("RESOURCE_FOOD")
		"wood": return TranslationServer.translate("RESOURCE_WOOD")
		"ore": return TranslationServer.translate("RESOURCE_ORE")
		_: return resource_name

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

## Icône d'une ressource (sprite si dispo, sinon ColorRect placeholder).
## Taille paramétrable pour permettre les usages variés (barres, lignes de prod, etc).
static func resource_icon(resource_name: String, icon_size: int) -> Control:
	var sprite_path := RESOURCE_SPRITE_PATH % resource_name
	if ResourceLoader.exists(sprite_path):
		var icon := TextureRect.new()
		icon.texture = load(sprite_path)
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
