extends CharacterBody3D

## How fast the player walks, in metres per second.
const SPEED := 6.0
## How much faster the player moves while sprinting.
const SPRINT_MULTIPLIER := 1.6
## Upward speed given to the player when jumping (reaches ~1.5 m).
const JUMP_VELOCITY := 4.6
## Player gravity while rising: lower than real gravity for a light jump.
const GRAVITY_UP := 7.0
## Falling gravity multiplier: drops stay fast and weighty, never floaty.
const FALL_GRAVITY_MULT := 1.8
## Near the apex (rising slower than this), extra gravity kills the hang.
const APEX_THRESHOLD := 1.2
const APEX_EXTRA_MULT := 1.5
## How quickly the player model turns to face the direction it moves in.
const TURN_SPEED := 10.0
## If the player falls below this height, respawn at the start.
const FALL_LIMIT := -25.0
## How far the arms and legs swing (in radians) while walking.
const WALK_SWING := 0.7
## How fast the step rhythm plays.
const WALK_SPEED := 9.0
## How far the player model leans forward while sprinting.
const SPRINT_LEAN := 0.15
## How fast the player climbs ridged walls.
const CLIMB_SPEED := 2.5
## How long the grip holds on without touching a ridge (between ridges).
const CLIMB_GRACE := 0.6
## Camera zoom limits (metres behind the player) and step per scroll tick.
const ZOOM_MIN := 3.0
const ZOOM_MAX := 14.0
const ZOOM_STEP := 1.0
## How fast the camera turns while holding right mouse button.
const MOUSE_SENSITIVITY := 0.003
## How far the camera may look down (-) or up (+), in radians.
const PITCH_MIN := -1.1
const PITCH_MAX := 0.45

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var visual: Node3D = $Visual
@onready var left_arm: Node3D = $Visual/LeftArm
@onready var right_arm: Node3D = $Visual/RightArm
@onready var left_leg: Node3D = $Visual/LeftLeg
@onready var right_leg: Node3D = $Visual/RightLeg

## Where the player started, used for respawning after a fall.
var _start_position: Vector3
## Timers for the walk and climb animation cycles.
var _walk_time := 0.0
var _climb_anim_time := 0.0
## Current target distance of the camera behind the player.
var _zoom := 6.5
## Climbing state: are we on a wall, and which way does it face?
var _climbing := false
var _climb_grace_left := 0.0
var _wall_normal := Vector3.ZERO


func _ready() -> void:
	_start_position = global_position
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	# Hold right mouse button: hide the cursor and let the mouse orbit the camera.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# While the cursor is captured, mouse movement turns the camera.
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotation.y -= event.relative.x * MOUSE_SENSITIVITY
		camera_pivot.rotation.x = clampf(
			camera_pivot.rotation.x - event.relative.y * MOUSE_SENSITIVITY,
			PITCH_MIN, PITCH_MAX
		)


