extends RefCounted
class_name EventManager
## Gère la queue d'événements narratifs : déclenchement par milestones,
## tri par priorité/urgence, résolution des choix avec application des effets.
## Sous-système de GameState — pas un autoload.

var _gs  # GameState — non typé pour éviter la dépendance circulaire

## Ids des events déjà résolus (one_shot + vérification des prerequisites).
var _resolved_ids: Array[StringName] = []

## Flags milestones posés durant la partie.
var _milestone_flags: Dictionary = {}

## Queue d'events en attente de résolution. Triée : urgents d'abord, puis
## par priority décroissante.
var _queue: Array[EventConfig] = []

func _init(game_state) -> void:
	_gs = game_state

# ── API PUBLIQUE ──

## Pose un flag milestone et enfile les events devenus éligibles.
func set_milestone(flag: StringName) -> void:
	if _milestone_flags.get(flag, false):
		return  # déjà posé
	_milestone_flags[flag] = true
	_scan_and_enqueue()

## La queue contient-elle des events à résoudre ?
func has_pending() -> bool:
	return not _queue.is_empty()

## Prochain event à présenter (sans dépiler).
func peek() -> EventConfig:
	if _queue.is_empty():
		return null
	return _queue[0]

## Résout l'event courant avec le choix donné. Applique les effets,
## marque résolu, dépile. Retourne le config résolu (pour le signal).
func resolve(choice_index: int) -> EventConfig:
	if _queue.is_empty():
		return null
	var config: EventConfig = _queue[0]
	if choice_index < 0 or choice_index >= config.choices.size():
		return null

	var choice: EventChoice = config.choices[choice_index]
	_apply_effects(choice)
	_resolved_ids.append(config.id)
	_queue.remove_at(0)

	_gs.chronicle.record(&"event_resolved", -1, config.id, { "choice": choice_index })
	_gs.log_event("event", "EVENT_RESOLVED", [
		"tr:" + config.title_key, "tr:" + choice.label_key])
	_gs.event_resolved.emit(config)

	# Résoudre un event peut débloquer des prerequisites d'un autre.
	_scan_and_enqueue()
	return config

## Events actuellement en attente de résolution (copie, ordre de la queue).
func pending_events() -> Array[EventConfig]:
	return _queue.duplicate()

## Retourne true si un event avec cet id a déjà été résolu.
func was_resolved(event_id: StringName) -> bool:
	return event_id in _resolved_ids

# ── SCAN & ENQUEUE ──

func _scan_and_enqueue() -> void:
	var registry := GameRegistry.load_default()
	for config in registry.events:
		if _is_eligible(config) and not _is_queued(config):
			_queue.append(config)
			_gs.event_queued.emit(config)
	_sort_queue()

func _is_eligible(config: EventConfig) -> bool:
	# Déjà résolu et one_shot ?
	if config.one_shot and config.id in _resolved_ids:
		return false
	# Prerequisites non remplis ?
	for req in config.prerequisites:
		if req not in _resolved_ids:
			return false
	# Condition de trigger
	if config.trigger_type == EventConfig.TriggerType.MILESTONE:
		if not _milestone_flags.get(config.trigger_milestone, false):
			return false
	return true

func _is_queued(config: EventConfig) -> bool:
	for queued in _queue:
		if queued.id == config.id:
			return true
	return false

func _sort_queue() -> void:
	_queue.sort_custom(func(a: EventConfig, b: EventConfig) -> bool:
		# Urgents d'abord
		if a.is_urgent != b.is_urgent:
			return a.is_urgent
		# Puis priority décroissante
		return a.priority > b.priority
	)

# ── APPLICATION DES EFFETS ──

func _apply_effects(choice: EventChoice) -> void:
	# Deltas de ressources
	for res_id in choice.resource_effects:
		var delta: float = choice.resource_effects[res_id]
		_gs.resources[res_id] = _gs.resources.get(res_id, 0.0) + delta
	# Traits sur tous les éveillés (Phase 1 — targeting à affiner en Phase 2)
	for trait_config in choice.traits_to_add:
		if trait_config == null:
			continue
		for s in _gs.awake_survivors():
			s.add_trait(trait_config)
