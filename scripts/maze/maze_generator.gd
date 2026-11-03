extends Node3D

## Builds a 3D maze from a MazeDefinition dictionary (AI or local fallback).
## Waits for MazeSession (C#) to emit maze_ready. Does not carve locally unless
## @export use_local_fallback_only is enabled (offline/dev only).

@export var grid_width: int = 9
@export var grid_height: int = 9

@export var cell_size: float = 4.0
@export var wall_height: float = 2.5
@export var wall_thickness: float = 0.2

@export var use_local_fallback_only: bool = false

const WALL_SCENE: PackedScene = preload("res://tscn/maze/wall_segment.tscn")
const FORK_TRIGGER_SCENE: PackedScene = preload("res://tscn/maze/fork_trigger.tscn")
const EXIT_GATE_SCENE: PackedScene = preload("res://tscn/maze/exit_gate.tscn")

const FORK_OPEN_SIDES := 3

const DIRS := {
	"N": Vector2i(0, 1),
	"S": Vector2i(0, -1),
	"E": Vector2i(1, 0),
	"W": Vector2i(-1, 0),
}

@onready var walls_root: Node3D = $Walls
@onready var fork_triggers_root: Node3D = $ForkTriggers
@onready var exit_root: Node3D = $Exit
@onready var blocking_root: Node3D = $BlockingVolumes
@onready var floor_mesh: MeshInstance3D = $Floor/MeshInstance3D
@onready var floor_shape: CollisionShape3D = $Floor/CollisionShape3D
@onready var player: CharacterBody3D = $Player
@onready var maze_session: Node = $MazeSession

var grid: Array = []
var spawn_cell := Vector2i(0, 0)
var exit_cell := Vector2i(8, 8)
var _loading_layer: CanvasLayer
var _loading_label: Label
var _waiting_for_network: bool = false
var _build_started: bool = false
var _last_status_log_ms: int = 0


func _ready() -> void:
	_set_player_active(false)
	set_process(false)
	_reset_maze_geometry()
	_set_maze_geometry_visible(false)

	if use_local_fallback_only:
		print("[Maze] Builder: use_local_fallback_only — procedural GDScript maze (no edge)")
		_build_local_procedural()
		_set_maze_geometry_visible(true)
		_set_player_active(true)
		return

	# MazeSession (C#) calls parent.on_maze_session_ready() on main thread when edge load finishes.
	_waiting_for_network = true
	set_process(true)
	_show_loading("Generating maze… 0.0s (network + Gemini — no walls yet)")
	print("[Maze] Builder: waiting for on_maze_session_ready() walls_children=%d" % [
		walls_root.get_child_count()
	])
	_timeline("builder waiting on edge — geometry hidden")


func _session_maze_data_ready() -> bool:
	if maze_session.has_method("is_maze_definition_ready"):
		if maze_session.call("is_maze_definition_ready") == true:
			return true
	if maze_session.get("MazeDefinitionReady") == true:
		return true
	return false


func _set_player_active(active: bool) -> void:
	player.set_process(active)
	player.set_physics_process(active)
	player.set_process_input(active)
	if not active:
		player.velocity = Vector3.ZERO


func _set_maze_geometry_visible(show_geometry: bool) -> void:
	walls_root.visible = show_geometry
	fork_triggers_root.visible = show_geometry
	exit_root.visible = show_geometry
	blocking_root.visible = show_geometry


func _reset_maze_geometry() -> void:
	_clear_children(walls_root)
	_clear_children(fork_triggers_root)
	_clear_children(exit_root)
	_clear_children(blocking_root)


