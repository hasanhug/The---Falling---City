extends Node3D

## The opening cutscene: the destroyed Earth below, a slow rise up beside
## a pillar to the sky island, then a fade into gameplay.
## Plays once when the game starts. Respawning never replays it.
## Press Space (or click) to skip.

const TEXT_1 := "The Earth was destroyed by the continuous earthquakes caused by human activities."
const TEXT_2 := "Now the earthquakes have gotten stronger — and they have reached the sky islands."

const TOTAL_TIME := 30.0
const TEXT_1_START := 1.5
const TEXT_1_END := 11.0
const TEXT_2_START := 22.0
const TEXT_2_END := 29.5
## How long the final fade to black takes.
const FADE_OUT_TIME := 0.8

## Camera path: [time, position]. Starts at ground level on the dead Earth,
## rises along a pillar, and ends under the island in the sky.
const PATH := [
	[0.0, Vector3(40, -112, 55)],
	[12.0, Vector3(30, -75, 42)],
	[22.0, Vector3(16, -35, 32)],
	[30.0, Vector3(4, 9, 42)],
]

## Where the camera looks, blending from the cracked ground ahead
## up to the floating island.
const LOOK_EARTH := Vector3(0, -110, 10)
const LOOK_ISLAND := Vector3(0, 4, 0)

## How violently the camera and pillars shake during the final text.
const SHAKE_AMOUNT := 0.35
## Subtle forever-sway of the pillars after the cutscene.
const IDLE_SWAY := 0.06

@onready var camera: Camera3D = $Camera
@onready var fade_rect: ColorRect = $UI/FadeRect
@onready var text_1: Label = $UI/Text1
@onready var text_2: Label = $UI/Text2
@onready var skip_hint: Label = $UI/SkipHint
@onready var player: Node = get_node("../Player")
@onready var player_camera: Camera3D = get_node("../Player/CameraPivot/Camera3D")
@onready var pillars: Array = get_node("../Pillars").get_children()

var _time := 0.0
var _finishing := false
var _fade_out := 0.0
var _pillar_bases: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for pillar in pillars:
		_pillar_bases.append(pillar.position)

	# Freeze the player (input, physics and its camera) for the cutscene.
	player.process_mode = Node.PROCESS_MODE_DISABLED
	camera.make_current()

	# Start fully black, fade in over the first second.
	fade_rect.color.a = 1.0
	text_1.modulate.a = 0.0
	text_2.modulate.a = 0.0
	text_1.text = TEXT_1
	text_2.text = TEXT_2


func _unhandled_input(event: InputEvent) -> void:
	if _finishing:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_finish()
	elif event is InputEventMouseButton and event.pressed:
		_finish()


func _process(delta: float) -> void:
	# Final phase: fade to black, then hand the game to the player.
	if _finishing:
		_fade_out += delta
		fade_rect.color.a = clampf(_fade_out / FADE_OUT_TIME, 0.0, 1.0)
		if _fade_out >= FADE_OUT_TIME:
			_hand_over()
		return

	_time += delta

	# 1. Camera position along the path, plus earthquake shake near the end.
	var pos := _path_position(_time)
	var shake := _shake_strength()
	pos += Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)
	) * shake
	camera.position = pos

	# 2. Look direction blends from the Earth up to the island.
	var look := LOOK_EARTH.lerp(LOOK_ISLAND, smoothstep(0.0, 1.0, _time / TOTAL_TIME))
	camera.look_at(look, Vector3.UP)

	# 3. Fade in at the start; texts fade in and out on schedule.
	fade_rect.color.a = clampf(1.0 - _time / 1.0, 0.0, 1.0)
	text_1.modulate.a = _text_alpha(TEXT_1_START, TEXT_1_END)
	text_2.modulate.a = _text_alpha(TEXT_2_START, TEXT_2_END)

	# 4. Pillars tremble while the earthquake text shows, then idle sway.
	for i in pillars.size():
		var base: Vector3 = _pillar_bases[i]
		var wobble := Vector3(
			_rng.randf_range(-1.0, 1.0),
			0.0,
			_rng.randf_range(-1.0, 1.0)
		) * shake * 0.8
		wobble.x += sin(_time * 0.8 + i * 1.7) * IDLE_SWAY
		wobble.z += cos(_time * 0.6 + i * 2.3) * IDLE_SWAY
		pillars[i].position = base + wobble

	# 5. Done: start the fade out (skip also jumps here).
	if _time >= TOTAL_TIME:
		_finish()


## Smoothly interpolates the camera position between path key points.
func _path_position(t: float) -> Vector3:
	for i in PATH.size() - 1:
		var t0: float = PATH[i][0]
		var t1: float = PATH[i + 1][0]
		if t <= t1 or i == PATH.size() - 2:
			var blend := smoothstep(t0, t1, t)
			return (PATH[i][1] as Vector3).lerp(PATH[i + 1][1] as Vector3, blend)
	return (PATH[PATH.size() - 1][1] as Vector3)


## 0 -> 1 -> 0 fade envelope for a text window, with 1 s fade edges.
func _text_alpha(start: float, end: float) -> float:
	if _time < start or _time > end:
		return 0.0
	var into := clampf((_time - start) / 1.0, 0.0, 1.0)
	var out_of := clampf((end - _time) / 1.0, 0.0, 1.0)
	return min(into, out_of)


## How hard things shake: ramps up during the final earthquake section.
func _shake_strength() -> float:
	if _time < TEXT_2_START - 1.0:
		return 0.0
	return SHAKE_AMOUNT * clampf((_time - (TEXT_2_START - 1.0)) / 2.0, 0.0, 1.0)


## Begin the ending: freeze the scene and fade to black.
func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	text_1.modulate.a = 0.0
	text_2.modulate.a = 0.0
	skip_hint.modulate.a = 0.0
	for i in pillars.size():
		pillars[i].position = _pillar_bases[i]


## Fade is complete: restore the player and remove the cutscene.
func _hand_over() -> void:
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player_camera.make_current()
	queue_free()
