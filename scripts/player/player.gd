extends CharacterBody3D

@export var move_speed: float = 5.0
@export var mouse_sensitivity: float = 0.003   # radians per pixel of mouse motion
@export var jump_velocity: float = 4.5

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/SpotLight3D

const PITCH_LIMIT_DEGREES := 89.0
const PROJECTILE := preload("res://scripts/player/projectile.gd")
const FIRE_COOLDOWN := 0.4
# Flashlight tint while Ghost Mode is active.
const GHOST_LIGHT_COLOR := Color(0.6, 0.8, 1.0)

var _fire_cooldown := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group("player")
	GameState.power_up_changed.connect(_on_power_up_changed)


func _unhandled_input(event: InputEvent) -> void:
	# Esc is handled by the pause menu.
	if event is InputEventMouseButton and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Yaw: rotate the whole body left/right.
		rotate_y(-event.relative.x * mouse_sensitivity)

		# Pitch: rotate only the head up/down, clamped so you can't flip over.
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		var pitch_limit := deg_to_rad(PITCH_LIMIT_DEGREES)
		head.rotation.x = clamp(head.rotation.x, -pitch_limit, pitch_limit)

	# has_blaster() is checked first so the "shoot" action is only looked up
	# while Blaster Mode is active.
	if GameState.has_blaster() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and event.is_action_pressed("shoot"):
		_shoot()


func _shoot() -> void:
	if _fire_cooldown > 0.0:
		return
	_fire_cooldown = FIRE_COOLDOWN

	var shot: Area3D = PROJECTILE.new()
	# Fire where the camera looks, including pitch.
	shot.direction = -camera.global_basis.z
	# Added to the maze, not the player, so the shot doesn't move or turn with us.
	get_parent().add_child(shot)
	shot.global_position = camera.global_position


func _on_power_up_changed(power_up: int, _time_left: float) -> void:
	flashlight.light_color = GHOST_LIGHT_COLOR if power_up == GameState.PowerUp.GHOST else Color.WHITE


func _physics_process(delta: float) -> void:
	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta

	# Will allow player to fall back down after jumping (jumping may not be necessary in the end)
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	# Movement input
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction.length() > 0.0:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		# Decelerate instead of stopping instantly. Feels a bit better for me
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)

	move_and_slide()

