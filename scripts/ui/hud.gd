extends CanvasLayer

## Shows the current key count and transient lock/win messages.

const HEART_TEXTURE: Texture2D = preload("res://scripts/ui/assets/images/heart.png")
const HEART_SIZE := Vector2(40, 40)

@onready var key_label: Label = $MarginContainer/KeyLabel
@onready var message_label: Label = $MessageLabel
@onready var message_timer: Timer = $MessageTimer

var _hearts_box: HBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hearts()
	GameState.key_count_changed.connect(_on_key_count_changed)
	GameState.exit_denied.connect(_on_exit_denied)
	GameState.level_completed.connect(_on_level_completed)
	GameState.lives_changed.connect(_on_lives_changed)
	message_timer.timeout.connect(_on_message_timer_timeout)
	message_label.hide()
	_on_key_count_changed(GameState.keys_collected)
	_on_lives_changed(GameState.lives)


# Hearts sit in the top-right corner, one icon per remaining life.
func _build_hearts() -> void:
	_hearts_box = HBoxContainer.new()
	_hearts_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hearts_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hearts_box.offset_top = 16
	_hearts_box.offset_right = -16
	_hearts_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hearts_box)


func _on_lives_changed(new_lives: int) -> void:
	for child in _hearts_box.get_children():
		_hearts_box.remove_child(child)
		child.queue_free()
	for i in range(new_lives):
		var heart := TextureRect.new()
		heart.texture = HEART_TEXTURE
		heart.custom_minimum_size = HEART_SIZE
		heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_hearts_box.add_child(heart)


func _on_key_count_changed(new_count: int) -> void:
	key_label.text = "Keys: %d/%d" % [new_count, GameState.keys_required]


func _on_exit_denied(keys_needed: int) -> void:
	_show_message("Locked! Need %d more key(s)." % keys_needed)


func _on_level_completed() -> void:
	_show_message("You escaped the maze! A new maze awaits...")


func _show_message(text: String) -> void:
	message_label.text = text
	message_label.show()
	message_timer.start()


func _on_message_timer_timeout() -> void:
	message_label.hide()
