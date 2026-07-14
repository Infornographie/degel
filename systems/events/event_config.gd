extends Resource
class_name EventConfig
## Template d'un événement narratif. Stocké en .tres, éditable dans l'inspecteur.
## Le trigger conditionne l'entrée dans la queue ; la priorité conditionne
## l'ordre de présentation au joueur.

enum TriggerType {
	## Se déclenche quand un flag milestone est posé (premier éveil, etc.).
	MILESTONE,
}

@export_group("Identity")
@export var id: StringName
@export var title_key: String
@export var body_key: String

@export_group("Choices")
@export var choices: Array[EventChoice] = []

@export_group("Queue")
## Plus élevé = passe avant dans la queue (à priorité urgente égale).
@export var priority: int = 0
## Passe devant tous les non-urgents, quel que soit le priority.
@export var is_urgent: bool = false
## Si true, ne se déclenche qu'une seule fois par partie.
@export var one_shot: bool = true

@export_group("Trigger")
@export var trigger_type: TriggerType = TriggerType.MILESTONE
## Flag milestone attendu (ex: &"first_wake"). Ignoré si trigger_type != MILESTONE.
@export var trigger_milestone: StringName
## Ids d'events qui doivent avoir été résolus avant que celui-ci soit éligible.
@export var prerequisites: Array[StringName] = []
