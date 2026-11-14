extends Node3D

## Level script for the main scene.
## Pulses the tower beacon so the city has one steady landmark.

@onready var beacon_material: StandardMaterial3D = $Tower/TopPlatform/Beacon.get_active_material(0) as StandardMaterial3D

var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	beacon_material.emission_energy_multiplier = 2.5 + sin(_time * 2.0) * 0.8
