extends Control

signal choice_selected(is_correct: bool)

@onready var question_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/QuestionLabel
@onready var choice_buttons: Array[Button] = [
	$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Choice1,
	$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Choice2,
	$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Choice3,
	$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Choice4,
]
@onready var hint_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/HintButton

var _correct_index: int = -1


func _ready() -> void:
	for i in choice_buttons.size():
		choice_buttons[i].pressed.connect(_on_choice_pressed.bind(i))
	hint_button.pressed.connect(_on_hint_pressed)


func open(question: Dictionary) -> void:
	question_label.text = question["question"]
	var choices: Array = question["choices"]
	for i in choice_buttons.size():
		choice_buttons[i].text = "%d. %s" % [i + 1, choices[i]]
		choice_buttons[i].disabled = false
		choice_buttons[i].show()
	_correct_index = question["correct"]
	hint_button.text = "Use Hint (%d)" % GameState.hints_available
	hint_button.visible = GameState.hints_available > 0
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_hint_pressed() -> void:
	if not GameState.use_hint():
		hint_button.hide()
		return

	var incorrect_indices: Array[int] = []
	for i in choice_buttons.size():
		if i != _correct_index:
			incorrect_indices.append(i)
	var removed_index: int = incorrect_indices.pick_random()
	choice_buttons[removed_index].disabled = true
	choice_buttons[removed_index].text = "%d. (Removed by hint)" % [removed_index + 1]
	hint_button.hide()


func _on_choice_pressed(index: int) -> void:
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	choice_selected.emit(index == _correct_index)
