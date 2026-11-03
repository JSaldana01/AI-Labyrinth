extends GutTest

## Tests for maze generation and its helpers. The real maze scene is
## instantiated and rebuilt many times (the carving is random), so any
## intermittent failure such as an unreachable exit shows up as a failure here.

const D = preload("res://scripts/game/game_state.gd").Difficulty
const MAZE_SCENE: PackedScene = preload("res://tscn/maze/maze.tscn")
const REBUILDS := 40


func after_all() -> void:
	GameState.set_difficulty(D.MEDIUM)


func _make_maze(level: int) -> Node3D:
	GameState.set_difficulty(level)
	var maze: Node3D = MAZE_SCENE.instantiate()
	add_child_autofree(maze)
	return maze


func _exit_cell(maze: Node3D) -> Vector2i:
	return Vector2i(maze.grid_width - 1, maze.grid_height - 1)


# --- Grid structure ------------------------------------------------------

func test_grid_size_matches_difficulty() -> void:
	for level in [D.EASY, D.MEDIUM, D.HARD]:
		var maze := _make_maze(level)
		var expected: int = GameState.DIFFICULTY_SETTINGS[level]["grid_size"]
		assert_eq(maze.grid_width, expected, "width for %d" % level)
		assert_eq(maze.grid.size(), expected)
		assert_eq(maze.grid[0].size(), expected)


func test_every_cell_is_reachable_from_start() -> void:
	for level in [D.EASY, D.MEDIUM, D.HARD]:
		var maze := _make_maze(level)
		for i in range(REBUILDS):
			maze._rebuild_maze()
			var reachable: Dictionary = maze._distances_from(Vector2i(0, 0))
			assert_eq(reachable.size(), maze.grid_width * maze.grid_height, "level %d run %d" % [level, i])


func test_exit_is_reachable_and_not_the_start() -> void:
	for level in [D.EASY, D.MEDIUM, D.HARD]:
		var maze := _make_maze(level)
		for i in range(REBUILDS):
			maze._rebuild_maze()
			var reachable: Dictionary = maze._distances_from(Vector2i(0, 0))
			assert_true(reachable.has(_exit_cell(maze)))
			assert_ne(_exit_cell(maze), Vector2i(0, 0))


func test_maze_is_a_perfect_maze_without_loops() -> void:
	# DFS carving makes a spanning tree: open passages = cells - 1.
	var maze := _make_maze(D.HARD)
	for i in range(REBUILDS):
		maze._rebuild_maze()
		var open_sides := 0
		for x in range(maze.grid_width):
			for y in range(maze.grid_height):
				open_sides += maze._open_side_count(maze.grid[x][y])
		assert_eq(open_sides, 2 * (maze.grid_width * maze.grid_height - 1))


func test_outer_boundary_is_fully_walled() -> void:
	var maze := _make_maze(D.MEDIUM)
	for i in range(REBUILDS):
		maze._rebuild_maze()
		var w: int = maze.grid_width
		var h: int = maze.grid_height
		for x in range(w):
			assert_true(maze.grid[x][0]["S"], "south edge x=%d" % x)
			assert_true(maze.grid[x][h - 1]["N"], "north edge x=%d" % x)
		for y in range(h):
			assert_true(maze.grid[0][y]["W"], "west edge y=%d" % y)
			assert_true(maze.grid[w - 1][y]["E"], "east edge y=%d" % y)


func test_walls_are_consistent_between_neighbours() -> void:
	var maze := _make_maze(D.MEDIUM)
	for i in range(REBUILDS):
		maze._rebuild_maze()
		for x in range(maze.grid_width):
			for y in range(maze.grid_height):
				for dir_key in maze.DIRS.keys():
					if maze.grid[x][y][dir_key]:
						continue
					var n: Vector2i = Vector2i(x, y) + maze.DIRS[dir_key]
					assert_true(n.x >= 0 and n.x < maze.grid_width and n.y >= 0 and n.y < maze.grid_height)
					assert_false(maze.grid[n.x][n.y][maze.OPPOSITE[dir_key]], "one-way opening at %s" % str(Vector2i(x, y)))


func test_fork_detection_uses_three_or_more_open_sides() -> void:
	var maze := _make_maze(D.EASY)
	assert_eq(maze._open_side_count({"N": true, "S": true, "E": true, "W": true}), 0)
	assert_eq(maze._open_side_count({"N": false, "S": true, "E": true, "W": true}), 1)
	assert_eq(maze._open_side_count({"N": false, "S": false, "E": false, "W": true}), 3)


# --- Coordinates ---------------------------------------------------------

func test_world_to_cell_and_cell_center_round_trip() -> void:
	var maze := _make_maze(D.MEDIUM)
	for x in range(maze.grid_width):
		for y in range(maze.grid_height):
			var cell := Vector2i(x, y)
			assert_eq(maze.world_to_cell(maze.cell_center(cell)), cell)


func test_world_to_cell_clamps_outside_positions() -> void:
	var maze := _make_maze(D.MEDIUM)
	assert_eq(maze.world_to_cell(Vector3(-50, 0, -50)), Vector2i(0, 0))
	assert_eq(maze.world_to_cell(Vector3(9999, 0, 9999)), _exit_cell(maze))


# --- Pathfinding helpers -------------------------------------------------

