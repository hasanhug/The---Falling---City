extends CharacterBody3D

## How fast the player moves, in metres per second.
const SPEED := 6.0
## Upward speed given to the player when jumping.
const JUMP_VELOCITY := 6.5
## How quickly the player model turns to face the direction it moves in.
const TURN_SPEED := 10.0
## If the player falls below this height, respawn at the start.
const FALL_LIMIT := -25.0
## How far the arms and legs swing (in radians) while walking.
const WALK_SWING := 0.7
## How fast the step rhythm plays.
const WALK_SPEED := 9.0

@onready var camera: Camera3D = $Camera3D
@onready var visual: Node3D = $Visual
@onready var left_arm: Node3D = $Visual/LeftArm
@onready var right_arm: Node3D = $Visual/RightArm
@onready var left_leg: Node3D = $Visual/LeftLeg
@onready var right_leg: Node3D = $Visual/RightLeg

## Where the player started, used for respawning after a fall.
var _start_position: Vector3
## Timer used for the walk cycle animation.
var _walk_time := 0.0


func _ready() -> void:
	_start_position = global_position


func _physics_process(delta: float) -> void:
	# 1. Apply gravity while the player is in the air.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# 2. Jump with Space, but only when standing on ground or a platform.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# 3. Read the WASD input as a 2D vector (length up to 1).
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	# 4. Turn that input into a 3D direction, relative to the camera's facing.
	var direction := Vector3.ZERO
	if input_dir != Vector2.ZERO:
		direction = (camera.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# 5. Move horizontally. In the air we keep full control (simple arcade feel).
	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED

	# 6. Smoothly turn the player model so it faces where it is going.
	if direction != Vector3.ZERO:
		var target_yaw := atan2(direction.x, direction.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, TURN_SPEED * delta)

	# 7. Animate the limbs: swing while walking, relax when idle or airborne.
	var walking := is_on_floor() and direction != Vector3.ZERO
	if walking:
		_walk_time += delta * WALK_SPEED
		var swing := sin(_walk_time) * WALK_SWING
		left_arm.rotation.x = swing
		right_arm.rotation.x = -swing
		left_leg.rotation.x = -swing
		right_leg.rotation.x = swing
	else:
		_walk_time = 0.0
		left_arm.rotation.x = lerpf(left_arm.rotation.x, 0.0, TURN_SPEED * delta)
		right_arm.rotation.x = lerpf(right_arm.rotation.x, 0.0, TURN_SPEED * delta)
		left_leg.rotation.x = lerpf(left_leg.rotation.x, 0.0, TURN_SPEED * delta)
		right_leg.rotation.x = lerpf(right_leg.rotation.x, 0.0, TURN_SPEED * delta)

	# 8. Apply the movement (and slide along walls and platforms).
	move_and_slide()

	# 9. Fell off the city? Respawn at the start position.
	if global_position.y < FALL_LIMIT:
		global_position = _start_position
		velocity = Vector3.ZERO
