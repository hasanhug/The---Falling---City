extends StaticBody3D

## Generates the whole floating island at runtime:
## - a ragged top outline that bulges at the corners and carves bays
##   into the cardinal edges (every building stays safely on rock),
## - a two-tone rocky underside that tapers down to a single spike.
## A fixed seed means the island looks identical every time you run.

## Seed for the random jitter (change for a different island).
const SEED_VALUE := 7

## Outline control points: [angle in degrees, radius in metres].
## Interpolated smoothly; bays are the four cardinal entries.
const OUTLINE := [
	[0.0, 35.0], [22.5, 44.0], [45.0, 52.0], [67.5, 49.0],
	[90.0, 35.5], [112.5, 37.0], [135.0, 41.5], [157.5, 40.0],
	[180.0, 38.5], [202.5, 44.0], [225.0, 46.0], [247.5, 44.5],
	[270.0, 35.0], [292.5, 41.0], [315.0, 52.5], [337.5, 46.0],
]

## Each ring of the underside: [depth below the surface, radius scale, rotation].
const RINGS := [
	[0.0, 1.0, 0.0],
	[6.0, 0.72, 0.35],
	[12.0, 0.42, 0.8],
	[17.0, 0.15, 1.3],
]

const RING_POINTS := 64
## How far below the surface the spike tip reaches.
const SPIKE_DEPTH := 20.0
## Angles that are bay floors: no jitter there so the streets stay safe.
const BAY_ANGLES := [0.0, 90.0, 180.0, 270.0]

var _rng := RandomNumberGenerator.new()
## Every triangle we generate, reused for the collision shape.
var _faces := PackedVector3Array()


func _ready() -> void:
	_rng.seed = SEED_VALUE

	# Build the four rings from the outline, then the mesh and collision.
	var rings: Array[PackedVector3Array] = []
	for ring in RINGS:
		rings.append(_make_ring(ring[0], ring[1], ring[2]))

	var mesh := ArrayMesh.new()
	_build_surface(mesh, 0, rings, true)
	_build_surface(mesh, 1, rings, false)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_faces)
	# Solid from both sides, so the floor can never be phased through.
	shape.backface_collision = true
	collision.shape = shape
	add_child(collision)


## Smoothly interpolates the outline radii, with seeded jitter
## (skipped near the bay floors so they keep their safe depth).
func _radius_at(angle: float) -> float:
	var degrees := fmod(rad_to_deg(angle) + 360.0, 360.0)
	# Find the two control points this angle sits between.
	var idx := int(degrees / 22.5)
	var t := (degrees - idx * 22.5) / 22.5
	# Smooth cosine blend between the two radii.
	var blend := (1.0 - cos(t * PI)) * 0.5
	var radius: float = lerpf(OUTLINE[idx][1], OUTLINE[(idx + 1) % OUTLINE.size()][1], blend)

	# Jitter, unless we are close to a bay floor angle.
	var nearest_bay := 999.0
	for bay in BAY_ANGLES:
		var distance := absf(fmod(degrees - bay + 540.0, 360.0) - 180.0)
		nearest_bay = min(nearest_bay, distance)
	if nearest_bay > 12.0:
		radius += _rng.randf_range(-0.8, 0.8)
	else:
		radius += _rng.randf_range(-0.2, 0.2)
	return radius


## One ring of points at the given depth, scale and rotation.
func _make_ring(depth: float, radius_scale: float, rotation: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in RING_POINTS:
		var angle := TAU * i / RING_POINTS
		var radius := _radius_at(angle) * radius_scale
		if depth > 0.0:
			radius += _rng.randf_range(-0.5, 0.5)
			angle += rotation
		points.append(Vector3(cos(angle) * radius, -depth, sin(angle) * radius))
	return points


## Builds one material surface. Surface 0: flat top + upper walls (light rock).
## Surface 1: lower walls + spike (dark rock).
func _build_surface(mesh: ArrayMesh, surface_id: int, rings: Array[PackedVector3Array], upper: bool) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var top := rings[0]
	var count := top.size()

	if upper:
		# Flat top cap: fan from the centre.
		var centre := Vector3(0, 0, 0)
		for i in count:
			_add_triangle(tool, centre, top[(i + 1) % count], top[i])
		# Upper walls: ring 0 down to ring 1.
		_add_wall(tool, rings[0], rings[1])
	else:
		# Lower walls: ring 1 down to ring 3.
		_add_wall(tool, rings[1], rings[2])
		_add_wall(tool, rings[2], rings[3])
		# Spike tip: fan from a single low point.
		var tip := Vector3(1.5, -SPIKE_DEPTH, -1.0)
		var bottom := rings[3]
		for i in count:
			_add_triangle(tool, tip, bottom[i], bottom[(i + 1) % count])

	var material := StandardMaterial3D.new()
	if upper:
		material.albedo_color = Color(0.42, 0.4, 0.38, 1)
	else:
		material.albedo_color = Color(0.25, 0.23, 0.24, 1)
	material.roughness = 0.95
	tool.set_material(material)
	tool.generate_normals()
	tool.commit(mesh, surface_id)


## The wall between an upper and a lower ring, as quads of two triangles.
func _add_wall(tool: SurfaceTool, upper_ring: PackedVector3Array, lower_ring: PackedVector3Array) -> void:
	var count := upper_ring.size()
	for i in count:
		var j := (i + 1) % count
		_add_triangle(tool, lower_ring[i], upper_ring[i], upper_ring[j])
		_add_triangle(tool, lower_ring[i], upper_ring[j], lower_ring[j])


## Adds one triangle to the mesh and remembers it for the collision shape.
## Note: b and c are added in swapped order on purpose — it flips every
## face so the top surface and outer walls face the player (the original
## winding rendered inside-out). Collision is two-sided, so it is unaffected.
## Zero-area (degenerate) triangles are skipped: they render as nothing and
## can upset the physics engine's shape building.
func _add_triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).length_squared() < 0.000001:
		return
	tool.add_vertex(a)
	tool.add_vertex(c)
	tool.add_vertex(b)
	_faces.append(a)
	_faces.append(c)
	_faces.append(b)
