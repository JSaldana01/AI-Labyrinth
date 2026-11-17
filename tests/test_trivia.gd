extends GutTest

## Tests for trivia question data, the manager, and the popup.

const D = preload("res://scripts/game/game_state.gd").Difficulty
const POPUP_SCENE: PackedScene = preload("res://tscn/trivia/trivia_popup.tscn")


func before_each() -> void:
	GameState.set_difficulty(D.MEDIUM)
	TriviaManager._question_bag.clear()
	TriviaManager._last_question_index = -1


func after_all() -> void:
	GameState.set_difficulty(D.MEDIUM)


# --- Question data -------------------------------------------------------

func test_every_question_is_well_formed() -> void:
	for i in range(TriviaManager.QUESTIONS.size()):
		var q: Dictionary = TriviaManager.QUESTIONS[i]
		assert_true(q.has("question") and q.has("choices") and q.has("correct"), "question %d missing keys" % i)
		assert_false(String(q["question"]).strip_edges().is_empty(), "question %d empty" % i)
		assert_gte(q["choices"].size(), 2, "question %d needs 2+ choices" % i)
		assert_true(q["correct"] >= 0 and q["correct"] < q["choices"].size(), "question %d correct index out of range" % i)


func test_choices_are_unique_within_each_question() -> void:
	for i in range(TriviaManager.QUESTIONS.size()):
		var choices: Array = TriviaManager.QUESTIONS[i]["choices"]
		var unique := {}
		for c in choices:
			unique[c] = true
		assert_eq(unique.size(), choices.size(), "question %d has duplicate choices" % i)


func test_there_are_enough_questions_for_every_difficulty() -> void:
	var most_keys := 0
	for level in GameState.DIFFICULTY_SETTINGS:
		most_keys = maxi(most_keys, GameState.DIFFICULTY_SETTINGS[level]["keys_required"])
	assert_gt(TriviaManager.QUESTIONS.size(), most_keys)


# --- Question bag --------------------------------------------------------

func test_refill_contains_every_question_exactly_once() -> void:
	TriviaManager._refill_question_bag()
	var sorted_bag: Array = TriviaManager._question_bag.duplicate()
	sorted_bag.sort()
	assert_eq(sorted_bag, range(TriviaManager.QUESTIONS.size()))


func test_no_back_to_back_repeat_across_cycles() -> void:
	for i in range(100):
		TriviaManager._last_question_index = TriviaManager.QUESTIONS.size() - 1
		TriviaManager._refill_question_bag()
		# The next draw pops from the back.
		assert_ne(TriviaManager._question_bag.back(), TriviaManager._last_question_index)


# --- Answers -------------------------------------------------------------

func test_correct_answer_adds_a_key_and_reports_true() -> void:
	watch_signals(TriviaManager)
	TriviaManager._on_choice_selected(true)
	assert_eq(GameState.keys_collected, 1)
	assert_signal_emitted_with_parameters(TriviaManager, "answered", [true])


func test_wrong_answer_adds_no_key_and_reports_false() -> void:
	watch_signals(TriviaManager)
	watch_signals(GameState)
	TriviaManager._on_choice_selected(false)
	assert_eq(GameState.keys_collected, 0)
	assert_signal_emitted_with_parameters(TriviaManager, "answered", [false])
	assert_signal_not_emitted(GameState, "reward_granted")


func test_wrong_answers_grant_no_reward_on_medium_or_hard() -> void:
	watch_signals(GameState)
	for level in [D.MEDIUM, D.HARD]:
		GameState.set_difficulty(level)
		TriviaManager._on_choice_selected(false)
		assert_eq(GameState.keys_collected, 0)
	assert_signal_not_emitted(GameState, "reward_granted")


func test_correct_answers_grant_rewards_only_on_medium_and_hard() -> void:
	watch_signals(GameState)
	for level in [D.MEDIUM, D.HARD]:
		GameState.set_difficulty(level)
		TriviaManager._on_choice_selected(true)
	assert_signal_emit_count(GameState, "reward_granted", 2)

	GameState.set_difficulty(D.EASY)
	TriviaManager._on_choice_selected(true)
	assert_signal_emit_count(GameState, "reward_granted", 2)


func test_answering_unpauses_the_game() -> void:
	get_tree().paused = true
	TriviaManager._on_choice_selected(false)
	assert_false(get_tree().paused)


func test_hint_removes_one_wrong_choice_and_next_question_restores_choices() -> void:
	var popup: Control = POPUP_SCENE.instantiate()
	add_child_autofree(popup)
	var question := {
		"question": "Test question",
		"choices": ["A", "B", "C", "D"],
		"correct": 0,
	}

	for correct_index in range(4):
		question["correct"] = correct_index
		GameState._grant_reward(GameState.Reward.HINT)
		GameState._grant_reward(GameState.Reward.HINT)
		popup.open(question)
		assert_true(popup.hint_button.visible)
		popup.hint_button.pressed.emit()

		assert_eq(GameState.hints_available, 1)
		assert_false(popup.hint_button.visible)
		assert_false(popup.choice_buttons[correct_index].disabled)
		var removed := 0
		for button in popup.choice_buttons:
			if button.disabled:
				removed += 1
		assert_eq(removed, 1)

		popup.open(question)
		assert_true(popup.hint_button.visible)
		for i in range(popup.choice_buttons.size()):
			assert_false(popup.choice_buttons[i].disabled)
			assert_eq(popup.choice_buttons[i].text, "%d. %s" % [i + 1, question["choices"][i]])
		popup.hint_button.pressed.emit()
		assert_eq(GameState.hints_available, 0)

	popup.open(question)
	assert_false(popup.hint_button.visible)
	popup.choice_buttons[question["correct"]].pressed.emit()
