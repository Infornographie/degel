extends Node
## Test de l'étape 1.5b. Temporaire.

func _ready() -> void:
	GameState.turn_advanced.connect(_on_turn_advanced)
	GameState.resources_changed.connect(_on_resources_changed)
	GameState.survivor_woken.connect(_on_survivor_woken)
	GameState.survivor_assigned.connect(_on_survivor_assigned)
	GameState.survivor_died.connect(_on_survivor_died)
	GameState.famine_started.connect(_on_famine_started)
	GameState.run_ended.connect(_on_run_ended)

	print("Roster :")
	for s in GameState.survivors():
		print("  #%d %s — %s" % [s.id, s.name, s.profession])

	print("\n-- On réveille deux survivants et on les affecte à des jobs différents --")
	var first_id: int = GameState.survivors()[0].id
	var second_id: int = GameState.survivors()[1].id

	GameState.wake(first_id)
	GameState.assign_job(first_id, GameState.Job.FARM)
	GameState.advance_turn()

	GameState.wake(second_id)
	GameState.assign_job(second_id, GameState.Job.LOG)
	GameState.advance_turn()
	GameState.advance_turn()
	GameState.advance_turn()

	print("\n-- On brûle 2 bois : l'énergie du tour grimpe immédiatement --")
	print("Avant : énergie %.1f, bois %.1f" % [GameState.energy_available, GameState.resources["wood"]])
	GameState.burn_wood(2.0)
	print("Après : énergie %.1f, bois %.1f" % [GameState.energy_available, GameState.resources["wood"]])
	GameState.advance_turn()

	print("\n-- On laisse filer pour observer une éventuelle famine --")
	for i in 200:
		if GameState.is_over:
			break
		GameState.advance_turn()

func _on_turn_advanced(turn: int, energy: float, reserve: float) -> void:
	print("Tour %d — réserve %.1f, budget %.1f, food %.1f, wood %.1f, éveillés %d, famine %d" % [
		turn, reserve, energy,
		GameState.resources["food"], GameState.resources["wood"],
		GameState.awake_count(), GameState.famine_turns])

func _on_resources_changed(_resources: Dictionary) -> void:
	pass  # bruyant si activé, mais le signal existe pour l'UI à venir

func _on_survivor_woken(s: Survivor) -> void:
	print("  >> %s (%s) réveillé(e)." % [s.name, s.profession])

func _on_survivor_assigned(s: Survivor, job: int) -> void:
	var label: String = GameState.Job.keys()[job]
	print("  → %s affecté(e) à %s." % [s.name, label])

func _on_survivor_died(s: Survivor) -> void:
	print("  ✝ %s (%s) est mort(e) de faim." % [s.name, s.profession])

func _on_famine_started() -> void:
	print("  !! Famine déclarée.")

func _on_run_ended(cause: GameState.EndCause) -> void:
	var label := ""
	match cause:
		GameState.EndCause.RESERVE_DEPLETED: label = "réserve épuisée"
		GameState.EndCause.AUTONOMY_REACHED: label = "autonomie atteinte"
		GameState.EndCause.COLONY_LOST: label = "colonie perdue"
	var score = GameState.compute_score()
	print(">>> Fin de run (%s). Score : %d / %d survivants." % [
		label, score.survivors_saved, score.survivors_total])
