class_name MemorySpot
extends Interactable
## A sparkle on the ground that holds a memory: walk up, press E, read it.
## Chapters place these to tell the story of the year.

signal remembered(spot: MemorySpot)

@export var title := "A memory"
@export var lines: Array[String] = []
var seen := false
var _sparkle: GPUParticles3D


func _ready() -> void:
	kind = "memory"
	prompt = "Remember"
	radius = 2.0
	super._ready()
	_sparkle = GPUParticles3D.new()
	_sparkle.amount = 24
	_sparkle.lifetime = 1.6
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.45
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var curve := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 0))
	c.add_point(Vector2(0.3, 1))
	c.add_point(Vector2(1, 0))
	curve.curve = c
	pm.scale_curve = curve
	_sparkle.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(1.0, 0.92, 0.55)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.85, 0.45)
	m.emission_energy_multiplier = 2.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = Person._blob_texture()
	q.material = m
	_sparkle.draw_pass_1 = q
	_sparkle.position.y = 0.5
	add_child(_sparkle)
	used.connect(_on_used)


func _on_used(_by: Node, _seat: Node3D) -> void:
	if Game.hud:
		await Game.hud.say(title, lines, Color(0.95, 0.55, 0.62))
	if not seen:
		seen = true
		_sparkle.amount_ratio = 0.35
		remembered.emit(self)
