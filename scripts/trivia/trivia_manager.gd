extends CanvasLayer

## Autoloaded singleton. Owns the trivia popup and pauses the tree while a
## question is on screen so the player can't wander off mid-question.

signal answered(was_correct: bool)

const POPUP_SCENE: PackedScene = preload("res://tscn/trivia/trivia_popup.tscn")

const QUESTIONS: Array[Dictionary] = [
	{"question": "What is the capital of France?", "choices": ["Paris", "London", "Rome", "Berlin"], "correct": 0},
	{"question": "What is 7 x 8?", "choices": ["54", "56", "62", "64"], "correct": 1},
	{"question": "Which planet is known as the Red Planet?", "choices": ["Venus", "Jupiter", "Mars", "Saturn"], "correct": 2},
	{"question": "How many continents are there on Earth?", "choices": ["5", "6", "7", "8"], "correct": 2},
	{"question": "What is the largest ocean on Earth?", "choices": ["Atlantic", "Indian", "Arctic", "Pacific"], "correct": 3},
	{"question": "In what year did World War II end?", "choices": ["1943", "1944", "1945", "1946"], "correct": 2},
]

var _popup: Control
var _question_bag: Array[int] = []
var _last_question_index: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_popup = POPUP_SCENE.instantiate()
	add_child(_popup)
	_popup.hide()
	_popup.choice_selected.connect(_on_choice_selected)


func ask_random_question() -> void:
	if _question_bag.is_empty():
		_refill_question_bag()
	var index: int = _question_bag.pop_back()
	_last_question_index = index
	var question: Dictionary = QUESTIONS[index]
	get_tree().paused = true
	_popup.open(question)


# Shuffled draw order avoids repeating a question until the whole set is used.
# Also re-shuffles if the last question of the previous cycle would land
# first again, so cycle boundaries can't repeat a question back-to-back.
func _refill_question_bag() -> void:
	_question_bag.assign(range(QUESTIONS.size()))
	_question_bag.shuffle()
	while QUESTIONS.size() > 1 and _question_bag.back() == _last_question_index:
		_question_bag.shuffle()


func _on_choice_selected(is_correct: bool) -> void:
	get_tree().paused = false
	if is_correct:
		GameState.add_key()
	answered.emit(is_correct)
