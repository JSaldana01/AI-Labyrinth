extends Node3D

## NOTE: cell_size / wall_height / wall_thickness must match the box
## dimensions baked into wall_segment.tscn (currently 4 x 4 x 0.2). If you
## change one, update the other to keep walls from floating or overlapping.

@export var grid_width: int = 6
@export var grid_height: int = 6

@export var cell_size: float = 4.0
@export var wall_height: float = 4.0
@export var wall_thickness: float = 0.2

const WALL_SCENE: PackedScene = preload("res://tscn/maze/wall_segment.tscn")
const FORK_TRIGGER_SCENE: PackedScene = preload("res://tscn/maze/fork_trigger.tscn")
const EXIT_GATE_SCENE: PackedScene = preload("res://tscn/maze/exit_gate.tscn")
const ENEMY_SCENE: PackedScene = preload("res://tscn/maze/enemy.tscn")
const MAZE_TEXTURE: Texture2D = preload("res://scripts/ui/assets/images/maze-wall-texture.png")
# World units covered by one repeat of the texture.
const TEXTURE_TILE_SIZE := 2.0

# Ground fog: stacked, semi-transparent planes whose noise scrolls over time.
# Lit by the flashlight only, so it shows up where the player is looking.
const FOG_LAYER_HEIGHTS := [0.05, 0.15, 0.28]
const FOG_SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec2 scroll = vec2(0.03, 0.012);
uniform float tile = 0.12;
uniform float density = 0.55;
uniform vec3 fog_color : source_color = vec3(0.72, 0.78, 0.85);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * tile;
	float n1 = texture(noise_tex, uv + scroll * TIME).r;
	float n2 = texture(noise_tex, uv * 1.8 - vec2(scroll.y, scroll.x) * 1.4 * TIME).r;
	float n = (n1 + n2) * 0.5;
	ALBEDO = fog_color;
	EMISSION = fog_color * 0.03;
	ROUGHNESS = 1.0;
	ALPHA = smoothstep(0.42, 0.72, n) * density;
}
"""

var _maze_material: StandardMaterial3D
var _enemy: Node3D
var _fog_layers: Array[MeshInstance3D] = []

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
	_create_maze_material()
	GameState.level_completed.connect(_on_level_completed)
	GameState.difficulty_changed.connect(_on_difficulty_changed)
	_rebuild_maze()


func _exit_tree() -> void:
	if GameState.level_completed.is_connected(_on_level_completed):
		GameState.level_completed.disconnect(_on_level_completed)
	if GameState.difficulty_changed.is_connected(_on_difficulty_changed):
		GameState.difficulty_changed.disconnect(_on_difficulty_changed)


# Applies the current difficulty (maze size, flashlight range), then builds a fresh maze.
func _rebuild_maze() -> void:
	for root in [walls_root, fork_triggers_root, exit_root]:
		for child in root.get_children():
			root.remove_child(child)
			child.queue_free()

	grid_width = GameState.get_setting("grid_size")
	grid_height = GameState.get_setting("grid_size")
	var flashlight: SpotLight3D = player.get_node_or_null("Head/Camera3D/SpotLight3D")
	if flashlight:
		flashlight.spot_range = GameState.get_setting("light_range")

	_resize_floor()
	_build_roof()
	_build_fog()
	_generate_grid()
	_carve_maze()
	_build_walls()
	_place_fork_triggers()
	_place_exit_gate()
	_place_player()
	_spawn_enemy()


# --- Ground fog ----------------------------------------------------------

func _build_fog() -> void:
	var size := Vector2(grid_width * cell_size, grid_height * cell_size)
	var center := Vector3(size.x / 2.0, 0.0, size.y / 2.0)

	if _fog_layers.is_empty():
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.02
		var noise_texture := NoiseTexture2D.new()
		noise_texture.noise = noise
		noise_texture.seamless = true
		noise_texture.width = 256
		noise_texture.height = 256

		var shader := Shader.new()
		shader.code = FOG_SHADER_CODE

		for i in range(FOG_LAYER_HEIGHTS.size()):
			var material := ShaderMaterial.new()
			material.shader = shader
			material.set_shader_parameter("noise_tex", noise_texture)
			# Each layer drifts at its own speed and direction for a layered look.
			var drift := 1.0 + i * 0.6
			material.set_shader_parameter("scroll", Vector2(0.03 * drift, 0.012 * (i % 2 * 2 - 1) * drift))

			var layer := MeshInstance3D.new()
			layer.name = "Fog%d" % i
			layer.mesh = PlaneMesh.new()
			layer.material_override = material
			layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(layer)
			_fog_layers.append(layer)

	for i in range(_fog_layers.size()):
		var layer: MeshInstance3D = _fog_layers[i]
		layer.mesh.size = size
		layer.position = center + Vector3(0, FOG_LAYER_HEIGHTS[i], 0)


# --- Enemy support -------------------------------------------------------

func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(
		clampi(floori(pos.x / cell_size), 0, grid_width - 1),
		clampi(floori(pos.z / cell_size), 0, grid_height - 1)
	)


func cell_center(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * cell_size, 0.0, (cell.y + 0.5) * cell_size)


# Breadth-first walk over open sides; returns steps from `origin` for each cell.
func _distances_from(origin: Vector2i) -> Dictionary:
	var dist := {origin: 0}
	var queue: Array[Vector2i] = [origin]
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for dir_key in DIRS.keys():
			if grid[cell.x][cell.y][dir_key]:
				continue
			var neighbor: Vector2i = cell + DIRS[dir_key]
			if not dist.has(neighbor):
				dist[neighbor] = dist[cell] + 1
				queue.append(neighbor)
	return dist


# The neighbouring open cell of `from` that is one step closer to `to`.
func next_cell_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	var dist := _distances_from(to)
	var best := from
	for dir_key in DIRS.keys():
		if grid[from.x][from.y][dir_key]:
			continue
		var neighbor: Vector2i = from + DIRS[dir_key]
		if dist.has(neighbor) and dist[neighbor] < dist[best]:
			best = neighbor
	return best


func farthest_cell_center_from(pos: Vector3) -> Vector3:
	var dist := _distances_from(world_to_cell(pos))
	var best := Vector2i(0, 0)
	var best_dist := -1
	for cell in dist:
		if dist[cell] > best_dist:
			best_dist = dist[cell]
			best = cell
	return cell_center(best)


func _spawn_enemy() -> void:
	if _enemy != null:
		_enemy.queue_free()
		_enemy = null

	var enemy_speed: float = GameState.get_setting("enemy_speed")
	if enemy_speed <= 0.0:
		return

	_enemy = ENEMY_SCENE.instantiate()
	add_child(_enemy)
	_enemy.setup(self, player, enemy_speed)
	_enemy.global_position = farthest_cell_center_from(player.global_position)


# Deferred so the exit gate isn't freed in the middle of its own physics callback.
func _on_level_completed() -> void:
	_regenerate_maze.call_deferred()


func _regenerate_maze() -> void:
	GameState.reset_keys()
	player.velocity = Vector3.ZERO
	_rebuild_maze()


func _on_difficulty_changed() -> void:
	player.velocity = Vector3.ZERO
	_rebuild_maze()


# Flat ceiling over the whole maze, textured like the walls. Visual only; it is
# viewed from below, so the plane is flipped to face downward.
func _build_roof() -> void:
	var size_x := grid_width * cell_size
	var size_z := grid_height * cell_size

	var roof: MeshInstance3D = get_node_or_null("Roof")
	if roof == null:
		roof = MeshInstance3D.new()
		roof.name = "Roof"
		roof.mesh = PlaneMesh.new()
		roof.material_override = _maze_material
		add_child(roof)

	roof.mesh.size = Vector2(size_x, size_z)
	roof.transform = Transform3D(
		Basis(Vector3.RIGHT, PI), Vector3(size_x / 2.0, wall_height, size_z / 2.0)
	)


# World-space triplanar mapping keeps the texture at the same scale on the
# floor and on walls of any orientation, with no UV stretching.
func _create_maze_material() -> void:
	_maze_material = StandardMaterial3D.new()
	_maze_material.albedo_texture = MAZE_TEXTURE
	_maze_material.uv1_triplanar = true
	_maze_material.uv1_world_triplanar = true
	_maze_material.uv1_scale = Vector3.ONE / TEXTURE_TILE_SIZE
	_maze_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


# Allows the floor size to cover the correct space
# regardless of its set values in the inspector
func _resize_floor() -> void:
	var size_x := grid_width * cell_size
	var size_z := grid_height * cell_size
	var center := Vector3(size_x / 2.0, 0.0, size_z / 2.0)

	var plane_mesh: PlaneMesh = floor_mesh.mesh
	plane_mesh.size = Vector2(size_x, size_z)
	floor_mesh.transform = Transform3D(Basis(), center)
	floor_mesh.material_override = _maze_material

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
	wall.get_node("MeshInstance3D").material_override = _maze_material

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
# so there are always at least keys_required chances to earn a key.
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
	if trigger_cells.size() < GameState.keys_required:
		other_cells.shuffle()
		var needed: int = GameState.keys_required - trigger_cells.size()
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

	_move_trigger_to_cell(trigger, Vector2i(x, y))
	trigger.relocate_requested.connect(_relocate_trigger)


func _move_trigger_to_cell(trigger: Node3D, cell_pos: Vector2i) -> void:
	trigger.set_meta("cell", cell_pos)
	var pos := Vector3(
		(cell_pos.x + 0.5) * cell_size, wall_height / 2.0, (cell_pos.y + 0.5) * cell_size
	)
	trigger.transform = Transform3D(Basis(), pos)


# Moves a trigger (and its key) to a random free cell after a wrong answer.
# The start cell, exit cell, and cells holding another trigger are excluded.
func _relocate_trigger(trigger: Node3D) -> void:
	var exit_cell := Vector2i(grid_width - 1, grid_height - 1)
	var occupied := {}
	for other in fork_triggers_root.get_children():
		occupied[other.get_meta("cell")] = true

	var free_cells: Array[Vector2i] = []
	for x in range(grid_width):
		for y in range(grid_height):
			var cell_pos := Vector2i(x, y)
			if (x == 0 and y == 0) or cell_pos == exit_cell or occupied.has(cell_pos):
				continue
			free_cells.append(cell_pos)

	if free_cells.is_empty():
		return
	_move_trigger_to_cell(trigger, free_cells.pick_random())


# Places the exit gate at the far corner of the maze, opposite the spawn.
func _place_exit_gate() -> void:
	var x := grid_width - 1
	var y := grid_height - 1

	var gate := EXIT_GATE_SCENE.instantiate()
	exit_root.add_child(gate)
	gate.setup(cell_size, wall_height, _exit_entry_angle(grid[x][y]))

	var pos := Vector3((x + 0.5) * cell_size, wall_height / 2.0, (y + 0.5) * cell_size)
	gate.transform = Transform3D(Basis(), pos)


# The exit cell's N and E sides are outer walls, so the stairs' bottom step
# must face its open "S" (world -Z) or "W" (world -X) side to be reachable.
# Returns the Y rotation that points the stairs' bottom toward that side.
func _exit_entry_angle(cell: Dictionary) -> float:
	if not cell["S"]:
		return PI
	return -PI / 2.0


func _place_player() -> void:
	# y value set to 1.0 so that player won't spawn inside of floor
	var start_pos := Vector3(cell_size / 2.0, 1.0, cell_size / 2.0)
	player.transform = Transform3D(Basis(), start_pos)
