extends RefCounted
class_name HexTile
## Une tuile hexagonale. Coordonnées en cube (q, r, s avec q+r+s=0).

enum Type { BUNKER, PLAINS, FOREST, MOUNTAIN }

var q: int
var r: int
var s: int
var type: int = Type.PLAINS
var worker_id: int = -1
# Rendements par job, rempli à la génération depuis le TileConfig.
# Forme : { GameState.Job.FARMER: 4.0, GameState.Job.LUMBERJACK: 1.0, ... }
var yields: Dictionary = {}

func _init(p_q: int, p_r: int) -> void:
	q = p_q
	r = p_r
	s = -p_q - p_r

func key() -> String:
	return "%d,%d" % [q, r]

static func make_key(p_q: int, p_r: int) -> String:
	return "%d,%d" % [p_q, p_r]