func test_next_cell_toward_always_steps_closer_through_an_open_side() -> void:
	var maze := _make_maze(D.HARD)
	for i in range(10):
		maze._rebuild_maze()
		var target := Vector2i(0, 0)
		var dist: Dictionary = maze._distances_from(target)
		for cell in dist:
			if cell == target:
				assert_eq(maze.next_cell_toward(cell, target), cell)
				continue
			var step: Vector2i = maze.next_cell_toward(cell, target)
			assert_eq(dist[step], dist[cell] - 1)
			var delta := step - cell
			var dir_key: String = maze.DIRS.find_key(delta)
			assert_false(maze.grid[cell.x][cell.y][dir_key], "step goes through a wall")


func test_farthest_cell_has_the_maximum_distance() -> void:
	var maze := _make_maze(D.MEDIUM)
	for i in range(10):
		maze._rebuild_maze()
		var origin := Vector3(maze.cell_size / 2.0, 1.0, maze.cell_size / 2.0)
		var dist: Dictionary = maze._distances_from(maze.world_to_cell(origin))
		var farthest: Vector2i = maze.world_to_cell(maze.farthest_cell_center_from(origin))
		assert_eq(dist[farthest], dist.values().max())


# --- Keys (fork triggers) ------------------------------------------------

func test_enough_triggers_exist_for_required_keys() -> void:
	for level in [D.EASY, D.MEDIUM, D.HARD]:
		var maze := _make_maze(level)
		for i in range(REBUILDS):
			maze._rebuild_maze()
			assert_gte(maze.fork_triggers_root.get_child_count(), GameState.keys_required)


func test_triggers_avoid_start_exit_and_each_other() -> void:
	for level in [D.EASY, D.MEDIUM, D.HARD]:
		var maze := _make_maze(level)
		for i in range(REBUILDS):
			maze._rebuild_maze()
			var seen := {}
			for trigger in maze.fork_triggers_root.get_children():
				var cell: Vector2i = trigger.get_meta("cell")
				assert_ne(cell, Vector2i(0, 0))
				assert_ne(cell, _exit_cell(maze))
				assert_false(seen.has(cell), "two triggers share a cell")
				seen[cell] = true


func test_relocated_trigger_lands_on_a_free_valid_cell() -> void:
	var maze := _make_maze(D.MEDIUM)
	for i in range(REBUILDS):
		maze._rebuild_maze()
		var trigger: Node3D = maze.fork_triggers_root.get_child(0)
		maze._relocate_trigger(trigger)
		var cell: Vector2i = trigger.get_meta("cell")
		assert_ne(cell, Vector2i(0, 0))
		assert_ne(cell, _exit_cell(maze))
		for other in maze.fork_triggers_root.get_children():
			if other != trigger:
				assert_ne(other.get_meta("cell"), cell)
		# The trigger's world position must match its new cell.
		assert_eq(maze.world_to_cell(trigger.position), cell)


func test_relocate_does_nothing_when_no_cell_is_free() -> void:
	var maze := _make_maze(D.EASY)
	# Fill every non-start, non-exit cell with a trigger.
	for trigger in maze.fork_triggers_root.get_children():
		trigger.queue_free()
		maze.fork_triggers_root.remove_child(trigger)
	var scene: PackedScene = load("res://tscn/maze/fork_trigger.tscn")
	for x in range(maze.grid_width):
		for y in range(maze.grid_height):
			var cell := Vector2i(x, y)
			if cell == Vector2i(0, 0) or cell == _exit_cell(maze):
				continue
			var t: Node3D = scene.instantiate()
			maze.fork_triggers_root.add_child(t)
			maze._move_trigger_to_cell(t, cell)
	var mover: Node3D = maze.fork_triggers_root.get_child(0)
	var before: Vector2i = mover.get_meta("cell")
	maze._relocate_trigger(mover)
	assert_eq(mover.get_meta("cell"), before)


# --- Exit stairs ---------------------------------------------------------

func test_stairs_always_face_an_open_side_of_the_exit_cell() -> void:
	for level in [D.EASY, D.MEDIUM, D.HARD]:
		var maze := _make_maze(level)
		for i in range(REBUILDS * 5):
			maze._rebuild_maze()
			var cell: Dictionary = maze.grid[maze.grid_width - 1][maze.grid_height - 1]
			# Exit cell's N and E are outer walls, so entry is via S or W.
			assert_true(cell["N"] and cell["E"])
			assert_false(cell["S"] and cell["W"], "exit cell sealed off")
			var angle: float = maze._exit_entry_angle(cell)
			if not cell["S"]:
				assert_eq(angle, PI)
			else:
				assert_eq(angle, -PI / 2.0)


func test_one_exit_gate_is_created_per_maze() -> void:
	var maze := _make_maze(D.MEDIUM)
	for i in range(5):
		maze._rebuild_maze()
		assert_eq(maze.exit_root.get_child_count(), 1)


# --- Rebuilding ----------------------------------------------------------

func test_rebuild_does_not_accumulate_walls() -> void:
	var maze := _make_maze(D.EASY)
	maze._rebuild_maze()
	# Wall count of a perfect maze is fixed by grid size.
	var w: int = maze.grid_width
	var expected := 2 * w * (w + 1) - (w * w - 1)
	for i in range(10):
		maze._rebuild_maze()
		assert_eq(maze.walls_root.get_child_count(), expected)


func test_roof_matches_maze_size_and_height() -> void:
	var maze := _make_maze(D.HARD)
	var roof: MeshInstance3D = maze.get_node("Roof")
	var size: float = maze.grid_width * maze.cell_size
	assert_eq(roof.mesh.size, Vector2(size, size))
	assert_eq(roof.position.y, maze.wall_height)
