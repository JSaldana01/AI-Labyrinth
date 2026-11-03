extends Area3D

## Placed at maze fork cells; asks a trivia question the first time the
## player enters. A correct answer removes the trigger for good; a wrong
## answer moves it (and its key) to a random other cell, so no key is lost
## forever.


signal relocate_requested(trigger: Node3D)

const KEY_MESH: Mesh = preload("res://scripts/ui/assets/models/key model/key.obj")
const KEY_TEXTURE: Texture2D = preload("res://scripts/ui/assets/models/key model/keytexture.png")
const KEY_SCALE := 1.6
const KEY_FLOAT_HEIGHT := 0.9
const KEY_SPIN_SPEED := 1.5
const KEY_BOB_AMPLITUDE := 0.1

var _key: Node3D
var _key_base_y := 0.0
var _time := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_create_key_sprite()


func _process(delta: float) -> void:
	if _key == null:
		return
	_time += delta
	_key.rotate_y(KEY_SPIN_SPEED * delta)
	_key.position.y = _key_base_y + sin(_time * 2.0) * KEY_BOB_AMPLITUDE


# The OBJ's long axis is Z; tilt it upright and center it on the trigger so it
# floats at a fixed height regardless of the trigger's collision box size.
func _create_key_sprite() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_texture = KEY_TEXTURE
	material.metallic = 0.6
	material.roughness = 0.35
	material.emission_enabled = true
	material.emission_texture = KEY_TEXTURE
	material.emission_energy_multiplier = 0.4

	var pivot := Node3D.new()
	_key = pivot
	add_child(pivot)
	# The trigger sits at wall_height / 2 (2.0 by default); drop the key to KEY_FLOAT_HEIGHT.
	_key_base_y = KEY_FLOAT_HEIGHT - 2.0
	pivot.position = Vector3(0, _key_base_y, 0)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = KEY_MESH
	mesh_instance.material_override = material
	mesh_instance.scale = Vector3.ONE * KEY_SCALE
	mesh_instance.rotation.x = -PI / 2.0
	# Mesh center along its Z axis is ~0.206 before rotation/scaling.
	mesh_instance.position = Vector3(0, -0.206 * KEY_SCALE, 0)
	pivot.add_child(mesh_instance)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	set_deferred("monitoring", false)
	TriviaManager.ask_random_question()
	TriviaManager.answered.connect(_on_answered, CONNECT_ONE_SHOT)


func _on_answered(was_correct: bool) -> void:
	if was_correct:
		queue_free()
	else:
		# The maze generator moves this trigger elsewhere, away from the player.
		relocate_requested.emit(self)
		set_deferred("monitoring", true)