func _process(_delta: float) -> void:
	if _waiting_for_network and not _build_started and _session_maze_data_ready():
		print("[Maze] Builder: poll fallback — definition ready, building now")
		on_maze_session_ready(_fetch_definition_from_session())
		return
	if not _waiting_for_network:
		return
	var wall_count := walls_root.get_child_count()
	if wall_count > 0:
		push_error("[Maze] Builder: unexpected walls (%d) before maze_ready — stale scene or old export?" % wall_count)
	var start := _load_start_ticks()
	if start <= 0:
		return
	var elapsed_ms := Time.get_ticks_msec() - start
	if elapsed_ms - _last_status_log_ms >= 15000:
		_last_status_log_ms = elapsed_ms
		var data_ready := _session_maze_data_ready()
		print("[Maze] Builder: still waiting elapsed=%.1fs edge_http_done=%s (Supabase+Gemini can take 60–120s)" % [
			elapsed_ms / 1000.0, data_ready
		])
	_show_loading(
		"Generating maze… %.1fs\n(waiting for bright-service + Gemini on server)" % (elapsed_ms / 1000.0)
	)


func _load_start_ticks() -> int:
	var v: Variant = maze_session.get("load_started_ticks_msec")
	if v == null:
		v = maze_session.get("LoadStartedTicksMsec")
	return int(v) if v != null else 0


func _timeline(phase: String) -> void:
	var start := _load_start_ticks()
	if start <= 0:
		print("[Maze] Timeline: %s" % phase)
		return
	var elapsed_ms := Time.get_ticks_msec() - start
	print("[Maze] Timeline: t=%dms %s" % [elapsed_ms, phase])


## Called from MazeSession (C#) with definition dict + metadata (public — no leading _).
func on_maze_session_ready(
	definition: Dictionary = {},
	gen: String = "",
	inst: String = "",
	network_ms: int = 0,
) -> void:
	if _build_started:
		return

	if definition.is_empty():
		definition = _fetch_definition_from_session()
	if definition.is_empty():
		if not _session_maze_data_ready():
			push_warning("[Maze] Builder: on_maze_session_ready ignored — no definition yet")
			return
		definition = _fetch_definition_from_session()

	if definition.is_empty():
		push_error("[Maze] Builder: empty definition after edge — not building")
		_show_loading("ERROR: empty maze definition from server")
		return

	if gen.is_empty():
		gen = str(maze_session.get("generator"))
	if inst.is_empty():
		inst = str(maze_session.get("maze_instance_id"))
	if network_ms == 0:
		network_ms = int(maze_session.get("last_network_load_ms"))
		if network_ms == 0:
			network_ms = int(maze_session.get("LastNetworkLoadMs"))

	_build_started = true
	_waiting_for_network = false
	set_process(false)

	_timeline("builder on_maze_session_ready — spawning 3D geometry now")
	print("[Maze] Builder: build generator=%s maze_instance_id=%s network_ms=%d walls_before=%d" % [
		gen, inst, network_ms, walls_root.get_child_count()
	])

	var schema_v: int = int(definition.get("schema_version", 0))
	if schema_v != 1:
		push_error("[Maze] Builder: bad schema_version=%s — not building" % str(definition.get("schema_version")))
		_show_loading("ERROR: invalid maze schema from server")
		return

	build_from_definition(definition)
	_set_maze_geometry_visible(true)
	_timeline("builder finished 3D geometry — enabling player")
	_hide_loading()
	_set_player_active(true)
	var hud: CanvasLayer = get_node_or_null("HUD")
	if hud and hud.has_method("set_maze_source"):
		hud.call("set_maze_source", gen, inst, network_ms)


func _fetch_definition_from_session() -> Dictionary:
	# C# methods are not always visible to call(); try PascalCase then property.
	if maze_session.has_method("GetDefinitionDictionary"):
		var d = maze_session.call("GetDefinitionDictionary")
		if d is Dictionary:
			return d
	var prop: Variant = maze_session.get("DefinitionDictionary")
	if prop is Dictionary:
		return prop
	return {}


func _on_maze_ready() -> void:
	on_maze_session_ready()


