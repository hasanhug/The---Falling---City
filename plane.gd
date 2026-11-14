extends Node3D

## The ending sequence. When the player steps onto the landing pad:
## the camera locks exactly where it is, the character walks over and
## boards the plane, the propeller revs, and the plane takes off toward
## the beacon island on the horizon. When it has disappeared into the
## distance, the win text fades in and stays on screen.

## How close to the plane triggers the ending.
const PAD_RANGE := 3.5
## How long the character takes to walk in, and the propeller to rev.
const ENTER_TIME := 1.2
const REV_TIME := 1.0
## Takeoff: acceleration, cruising speed, and the flight direction
## (toward the beacon island, climbing gently into the horizon).
const TAKEOFF_ACCEL := 7.0
const TAKEOFF_SPEED := 45.0
const FLIGHT_DIRECTION := Vector3(-0.85, 0.18, -0.45)
## How far away the plane must get before the win text appears.
const WIN_DISTANCE := 260.0
## How long the win text takes to fade in.
const WIN_FADE := 1.5

@onready var player: Node3D = get_node("../Player") as Node3D
@onready var player_camera: Camera3D = get_node("../Player/CameraPivot/Camera3D") as Camera3D
@onready var rumble: Node = get_node("../Rumble")
@onready var body: Node3D = $Body
@onready var propeller: Node3D = $Body/Propeller
@onready var end_label: Label = $UI/EndLabel

var _started := false
var _phase := 0  # 1 = walking in, 2 = revving, 3 = flying away, 4 = won
var _phase_time := 0.0
var _time := 0.0
var _speed := 0.0
var _enter_from := Vector3.ZERO
var _enter_to := Vector3.ZERO
var _takeoff_from := Vector3.ZERO
var _win_time := 0.0
var _static_camera: Camera3D


func _ready() -> void:
	end_label.visible = false
	end_label.modulate.a = 0.0


func _process(delta: float) -> void:
	_time += delta

	if not _started:
		# Parked: the propeller idles until the player reaches the pad.
		propeller.rotation.z += delta * 8.0
		if player.global_position.distance_to(global_position) < PAD_RANGE:
			_begin()
		return

	_phase_time += delta

	if _phase == 1:
		# The character walks to the fuselage and disappears inside.
		var blend := clampf(_phase_time / ENTER_TIME, 0.0, 1.0)
		player.global_position = _enter_from.lerp(_enter_to, blend)
		if blend >= 1.0:
			player.visible = false
			_next_phase()
	elif _phase == 2:
		# A short beat while the propeller revs up.
		propeller.rotation.z += delta * 45.0
		if _phase_time >= REV_TIME:
			_next_phase()
	elif _phase == 3:
		# Accelerate away toward the horizon.
		propeller.rotation.z += delta * 45.0
		_speed = move_toward(_speed, TAKEOFF_SPEED, TAKEOFF_ACCEL * delta)
		global_position += FLIGHT_DIRECTION * _speed * delta
		if global_position.distance_to(_takeoff_from) > WIN_DISTANCE:
			_next_phase()
	elif _phase == 4:
		# The plane is gone: fade the win text in and leave it there.
		_win_time += delta
		end_label.modulate.a = clampf(_win_time / WIN_FADE, 0.0, 1.0)


## Start the ending: lock the camera, freeze the character, halt the doomsday.
func _begin() -> void:
	_started = true
	if rumble.has_method("halt_timer"):
		rumble.halt_timer()

	# Spawn a camera exactly where the player's camera is, then take over.
	# This shot never moves for the rest of the game.
	_static_camera = Camera3D.new()
	_static_camera.global_transform = player_camera.global_transform
	get_parent().add_child(_static_camera)
	_static_camera.make_current()

	# Freeze the character and set up the walk into the plane.
	player.process_mode = Node.PROCESS_MODE_DISABLED
	_enter_from = player.global_position
	_enter_to = global_position + Vector3(1.1, -0.4, 0.4)

	# Point the plane body toward its escape direction, ready for takeoff.
	body.rotation.y = atan2(-FLIGHT_DIRECTION.x, -FLIGHT_DIRECTION.z)

	_phase = 1
	_phase_time = 0.0


func _next_phase() -> void:
	if _phase == 2:
		_takeoff_from = global_position
	_phase += 1
	_phase_time = 0.0
	if _phase == 4:
		end_label.visible = true
