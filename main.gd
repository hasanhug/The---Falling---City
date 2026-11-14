extends Node3D

## Level script for the main scene.
## Animates the bobbing bridge platforms, the pulsing beacon and portal,
## the spinning holo-rings, and shows the victory label at the portal.

## How far bridge platforms bob up and down, and how fast.
const BOB_HEIGHT := 0.15
const BOB_SPEED := 1.2
## How close to the portal counts as reaching the goal.
const WIN_DISTANCE := 5.0

@onready var player: Node3D = $Player
@onready var beacon_material: StandardMaterial3D = $Tower/TopPlatform/Beacon.get_active_material(0) as StandardMaterial3D
@onready var portal_material: StandardMaterial3D = $GoalIsland/Portal/Ring.get_active_material(0) as StandardMaterial3D
@onready var portal: Node3D = $GoalIsland/Portal
@onready var win_label: Label3D = $GoalIsland/Portal/WinLabel
@onready var bridge_platforms: Array[Node3D] = []

## Remember each bridge platform's resting height so we can bob around it.
var _base_heights: Array[float] = []
var _time := 0.0


func _ready() -> void:
	for child in $Bridge.get_children():
		bridge_platforms.append(child)
		_base_heights.append(child.position.y)
	win_label.visible = false


func _process(delta: float) -> void:
	_time += delta

	# 1. Bob the bridge platforms gently, each slightly out of phase.
	for i in bridge_platforms.size():
		var platform := bridge_platforms[i]
		platform.position.y = _base_heights[i] + sin(_time * BOB_SPEED + i * 0.7) * BOB_HEIGHT

	# 2. Pulse the beacon and portal glow.
	beacon_material.emission_energy_multiplier = 2.5 + sin(_time * 2.0) * 0.8
	portal_material.emission_energy_multiplier = 1.6 + sin(_time * 2.5) * 0.9

	# 3. Reached the portal? Show the victory label.
	if not win_label.visible:
		if player.global_position.distance_to(portal.global_position) < WIN_DISTANCE:
			win_label.visible = true
