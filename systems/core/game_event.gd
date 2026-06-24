extends RefCounted
class_name GameEvent
## Un événement de partie, stocké dans GameState.event_log et affiché dans le
## journal. Sert aussi à la news popup de fin de tour (qui filtre les events
## du tour courant).
##
## Forme : key i18n + params positionnels, traduits à l'affichage. Permet de
## stocker un event en langue-neutre et de changer de langue à chaud.
##
## Convention spéciale : un param de la forme "tr:CLÉ" est lui-même traduit
## à l'affichage. Permet de logger [name, "tr:CEO"] sans figer la traduction.

var turn: int
var category: String   # "loss", "colony", "system"
var key: String        # ID i18n (ex: "EVENT_DEATH_STARVED")
var params: Array      # Params positionnels passés à `%` après traduction

func _init(p_turn: int, p_category: String, p_key: String, p_params: Array = []) -> void:
	turn = p_turn
	category = p_category
	key = p_key
	params = p_params

## Rend le texte final, traduit dans la langue courante.
func format() -> String:
	var template := TranslationServer.translate(key)
	if params.is_empty():
		return template
	var resolved: Array = []
	for p in params:
		if typeof(p) == TYPE_STRING and p.begins_with("tr:"):
			resolved.append(TranslationServer.translate(p.substr(3)))
		else:
			resolved.append(p)
	return template % resolved
