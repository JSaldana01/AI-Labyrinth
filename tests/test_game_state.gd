extends GutTest

## Tests for the GameState autoload: difficulty settings, keys, hearts,
## exit logic and per-difficulty completion counts.

const D = preload("res://scripts/game/game_state.gd").Difficulty
const PLAYER_SCENE: PackedScene = preload("res://tscn/player.tscn")


func before_each() -> void:
	GameState.mazes_completed = {D.EASY: 0, D.MEDIUM: 0, D.HARD: 0}
	GameState.set_difficulty(D.MEDIUM)


func after_all() -> void:
	GameState.set_difficulty(D.MEDIUM)


# --- Difficulty settings -------------------------------------------------

func test_easy_settings() -> void:
	GameState.set_difficulty(D.EASY)
	assert_eq(GameState.get_setting("grid_size"), 5)
	assert_eq(GameState.keys_required, 2)
	assert_eq(GameState.lives, 0)
	assert_eq(GameState.get_setting("enemy_speed"), 0.0)


func test_medium_settings() -> void:
	GameState.set_difficulty(D.MEDIUM)
	assert_eq(GameState.get_setting("grid_size"), 6)
	assert_eq(GameState.keys_required, 3)
	assert_eq(GameState.lives, 3)
	assert_gt(GameState.get_setting("enemy_speed"), 0.0)


func test_hard_settings() -> void:
	GameState.set_difficulty(D.HARD)
	assert_eq(GameState.get_setting("grid_size"), 8)
	assert_eq(GameState.keys_required, 3)
	assert_eq(GameState.lives, 1)


func test_enemy_is_faster_on_hard_than_medium() -> void:
	var medium: float = GameState.DIFFICULTY_SETTINGS[D.MEDIUM]["enemy_speed"]
	var hard: float = GameState.DIFFICULTY_SETTINGS[D.HARD]["enemy_speed"]
	assert_gt(hard, medium)


func test_set_difficulty_resets_progress() -> void:
	GameState.add_key()
	GameState.damage_player()
	GameState.set_difficulty(D.HARD)
	assert_eq(GameState.keys_collected, 0)
	assert_eq(GameState.lives, 1)
	assert_false(GameState.is_game_over)


func test_set_difficulty_emits_signals() -> void:
	watch_signals(GameState)
	GameState.set_difficulty(D.HARD)
	assert_signal_emitted(GameState, "difficulty_changed")
	assert_signal_emitted(GameState, "key_count_changed")
	assert_signal_emitted(GameState, "lives_changed")


# --- Keys ----------------------------------------------------------------

func test_add_key_increments_and_emits() -> void:
	watch_signals(GameState)
	GameState.add_key()
	assert_eq(GameState.keys_collected, 1)
	assert_signal_emitted_with_parameters(GameState, "key_count_changed", [1])


func test_has_enough_keys_boundary() -> void:
	for i in range(GameState.keys_required - 1):
		GameState.add_key()
	assert_false(GameState.has_enough_keys())
	GameState.add_key()
	assert_true(GameState.has_enough_keys())


func test_reset_keys_restores_keys_and_hearts() -> void:
	GameState.add_key()
	GameState.damage_player()
	GameState.reset_keys()
	assert_eq(GameState.keys_collected, 0)
	assert_eq(GameState.lives, 3)


# --- Hearts / game over --------------------------------------------------

func test_damage_reduces_lives_and_emits() -> void:
	watch_signals(GameState)
	GameState.damage_player()
	assert_eq(GameState.lives, 2)
	assert_signal_emitted_with_parameters(GameState, "lives_changed", [2])
	assert_signal_not_emitted(GameState, "game_over")


func test_game_over_after_losing_all_hearts_emits_once() -> void:
	watch_signals(GameState)
	for i in range(3):
		GameState.damage_player()
	assert_true(GameState.is_game_over)
	assert_eq(GameState.lives, 0)
	# Extra hits after game over must not emit again or go negative.
	GameState.damage_player()
	assert_eq(GameState.lives, 0)
	assert_signal_emit_count(GameState, "game_over", 1)


func test_hard_game_over_on_first_hit() -> void:
	GameState.set_difficulty(D.HARD)
	watch_signals(GameState)
	GameState.damage_player()
	assert_true(GameState.is_game_over)
	assert_signal_emit_count(GameState, "game_over", 1)


func test_easy_has_no_hearts_so_damage_does_nothing() -> void:
	GameState.set_difficulty(D.EASY)
	watch_signals(GameState)
	GameState.damage_player()
	assert_eq(GameState.lives, 0)
	assert_false(GameState.is_game_over)
	assert_signal_not_emitted(GameState, "game_over")
	assert_signal_not_emitted(GameState, "lives_changed")


func test_replay_restores_hearts_after_game_over() -> void:
	for i in range(3):
		GameState.damage_player()
	GameState.set_difficulty(D.MEDIUM)
	assert_false(GameState.is_game_over)
	assert_eq(GameState.lives, 3)


