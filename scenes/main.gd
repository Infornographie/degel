extends Node
## Test de l'étape 1.5a. Temporaire.

func _ready() -> void:
	GameState.turn_advanced.connect(_on_turn_advanced)
	GameState.survivor_woken.connect(_on_survivor_woken)
	GameState.survivor_died.connect(_on_survivor_died)
	GameState.famine_started.connect(_on_famine_started)
	GameState.famine_ended.connect(_on_famine_ended)
	GameState.run_ended.connect(_on_run_ended)

	print("Roster généré aléatoirement :")
	for i in GameState.survivors().size():
		var s: Survivor = GameState.survivors()[i]
		print("  #%d %s — %s" % [i, s.name, s.profession])

	print("\n-- On rejoue : réveil de tout le monde, puis on les laisse crever --")
	var to_wake := GameState.survivors().duplicate()
	for s in to_wake:
		GameState.wake(s.id)
		GameState.advance_turn()

	for i in 500:
		if GameState.is_over:
			break
		GameState.advance_turn()

func _on_turn_advanced(turn: int, energy: float, reserve: float, food: float) -> void:
	print("Tour %d — réserve %.1f, nourriture %.1f, éveillés %d, famine_turns %d" % [
		turn, reserve, food, GameState.awake_count(), GameState.famine_turns])

func _on_survivor_woken(s: Survivor) -> void:
	print("  >> %s (%s) réveillé(e)." % [s.name, s.profession])

func _on_survivor_died(s: Survivor) -> void:
	print("  ✝ %s (%s) est mort(e) de faim." % [s.name, s.profession])

func _on_famine_started() -> void:
	print("  !! Famine déclarée.")

func _on_famine_ended() -> void:
	print("  ~~ Famine résolue.")

func _on_run_ended(cause: GameState.EndCause) -> void:
	var label := ""
	match cause:
		GameState.EndCause.RESERVE_DEPLETED: label = "réserve épuisée"
		GameState.EndCause.AUTONOMY_REACHED: label = "autonomie atteinte"
		GameState.EndCause.COLONY_LOST: label = "colonie perdue"
	var score = GameState.compute_score()
	print(">>> Fin de run (%s). Score : %d / %d survivants." % [
		label, score.survivors_saved, score.survivors_total])
