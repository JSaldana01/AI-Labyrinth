extends "res://addons/gut/test.gd"

## Tests for the skeleton enemy: spawn rules per difficulty, speed, pausing
## behaviour, and that chasing only ever moves through open maze passages.

const D = preload("res://scripts/game/game_state.gd").Difficulty
const MAZE_SCENE: PackedScene = preload("res://tscn/maze/maze.tscn")


func after_all() -> void:
	GameState.set_difficulty(D.MEDIUM)


func _make_maze(level: int) -> Node3D:
	GameState.set_difficulty(level)
	var maze: Node3D = MAZE_SCENE.instantiate()
	add_child_autofree(maze)
	return maze


func test_no_enemy_on_easy() -> void:
	var maze := _make_maze(D.EASY)
	assert_null(maze._enemy)


func test_enemy_spawns_on_medium_with_medium_speed() -> void:
	var maze := _make_maze(D.MEDIUM)
	assert_not_null(maze._enemy)
	assert_eq(maze._enemy.speed, GameState.DIFFICULTY_SETTINGS[D.MEDIUM]["enemy_speed"])


func test_enemy_spawns_on_hard_with_hard_speed() -> void:
	var maze := _make_maze(D.HARD)
	assert_not_null(maze._enemy)
	assert_eq(maze._enemy.speed, GameState.DIFFICULTY_SETTINGS[D.HARD]["enemy_speed"])


func test_switching_to_easy_removes_the_enemy() -> void:
	var maze := _make_maze(D.MEDIUM)
	GameState.set_difficulty(D.EASY)
	assert_null(maze._enemy)


func test_enemy_spawns_far_from_the_player() -> void:
	var maze := _make_maze(D.HARD)
	for i in range(20):
		maze._rebuild_maze()
		var dist: Dictionary = maze._distances_from(maze.world_to_cell(maze.player.global_position))
		var enemy_cell: Vector2i = maze.world_to_cell(maze._enemy.global_position)
		assert_eq(dist[enemy_cell], dist.values().max())


func test_enemy_freezes_with_the_tree_pause() -> void:
	# Trivia and the pause menu freeze the enemy by pausing the tree, which only
	# works if the enemy (and its parents) use the default, pausable mode.
	var maze := _make_maze(D.MEDIUM)
	assert_eq(maze._enemy.process_mode, Node.PROCESS_MODE_INHERIT)
	assert_eq(maze.process_mode, Node.PROCESS_MODE_INHERIT)


func test_enemy_stops_moving_after_game_over() -> void:
	var maze := _make_maze(D.HARD)
	# Set directly: damage_player() would open the game-over menu and pause the test runner.
	GameState.is_game_over = true
	var before: Vector3 = maze._enemy.global_position
	maze._enemy._physics_process(1.0)
	assert_eq(maze._enemy.global_position, before)


func test_chase_only_moves_through_open_passages_and_reaches_player() -> void:
	var maze := _make_maze(D.MEDIUM)
	for run in range(5):
		maze._rebuild_maze()
		var enemy: Node3D = maze._enemy
		var player_cell: Vector2i = maze.world_to_cell(maze.player.global_position)
		var delta := 0.1
		var max_step: float = enemy.speed * delta + 0.001
		var last_cell: Vector2i = maze.world_to_cell(enemy.global_position)
		var reached := false

		for step in range(3000):
			var before: Vector3 = enemy.global_position
			enemy._chase(delta)
			assert_lte(before.distance_to(enemy.global_position), max_step, "moved faster than its speed")

			var cell: Vector2i = maze.world_to_cell(enemy.global_position)
			if cell != last_cell:
				var dir_key = maze.DIRS.find_key(cell - last_cell)
				assert_not_null(dir_key, "jumped more than one cell")
				if dir_key != null:
					assert_false(maze.grid[last_cell.x][last_cell.y][dir_key], "walked through a wall")
				last_cell = cell
			if cell == player_cell:
				reached = true
				break
		assert_true(reached, "enemy never reached the player (run %d)" % run)


func test_enemy_does_not_move_when_already_on_the_player() -> void:
	var maze := _make_maze(D.MEDIUM)
	var enemy: Node3D = maze._enemy
	enemy.global_position = maze.player.global_position
	var before: Vector3 = enemy.global_position
	enemy._chase(0.1)
	assert_lte(before.distance_to(enemy.global_position), 0.001 + enemy.speed * 0.1)
