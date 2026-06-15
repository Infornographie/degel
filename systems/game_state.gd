extends Node
## GameState — cœur de la simulation (autoload).
## Détient TOUT l'état du jeu et la logique de tour.
## L'UI se contentera plus tard de lire cet état et d'appeler ces méthodes.

signal turn_advanced(turn: int, energy: float)
signal game_over

var turn: int = 0
var energy: float = 100.0
var base_drain: float = 5.0   # énergie consommée par tour, hors survivants
var is_over: bool = false

## Avance d'un tour : consomme l'énergie, puis vérifie la défaite.
func advance_turn() -> void:
	if is_over:
		return
	turn += 1
	energy -= total_drain()
	if energy <= 0.0:
		energy = 0.0
		is_over = true
	turn_advanced.emit(turn, energy)
	if is_over:
		game_over.emit()

## Ponction d'énergie sur ce tour. Étape 1 : seulement la base.
## (Les survivants éveillés viendront s'ajouter ici à l'étape 2.)
func total_drain() -> float:
	return base_drain
