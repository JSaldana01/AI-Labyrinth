extends Area3D

## Skeleton enemy that chases the player through the maze along open cells.
## Spawned by the maze generator on Medium/Hard. Because it is a normal node,
## it freezes automatically while the tree is paused (trivia, pause menu).

const MODEL_SCENE: PackedScene = preload("res://scripts/ui/assets/models/enemy model/gltf/Skeleton_Mage.glb")
const MOVEMENT_RIG: PackedScene = preload("res://scripts/ui/assets/models/enemy model/gltf/Rig_Medium/Rig_Medium_MovementBasic.glb")
const GENERAL_RIG: PackedScene = preload("res://scripts/ui/assets/models/enemy model/gltf/Rig_Medium/Rig_Medium_General.glb")

const MODEL_HEIGHT := 2.17
const TARGET_HEIGHT := 1.9
const HIT_COOLDOWN := 2.0
# Above this speed the enemy plays its running animation instead of walking.
const RUN_SPEED_THRESHOLD := 2.5

var speed := 1.0
var _maze: Node
var _player: Node3D
var _cooldown := 0.0
var _model: Node3D
var _anim: AnimationPlayer
var _current_anim := ""


func setup(maze: Node, player: Node3D, move_speed: float) -> void:
	_maze = maze
	_player = player
	speed = move_speed

	_model = MODEL_SCENE.instantiate()
	_model.scale = Vector3.ONE * (TARGET_HEIGHT / MODEL_HEIGHT)
	add_child(_model)
	_setup_animations()

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.8
	shape.shape = sphere
	shape.position = Vector3(0, 1.0, 0)
	add_child(shape)


# The skeleton mesh ships without animations. It shares the Rig_Medium bone
# layout with the rig files, so their clips are copied onto this model.
func _setup_animations() -> void:
	var library := AnimationLibrary.new()
	for rig_scene in [MOVEMENT_RIG, GENERAL_RIG]:
		var rig: Node = rig_scene.instantiate()
		var source: AnimationPlayer = rig.find_child("AnimationPlayer", true, false)
		if source:
			for anim_name in source.get_animation_list():
				if anim_name == "RESET" or library.has_animation(anim_name):
					continue
				var clip: Animation = source.get_animation(anim_name).duplicate()
				clip.loop_mode = Animation.LOOP_LINEAR
				library.add_animation(anim_name, clip)
		rig.free()

	_anim = AnimationPlayer.new()
	_model.add_child(_anim)
	_anim.add_animation_library("", library)
	_play("Idle_A")


func _play(anim_name: String) -> void:
	if _anim == null or anim_name == _current_anim or not _anim.has_animation(anim_name):
		return
	_current_anim = anim_name
	_anim.play(anim_name, 0.2)


func _physics_process(delta: float) -> void:
	if _maze == null or _player == null or GameState.is_game_over:
		return

	if _cooldown > 0.0:
		_cooldown -= delta
		_play("Idle_A")
		return

	_try_hit_player()
	_play("Running_A" if speed >= RUN_SPEED_THRESHOLD else "Walking_A")
	_chase(delta)


func _chase(delta: float) -> void:
	var my_cell: Vector2i = _maze.world_to_cell(global_position)
	var player_cell: Vector2i = _maze.world_to_cell(_player.global_position)

	var destination: Vector3
	if my_cell == player_cell:
		destination = _player.global_position
	else:
		var next_cell: Vector2i = _maze.next_cell_toward(my_cell, player_cell)
		destination = _maze.cell_center(next_cell)

	var flat_target := Vector3(destination.x, global_position.y, destination.z)
	var offset := flat_target - global_position
	if offset.length() < 0.01:
		return

	var step := minf(speed * delta, offset.length())
	var direction := offset.normalized()
	global_position += direction * step
	# glTF models face +Z.
	rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), 10.0 * delta)


func _try_hit_player() -> void:
	for body in get_overlapping_bodies():
		if body == _player:
			GameState.damage_player()
			_cooldown = HIT_COOLDOWN
			# Back off to the far side of the maze so the player can recover.
			global_position = _maze.farthest_cell_center_from(_player.global_position)
			return
