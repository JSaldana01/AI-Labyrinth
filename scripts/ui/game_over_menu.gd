extends CanvasLayer

## Shown when the player loses all hearts. Offers Replay (same difficulty),
## a difficulty switch, or Quit. Both Replay and Change Difficulty go through
## GameState.set_difficulty, which rebuilds the maze and resets keys/hearts.

var _panel: Control
var _difficulty_button: OptionButton


func _ready() -> void:
	_build_ui()
	_panel.hide()
	GameState.game_over.connect(_on_game_over)


func _on_game_over() -> void:
	_difficulty_button.select(GameState.difficulty)
	_panel.show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _restart(difficulty: int) -> void:
	_panel.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	GameState.set_difficulty(difficulty)


func _on_difficulty_selected(index: int) -> void:
	_restart(index)


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_panel = root

	var dim := ColorRect.new()
	dim.color = Color(0.1, 0, 0, 0.8)
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
	title.text = "Game Over"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	box.add_child(title)

	var replay_button := Button.new()
	replay_button.text = "Replay"
	replay_button.pressed.connect(func(): _restart(GameState.difficulty))
	box.add_child(replay_button)

	var difficulty_label := Label.new()
	difficulty_label.text = "Change difficulty"
	difficulty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(difficulty_label)

	_difficulty_button = OptionButton.new()
	for level in GameState.DIFFICULTY_SETTINGS:
		_difficulty_button.add_item(GameState.DIFFICULTY_SETTINGS[level]["name"], level)
	_difficulty_button.item_selected.connect(_on_difficulty_selected)
	box.add_child(_difficulty_button)

	var quit_button := Button.new()
	quit_button.text = "Quit"
	quit_button.pressed.connect(func(): get_tree().quit())
	box.add_child(quit_button)
