extends Node3D

## A small prop plane parked on the tower roof landing pad.
## Press E nearby to board. Once aboard, it cruises forward constantly —
## just hover the mouse to steer: left/right of screen centre banks and
## turns, above/below centre pitches, dead centre flies straight and
## auto-levels. There is no exiting mid-flight.
## Reach the beacon island to trigger the ending hook.

## Cruising speed once aboard.
const CRUISE_SPEED := 18.0
## Steering: turn rate at full deflection, max pitch, max bank angle.
const TURN_RATE := 1.6
const MAX_PITCH := 0.85
const MAX_BANK := 0.9
## How quickly pitch and bank ease toward their targets.
const LEVEL_SPEED := 3.0
## Dead zone in the middle of the screen (fraction of the radius).
const DEAD_ZONE := 0.12
## How close the player must be to board, and to the beacon to escape.
const BOARD_RANGE := 4.5
const DESTINATION_RANGE := 35.0

@onready var player: Node3D = get_node("../Player") as Node3D
@onready var rumble: Node = get_node("../Rumble")
@onready var beacon: Node3D = get_node("../BeaconIsland")
@onready var body: Node3D = $Body
@onready var propeller: Node3D = $Body/Propeller
@onready var camera: Camera3D = $Body/CameraPivot/Camera3D
@onready var hint_label: Label3D = $HintLabel
@onready var fade_rect: ColorRect = $UI/FadeRect
@onready var end_label: Label = $UI/EndLabel

var _aboard := false
var _escaped := false
var _time := 0.0
var _end_time := 0.0


func _ready() -> void:
	hint_label.visible = false
	end_label.visible = false
	fade_rect.color.a = 0.0


func _process(delta: float) -> void:
	_time += delta

	# The propeller idles while parked and spins fast while cruising.
	propeller.rotation.z += delta * (8.0 if not _aboard else 40.0)

	if _escaped:
		_ending(delta)
		return

	if not _aboard:
		# Parked: gentle bob and a boarding hint when the player is close.
		var near := player.global_position.distance_to(global_position) < BOARD_RANGE
		hint_label.visible = near
		position.y += sin(_time * 1.2) * 0.004
		if near and Input.is_action_just_pressed("interact"):
			_board()
		return

	_fly(delta)


## Cruise forward and steer by hovering the mouse around screen centre.
func _fly(delta: float) -> void:
	# Mouse offset from screen centre, roughly -1..1 on each axis.
	var screen := get_viewport().get_visible_rect().size
	var offset := (get_viewport().get_mouse_position() - screen * 0.5) / (screen * 0.5)

	# Dead zone: hovering the exact centre means fly straight.
	if offset.length() < DEAD_ZONE:
		offset = Vector2.ZERO
	else:
		# Rescale so the edge of the dead zone is zero deflection.
		offset = offset.normalized() * ((offset.length() - DEAD_ZONE) / (1.0 - DEAD_ZONE))

	# Heading: turn rate from horizontal hover, banking into the turn.
	body.rotation.y -= offset.x * TURN_RATE * delta
	body.rotation.z = lerpf(body.rotation.z, -offset.x * MAX_BANK, LEVEL_SPEED * delta)

	# Pitch: hover above centre climbs, below centre dives, centre levels out.
	body.rotation.x = lerpf(body.rotation.x, -offset.y * MAX_PITCH, LEVEL_SPEED * delta)

	# Cruise forward along the body's forward direction.
	var forward := -body.global_transform.basis.z
	global_position += forward * CRUISE_SPEED * delta

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


## ENDING HOOK — replace the body of this function with the real ending
## cutscene in the next version. For now: drift, fade, victory text.
func _start_ending() -> void:
	_escaped = true


func _ending(delta: float) -> void:
	_end_time += delta
	# Keep cruising gently while the screen fades out.
	var forward := -body.global_transform.basis.z
	global_position += forward * CRUISE_SPEED * 0.5 * delta
	propeller.rotation.z += delta * 30.0
	fade_rect.color.a = clampf(_end_time / 1.5, 0.0, 1.0)
	if _end_time > 1.8 and not end_label.visible:
		end_label.visible = true
