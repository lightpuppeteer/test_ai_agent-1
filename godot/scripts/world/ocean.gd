class_name Ocean
extends Node3D
## The sea surface. Owns the simulation clock used by the wave shader and by
## buoyant bodies, so the floating props always ride the visible waves.

const SHADER := preload("res://shaders/ocean.gdshader")
## dir.x, dir.y, amplitude (m), wavelength (m)
const WAVES := [
	Vector4(0.25, 1.0, 0.11, 22.0),
	Vector4(-0.55, 1.0, 0.06, 11.0),
	Vector4(0.9, 0.35, 0.035, 6.5),
]

var time := 0.0
var material: ShaderMaterial


func _ready() -> void:
	Game.ocean = self
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("waves", WAVES)
	var terrain: Terrain = Game.terrain
	if terrain:
		material.set_shader_parameter("ground_height", terrain.height_texture)
		var half := Terrain.SIZE * 0.5
		var texel := Terrain.SIZE / float(Terrain.N - 1)
		# Texel centres line up with the heightfield vertices.
		material.set_shader_parameter("ground_rect", Vector4(-half - texel * 0.5, -half - texel * 0.5, Terrain.SIZE + texel, Terrain.SIZE + texel))
	# A detailed patch around the island (waves fade out at its rim) and a flat,
	# coarse skirt out to the horizon.
	_patch("Sea", Vector2(INNER * 2.0, INNER * 2.0), Vector2.ZERO, int(INNER))
	var outer := FAR - INNER
	_patch("SeaN", Vector2(FAR * 2.0, outer), Vector2(0, -INNER - outer * 0.5), 6)
	_patch("SeaS", Vector2(FAR * 2.0, outer), Vector2(0, INNER + outer * 0.5), 6)
	_patch("SeaW", Vector2(outer, INNER * 2.0), Vector2(-INNER - outer * 0.5, 0), 6)
	_patch("SeaE", Vector2(outer, INNER * 2.0), Vector2(INNER + outer * 0.5, 0), 6)


const INNER := 200.0     # half-size of the wavy patch
const FAR := 700.0       # half-size of the whole sea


func _patch(nm: String, size: Vector2, at: Vector2, subdiv: int) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = size
	mesh.subdivide_width = subdiv
	mesh.subdivide_depth = subdiv
	mesh.material = material
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(at.x, WorldLayout.WATER_LEVEL, at.y)
	add_child(mi)


func _physics_process(delta: float) -> void:
	time += delta


func _process(_delta: float) -> void:
	# Interpolated render time keeps the shader in step with physics-interpolated bodies.
	var alpha := Engine.get_physics_interpolation_fraction()
	material.set_shader_parameter("t", time + alpha / float(Engine.physics_ticks_per_second) - 1.0 / float(Engine.physics_ticks_per_second))


## Water surface height at (x, z) for the current simulation time.
func height_at(x: float, z: float, at_time: float = -1.0) -> float:
	var tt := time if at_time < 0.0 else at_time
	var h := WorldLayout.WATER_LEVEL
	for i in WAVES.size():
		var w: Vector4 = WAVES[i]
		var d := Vector2(w.x, w.y).normalized()
		var k := TAU / w.w
		var om := sqrt(9.8 * k)
		h += w.z * sin(k * d.dot(Vector2(x, z)) - om * tt + float(i) * 1.7) * wave_fade(x, z)
	return h


## Waves calm down towards the edge of the detailed patch (matches the shader).
static func wave_fade(x: float, z: float) -> float:
	return 1.0 - smoothstep(INNER - 30.0, INNER - 5.0, maxf(absf(x), absf(z)))
