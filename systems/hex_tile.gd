extends RefCounted
class_name HexTile
## Une tuile hexagonale. Coordonnées en cube (q, r, s avec q+r+s=0).

enum Type { BUNKER, PLAINS, FOREST, MOUNTAIN }

var q: int
var r: int
var s: int
var type: int = Type.PLAINS
var worker_id: int = -1   # id du survivant qui travaille ici, -1 si vide

func _init(p_q: int, p_r: int) -> void:
	q = p_q
	r = p_r
	s = -p_q - p_r   # contrainte q+r+s=0

## Clé string pour stocker la tuile dans un Dictionary indexé par position.
func key() -> String:
	return "%d,%d" % [q, r]

## Clé pour une paire de coords arbitraires (utilitaire statique).
static func make_key(p_q: int, p_r: int) -> String:
	return "%d,%d" % [p_q, p_r]
