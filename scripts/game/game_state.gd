extends Node

## Autoloaded singleton. Tracks keys earned from trivia questions and
## whether the maze exit can be unlocked yet.

signal key_count_changed(new_count: int)
signal exit_denied(keys_needed: int)
signal level_completed

const KEYS_REQUIRED := 3

var keys_collected: int = 0


func add_key() -> void:
	keys_collected += 1
	key_count_changed.emit(keys_collected)


func has_enough_keys() -> bool:
	return keys_collected >= KEYS_REQUIRED


func try_open_exit() -> void:
	if has_enough_keys():
		level_completed.emit()
	else:
		exit_denied.emit(KEYS_REQUIRED - keys_collected)
