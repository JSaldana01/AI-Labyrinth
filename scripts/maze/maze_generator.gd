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
const FORK_TRIGGER_SCENE: PackedScene = preload("res://tscn/maze/fork_trigger.tscn")
const EXIT_GATE_SCENE: PackedScene = preload("res://tscn/maze/exit_gate.tscn")

# A cell with 3+ open sides is a fork: the player has more than one
# direction to choose from, so that's where a trivia question is asked.
const FORK_OPEN_SIDES := 3

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
@onready var fork_triggers_root: Node3D = $ForkTriggers
@onready var exit_root: Node3D = $Exit
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
	_place_fork_triggers()
	_place_exit_gate()
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



# Places a trivia trigger at every fork cell (except the player's start
# cell and the exit cell, so those aren't crowded with a redundant trigger).
# Falls back to plain corridor cells if the maze doesn't have enough forks,
# so there are always at least KEYS_REQUIRED chances to earn a key.
func _place_fork_triggers() -> void:
	var exit_cell := Vector2i(grid_width - 1, grid_height - 1)
	var fork_cells: Array[Vector2i] = []
	var other_cells: Array[Vector2i] = []

	for x in range(grid_width):
		for y in range(grid_height):
			var cell_pos := Vector2i(x, y)
			if (x == 0 and y == 0) or cell_pos == exit_cell:
				continue
			if _open_side_count(grid[x][y]) >= FORK_OPEN_SIDES:
				fork_cells.append(cell_pos)
			else:
				other_cells.append(cell_pos)

	var trigger_cells := fork_cells.duplicate()
	if trigger_cells.size() < GameState.KEYS_REQUIRED:
		other_cells.shuffle()
		var needed: int = GameState.KEYS_REQUIRED - trigger_cells.size()
		trigger_cells.append_array(other_cells.slice(0, needed))

	for cell_pos in trigger_cells:
		_place_fork_trigger(cell_pos.x, cell_pos.y)


func _open_side_count(cell: Dictionary) -> int:
	var count := 0
	for dir_key in DIRS.keys():
		if not cell[dir_key]:
			count += 1
	return count


func _place_fork_trigger(x: int, y: int) -> void:
	var trigger := FORK_TRIGGER_SCENE.instantiate()
	fork_triggers_root.add_child(trigger)

	var shape: BoxShape3D = trigger.get_node("CollisionShape3D").shape
	shape.size = Vector3(cell_size * 0.6, wall_height, cell_size * 0.6)

	var pos := Vector3((x + 0.5) * cell_size, wall_height / 2.0, (y + 0.5) * cell_size)
	trigger.transform = Transform3D(Basis(), pos)


# Places the exit gate at the far corner of the maze, opposite the spawn.
func _place_exit_gate() -> void:
	var x := grid_width - 1
	var y := grid_height - 1

	var gate := EXIT_GATE_SCENE.instantiate()
	exit_root.add_child(gate)

	var shape: BoxShape3D = gate.get_node("CollisionShape3D").shape
	shape.size = Vector3(cell_size * 0.6, wall_height, cell_size * 0.6)

	var mesh: MeshInstance3D = gate.get_node("MeshInstance3D")
	mesh.mesh.size = Vector3(cell_size * 0.4, wall_height * 0.4, cell_size * 0.4)

	var pos := Vector3((x + 0.5) * cell_size, wall_height / 2.0, (y + 0.5) * cell_size)
	gate.transform = Transform3D(Basis(), pos)


func _place_player() -> void:
	# y value set to 1.0 so that player won't spawn inside of floor
	var start_pos := Vector3(cell_size / 2.0, 1.0, cell_size / 2.0)
	player.transform = Transform3D(Basis(), start_pos)