func test_extra_life_reward_adds_a_heart_and_emits() -> void:
	watch_signals(GameState)
	GameState._grant_reward(GameState.Reward.EXTRA_LIFE)
	assert_eq(GameState.lives, 4)
	assert_signal_emitted_with_parameters(GameState, "lives_changed", [4])
	assert_signal_emitted_with_parameters(
		GameState, "reward_granted", [GameState.Reward.EXTRA_LIFE]
	)


func test_speed_reward_starts_timed_speed_boost() -> void:
	GameState._grant_reward(GameState.Reward.SPEED)
	assert_true(GameState.has_speed_boost())
	assert_eq(GameState.power_up_time_left, GameState.POWER_UP_DURATION)


func test_speed_reward_changes_movement_until_it_expires() -> void:
	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.set_physics_process(false)
	GameState.set_process(false)
	Input.action_press("move_forward")

	player._physics_process(0.0)
	var normal_speed := Vector2(player.velocity.x, player.velocity.z).length()
	GameState._grant_reward(GameState.Reward.SPEED)
	player._physics_process(0.0)
	var boosted_speed := Vector2(player.velocity.x, player.velocity.z).length()
	GameState._process(GameState.POWER_UP_DURATION)
	player._physics_process(0.0)
	var expired_speed := Vector2(player.velocity.x, player.velocity.z).length()

	Input.action_release("move_forward")
	GameState.set_process(true)
	assert_almost_eq(normal_speed, player.move_speed, 0.001)
	assert_almost_eq(boosted_speed, normal_speed * GameState.SPEED_MULTIPLIER, 0.001)
	assert_false(GameState.has_speed_boost())
	assert_almost_eq(expired_speed, normal_speed, 0.001)


func test_speed_timer_pauses_during_trivia() -> void:
	GameState._grant_reward(GameState.Reward.SPEED)
	TriviaManager.ask_random_question()
	var paused_time: float = GameState.power_up_time_left
	await get_tree().create_timer(0.2, true).timeout
	var time_after_pause: float = GameState.power_up_time_left
	var wrong_index: int = (TriviaManager._popup._correct_index + 1) % TriviaManager._popup.choice_buttons.size()
	TriviaManager._popup.choice_buttons[wrong_index].pressed.emit()
	await get_tree().create_timer(0.2, true).timeout
	var time_after_resume: float = GameState.power_up_time_left

	assert_eq(time_after_pause, paused_time)
	assert_lt(time_after_resume, time_after_pause)


func test_hint_reward_can_be_saved_and_used_once() -> void:
	GameState._grant_reward(GameState.Reward.HINT)
	assert_eq(GameState.hints_available, 1)
	assert_true(GameState.use_hint())
	assert_eq(GameState.hints_available, 0)
	assert_false(GameState.use_hint())


func test_hints_survive_new_maze_but_reset_on_replay() -> void:
	GameState._grant_reward(GameState.Reward.HINT)
	GameState._grant_reward(GameState.Reward.HINT)
	GameState.reset_keys()
	assert_eq(GameState.hints_available, 2)
	GameState.set_difficulty(D.MEDIUM)
	assert_eq(GameState.hints_available, 0)


# --- Exit ----------------------------------------------------------------

func test_exit_denied_reports_missing_keys() -> void:
	watch_signals(GameState)
	GameState.add_key()
	GameState.try_open_exit()
	assert_signal_emitted_with_parameters(GameState, "exit_denied", [GameState.keys_required - 1])
	assert_signal_not_emitted(GameState, "level_completed")
	assert_eq(GameState.mazes_completed[D.MEDIUM], 0)


func test_exit_with_enough_keys_completes_once() -> void:
	watch_signals(GameState)
	for i in range(GameState.keys_required):
		GameState.add_key()
	GameState.try_open_exit()
	GameState.try_open_exit()
	assert_signal_emit_count(GameState, "level_completed", 1)
	assert_eq(GameState.mazes_completed[D.MEDIUM], 1)


func test_exit_works_again_after_reset() -> void:
	for i in range(GameState.keys_required):
		GameState.add_key()
	GameState.try_open_exit()
	GameState.reset_keys()
	for i in range(GameState.keys_required):
		GameState.add_key()
	GameState.try_open_exit()
	assert_eq(GameState.mazes_completed[D.MEDIUM], 2)


func test_completions_tracked_per_difficulty() -> void:
	GameState.set_difficulty(D.EASY)
	for i in range(GameState.keys_required):
		GameState.add_key()
	GameState.try_open_exit()
	GameState.set_difficulty(D.HARD)
	for i in range(GameState.keys_required):
		GameState.add_key()
	GameState.try_open_exit()
	assert_eq(GameState.mazes_completed[D.EASY], 1)
	assert_eq(GameState.mazes_completed[D.MEDIUM], 0)
	assert_eq(GameState.mazes_completed[D.HARD], 1)
