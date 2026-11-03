extends CanvasLayer

## Esc toggles a pause menu with Resume, Difficulty and Quit. The UI is built
## in code. Picking a difficulty restarts the maze with that difficulty's
## size, key requirement and flashlight range.

var _panel: Control
var _difficulty_button: OptionButton
var _completed_label: Label


func _ready() -> void:
	_build_ui()
	_panel.hide()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _panel.visible:
		_resume()
	elif not get_tree().paused:
		# Paused by something else (trivia popup): don't stack the menu on top.
		_open()
	get_viewport().set_input_as_handled()


func _open() -> void:
	_difficulty_button.select(GameState.difficulty)
	_refresh_completed_label()
	_panel.show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _refresh_completed_label() -> void:
	var lines: Array[String] = ["Mazes completed"]
	for level in GameState.DIFFICULTY_SETTINGS:
		lines.append("%s: %d" % [GameState.DIFFICULTY_SETTINGS[level]["name"], GameState.mazes_completed[level]])
	_completed_label.text = "\n".join(lines)


func _resume() -> void:
	_panel.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_difficulty_selected(index: int) -> void:
	if index == GameState.difficulty:
		return
	GameState.set_difficulty(index)
	_resume()


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_panel = root

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(260, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)

	var resume_button := Button.new()
	resume_button.text = "Resume"
	resume_button.pressed.connect(_resume)
	box.add_child(resume_button)

	var difficulty_label := Label.new()
	difficulty_label.text = "Difficulty (restarts the maze)"
	difficulty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(difficulty_label)

	_difficulty_button = OptionButton.new()
	for level in GameState.DIFFICULTY_SETTINGS:
		_difficulty_button.add_item(GameState.DIFFICULTY_SETTINGS[level]["name"], level)
	_difficulty_button.item_selected.connect(_on_difficulty_selected)
	box.add_child(_difficulty_button)

	_completed_label = Label.new()
	_completed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_completed_label)

	var quit_button := Button.new()
	quit_button.text = "Quit"
	quit_button.pressed.connect(func(): get_tree().quit())
	box.add_child(quit_button)
