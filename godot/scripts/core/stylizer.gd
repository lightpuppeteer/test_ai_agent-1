class_name Stylizer
extends RefCounted
## Turns every StandardMaterial3D in the world into the "cozy" toon material
## (soft cel light + the rolling world curve), so Kenney models, avatars and
## props all share one Animal Crossing–like look. Runs on every node added to
## the tree. Materials can opt out with set_meta("keep", true).

const SHADERS := {
	"": preload("res://shaders/cozy.gdshader"),
	"double": preload("res://shaders/cozy_double.gdshader"),
	"cutout": preload("res://shaders/cozy_cutout.gdshader"),
	"cutout_double": preload("res://shaders/cozy_cutout_double.gdshader"),
	"alpha": preload("res://shaders/cozy_alpha.gdshader"),
	"alpha_double": preload("res://shaders/cozy_alpha_double.gdshader"),
}

static var enabled := true
static var _cache := {}          # original material -> cozy material
static var _done_meshes := {}    # mesh resources already converted


static func attach(tree: SceneTree) -> void:
	tree.node_added.connect(_on_node_added)


static func _on_node_added(n: Node) -> void:
	if not enabled or not (n is GeometryInstance3D):
		return
	if n is Label3D or n is SpriteBase3D or n is GPUParticles3D or n is CPUParticles3D:
		return
	stylize_node.call_deferred(n)


static func stylize_node(n: Node) -> void:
	if not is_instance_valid(n):
		return
	var gi := n as GeometryInstance3D
	if gi.material_override:
		gi.material_override = to_cozy(gi.material_override)
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			return
		for i in mi.mesh.get_surface_count():
			var o := mi.get_surface_override_material(i)
			if o:
				mi.set_surface_override_material(i, to_cozy(o))
		_convert_mesh(mi.mesh)
	elif n is MultiMeshInstance3D:
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm and mm.mesh:
			_convert_mesh(mm.mesh)


static func _convert_mesh(mesh: Mesh) -> void:
	if _done_meshes.has(mesh):
		return
	_done_meshes[mesh] = true
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m:
			var c: Material = to_cozy(m)
			if c != m:
				mesh.surface_set_material(i, c)


static func to_cozy(m: Material) -> Material:
	if not (m is BaseMaterial3D) or m.has_meta("keep"):
		return m
	if _cache.has(m):
		return _cache[m]
	var b := m as BaseMaterial3D
	if b.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or b.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
		_cache[m] = m
		return m
	var cutout := b.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR or b.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	var blend := b.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA or b.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	var double := b.cull_mode == BaseMaterial3D.CULL_DISABLED
	var kind := "cutout" if cutout else ("alpha" if blend else "")
	var key := kind + ("_double" if double and kind != "" else ("double" if double else ""))
	var sm := ShaderMaterial.new()
	sm.shader = SHADERS[key]
	sm.render_priority = b.render_priority
	sm.set_shader_parameter("albedo", b.albedo_color)
	if b.albedo_texture:
		sm.set_shader_parameter("albedo_tex", b.albedo_texture)
		sm.set_shader_parameter("use_tex", true)
	sm.set_shader_parameter("use_vcol", b.vertex_color_use_as_albedo)
	sm.set_shader_parameter("vcol_srgb", b.vertex_color_is_srgb)
	sm.set_shader_parameter("uv1_scale", b.uv1_scale)
	sm.set_shader_parameter("uv1_offset", b.uv1_offset)
	sm.set_shader_parameter("roughness", b.roughness)
	sm.set_shader_parameter("metallic", b.metallic)
	sm.set_shader_parameter("specular_amt", b.metallic_specular)
	if b.emission_enabled:
		sm.set_shader_parameter("emission", b.emission)
		sm.set_shader_parameter("emission_energy", b.emission_energy_multiplier)
		if b.emission_texture:
			sm.set_shader_parameter("emission_tex", b.emission_texture)
			sm.set_shader_parameter("use_emission_tex", true)
	if cutout:
		sm.set_shader_parameter("scissor", b.alpha_scissor_threshold)
	_cache[m] = sm
	return sm
