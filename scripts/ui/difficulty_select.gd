extends Control

## Shown right after login. Picks the difficulty, then loads the maze.

const MAZE_SCENE := "res://tscn/maze/maze.tscn"
const BACKGROUND: Texture2D = preload("res://scripts/ui/assets/images/background-image.png")

const DESCRIPTIONS := {
	GameState.Difficulty.EASY: "Smaller maze, no enemy",
	GameState.Difficulty.MEDIUM: "Slow skeleton chases you, 3 hearts",
	GameState.Difficulty.HARD: "Fast skeleton, larger maze, 1 heart",
}


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var background := TextureRect.new()
	background.texture = BACKGROUND
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(340, 0)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = "Choose Difficulty"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	box.add_child(title)

	for level in GameState.DIFFICULTY_SETTINGS:
		var button := Button.new()
		button.text = GameState.DIFFICULTY_SETTINGS[level]["name"]
		button.custom_minimum_size = Vector2(0, 48)
		button.pressed.connect(_start.bind(level))
		box.add_child(button)

		var description := Label.new()
		description.text = DESCRIPTIONS[level]
		description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		description.modulate = Color(1, 1, 1, 0.75)
		box.add_child(description)


func _start(level: int) -> void:
	GameState.set_difficulty(level)
	get_tree().change_scene_to_file(MAZE_SCENE)
