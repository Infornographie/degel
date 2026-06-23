extends Object
class_name UiPresentation
## Helpers de présentation : transforment une donnée du modèle en string ou
## couleur d'affichage. Toutes les fonctions sont statiques — aucune logique
## d'état. Centralise ce qui sera partagé entre les futures vues séparées.
##
## Note : on utilise TranslationServer.translate() au lieu de tr() parce que
## tr() est une méthode de Object, inaccessible depuis static func.

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
