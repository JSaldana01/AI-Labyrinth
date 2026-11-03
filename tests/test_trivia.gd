extends GutTest

## Tests for the trivia question data and the TriviaManager autoload logic.
## The popup UI is not opened here; answers are fed straight to the handler.

const D = preload("res://scripts/game/game_state.gd").Difficulty


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
	TriviaManager._on_choice_selected(false)
	assert_eq(GameState.keys_collected, 0)
	assert_signal_emitted_with_parameters(TriviaManager, "answered", [false])


func test_answering_unpauses_the_game() -> void:
	get_tree().paused = true
	TriviaManager._on_choice_selected(false)
	assert_false(get_tree().paused)
