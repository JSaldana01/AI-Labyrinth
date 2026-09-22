extends Area3D

## Placed at the maze's far cell; only lets the player finish the level
## once GameState reports enough keys have been collected.


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	GameState.try_open_exit()
