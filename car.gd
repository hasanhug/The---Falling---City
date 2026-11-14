extends StaticBody3D

## A simple parked car. Each instance can pick its own paint colour.

## Paint colour for this car's body and cabin.
@export var paint := Color(0.8, 0.8, 0.82)

@onready var body: MeshInstance3D = $Body
@onready var cabin: MeshInstance3D = $Cabin


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = paint
	mat.metallic = 0.3
	mat.roughness = 0.4
	body.material_override = mat
	cabin.material_override = mat
