extends Area3D

## Placed at maze fork cells; asks a trivia question the first time the
## player enters. A correct answer removes the trigger for good; a wrong
## answer just re-arms it once the player steps away, so no key is lost
## forever.


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	set_deferred("monitoring", false)
	TriviaManager.ask_random_question()
	TriviaManager.answered.connect(_on_answered, CONNECT_ONE_SHOT)


func _on_answered(was_correct: bool) -> void:
	if was_correct:
		queue_free()
	else:
		body_exited.connect(_on_body_exited, CONNECT_ONE_SHOT)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		set_deferred("monitoring", true)
