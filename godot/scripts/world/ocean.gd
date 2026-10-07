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
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(1400, 1400)
	mesh.subdivide_width = 350
	mesh.subdivide_depth = 350
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
	mesh.material = material
	var mi := MeshInstance3D.new()
	mi.name = "Sea"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = WorldLayout.WATER_LEVEL
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
		h += w.z * sin(k * d.dot(Vector2(x, z)) - om * tt + float(i) * 1.7)
	return h
