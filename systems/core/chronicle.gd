extends RefCounted
class_name Chronicle
## Journal de faits de la partie, requêtable par les triggers d'événements.
## Sous-système de GameState — pas un autoload.
##
## Distinct de GameState.event_log (journal d'affichage : clés i18n pour les
## humains). Le Chronicle enregistre des faits structurés pour la machine.
##
## Deux natures de données :
## - FAITS : choses qui arrivent à un instant (wake, mort, déforestation...).
##   Immuables, enregistrées au moment où elles se produisent.
## - SNAPSHOTS D'ACTIVITÉ : ce que chaque survivant a réellement fait à chaque
##   tour, posés par TurnResolver à la résolution. Permettent les requêtes
##   temporelles ("assigné à chop depuis 6 tours") sans reconstruction.
##
## L'état courant (équilibre tribal, assignations) n'est PAS journalisé :
## il se lit directement dans le roster. On ne stocke que ce qui disparaît
## avec le temps.

## Actions enregistrées en Phase 1. Étendre ici quand un nouveau fait apparaît.
## wake                  — réveil normal        (actor = survivant, data.targeted = false)
## targeted_wake         — réveil ciblé réussi  (actor = survivant, data.profession)
## targeted_wake_failed  — réveil ciblé échoué  (actor = -1, data.profession)
## assign                — affectation activité (actor = survivant, target = activity_id)
## deforestation         — mutation FOREST→PLAINS (actor = worker de la tuile ou -1, target = tile key)
## construction_started  — chantier lancé       (target = building type id)
## construction_completed— chantier terminé     (target = building type id)
## death                 — mort                 (actor = survivant, data.cause)
## famine_started / famine_ended

var _gs  # GameState — non typé pour éviter la dépendance circulaire

## Faits : { turn: int, action: StringName, actor_id: int, target: String, data: Dictionary }
var _facts: Array[Dictionary] = []

## Snapshots : { turn: int, survivor_id: int, activity_id: String }
var _activity_snapshots: Array[Dictionary] = []

## Snapshots de stocks en fin de tour : { turn: int, resources: Dictionary }
## Alimente les courbes historiques. On snapshote tout — le filtre stock/flux
## se fait à l'affichage via ResourceType.stackable.
var _resource_snapshots: Array[Dictionary] = []

func _init(game_state) -> void:
	_gs = game_state

# ── ENREGISTREMENT ──

## Enregistre un fait. actor_id = -1 si pas d'acteur (événement système).
func record(action: StringName, actor_id: int = -1, target: String = "", data: Dictionary = {}) -> void:
	_facts.append({
		"turn": _gs.turn,
		"action": action,
		"actor_id": actor_id,
		"target": target,
		"data": data,
	})

## Enregistre ce qu'un survivant a réellement fait ce tour.
## Appelé par TurnResolver à la résolution (pas à l'assignation).
func snapshot_activity(survivor_id: int, activity_id: String) -> void:
	_activity_snapshots.append({
		"turn": _gs.turn,
		"survivor_id": survivor_id,
		"activity_id": activity_id,
	})

## Enregistre l'état des stocks en fin de tour. Appelé par TurnResolver
## à la toute fin d'execute_turn(), après toutes les résolutions.
func snapshot_resources() -> void:
	_resource_snapshots.append({
		"turn": _gs.turn,
		"resources": _gs.resources.duplicate(),
	})

## Historique d'une ressource : [{ turn, value }] en ordre chronologique.
func resource_history(resource_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for snap in _resource_snapshots:
		result.append({
			"turn": snap.turn,
			"value": snap.resources.get(resource_id, 0.0),
		})
	return result

# ── REQUÊTES DE BASE ──
## Phase 2 étendra ce vocabulaire quand les triggers migreront dessus.

## Tous les faits d'une action donnée, optionnellement filtrés par acteur.
func facts_of(action: StringName, actor_id: int = -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for f in _facts:
		if f.action != action:
			continue
		if actor_id != -1 and f.actor_id != actor_id:
			continue
		result.append(f)
	return result

## Nombre de faits d'une action, optionnellement par acteur.
func count_of(action: StringName, actor_id: int = -1) -> int:
	return facts_of(action, actor_id).size()

## Totaux d'activité, tous tours confondus : { activity_id: nb de tours }.
func activity_totals() -> Dictionary:
	var totals: Dictionary = {}
	for snap in _activity_snapshots:
		totals[snap.activity_id] = totals.get(snap.activity_id, 0) + 1
	return totals

## Ventilation par survivant : { survivor_id: { activity_id: nb de tours } }.
func activity_totals_by_survivor() -> Dictionary:
	var result: Dictionary = {}
	for snap in _activity_snapshots:
		if not result.has(snap.survivor_id):
			result[snap.survivor_id] = {}
		var per: Dictionary = result[snap.survivor_id]
		per[snap.activity_id] = per.get(snap.activity_id, 0) + 1
	return result

## Nombre de tours consécutifs (en remontant depuis le dernier snapshot)
## où ce survivant a fait cette activité. 0 si son dernier tour actif
## était sur une autre activité.
func consecutive_turns_on(survivor_id: int, activity_id: String) -> int:
	var streak: int = 0
	var expected_turn: int = -1
	for i in range(_activity_snapshots.size() - 1, -1, -1):
		var snap: Dictionary = _activity_snapshots[i]
		if snap.survivor_id != survivor_id:
			continue
		if expected_turn != -1 and snap.turn != expected_turn:
			break  # trou dans la série : le survivant n'a rien fait ce tour-là
		if snap.activity_id != activity_id:
			break
		streak += 1
		expected_turn = snap.turn - 1
	return streak
