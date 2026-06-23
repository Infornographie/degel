extends RefCounted
class_name HexTile
## Une tuile hexagonale. Coordonnées en cube (q, r, s avec q+r+s=0).

enum Type { BUNKER, PLAINS, FOREST, MOUNTAIN }

var q: int
var r: int
var s: int
var type: int = Type.PLAINS
var worker_id: int = -1

# Forme : { "gathering": 3.0, "lumberjack": 4.0, ... } — indexé par activity_id.
var yields: Dictionary = {}
var health: int = 0   # 0 = état initial, +1 par bûcheron, -1 par forestier

func _init(p_q: int, p_r: int) -> void:
	q = p_q
	r = p_r
	s = -p_q - p_r

func key() -> String:
	return "%d,%d" % [q, r]

static func make_key(p_q: int, p_r: int) -> String:
	return "%d,%d" % [p_q, p_r]
