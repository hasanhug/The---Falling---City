extends CharacterBody3D

## ---------------------------------------------------------------
## Movement settings
## ---------------------------------------------------------------
const SPEED := 6.0
const SPRINT_MULTIPLIER := 1.6
const JUMP_VELOCITY := 4.6
const TURN_SPEED := 10.0
const FALL_LIMIT := -25.0
const GRAVITY_UP := 7.0
const FALL_GRAVITY_MULT := 1.8
const APEX_THRESHOLD := 1.2
const APEX_EXTRA_MULT := 1.5
const CLIMB_SPEED := 2.5
const CLIMB_GRACE := 0.6
const ZOOM_MIN := 3.0
const ZOOM_MAX := 14.0
const ZOOM_STEP := 1.0
const MOUSE_SENSITIVITY := 0.003
const PITCH_MIN := -1.1
const PITCH_MAX := 0.45

## ---------------------------------------------------------------
## Animation settings
## ---------------------------------------------------------------
## Walk cycle: how far the legs and arms swing, how far knees bend.
const LEG_SWING := 0.75
const ARM_SWING := 0.55
const KNEE_BEND := 1.1
const WALK_SPEED_ANIM := 9.0
## Sprint multiplies swing and step frequency by these.
const SPRINT_SWING := 1.35
const SPRINT_RATE := 1.5
const SPRINT_LEAN := 0.18
## Idle breathing speed and depth.
const BREATH_SPEED := 1.4
## Landing squash: how long and how deep.
const LAND_TIME := 0.22
const LAND_DIP := 0.1
## How quickly limbs blend toward their target pose.
const ANIM_BLEND := 12.0

## ---------------------------------------------------------------
## Node references
## ---------------------------------------------------------------
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var visual: Node3D = $Visual
@onready var pelvis: Node3D = $Visual/Pelvis
@onready var torso: Node3D = $Visual/Pelvis/Torso
@onready var chest: Node3D = $Visual/Pelvis/Torso/Chest
@onready var shoulder_l: Node3D = $Visual/Pelvis/Torso/Chest/ShoulderL
@onready var shoulder_r: Node3D = $Visual/Pelvis/Torso/Chest/ShoulderR
@onready var elbow_l: Node3D = $Visual/Pelvis/Torso/Chest/ShoulderL/UpperArmL/ElbowL
@onready var elbow_r: Node3D = $Visual/Pelvis/Torso/Chest/ShoulderR/UpperArmR/ElbowR
@onready var hip_l: Node3D = $Visual/Pelvis/HipL
@onready var hip_r: Node3D = $Visual/Pelvis/HipR
@onready var knee_l: Node3D = $Visual/Pelvis/HipL/KneeL
@onready var knee_r: Node3D = $Visual/Pelvis/HipR/KneeR
@onready var ankle_l: Node3D = $Visual/Pelvis/HipL/KneeL/AnkleL
@onready var ankle_r: Node3D = $Visual/Pelvis/HipR/KneeR/AnkleR

## ---------------------------------------------------------------
## State
## ---------------------------------------------------------------
var _start_position: Vector3
var _walk_time := 0.0
var _climb_anim_time := 0.0
var _idle_time := 0.0
var _air_time := 0.0
var _land_timer := 0.0
var _pelvis_base_y := 0.0
var _zoom := 6.5
var _climbing := false
var _climb_grace_left := 0.0
var _wall_normal := Vector3.ZERO


