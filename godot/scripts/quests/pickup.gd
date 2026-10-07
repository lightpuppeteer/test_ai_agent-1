class_name Pickup
extends Interactable
## Something to pick up for a quest (press E). Sparkles and bobs a little.

signal picked(item: String)

var item := "item"
var display_name := "item"
var model_id := ""
var tint := Color(1, 1, 1)
var _visual: Node3D
var _t := randf() * TAU


func _ready() -> void:
	kind = "pickup"
	prompt = "Pick up " + display_name
	radius = 1.6
	super._ready()
	_visual = Node3D.new()
	add_child(_visual)
	if model_id != "":
		var m := Props.model(model_id)
		m.scale = Vector3.ONE * Props.kit_scale(model_id) * 0.5
		_visual.add_child(m)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tint
		mat.roughness = 0.4
		for mi in Props._mesh_instances(m):
			(mi as MeshInstance3D).material_override = mat
	else:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.15
		sm.height = 0.18
		mi.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tint
		mi.material_override = mat
		_visual.add_child(mi)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.9, 0.7)
	glow.light_energy = 0.6
	glow.omni_range = 1.5
	glow.position.y = 0.4
	add_child(glow)
	used.connect(func(_by: Node, _seat: Node3D) -> void:
		picked.emit(item)
		queue_free())


func _process(delta: float) -> void:
	_t += delta
	_visual.position.y = 0.12 + sin(_t * 2.5) * 0.05
	_visual.rotation.y += delta * 1.2
