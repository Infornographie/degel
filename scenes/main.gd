extends Node
## Script de test de l'étape 1. À retirer une fois l'UI en place.

func _ready() -> void:
	GameState.turn_advanced.connect(_on_turn_advanced)
	GameState.game_over.connect(_on_game_over)
	# Simule 25 tours d'affilée pour voir la réserve descendre jusqu'à la défaite.
	for i in 25:
		GameState.advance_turn()

func _on_turn_advanced(turn: int, energy: float) -> void:
	print("Tour %d — énergie : %.1f" % [turn, energy])

func _on_game_over() -> void:
	print(">>> Réserves épuisées. Partie perdue.")