func build_from_definition(definition: Dictionary) -> void:
	grid_width = int(definition.get("width", grid_width))
	grid_height = int(definition.get("height", grid_height))

	var spawn_arr: Array = definition.get("spawn", [0, 0])
	var exit_arr: Array = definition.get("exit", [grid_width - 1, grid_height - 1])
	spawn_cell = Vector2i(int(spawn_arr[0]), int(spawn_arr[1]))
	exit_cell = Vector2i(int(exit_arr[0]), int(exit_arr[1]))

	_populate_grid_from_cells(definition.get("cells", []))

	var trivia_count := _count_tagged_cells("trivia")
	var block_count := _count_blocking_cells()
	print("[Maze] Builder: build_from_definition START %dx%d spawn=%s exit=%s trivia=%d blocking=%d" % [
		grid_width, grid_height, spawn_cell, exit_cell, trivia_count, block_count
	])

	_clear_children(walls_root)
	_clear_children(fork_triggers_root)
	_clear_children(exit_root)
	_clear_children(blocking_root)

	_resize_floor()
	_build_walls()
	_place_fork_triggers_from_tags()
	_place_blocking_volumes()
	_place_exit_gate()
	_place_player()
	print("[Maze] Builder: build_from_definition DONE wall_nodes=%d" % walls_root.get_child_count())


func _show_loading(text: String) -> void:
	if _loading_layer == null:
		_loading_layer = CanvasLayer.new()
		_loading_layer.layer = 50
		_loading_layer.name = "MazeLoadingLayer"
		var margin := MarginContainer.new()
		margin.name = "MarginContainer"
		margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		_loading_label = Label.new()
		_loading_label.name = "LoadingLabel"
		_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		margin.add_child(_loading_label)
		_loading_layer.add_child(margin)
		add_child(_loading_layer)
	if _loading_label == null:
		return
	_loading_label.text = text
	_loading_layer.visible = true


func _hide_loading() -> void:
	if _loading_layer:
		_loading_layer.visible = false


func _count_tagged_cells(tag: String) -> int:
	var n := 0
	for x in range(grid_width):
		for y in range(grid_height):
			var tags: Array = grid[x][y].get("tags", [])
			if tags.has(tag):
				n += 1
	return n


func _count_blocking_cells() -> int:
	var n := 0
	for x in range(grid_width):
		for y in range(grid_height):
			if grid[x][y].get("player_blocking", false):
				n += 1
	return n


func _populate_grid_from_cells(cells: Array) -> void:
	grid.clear()
	for x in range(grid_width):
		var column: Array = []
		for y in range(grid_height):
			column.append({"N": true, "S": true, "E": true, "W": true})
		grid.append(column)

	for y in range(mini(cells.size(), grid_height)):
		var row: Array = cells[y]
		for x in range(mini(row.size(), grid_width)):
			var cell_data: Dictionary = row[x]
			var walls: Dictionary = cell_data.get("walls", {})
			grid[x][y] = {
				"N": bool(walls.get("N", true)),
				"S": bool(walls.get("S", true)),
				"E": bool(walls.get("E", true)),
				"W": bool(walls.get("W", true)),
				"player_blocking": bool(cell_data.get("player_blocking", false)),
				"tags": cell_data.get("tags", []).duplicate(),
			}


func _build_local_procedural() -> void:
	if not use_local_fallback_only:
		push_error("[Maze] Builder: blocked local procedural carve (enable use_local_fallback_only to allow)")
		return
	grid_width = 9
	grid_height = 9
	spawn_cell = Vector2i(0, 0)
	exit_cell = Vector2i(grid_width - 1, grid_height - 1)
	_clear_children(walls_root)
	_clear_children(fork_triggers_root)
	_clear_children(exit_root)
	_clear_children(blocking_root)
	_resize_floor()
	_generate_grid()
	_carve_maze()
	_build_walls()
	_place_fork_triggers()
	_place_exit_gate()
	_place_player()


func _clear_children(node: Node3D) -> void:
	for child in node.get_children():
		child.queue_free()


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


