extends Node3D

## Level script: animates the hidden route's moving set-pieces
## (swaying planks, the swinging crane hook, the rotating crane arm)
## and pulses the tower beacon.

## How far the planks sway sideways, and how fast.
const PLANK_SWAY := 0.9
const PLANK_SPEED := 1.3
## How fast the hook pendulum swings and the crane arm rotates.
const HOOK_SPEED := 0.45
const ARM_SPEED := 0.35
## The point the hook cable hangs from.
const HOOK_ANCHOR := Vector3(-32, 30, -19)

@onready var beacon_material: StandardMaterial3D = $Tower/TopPlatform/Beacon.get_active_material(0) as StandardMaterial3D
@onready var planks: Array[Node3D] = [
	$Parkour/Plank1,
	$Parkour/Plank2,
	$Parkour/Plank3,
]
@onready var hook: Node3D = $Parkour/Hook
@onready var cable: MeshInstance3D = $Parkour/Cable
@onready var arm_pivot: Node3D = $Parkour/ArmPivot

var _time := 0.0


func _physics_process(delta: float) -> void:
	_time += delta

	# 1. Pulse the beacon glow.
	beacon_material.emission_energy_multiplier = 2.5 + sin(_time * 2.0) * 0.8

	# 2. Sway the three planks, each out of phase with the others.
	for i in planks.size():
		planks[i].position.x = -32.0 + sin(_time * PLANK_SPEED + i * 1.9) * PLANK_SWAY

	# 3. Swing the hook across the gap: low near the first roof, high by the tower.
	var swing := sin(_time * HOOK_SPEED)
	hook.position = Vector3(-32.0, 14.55 - 2.55 * swing, -19.0 + 4.5 * swing)
	_update_cable()

	# 4. Rotate the crane arm slowly, like a clock hand.
	arm_pivot.rotation.y = _time * ARM_SPEED


## Point the thin cable box from the hook up to its anchor.
func _update_cable() -> void:
	var hook_pos := hook.global_position
	cable.global_position = (HOOK_ANCHOR + hook_pos) * 0.5
	cable.look_at(HOOK_ANCHOR, Vector3.UP)
	cable.scale = Vector3(1, 1, HOOK_ANCHOR.distance_to(hook_pos))
