extends Area3D

## Blaster shot fired by the player while Blaster Mode is active. Flies in a
## straight line; hitting the enemy sends it back to the far side of the maze,
## hitting a wall (or anything else solid) just removes the shot.

const SPEED := 20.0
const LIFETIME := 3.0
# Keep the radius large enough that the shot can't skip over a 0.2-thick wall
# between physics frames at SPEED.
const RADIUS := 0.15
const COLOR := Color(0.9, 0.2, 1.0)

var direction := Vector3.FORWARD
var _time_left := LIFETIME


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	shape.shape = sphere
	add_child(shape)

	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR
	material.emission_enabled = true
	material.emission = COLOR
	material.emission_energy_multiplier = 3.0

	var mesh := SphereMesh.new()
	mesh.radius = RADIUS
	mesh.height = RADIUS * 2.0
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)

	# A small light so the shot is visible in the dark maze.
	var glow := OmniLight3D.new()
	glow.light_color = COLOR
	glow.light_energy = 1.5
	glow.omni_range = 2.0
	add_child(glow)

	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += direction * SPEED * delta
	_time_left -= delta
	if _time_left <= 0.0:
		queue_free()


# The enemy is an Area3D; fork triggers are too, so only the "enemy" group counts.
func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group("enemy"):
		area.respawn()
		queue_free()


# Walls and the floor are StaticBody3Ds. The shot starts inside the player,
# so the player's own body is ignored.
func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		return
	queue_free()
