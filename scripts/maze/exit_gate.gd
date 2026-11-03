extends Area3D

## Placed at the maze's far cell as a staircase; touching it only lets the
## player finish the level once GameState reports enough keys have been
## collected.

const STAIRS_MESH: Mesh = preload("res://scripts/ui/assets/models/staircase model/stairsculpt.obj")
const STAIRS_TEXTURE: Texture2D = preload("res://scripts/ui/assets/models/staircase model/maze-wall-texture.png")

# Raw model bounds: x -16.88..15.46, y 0.20..10.57, z -23.05..0.11. The stairs
# are wide along X and climb toward -Z.
const MODEL_CENTER_XZ := Vector2(-0.71, -11.47)
const MODEL_BOTTOM_Y := 0.197
const MODEL_SIZE := Vector3(32.34, 10.37, 23.17)

var _cell_size := 4.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# Stay inert briefly after being created so a freshly built maze can't
	# trigger the exit before the player has been moved back to the start.
	monitoring = false
	await get_tree().create_timer(0.75).timeout
	monitoring = true


# Fits the stairs inside one maze cell, as tall as the walls allow, and builds
# a trimesh collider so the player can actually walk up them.
func setup(cell_size: float, wall_height: float, entry_angle: float) -> void:
	_cell_size = cell_size
	var target := Vector3(cell_size * 0.8, wall_height * 0.9, cell_size * 0.8)
	var model_scale := target / MODEL_SIZE

	# The model's low end is at +Z; entry_angle turns it toward the open side.
	var stairs := Node3D.new()
	stairs.name = "Stairs"
	stairs.rotation.y = entry_angle
	stairs.scale = model_scale
	stairs.position = Vector3(0, -wall_height / 2.0, 0)
	add_child(stairs)

	var material := StandardMaterial3D.new()
	material.albedo_texture = STAIRS_TEXTURE
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / 2.0

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = STAIRS_MESH
	mesh_instance.material_override = material
	mesh_instance.position = Vector3(-MODEL_CENTER_XZ.x, -MODEL_BOTTOM_Y, -MODEL_CENTER_XZ.y)
	stairs.add_child(mesh_instance)

	var body := StaticBody3D.new()
	body.name = "StairsBody"
	stairs.add_child(body)
	var collider := CollisionShape3D.new()
	collider.shape = STAIRS_MESH.create_trimesh_shape()
	collider.position = mesh_instance.position
	body.add_child(collider)

	var shape: BoxShape3D = $CollisionShape3D.shape
	shape.size = Vector3(cell_size * 0.6, wall_height, cell_size * 0.6)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	# Ignore stale overlaps from a player who has already been moved away.
	var offset := body.global_position - global_position
	if Vector2(offset.x, offset.z).length() > _cell_size:
		return
	GameState.try_open_exit()