func _generate_grid() -> void:
	grid.clear()
	for x in range(grid_width):
		var column: Array = []
		for y in range(grid_height):
			column.append({
				"N": true, "S": true, "E": true, "W": true,
				"player_blocking": false,
				"tags": [],
			})
		grid.append(column)


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
		grid[next.x][next.y][_opposite(dir_key)] = false

		visited[next] = true
		stack.push_back(next)


func _opposite(dir_key: String) -> String:
	match dir_key:
		"N": return "S"
		"S": return "N"
		"E": return "W"
		_: return "E"


func _unvisited_neighbor_dirs(cell: Vector2i, visited: Dictionary) -> Array:
	var result: Array = []
	for dir_key in DIRS.keys():
		var neighbor: Vector2i = cell + DIRS[dir_key]
		var in_bounds := neighbor.x >= 0 and neighbor.x < grid_width \
			and neighbor.y >= 0 and neighbor.y < grid_height
		if in_bounds and not visited.has(neighbor):
			result.append(dir_key)
	return result


func _build_walls() -> void:
	for x in range(grid_width):
		for y in range(grid_height):
			var cell = grid[x][y]
			if cell["N"]:
				_place_wall(x, y, "N")
			if cell["E"]:
				_place_wall(x, y, "E")
			if x == 0 and cell["W"]:
				_place_wall(x, y, "W")
			if y == 0 and cell["S"]:
				_place_wall(x, y, "S")


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


func _place_fork_triggers_from_tags() -> void:
	var trigger_cells: Array[Vector2i] = []
	for x in range(grid_width):
		for y in range(grid_height):
			var cell_pos := Vector2i(x, y)
			if cell_pos == spawn_cell or cell_pos == exit_cell:
				continue
			var tags: Array = grid[x][y].get("tags", [])
			if tags.has("trivia"):
				trigger_cells.append(cell_pos)

	if trigger_cells.size() < GameState.KEYS_REQUIRED:
		_place_fork_triggers()
		return

	for cell_pos in trigger_cells:
		_place_fork_trigger(cell_pos.x, cell_pos.y)


func _place_fork_triggers() -> void:
	var fork_cells: Array[Vector2i] = []
	var other_cells: Array[Vector2i] = []

	for x in range(grid_width):
		for y in range(grid_height):
			var cell_pos := Vector2i(x, y)
			if cell_pos == spawn_cell or cell_pos == exit_cell:
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


func _place_blocking_volumes() -> void:
	for x in range(grid_width):
		for y in range(grid_height):
			if not grid[x][y].get("player_blocking", false):
				continue
			var body := StaticBody3D.new()
			body.name = "Block_%d_%d" % [x, y]
			blocking_root.add_child(body)

			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(cell_size * 0.9, wall_height, cell_size * 0.9)
			shape.shape = box
			body.add_child(shape)

			var pos := Vector3((x + 0.5) * cell_size, wall_height / 2.0, (y + 0.5) * cell_size)
			body.transform = Transform3D(Basis(), pos)


func _place_exit_gate() -> void:
	var x := exit_cell.x
	var y := exit_cell.y

	var gate := EXIT_GATE_SCENE.instantiate()
	exit_root.add_child(gate)

	var shape: BoxShape3D = gate.get_node("CollisionShape3D").shape
	shape.size = Vector3(cell_size * 0.6, wall_height, cell_size * 0.6)

	var mesh: MeshInstance3D = gate.get_node("MeshInstance3D")
	mesh.mesh.size = Vector3(cell_size * 0.4, wall_height * 0.4, cell_size * 0.4)

	var pos := Vector3((x + 0.5) * cell_size, wall_height / 2.0, (y + 0.5) * cell_size)
	gate.transform = Transform3D(Basis(), pos)


func _place_player() -> void:
	var start_pos := Vector3(
		(spawn_cell.x + 0.5) * cell_size,
		1.0,
		(spawn_cell.y + 0.5) * cell_size
	)
	player.transform = Transform3D(Basis(), start_pos)
