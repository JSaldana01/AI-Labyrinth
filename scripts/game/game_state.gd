extends Node

## Autoloaded singleton. Tracks keys earned from trivia questions and
## whether the maze exit can be unlocked yet. Also owns the timed power-up
## granted for correct trivia answers.

signal key_count_changed(new_count: int)
signal exit_denied(keys_needed: int)
signal level_completed
signal difficulty_changed
signal lives_changed(new_lives: int)
signal game_over
signal power_up_changed(power_up: int, time_left: float)
signal reward_granted(reward: int)

## When true, maze_generator uses local DFS only (GUT / offline).
var use_local_maze := false

enum Difficulty { EASY, MEDIUM, HARD }
enum PowerUp { NONE, GHOST, BLASTER, SPEED }
enum Reward { EXTRA_LIFE, SPEED, HINT, GHOST, BLASTER }

const POWER_UP_DURATION := 10.0
const SPEED_MULTIPLIER := 1.5

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
var active_power_up: int = PowerUp.NONE
var power_up_time_left := 0.0
var hints_available := 0
# Mazes escaped this session, keyed by Difficulty.
var mazes_completed := {Difficulty.EASY: 0, Difficulty.MEDIUM: 0, Difficulty.HARD: 0}
# Set once the exit is used, so repeated stair contacts in the same frame can't
# re-check keys against a half-reset state. Cleared by reset_keys().
var _exiting := false


# Uses the default pausable process mode, so the countdown stops while a
# trivia question or the pause menu is open.
func _process(delta: float) -> void:
	if active_power_up == PowerUp.NONE:
		return
	power_up_time_left -= delta
	if power_up_time_left <= 0.0:
		clear_power_up()


# Also used to replay: re-selecting the current difficulty restarts everything.
func set_difficulty(new_difficulty: int) -> void:
	difficulty = new_difficulty
	keys_required = DIFFICULTY_SETTINGS[difficulty]["keys_required"]
	keys_collected = 0
	lives = DIFFICULTY_SETTINGS[difficulty]["lives"]
	is_game_over = false
	hints_available = 0
	_exiting = false
	clear_power_up()
	difficulty_changed.emit()
	key_count_changed.emit(keys_collected)
	lives_changed.emit(lives)


func damage_player() -> void:
	if is_game_over or lives <= 0 or is_ghost():
		return
	lives -= 1
	lives_changed.emit(lives)
	if lives == 0:
		is_game_over = true
		game_over.emit()


func get_setting(key: String):
	return DIFFICULTY_SETTINGS[difficulty][key]


func maze_profile_slug() -> String:
	match difficulty:
		Difficulty.EASY:
			return "easy-5x5"
		Difficulty.HARD:
			return "hard-8x8"
		_:
			return "medium-6x6"


func add_key() -> void:
	keys_collected += 1
	key_count_changed.emit(keys_collected)


func reset_keys() -> void:
	_exiting = false
	keys_collected = 0
	lives = DIFFICULTY_SETTINGS[difficulty]["lives"]
	clear_power_up()
	lives_changed.emit(lives)
	key_count_changed.emit(keys_collected)


# A new power-up replaces whatever is active and restarts the timer.
func grant_random_reward() -> void:
	var rewards: Array[int] = [
		Reward.EXTRA_LIFE,
		Reward.SPEED,
		Reward.HINT,
		Reward.GHOST,
		Reward.BLASTER,
	]
	_grant_reward(rewards.pick_random())


func _grant_reward(reward: int) -> void:
	match reward:
		Reward.EXTRA_LIFE:
			lives += 1
			lives_changed.emit(lives)
		Reward.SPEED:
			_start_power_up(PowerUp.SPEED)
		Reward.HINT:
			hints_available += 1
		Reward.GHOST:
			_start_power_up(PowerUp.GHOST)
		Reward.BLASTER:
			_start_power_up(PowerUp.BLASTER)
	reward_granted.emit(reward)


func _start_power_up(power_up: int) -> void:
	active_power_up = power_up
	power_up_time_left = POWER_UP_DURATION
	power_up_changed.emit(active_power_up, power_up_time_left)


func use_hint() -> bool:
	if hints_available <= 0:
		return false
	hints_available -= 1
	return true


func clear_power_up() -> void:
	if active_power_up == PowerUp.NONE:
		return
	active_power_up = PowerUp.NONE
	power_up_time_left = 0.0
	power_up_changed.emit(active_power_up, power_up_time_left)


func is_ghost() -> bool:
	return active_power_up == PowerUp.GHOST


func has_blaster() -> bool:
	return active_power_up == PowerUp.BLASTER


func has_speed_boost() -> bool:
	return active_power_up == PowerUp.SPEED


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
