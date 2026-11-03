extends GutTest

## Tests for the key trigger (ForkTrigger) and the staircase exit (ExitGate).

const D = preload("res://scripts/game/game_state.gd").Difficulty
const TRIGGER_SCENE: PackedScene = preload("res://tscn/maze/fork_trigger.tscn")
const GATE_SCENE: PackedScene = preload("res://tscn/maze/exit_gate.tscn")
const CELL_SIZE := 4.0
const WALL_HEIGHT := 4.0


func before_each() -> void:
	GameState.set_difficulty(D.MEDIUM)


func after_all() -> void:
	GameState.set_difficulty(D.MEDIUM)


func _make_player_at(pos: Vector3) -> Node3D:
	var body := CharacterBody3D.new()
	body.add_to_group("player")
	add_child_autofree(body)
	body.global_position = pos
	return body


func _make_gate() -> Area3D:
	var gate: Area3D = GATE_SCENE.instantiate()
	add_child_autofree(gate)
	gate.setup(CELL_SIZE, WALL_HEIGHT, PI)
	gate.global_position = Vector3(10, 0, 10)
	return gate


# --- ForkTrigger (key) ---------------------------------------------------

func test_trigger_builds_a_key_visual() -> void:
	var trigger: Area3D = TRIGGER_SCENE.instantiate()
	add_child_autofree(trigger)
	assert_not_null(trigger._key)
	assert_true(trigger._key.get_child(0) is MeshInstance3D)


func test_correct_answer_removes_the_trigger() -> void:
	var trigger: Area3D = TRIGGER_SCENE.instantiate()
	add_child_autofree(trigger)
	trigger._on_answered(true)
	assert_true(trigger.is_queued_for_deletion())


func test_wrong_answer_requests_relocation_and_keeps_the_trigger() -> void:
	var trigger: Area3D = TRIGGER_SCENE.instantiate()
	add_child_autofree(trigger)
	watch_signals(trigger)
	trigger._on_answered(false)
	assert_signal_emitted_with_parameters(trigger, "relocate_requested", [trigger])
	assert_false(trigger.is_queued_for_deletion())


func test_non_player_bodies_do_not_start_a_question() -> void:
	var trigger: Area3D = TRIGGER_SCENE.instantiate()
	add_child_autofree(trigger)
	var rock := Node3D.new()
	add_child_autofree(rock)
	trigger._on_body_entered(rock)
	assert_true(trigger.monitoring, "monitoring stays on when a non-player enters")


# --- ExitGate (stairs) ---------------------------------------------------

func test_gate_denies_exit_without_enough_keys() -> void:
	var gate := _make_gate()
	var player := _make_player_at(gate.global_position)
	watch_signals(GameState)
	gate._on_body_entered(player)
	assert_signal_emitted(GameState, "exit_denied")
	assert_signal_not_emitted(GameState, "level_completed")


func test_gate_completes_level_with_enough_keys() -> void:
	var gate := _make_gate()
	var player := _make_player_at(gate.global_position)
	for i in range(GameState.keys_required):
		GameState.add_key()
	watch_signals(GameState)
	gate._on_body_entered(player)
	assert_signal_emitted(GameState, "level_completed")


func test_gate_ignores_non_player_bodies() -> void:
	var gate := _make_gate()
	var other := Node3D.new()
	add_child_autofree(other)
	other.global_position = gate.global_position
	watch_signals(GameState)
	gate._on_body_entered(other)
	assert_signal_not_emitted(GameState, "exit_denied")
	assert_signal_not_emitted(GameState, "level_completed")


func test_gate_ignores_a_player_who_is_far_away() -> void:
	var gate := _make_gate()
	var player := _make_player_at(gate.global_position + Vector3(50, 0, 0))
	watch_signals(GameState)
	gate._on_body_entered(player)
	assert_signal_not_emitted(GameState, "exit_denied")


func test_gate_builds_stairs_with_collision() -> void:
	var gate := _make_gate()
	var stairs: Node3D = gate.get_node("Stairs")
	assert_not_null(stairs)
	assert_not_null(stairs.get_node("StairsBody/CollisionShape3D").shape)
