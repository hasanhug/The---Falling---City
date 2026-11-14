extends StaticBody3D

## A parked car with sloped hood, glass cabin and bumpers.
## Each instance can pick its own paint colour.

## Paint colour for this car's body panels.
@export var paint := Color(0.8, 0.8, 0.82)

@onready var body: MeshInstance3D = $Body
@onready var hood: MeshInstance3D = $Hood
@onready var trunk: MeshInstance3D = $Trunk
@onready var roof: MeshInstance3D = $Roof


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = paint
	mat.metallic = 0.35
	mat.roughness = 0.35
	body.material_override = mat
	hood.material_override = mat
	trunk.material_override = mat
	roof.material_override = mat
