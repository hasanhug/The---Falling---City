extends Node3D

## A small prop plane parked at the end of the hidden route.
## Press E nearby to board, then fly with W/S throttle and the
## right-click orbit camera — the plane travels wherever you look.
## Reach the beacon island to trigger the ending hook.

## Flight: top speed and how quickly the throttle responds.
const MAX_SPEED := 28.0
const ACCEL := 10.0
## How quickly the plane body turns to face its travel direction.
const TURN_SPEED := 3.0
## How strongly the plane banks into a turn.
const BANK_AMOUNT := 1.5
## Camera settings (same feel as the player camera).
const MOUSE_SENSITIVITY := 0.003
const PITCH_MIN := -1.2
const PITCH_MAX := 1.0
const ZOOM_MIN := 4.0
const ZOOM_MAX := 16.0
const ZOOM_STEP := 1.0
## How close the player must be to board, and to the beacon to escape.
const BOARD_RANGE := 4.5
const DESTINATION_RANGE := 35.0

@onready var player: Node = get_node("../Player")
@onready var player_camera: Camera3D = get_node("../Player/CameraPivot/Camera3D")
@onready var rumble: Node = get_node("../Rumble")
@onready var beacon: Node3D = get_node("../BeaconIsland")
@onready var body: Node3D = $Body
@onready var propeller: Node3D = $Body/Propeller
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var hint_label: Label3D = $HintLabel
@onready var fade_rect: ColorRect = $UI/FadeRect
@onready var end_label: Label = $UI/EndLabel

var _aboard := false
var _escaped := false
var _speed := 0.0
var _zoom := 9.0
var _time := 0.0
var _end_time := 0.0


func _ready() -> void:
	hint_label.visible = false
	end_label.visible = false
	fade_rect.color.a = 0.0


func _input(event: InputEvent) -> void:
	if _escaped:
		return
	# Hold right mouse button: hide the cursor and steer with the mouse.
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


func _process(delta: float) -> void:
	_time += delta

	# The propeller always spins, faster with throttle.
	propeller.rotation.z += delta * (8.0 + _speed * 1.5)

	if _escaped:
		_ending(delta)
		return

	# Boarding and exiting (one press, one action).
	if Input.is_action_just_pressed("interact"):
		if _aboard:
			_exit()
		elif player.global_position.distance_to(global_position) < BOARD_RANGE:
			_board()

	if _aboard:
		_fly(delta)
	else:
		# Parked: gentle bob and a boarding hint when the player is close.
		position.y += sin(_time * 1.2) * 0.004
		hint_label.visible = player.global_position.distance_to(global_position) < BOARD_RANGE


## Arcade flight: throttle with W/S, travel toward wherever the camera looks.
func _fly(delta: float) -> void:
	var throttle := Input.get_axis("move_back", "move_forward")
	_speed = move_toward(_speed, throttle * MAX_SPEED, ACCEL * delta)

	var forward := -camera_pivot.global_transform.basis.z
	global_position += forward * _speed * delta

	# Turn the body to face travel, banking into the turn.
	if _speed > 1.0:
		var target_yaw := atan2(forward.x, forward.z)
		var yaw_delta := wrapf(target_yaw - body.rotation.y, -PI, PI)
		body.rotation.y = lerp_angle(body.rotation.y, target_yaw, TURN_SPEED * delta)
		body.rotation.x = lerpf(body.rotation.x, -asin(clampf(forward.y, -1.0, 1.0)), TURN_SPEED * delta)
		body.rotation.z = lerpf(body.rotation.z, -yaw_delta * BANK_AMOUNT, TURN_SPEED * delta)

	# Scroll wheel camera zoom, same as on foot.
	if Input.is_action_just_pressed("zoom_in"):
		_zoom = clampf(_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	if Input.is_action_just_pressed("zoom_out"):
		_zoom = clampf(_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	camera.position.z = lerpf(camera.position.z, _zoom, 8.0 * delta)

	# Reached the beacon island: the ending hook.
	if global_position.distance_to(beacon.global_position) < DESTINATION_RANGE:
		_start_ending()


## Board: hide the player, take the controls, stop the doomsday countdown.
func _board() -> void:
	_aboard = true
	hint_label.visible = false
	player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	camera.make_current()
	if rumble.has_method("halt_timer"):
		rumble.halt_timer()


## Exit: put the player back beside the plane and resume the countdown.
func _exit() -> void:
	_aboard = false
	_speed = 0.0
	player.visible = true
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.global_position = global_position + Vector3(0, 2.5, 0)
	player_camera.make_current()
	if rumble.has_method("resume_timer"):
		rumble.resume_timer()


## ENDING HOOK — replace the body of this function with the real ending
## cutscene in the next version. For now: drift, fade, victory text.
func _start_ending() -> void:
	_escaped = true
	_speed = 8.0


func _ending(delta: float) -> void:
	_end_time += delta
	# Keep drifting gently forward while the screen fades out.
	global_position += -camera_pivot.global_transform.basis.z * _speed * delta
	propeller.rotation.z += delta * 20.0
	fade_rect.color.a = clampf(_end_time / 1.5, 0.0, 1.0)
	if _end_time > 1.8 and not end_label.visible:
		end_label.visible = true