func _physics_process(delta: float) -> void:
	# 1. Read the WASD input and camera-relative direction (climbing needs it too).
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3.ZERO
	if input_dir != Vector2.ZERO:
		direction = (camera.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var sprinting := Input.is_action_pressed("sprint") and direction != Vector3.ZERO

	if _climbing:
		# 2a. Climbing: Space leaps off, S lets go, otherwise keep scaling the wall.
		if Input.is_action_just_pressed("jump"):
			_climbing = false
			velocity = _wall_normal * 3.5 + Vector3.UP * 4.4
		elif input_dir.y > 0.3:
			_climbing = false
			velocity = Vector3.ZERO
		else:
			# Press gently into the wall while rising so we stay in contact.
			velocity = Vector3.UP * CLIMB_SPEED - _wall_normal * 1.0
			# Face the wall while climbing it.
			visual.rotation.y = atan2(-_wall_normal.x, -_wall_normal.z)
	else:
		# 2b. Normal movement: gravity and jumping.
		if not is_on_floor():
			# Asymmetric gravity: light rise, snappy fall, no apex hang.
			var gravity := GRAVITY_UP
			if velocity.y <= 0.0:
				gravity *= FALL_GRAVITY_MULT
			elif velocity.y < APEX_THRESHOLD:
				gravity *= APEX_EXTRA_MULT
			velocity.y -= gravity * delta
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY

	# 3. Horizontal movement (locked while climbing).
	if not _climbing:
		var speed := SPEED * (SPRINT_MULTIPLIER if sprinting else 1.0)
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed

	# 4. Turn the model toward where it is going (not while climbing).
	if not _climbing and direction != Vector3.ZERO:
		var target_yaw := atan2(direction.x, direction.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, TURN_SPEED * delta)

	# 5. Animate the player based on what it is doing.
	if _climbing or not is_on_floor():
		_animate_air(delta)
	else:
		_animate_ground(delta, direction, sprinting)

	# 6. Scroll wheel zoom: wheel up pulls the camera in, wheel out moves it back.
	if Input.is_action_just_pressed("zoom_in"):
		_zoom = clampf(_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	if Input.is_action_just_pressed("zoom_out"):
		_zoom = clampf(_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	camera.position.z = lerpf(camera.position.z, _zoom, 10.0 * delta)

	# 7. Apply the movement (and slide along walls and platforms).
	move_and_slide()

	# 8. After moving: grab new walls, keep or release the grip, top out.
	_update_climbing(delta, direction)

	# 9. Fell off the city? Respawn at the start position.
	if global_position.y < FALL_LIMIT:
		global_position = _start_position
		velocity = Vector3.ZERO
		_climbing = false


## Decide whether to start, keep, or stop climbing after the last move.
func _update_climbing(delta: float, direction: Vector3) -> void:
	var collision := get_last_slide_collision()
	var touching_climbable := false
	if collision != null and collision.get_collider() != null:
		if collision.get_collider().is_in_group("climbable"):
			touching_climbable = true
			_wall_normal = collision.get_normal()

	if _climbing:
		if is_on_floor():
			# Landed on something solid: let go.
			_climbing = false
		elif collision == null:
			# Climbed past the top of the wall: hop forward onto the roof.
			_climbing = false
			velocity = -_wall_normal * 2.5 + Vector3.UP * 4.5
		elif touching_climbable:
			# Still on ridges: refresh the grip.
			_climb_grace_left = CLIMB_GRACE
		else:
			# Between ridges: hold on briefly, drop if it lasts too long.
			_climb_grace_left -= delta
			if _climb_grace_left <= 0.0:
				_climbing = false

	if not _climbing and touching_climbable and direction != Vector3.ZERO:
		# Pressing toward a climbable wall: grab it.
		if direction.dot(-_wall_normal) > 0.4:
			_climbing = true
			_climb_grace_left = CLIMB_GRACE
			if velocity.y < 0.0:
				velocity.y = 0.0


## Limb poses while standing on ground: idle, walking or sprinting.
func _animate_ground(delta: float, direction: Vector3, sprinting: bool) -> void:
	# Sprinting leans the body forward; otherwise stand upright.
	var target_lean := SPRINT_LEAN if sprinting else 0.0
	visual.rotation.x = lerpf(visual.rotation.x, target_lean, TURN_SPEED * delta)

	if direction != Vector3.ZERO:
		# Walking (or a faster, wider stride when sprinting).
		var stride_speed := WALK_SPEED * (1.5 if sprinting else 1.0)
		_walk_time += delta * stride_speed
		var swing := sin(_walk_time) * WALK_SWING * (1.15 if sprinting else 1.0)
		left_arm.rotation.x = swing
		right_arm.rotation.x = -swing
		left_leg.rotation.x = -swing
		right_leg.rotation.x = swing
	else:
		# Idle: ease every limb back to neutral.
		_walk_time = 0.0
		_pose(delta, 0.0, 0.0, 0.0, 0.0)


## Limb poses while airborne: climbing a wall, jumping up, or falling.
func _animate_air(delta: float) -> void:
	visual.rotation.x = lerpf(visual.rotation.x, 0.0, TURN_SPEED * delta)

	# On a wall (or gripping one) while rising reads as climbing.
	if (is_on_wall() or _climbing) and velocity.y > 0.5:
		_climb_anim_time += delta * 7.0
		var reach := sin(_climb_anim_time)
		_pose(delta, -2.0 + reach * 0.6, -2.0 - reach * 0.6, 0.35 - reach * 0.2, 0.35 + reach * 0.2)
	# Rising freely: arms reach up, legs tuck — the jump pose.
	elif velocity.y > 0.5:
		_climb_anim_time = 0.0
		_pose(delta, -2.4, -2.4, 0.55, 0.55)
	# Falling: arms out to the sides-front for balance.
	else:
		_climb_anim_time = 0.0
		_pose(delta, -1.2, -1.2, 0.15, -0.15)


## Smoothly move all four limbs toward a target pose.
func _pose(delta: float, left_arm_x: float, right_arm_x: float, left_leg_x: float, right_leg_x: float) -> void:
	left_arm.rotation.x = lerpf(left_arm.rotation.x, left_arm_x, TURN_SPEED * delta)
	right_arm.rotation.x = lerpf(right_arm.rotation.x, right_arm_x, TURN_SPEED * delta)
	left_leg.rotation.x = lerpf(left_leg.rotation.x, left_leg_x, TURN_SPEED * delta)
	right_leg.rotation.x = lerpf(right_leg.rotation.x, right_leg_x, TURN_SPEED * delta)
