extends Node3D

## Generates the hollow Earth interior: a rocky shell about 95 m in radius,
## open at the top (the crust hole the pillars pass through), with all faces
## pointing inward so the cavern is visible from inside. The bottom pole is
## left open and covered by the rock mound placed over it in the scene.
## Seeded, so the cavern is identical every run.

## Seed for the wall jitter (change for a different cavern).
const SEED_VALUE := 11
## Shell radius and the radius of the hole in the crust at the top.
const SHELL_RADIUS := 95.0
const HOLE_RADIUS := 35.0
## How many rings of rock from the hole rim down to near the bottom pole,
## and how many segments around each ring.
const RING_COUNT := 14
const SEGMENTS := 32
## How craggy the walls and the rim are.
const WALL_JITTER := 1.5
const RIM_JITTER := 3.0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = SEED_VALUE
	_build_shell()


## One point on the shell: polar angle theta measured from straight up,
## azimuth angle around, with seeded jitter for a craggy rock look.
func _shell_point(theta: float, azimuth: float) -> Vector3:
	var jitter := WALL_JITTER
	if theta < 0.55:
		jitter = RIM_JITTER
	var radius := SHELL_RADIUS + _rng.randf_range(-jitter, jitter)
	var y := SHELL_RADIUS + _rng.randf_range(-jitter, jitter)
	# Keep the point on (roughly) the sphere: horizontal radius from theta,
	# height from theta, both scaled by the jittered amounts.
	var horizontal := radius * sin(theta)
	var height := y * cos(theta)
	return Vector3(cos(azimuth) * horizontal, height, sin(azimuth) * horizontal)


func _build_shell() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	# The hole rim starts where the shell's horizontal radius reaches HOLE_RADIUS.
	var theta_min := asin(HOLE_RADIUS / SHELL_RADIUS)
	var theta_max := PI - 0.06

	# Build every ring of points first.
	var rings: Array[PackedVector3Array] = []
	for r in RING_COUNT:
		var theta := lerpf(theta_min, theta_max, float(r) / float(RING_COUNT - 1))
		var ring := PackedVector3Array()
		for s in SEGMENTS:
			ring.append(_shell_point(theta, TAU * s / SEGMENTS))
		rings.append(ring)

	# Wall quads between rings, wound to face inward (toward the cavern).
	for r in RING_COUNT - 1:
		var upper := rings[r]
		var lower := rings[r + 1]
		for s in SEGMENTS:
			var s_next := (s + 1) % SEGMENTS
			var u0 := upper[s]
			var u1 := upper[s_next]
			var l0 := lower[s]
			var l1 := lower[s_next]
			_add_triangle(tool, u0, l1, u1)
			_add_triangle(tool, u0, l0, l1)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.13, 0.11, 1)
	material.roughness = 1.0
	tool.set_material(material)
	tool.generate_normals()

	var mesh := ArrayMesh.new()
	tool.commit(mesh)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	add_child(mesh_instance)


## Adds one triangle, skipping degenerate (zero-area) ones.
func _add_triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).length_squared() < 0.000001:
		return
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)
