extends CanvasLayer

## Shows the current key count and transient lock/win messages.

@onready var key_label: Label = $MarginContainer/KeyLabel
@onready var message_label: Label = $MessageLabel
@onready var message_timer: Timer = $MessageTimer

var _maze_source_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_maze_source_label = get_node_or_null("MarginContainer/MazeSourceLabel") as Label
	GameState.key_count_changed.connect(_on_key_count_changed)
	GameState.exit_denied.connect(_on_exit_denied)
	GameState.level_completed.connect(_on_level_completed)
	message_timer.timeout.connect(_on_message_timer_timeout)
	message_label.hide()
	if _maze_source_label:
		_maze_source_label.hide()
	_on_key_count_changed(GameState.keys_collected)


func set_maze_source(generator: String, maze_instance_id: String, network_load_ms: int = 0) -> void:
	if _maze_source_label == null:
		_maze_source_label = get_node_or_null("MarginContainer/MazeSourceLabel") as Label
	if _maze_source_label == null:
		push_warning("[HUD] MazeSourceLabel missing — open tscn/ui/hud.tscn in editor and save, or ignore HUD line")
		return
	var short_id := maze_instance_id.substr(0, 8) if maze_instance_id.length() >= 8 else maze_instance_id
	if network_load_ms > 0:
		_maze_source_label.text = "Maze: %s · %s… (Gemini/network %.1fs)" % [
			generator, short_id, network_load_ms / 1000.0
		]
	else:
		_maze_source_label.text = "Maze: %s · %s…" % [generator, short_id]
	_maze_source_label.show()


func _on_key_count_changed(new_count: int) -> void:
	key_label.text = "Keys: %d/%d" % [new_count, GameState.KEYS_REQUIRED]


func _on_exit_denied(keys_needed: int) -> void:
	_show_message("Locked! Need %d more key(s)." % keys_needed)


func _on_level_completed() -> void:
	_show_message("You escaped the maze!")
	get_tree().paused = true


func _show_message(text: String) -> void:
	message_label.text = text
	message_label.show()
	message_timer.start()


func _on_message_timer_timeout() -> void:
	message_label.hide()
