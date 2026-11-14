extends Node3D

## Post-cutscene doomsday sequence: once the cutscene hands control back,
## the island rumbles for one minute with a countdown on screen, escalating
## until the final fall — fade to black and a restart prompt.

## How long until the island falls.
const COUNTDOWN_TIME := 60.0
## Camera shake: from this gentle start to this violent peak.
const SHAKE_START := 0.02
const SHAKE_PEAK := 0.5
## Pillars wobble as a multiple of the camera shake.
const PILLAR_WOBBLE := 1.2
## The fall: how far the camera lurches down, per second.
const FALL_DROP := 30.0

@onready var player: Node = get_node("../Player")
@onready var camera_pivot: Node3D = get_node("../Player/CameraPivot")
@onready var pillars: Array = get_node("../Pillars").get_children()
@onready var timer_label: Label = $UI/TimerLabel
@onready var fade_rect: ColorRect = $UI/FadeRect
@onready var end_label: Label = $UI/EndLabel

var _started := false
var _fallen := false
var _time_left := COUNTDOWN_TIME
var _fall_time := 0.0
var _pivot_base := Vector3.ZERO
var _pillar_bases: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for pillar in pillars:
		_pillar_bases.append(pillar.position)
	_pivot_base = camera_pivot.position
	fade_rect.color.a = 0.0
	end_label.visible = false


func _unhandled_input(event: InputEvent) -> void:
	# After the fall has played out, any key or click restarts the game.
	if not _fallen or _fall_time < 2.0:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		get_tree().reload_current_scene()
	elif event is InputEventMouseButton and event.pressed:
		get_tree().reload_current_scene()


func _process(delta: float) -> void:
	# Wait until the cutscene is gone (it frees itself on hand-over or skip).
	if not _started:
		if get_node_or_null("../Cutscene") == null:
			_started = true
		else:
			return

	if not _fallen:
		_countdown(delta)
	else:
		_fall(delta)


## The rumbling minute: countdown, escalating camera and pillar shake.
func _countdown(delta: float) -> void:
	_time_left -= delta
	if _time_left <= 0.0:
		_time_left = 0.0
		_begin_fall()

	_update_timer_label()

	# Escalation curve: barely noticeable at first, violent near the end.
	var progress := 1.0 - _time_left / COUNTDOWN_TIME
	var shake := lerpf(SHAKE_START, SHAKE_PEAK, progress * progress)

	# Camera rumble around its resting position.
	camera_pivot.position = _pivot_base + Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)
	) * shake

	# Pillars tremble harder as time runs out.
	for i in pillars.size():
		var wobble := Vector3(
			_rng.randf_range(-1.0, 1.0),
			0.0,
			_rng.randf_range(-1.0, 1.0)
		) * shake * PILLAR_WOBBLE
		pillars[i].position = _pillar_bases[i] + wobble


## The fall itself: huge shake, camera lurching down, fade to black.
func _fall(delta: float) -> void:
	_fall_time += delta
	camera_pivot.position = _pivot_base + Vector3(
		_rng.randf_range(-1.0, 1.0) * SHAKE_PEAK * 2.0,
		-_fall_time * FALL_DROP,
		_rng.randf_range(-1.0, 1.0) * SHAKE_PEAK * 2.0
	)
	fade_rect.color.a = clampf(_fall_time / 1.2, 0.0, 1.0)
	if _fall_time > 1.2 and not end_label.visible:
		end_label.visible = true


## Switch from countdown to the falling sequence.
func _begin_fall() -> void:
	_fallen = true
	_fall_time = 0.0
	player.process_mode = Node.PROCESS_MODE_DISABLED
	timer_label.visible = false


## Big top-centre timer; red and pulsing for the final ten seconds.
func _update_timer_label() -> void:
	var total := int(ceil(_time_left))
	var minutes := int(total / 60.0)
	var seconds := total % 60
	timer_label.text = "%d:%02d" % [minutes, seconds]
	if _time_left <= 10.0:
		timer_label.modulate = Color(1, 0.2, 0.2, 1)
		var pulse := 0.5 + 0.5 * sin(_time_left * 8.0)
		timer_label.scale = Vector2(1.0 + pulse * 0.15, 1.0 + pulse * 0.15)
	else:
		timer_label.modulate = Color(1, 1, 1, 1)
		timer_label.scale = Vector2.ONE
