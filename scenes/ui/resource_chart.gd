extends Control
class_name ResourceChart
## Tracé des courbes de stocks au fil des tours, à partir du Chronicle.
## Lecture seule — se redessine sur `_draw()` avec les données courantes.
## Trace uniquement les ressources stackables (les flux electricity/heat
## se resettent chaque tour, une courbe n'y a pas de sens).

const MARGIN_LEFT := 40
const MARGIN_RIGHT := 90  # place pour la légende
const MARGIN_TOP := 12
const MARGIN_BOTTOM := 24
const GRID_STEPS := 4

## Couleurs par ressource. Fallback HSV cyclique si l'id est inconnu.
const PALETTE := {
	"food":  Color(0.35, 0.75, 0.35),
	"meal":  Color(0.95, 0.65, 0.20),
	"wood":  Color(0.55, 0.35, 0.20),
	"ore":   Color(0.55, 0.55, 0.60),
	"tools": Color(0.30, 0.55, 0.85),
}

func _init() -> void:
	custom_minimum_size = Vector2(420, 200)

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var plot_x: float = MARGIN_LEFT
	var plot_y: float = MARGIN_TOP
	var plot_w: float = w - MARGIN_LEFT - MARGIN_RIGHT
	var plot_h: float = h - MARGIN_TOP - MARGIN_BOTTOM

	# Collecter les séries à tracer (stackables uniquement, non vides)
	var series: Array = []  # [{ res_type, points: Array[Dictionary] }]
	for res_type in ResourceRegistry.all():
		if not res_type.stackable:
			continue
		var history: Array[Dictionary] = GameState.chronicle.resource_history(String(res_type.id))
		if history.is_empty():
			continue
		series.append({ "res_type": res_type, "points": history })

	if series.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(plot_x, plot_y + 20),
			tr("STATS_CHART_EMPTY"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		return

	# Bornes X (tours) et Y (valeurs)
	var min_turn: int = 999999
	var max_turn: int = 0
	var max_value: float = 1.0
	for s in series:
		for p in s.points:
			min_turn = min(min_turn, p.turn)
			max_turn = max(max_turn, p.turn)
			max_value = max(max_value, p.value)
	var value_ceiling: float = _nice_ceiling(max_value)
	var turn_span: int = max(1, max_turn - min_turn)

	# Fond + grille
	var grid_color := Color(1, 1, 1, 0.08)
	var axis_color := Color(1, 1, 1, 0.4)
	for i in range(GRID_STEPS + 1):
		var frac: float = float(i) / GRID_STEPS
		var y: float = plot_y + plot_h * (1.0 - frac)
		draw_line(Vector2(plot_x, y), Vector2(plot_x + plot_w, y), grid_color, 1.0)
		var label: String = "%d" % int(round(value_ceiling * frac))
		draw_string(ThemeDB.fallback_font, Vector2(plot_x - 30, y + 4),
			label, HORIZONTAL_ALIGNMENT_RIGHT, 26, 10, axis_color)

	# Axes
	draw_line(Vector2(plot_x, plot_y), Vector2(plot_x, plot_y + plot_h), axis_color, 1.0)
	draw_line(Vector2(plot_x, plot_y + plot_h), Vector2(plot_x + plot_w, plot_y + plot_h), axis_color, 1.0)
	# Labels tours (min et max)
	draw_string(ThemeDB.fallback_font, Vector2(plot_x - 4, plot_y + plot_h + 16),
		"%d" % min_turn, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, axis_color)
	draw_string(ThemeDB.fallback_font, Vector2(plot_x + plot_w - 20, plot_y + plot_h + 16),
		"%d" % max_turn, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, axis_color)

	# Courbes
	var legend_y: float = plot_y + 4
	for s in series:
		var color: Color = _color_for(String(s.res_type.id))
		var pts: PackedVector2Array = PackedVector2Array()
		for p in s.points:
			var px: float = plot_x + plot_w * float(p.turn - min_turn) / float(turn_span)
			var py: float = plot_y + plot_h * (1.0 - clamp(p.value / value_ceiling, 0.0, 1.0))
			pts.append(Vector2(px, py))
		if pts.size() == 1:
			draw_circle(pts[0], 3.0, color)
		else:
			draw_polyline(pts, color, 2.0, true)
		# Légende
		var label: String = tr(s.res_type.name_key)
		var legend_x: float = plot_x + plot_w + 8
		draw_line(Vector2(legend_x, legend_y + 6), Vector2(legend_x + 14, legend_y + 6), color, 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(legend_x + 18, legend_y + 10),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		legend_y += 16

## Couleur d'une ressource : palette si connue, sinon HSV cyclique déterministe.
func _color_for(id: String) -> Color:
	if PALETTE.has(id):
		return PALETTE[id]
	var h: float = fposmod(float(id.hash()) * 0.618033988, 1.0)
	return Color.from_hsv(h, 0.6, 0.85)

## Arrondit le plafond Y à une valeur "propre" (1, 2, 5, 10, 20, 50, 100...).
func _nice_ceiling(value: float) -> float:
	if value <= 0.0:
		return 1.0
	var exp10: float = pow(10.0, floor(log(value) / log(10.0)))
	var normalized: float = value / exp10
	var nice: float
	if normalized <= 1.0: nice = 1.0
	elif normalized <= 2.0: nice = 2.0
	elif normalized <= 5.0: nice = 5.0
	else: nice = 10.0
	return nice * exp10
