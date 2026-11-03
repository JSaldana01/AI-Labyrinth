extends CanvasLayer

## Autoloaded singleton. Owns the trivia popup and pauses the tree while a
## question is on screen so the player can't wander off mid-question.

signal answered(was_correct: bool)

const POPUP_SCENE: PackedScene = preload("res://tscn/trivia/trivia_popup.tscn")

const QUESTIONS: Array[Dictionary] = [
	{"question": "Which lecturer is also an advisor?", "choices": ["Christoph Csallner", "Donna French", "Chenxi Wang", "Marika Apostolova"], "correct": 1},
	{"question": "How many bits are in a byte?", "choices": ["4", "8", "16", "32"], "correct": 1},
	{"question": "Which building is the Science and Engineering Library in?", "choices": ["Nedderman Hall", "Engineering Research Building", "SEIR", "Central Library"], "correct": 0},
	{"question": "Out of the following companies, which is not considered a FAANG company?", "choices": ["Meta", "Amazon", "Nvidia", "Google"], "correct": 2},
	{"question": "Which of the below is not a current CSE undergraduate advisor?", "choices": ["Katy Gonzalez", "Melinda Rose", "Katie MacKenzie", "Ryanne Johnson"], "correct": 1},
	{"question": "What year was UTA founded?", "choices": ["1870", "1885", "1895", "1909"], "correct": 2},
	{"question": "Which UTA building houses the undergraduate CSE advisors?", "choices": ["Nedderman Hall", "Engineering Research Building", "SEIR", "Central Library"], "correct": 1},
	{"question": "Which programming language is primarily used for Godot Engine scripting?", "choices": ["C#", "GDScript", "Python", "JavaScript"], "correct": 1},
	{"question": "What does HTML stand for?", "choices": ["HyperText Markup Language", "HighText Machine Language", "HyperText Markdown Language", "HyperTool Multi Language"], "correct": 0},
	{"question": "Which of the following does not exist in GitHub?", "choices": ["Repositories", "Issues", "Pull Requests", "Branches", "Widgets"], "correct": 4},
	{"question": "Which version control system is commonly used with GitHub?", "choices": ["Subversion", "Mercurial", "Git", "CVS"], "correct": 2},
	{"question": "What is the main programming language taught in CSE 1310?", "choices": ["C", "C++", "Python", "Java"], "correct": 0},
	{"question": "Which of the following is a front-end web development framework?", "choices": ["Django", "React", "Flask", "Laravel"], "correct": 1},
	{"question": "Which of the following is a back-end web development framework?", "choices": ["Django", "React", "Flask", "Laravel"], "correct": 0},
	{"question": "Which of the following is a database management system?", "choices": ["MySQL", "React", "Flask", "Laravel"], "correct": 0},
	{"question": "Which of the following is not a programming language?", "choices": ["Python", "Java", "HTML", "C++"], "correct": 2},
	{"question": "Which of the following is a markup language?", "choices": ["HTML", "Python", "C++", "Java"], "correct": 0},
	{"question": "Which of the following is not a topic discussed in Dr. Csallner's CSE 3311 course?", "choices": ["Use Cases", "Iterative Programming", "Agentic Coding", "Citations"], "correct": 3},
	{"question": "Which of the following is not a gaming platform?", "choices": ["PlayStation", "Xbox", "Nintendo Switch", "Windows"], "correct": 3},
	{"question": "Which of the following is a type of computer memory?", "choices": ["RAM", "CPU", "GPU", "SSD"], "correct": 0},
	{"question": "Which of the following is a type of storage device?", "choices": ["RAM", "CPU", "GPU", "SSD"], "correct": 3},
	{"question": "Which of the following is a type of processor?", "choices": ["RAM", "CPU", "GPU", "SSD"], "correct": 1},
	{"question": "Who won UTA's Hackathon in 2024?", "choices": ["Team AiAiO", "Team Alpha", "Team GitShredded", "Team Beta"], "correct": 0},
	{"question": "What year did the BugHouse open?", "choices": ["2021", "2022", "2023", "2024"], "correct": 3},
	{"question": "What should you do if you encounter a bug in the game?", "choices": ["Ignore it", "Report it to the developers", "Try to fix it yourself", "Restart the game"], "correct": 1},
	{"question": "Which of the following is a common method for debugging code?", "choices": ["Print statements", "Guessing", "Ignoring errors", "Restarting the computer"], "correct": 0},
	{"question": "What does CSE stand for?", "choices": ["Computer Science and Engineering", "Civil and Structural Engineering", "Chemical Science and Engineering", "Computational Systems Engineering"], "correct": 0},
	{"question": "Which of the following is not an agile type of programming development process?", "choices": ["Iterative", "Waterfall", "Agile", "Scrum"], "correct": 1},
	{"question": "Which of the following is a version control system?", "choices": ["Git", "Docker", "Kubernetes", "Jenkins"], "correct": 0},
	{"question": "What is the minimum GPA required for CSE majors?", "choices": ["2.0", "2.25", "2.5", "2.35"], "correct": 1}
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
