extends Control

signal choice_selected(is_correct: bool)

@onready var question_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/QuestionLabel
@onready var choice_buttons: Array[Button] = [
	$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Choice1,
	$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Choice2,
	$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Choice3,
	$CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Choice4,
]

var _correct_index: int = -1


func _ready() -> void:
	for i in choice_buttons.size():
		choice_buttons[i].pressed.connect(_on_choice_pressed.bind(i))


func open(question: Dictionary) -> void:
	question_label.text = question["question"]
	var choices: Array = question["choices"]
	for i in choice_buttons.size():
		choice_buttons[i].text = "%d. %s" % [i + 1, choices[i]]
	_correct_index = question["correct"]
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_choice_pressed(index: int) -> void:
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	choice_selected.emit(index == _correct_index)
