extends Node3D

## NOTE: cell_size / wall_height / wall_thickness must match the box
## dimensions baked into wall_segment.tscn (currently 4 x 2.5 x 0.2). If you
## change one, update the other to keep walls from floating or overlapping.

@export var grid_width: int = 6
@export var grid_height: int = 6

@export var cell_size: float = 4.0
@export var wall_height: float = 2.5
@export var wall_thickness: float = 0.2

const WALL_SCENE: PackedScene = preload("res://tscn/maze/wall_segment.tscn")

# Grid-space direction offsets. 
#"N"/"S" map to world -Z/+Z via the y index,
# "E"/"W" map to world +X/-X via the x index 
# The compass names are just labels, not actual directions.
const DIRS := {
	"N": Vector2i(0, 1),
	"S": Vector2i(0, -1),
	"E": Vector2i(1, 0),
	"W": Vector2i(-1, 0),
}
const OPPOSITE := {"N": "S", "S": "N", "E": "W", "W": "E"}

@onready var walls_root: Node3D = $Walls
@onready var floor_mesh: MeshInstance3D = $Floor/MeshInstance3D
@onready var floor_shape: CollisionShape3D = $Floor/CollisionShape3D
@onready var player: CharacterBody3D = $Player

# grid[x][y] = {"N": bool, "S": bool, "E": bool, "W": bool}
# A true value means that a wall is present
var grid: Array = []


func _ready() -> void:
	_resize_floor()
	_generate_grid()
	_carve_maze()
	_build_walls()
	_place_player()

# Allows the floor size to cover the correct space
# regardless of its set values in the inspector
func _resize_floor() -> void:
	var size_x := grid_width * cell_size
	var size_z := grid_height * cell_size
	var center := Vector3(size_x / 2.0, 0.0, size_z / 2.0)

	var plane_mesh: PlaneMesh = floor_mesh.mesh
	plane_mesh.size = Vector2(size_x, size_z)
	floor_mesh.transform = Transform3D(Basis(), center)

	var box_shape: BoxShape3D = floor_shape.shape
	box_shape.size = Vector3(size_x, 1.0, size_z)
	floor_shape.transform = Transform3D(Basis(), center - Vector3(0, 0.5, 0))


# Builds 2-D array that will be used to build maze
func _generate_grid() -> void:
	grid.clear()
	for x in range(grid_width):
		var column: Array = []
		for y in range(grid_height):
			column.append({"N": true, "S": true, "E": true, "W": true})
		grid.append(column)


# Maze generation using DFS
func _carve_maze() -> void:
	var visited := {}
	var stack: Array[Vector2i] = []
	var start := Vector2i(0, 0)
	stack.push_back(start)
	visited[start] = true

	while not stack.is_empty():
		var current: Vector2i = stack.back()
		var candidates := _unvisited_neighbor_dirs(current, visited)

		if candidates.is_empty():
			stack.pop_back()
			continue

		var dir_key: String = candidates[randi() % candidates.size()]
		var next: Vector2i = current + DIRS[dir_key]

		grid[current.x][current.y][dir_key] = false
		grid[next.x][next.y][OPPOSITE[dir_key]] = false

		visited[next] = true
		stack.push_back(next)


# Helper function for _carve_maze()
# Takes a cell and checks all dir and returns the dirs that are in bounds
# and have not been visited yet
func _unvisited_neighbor_dirs(cell: Vector2i, visited: Dictionary) -> Array:
	var result: Array = []
	for dir_key in DIRS.keys():
		var neighbor: Vector2i = cell + DIRS[dir_key]
		var in_bounds := neighbor.x >= 0 and neighbor.x < grid_width \
			and neighbor.y >= 0 and neighbor.y < grid_height
		if in_bounds and not visited.has(neighbor):
			result.append(dir_key)
	return result

# Takes grid data and turns it into geometry
func _build_walls() -> void:
	for x in range(grid_width):
		for y in range(grid_height):
			var cell = grid[x][y]
			# Interior + far boundary walls: each shared edge is only ever
			# placed once, from the "N"/"E" side of its lower/left cell.
			if cell["N"]:
				_place_wall(x, y, "N")
			if cell["E"]:
				_place_wall(x, y, "E")
			# Near boundary walls have no lower/left neighbor to place them,
			# so they need an explicit check.
			if x == 0 and cell["W"]:
				_place_wall(x, y, "W")
			if y == 0 and cell["S"]:
				_place_wall(x, y, "S")


# Instantiates the wall segment scene and positions them in maze
func _place_wall(x: int, y: int, side: String) -> void:
	var wall := WALL_SCENE.instantiate()
	walls_root.add_child(wall)

	var pos: Vector3
	var rotation_y_deg: float = 0.0

	match side:
		"N":
			pos = Vector3((x + 0.5) * cell_size, 0.0, (y + 1) * cell_size)
		"S":
			pos = Vector3((x + 0.5) * cell_size, 0.0, y * cell_size)
		"E":
			pos = Vector3((x + 1) * cell_size, 0.0, (y + 0.5) * cell_size)
			rotation_y_deg = 90.0
		"W":
			pos = Vector3(x * cell_size, 0.0, (y + 0.5) * cell_size)
			rotation_y_deg = 90.0

	wall.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(rotation_y_deg)), pos)



func _place_player() -> void:
	# y value set to 1.0 so that player won't spawn inside of floor
	var start_pos := Vector3(cell_size / 2.0, 1.0, cell_size / 2.0)
	player.transform = Transform3D(Basis(), start_pos)