func _ready() -> void:
	_start_position = global_position
	_pelvis_base_y = pelvis.position.y
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	# Hold right mouse button: hide the cursor and let the mouse orbit the camera.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
			velocity = Vector3.UP * CLIMB_SPEED - _wall_normal * 1.0
			visual.rotation.y = atan2(-_wall_normal.x, -_wall_normal.z)
	else:
		# 2b. Normal movement: asymmetric gravity and jumping.
		if not is_on_floor():
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

	# 5. Track air/landing for the squash animation.
	if is_on_floor():
		if _air_time > 0.15:
			_land_timer = LAND_TIME
		_air_time = 0.0
	else:
		_air_time += delta
	if _land_timer > 0.0:
		_land_timer -= delta

	# 6. Animate the body based on what it is doing.
	if _climbing or not is_on_floor():
		_animate_air(delta)
	else:
		_animate_ground(delta, direction, sprinting)

	# 7. Scroll wheel zoom.
	if Input.is_action_just_pressed("zoom_in"):
		_zoom = clampf(_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	if Input.is_action_just_pressed("zoom_out"):
		_zoom = clampf(_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	camera.position.z = lerpf(camera.position.z, _zoom, 10.0 * delta)

	# 8. Apply the movement.
	move_and_slide()

	# 9. After moving: grab new walls, keep or release the grip, top out.
	_update_climbing(delta, direction)

	# 10. Fell off the city? Respawn.
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
			_climbing = false
		elif collision == null:
			_climbing = false
			velocity = -_wall_normal * 2.5 + Vector3.UP * 4.5
		elif touching_climbable:
			_climb_grace_left = CLIMB_GRACE
		else:
			_climb_grace_left -= delta
			if _climb_grace_left <= 0.0:
				_climbing = false

	if not _climbing and touching_climbable and direction != Vector3.ZERO:
		if direction.dot(-_wall_normal) > 0.4:
			_climbing = true
			_climb_grace_left = CLIMB_GRACE
			if velocity.y < 0.0:
				velocity.y = 0.0


## ---------------------------------------------------------------
## Animation: on the ground (idle, walking, sprinting, landing)
## ---------------------------------------------------------------
func _animate_ground(delta: float, direction: Vector3, sprinting: bool) -> void:
	if direction != Vector3.ZERO:
		_idle_time = 0.0
		_walk_time += delta * WALK_SPEED_ANIM * (SPRINT_RATE if sprinting else 1.0)
		_walk(delta, sprinting)
	else:
		_walk_time = 0.0
		_idle_time += delta
		_idle(delta)


func _walk(delta: float, sprinting: bool) -> void:
	var swing := LEG_SWING * (SPRINT_SWING if sprinting else 1.0)
	var arm := ARM_SWING * (SPRINT_SWING if sprinting else 1.0)
	var knee := KNEE_BEND * (SPRINT_SWING if sprinting else 1.0)
	var phase := _walk_time

	# Legs: thigh swing, knee bends during the forward swing, ankle evens out.
	_rot(hip_l, Vector3(-sin(phase) * swing, 0, 0), delta)
	_rot(hip_r, Vector3(sin(phase) * swing, 0, 0), delta)
	_rot(knee_l, Vector3(0.12 + maxf(0.0, sin(phase + 0.4)) * knee, 0, 0), delta)
	_rot(knee_r, Vector3(0.12 + maxf(0.0, -sin(phase + 0.4)) * knee, 0, 0), delta)
	_rot(ankle_l, Vector3(sin(phase) * swing * 0.35, 0, 0), delta)
	_rot(ankle_r, Vector3(-sin(phase) * swing * 0.35, 0, 0), delta)

	# Arms: opposite swing with a natural forward elbow bend.
	_rot(shoulder_l, Vector3(sin(phase) * arm, 0, 0.08), delta)
	_rot(shoulder_r, Vector3(-sin(phase) * arm, 0, -0.08), delta)
	_rot(elbow_l, Vector3(-(0.35 + maxf(0.0, sin(phase)) * 0.5), 0, 0), delta)
	_rot(elbow_r, Vector3(-(0.35 + maxf(0.0, -sin(phase)) * 0.5), 0, 0), delta)

	# Torso: counter-rotation against the hips, forward lean when sprinting.
	var lean := SPRINT_LEAN if sprinting else 0.05
	_rot(torso, Vector3(lean, sin(phase) * 0.1, 0), delta)
	_rot(chest, Vector3(0, -sin(phase) * 0.12, 0), delta)

	# Pelvis bob: dips between steps, doubles frequency.
	var bob := -(0.5 - 0.5 * cos(phase * 2.0)) * (0.05 if sprinting else 0.035)
	_apply_pelvis_y(bob, delta)


func _idle(delta: float) -> void:
	# Everything eases to a relaxed stance; the chest breathes gently.
	_rot(hip_l, Vector3.ZERO, delta)
	_rot(hip_r, Vector3.ZERO, delta)
	_rot(knee_l, Vector3(0.08, 0, 0), delta)
	_rot(knee_r, Vector3(0.08, 0, 0), delta)
	_rot(ankle_l, Vector3.ZERO, delta)
	_rot(ankle_r, Vector3.ZERO, delta)
	_rot(shoulder_l, Vector3(sin(_idle_time * BREATH_SPEED) * 0.03, 0, 0.09), delta)
	_rot(shoulder_r, Vector3(-sin(_idle_time * BREATH_SPEED) * 0.03, 0, -0.09), delta)
	_rot(elbow_l, Vector3(-0.22, 0, 0), delta)
	_rot(elbow_r, Vector3(-0.22, 0, 0), delta)
	_rot(torso, Vector3(0.02, 0, 0), delta)
	_rot(chest, Vector3(sin(_idle_time * BREATH_SPEED) * 0.02, 0, 0), delta)
	_apply_pelvis_y(0.0, delta)


## ---------------------------------------------------------------
## Animation: airborne (climbing, jumping, falling)
## ---------------------------------------------------------------
func _animate_air(delta: float) -> void:
	_apply_pelvis_y(0.0, delta)

	# Climbing: alternating reach-and-step cycle up the wall.
	if (is_on_wall() or _climbing) and velocity.y > 0.5:
		_climb_anim_time += delta * 7.0
		var reach := sin(_climb_anim_time)
		_rot(shoulder_l, Vector3(-2.1 + reach * 0.5, 0, 0.25), delta)
		_rot(shoulder_r, Vector3(-2.1 - reach * 0.5, 0, -0.25), delta)
		_rot(elbow_l, Vector3(-0.5 + reach * 0.25, 0, 0), delta)
		_rot(elbow_r, Vector3(-0.5 - reach * 0.25, 0, 0), delta)
		_rot(hip_l, Vector3(-0.45 + reach * 0.3, 0, 0), delta)
		_rot(hip_r, Vector3(-0.45 - reach * 0.3, 0, 0), delta)
		_rot(knee_l, Vector3(0.7 - reach * 0.2, 0, 0), delta)
		_rot(knee_r, Vector3(0.7 + reach * 0.2, 0, 0), delta)
		_rot(ankle_l, Vector3(0.2, 0, 0), delta)
		_rot(ankle_r, Vector3(0.2, 0, 0), delta)
		_rot(torso, Vector3(0.12, 0, 0), delta)
		_rot(chest, Vector3(0, 0, 0), delta)
	# Rising freely: the jump tuck — arms up, knees in.
	elif velocity.y > 0.5:
		_climb_anim_time = 0.0
		_rot(shoulder_l, Vector3(-1.9, 0, 0.35), delta)
		_rot(shoulder_r, Vector3(-1.9, 0, -0.35), delta)
		_rot(elbow_l, Vector3(-0.7, 0, 0), delta)
		_rot(elbow_r, Vector3(-0.7, 0, 0), delta)
		_rot(hip_l, Vector3(-0.35, 0, 0), delta)
		_rot(hip_r, Vector3(-0.35, 0, 0), delta)
		_rot(knee_l, Vector3(0.95, 0, 0), delta)
		_rot(knee_r, Vector3(0.95, 0, 0), delta)
		_rot(ankle_l, Vector3(0.35, 0, 0), delta)
		_rot(ankle_r, Vector3(0.35, 0, 0), delta)
		_rot(torso, Vector3(-0.06, 0, 0), delta)
		_rot(chest, Vector3(0, 0, 0), delta)
	# Falling: arms out for balance, legs trailing loose.
	else:
		_climb_anim_time = 0.0
		_rot(shoulder_l, Vector3(-0.5, 0, 0.8), delta)
		_rot(shoulder_r, Vector3(-0.5, 0, -0.8), delta)
		_rot(elbow_l, Vector3(-0.45, 0, 0), delta)
		_rot(elbow_r, Vector3(-0.45, 0, 0), delta)
		_rot(hip_l, Vector3(-0.15, 0, 0), delta)
		_rot(hip_r, Vector3(0.1, 0, 0), delta)
		_rot(knee_l, Vector3(0.35, 0, 0), delta)
		_rot(knee_r, Vector3(0.55, 0, 0), delta)
		_rot(ankle_l, Vector3(0.25, 0, 0), delta)
		_rot(ankle_r, Vector3(0.25, 0, 0), delta)
		_rot(torso, Vector3(0.08, 0, 0), delta)
		_rot(chest, Vector3(0, 0, 0), delta)


## ---------------------------------------------------------------
## Animation helpers
## ---------------------------------------------------------------
## Blend a joint toward a target rotation.
func _rot(joint: Node3D, target: Vector3, delta: float) -> void:
	var weight := minf(1.0, ANIM_BLEND * delta)
	joint.rotation = joint.rotation.lerp(target, weight)


## Set the pelvis height: base + step bob + landing squash.
func _apply_pelvis_y(extra: float, delta: float) -> void:
	var squash := 0.0
	if _land_timer > 0.0:
		var land_phase: float = _land_timer / LAND_TIME
		squash = -sin(PI * land_phase) * LAND_DIP
	pelvis.position.y = lerpf(pelvis.position.y, _pelvis_base_y + extra + squash, minf(1.0, ANIM_BLEND * delta))
