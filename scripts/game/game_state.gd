extends Node

## Autoloaded singleton. Tracks keys earned from trivia questions and
## whether the maze exit can be unlocked yet.

signal key_count_changed(new_count: int)
signal exit_denied(keys_needed: int)
signal level_completed
signal difficulty_changed
signal lives_changed(new_lives: int)
signal game_over

enum Difficulty { EASY, MEDIUM, HARD }

# enemy_speed 0 means no enemy; lives 0 means no hearts are shown.
const DIFFICULTY_SETTINGS := {
	Difficulty.EASY:
	{
		"name": "Easy", "grid_size": 5, "keys_required": 2, "light_range": 18.0,
		"enemy_speed": 0.0, "lives": 0,
	},
	Difficulty.MEDIUM:
	{
		"name": "Medium", "grid_size": 6, "keys_required": 3, "light_range": 14.0,
		"enemy_speed": 1.8, "lives": 3,
	},
	Difficulty.HARD:
	{
		"name": "Hard", "grid_size": 8, "keys_required": 3, "light_range": 9.0,
		"enemy_speed": 3.0, "lives": 1,
	},
}

var difficulty: int = Difficulty.MEDIUM
var keys_required: int = DIFFICULTY_SETTINGS[Difficulty.MEDIUM]["keys_required"]
var keys_collected: int = 0
var lives: int = DIFFICULTY_SETTINGS[Difficulty.MEDIUM]["lives"]
var is_game_over := false
# Mazes escaped this session, keyed by Difficulty.
var mazes_completed := {Difficulty.EASY: 0, Difficulty.MEDIUM: 0, Difficulty.HARD: 0}
# Set once the exit is used, so repeated stair contacts in the same frame can't
# re-check keys against a half-reset state. Cleared by reset_keys().
var _exiting := false


# Also used to replay: re-selecting the current difficulty restarts everything.
func set_difficulty(new_difficulty: int) -> void:
	difficulty = new_difficulty
	keys_required = DIFFICULTY_SETTINGS[difficulty]["keys_required"]
	keys_collected = 0
	lives = DIFFICULTY_SETTINGS[difficulty]["lives"]
	is_game_over = false
	_exiting = false
	difficulty_changed.emit()
	key_count_changed.emit(keys_collected)
	lives_changed.emit(lives)


func damage_player() -> void:
	if is_game_over or lives <= 0:
		return
	lives -= 1
	lives_changed.emit(lives)
	if lives == 0:
		is_game_over = true
		game_over.emit()


func get_setting(key: String):
	return DIFFICULTY_SETTINGS[difficulty][key]


func add_key() -> void:
	keys_collected += 1
	key_count_changed.emit(keys_collected)


func reset_keys() -> void:
	_exiting = false
	keys_collected = 0
	lives = DIFFICULTY_SETTINGS[difficulty]["lives"]
	lives_changed.emit(lives)
	key_count_changed.emit(keys_collected)


func has_enough_keys() -> bool:
	return keys_collected >= keys_required


func try_open_exit() -> void:
	if _exiting:
		return
	if has_enough_keys():
		_exiting = true
		mazes_completed[difficulty] += 1
		level_completed.emit()
	else:
		exit_denied.emit(keys_required - keys_collected)
