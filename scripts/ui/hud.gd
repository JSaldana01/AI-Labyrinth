extends CanvasLayer

## Shows the current key count and transient lock/win messages.

@onready var key_label: Label = $MarginContainer/KeyLabel
@onready var message_label: Label = $MessageLabel
@onready var message_timer: Timer = $MessageTimer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.key_count_changed.connect(_on_key_count_changed)
	GameState.exit_denied.connect(_on_exit_denied)
	GameState.level_completed.connect(_on_level_completed)
	message_timer.timeout.connect(_on_message_timer_timeout)
	message_label.hide()
	_on_key_count_changed(GameState.keys_collected)


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
