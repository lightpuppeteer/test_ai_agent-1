class_name NavBaker
extends Node
## Bakes walkable navigation meshes at startup (on a worker thread) so Marco and
## Yoggi can find their way around benches, houses and trees instead of walking
## into them. One region for the island (cut off below the waterline so paths
## never lead into the sea) and one per interior room.

const AGENT_RADIUS := 0.5
const CELL := 0.25

static var regions := {}      # "island" / interior id -> NavigationRegion3D
static var ready_count := 0


static func _new_navmesh(bounds: AABB) -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.cell_size = CELL
	nm.cell_height = CELL
	nm.agent_radius = AGENT_RADIUS
	nm.agent_height = 1.5
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 46.0
	nm.region_min_size = 4.0
	nm.edge_max_error = 1.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Game.PHYS_WORLD | Game.PHYS_PROPS | Game.PHYS_WALLS
	nm.filter_baking_aabb = bounds
	return nm


## Island + every interior. Call once the world is built.
static func bake_all(root: Node3D) -> void:
	var map := root.get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, CELL)
	NavigationServer3D.map_set_cell_height(map, CELL)
	var half := Terrain.SIZE * 0.5
	# Bottom just under the shallows: deeper sea floor is not walkable.
	bake(root, "island", root, AABB(Vector3(-half, -0.4, -half), Vector3(Terrain.SIZE, 30.0, Terrain.SIZE)))
	for id in Places.interiors:
		rebake_interior(root, id)


## Re-bake one room (after the furniture moved).
static func rebake_interior(root: Node3D, id: String) -> void:
	var it: Interior = Places.interiors.get(id)
	if it == null:
		return
	var sz := it.size
	# Geometry is parsed relative to the room, so the region lives in the room too.
	bake(it, id, it, AABB(Vector3(-sz.x * 0.5 - 1, -0.4, -sz.z * 0.5 - 1), Vector3(sz.x + 2, sz.y + 1, sz.z + 2)))


## (Re)bakes one region from the static colliders under `source_root`
## (`root` is where the region node goes; bounds are in its local space).
static func bake(root: Node3D, id: String, source_root: Node, bounds: AABB) -> void:
	var region: NavigationRegion3D = regions.get(id)
	if region == null or not is_instance_valid(region):
		region = NavigationRegion3D.new()
		region.name = "Nav_" + id
		root.add_child(region)
		regions[id] = region
	var nm := _new_navmesh(bounds)
	var src := NavigationMeshSourceGeometryData3D.new()
	var t0 := Time.get_ticks_msec()
	NavigationServer3D.parse_source_geometry_data(nm, src, source_root)
	var t1 := Time.get_ticks_msec()
	NavigationServer3D.bake_from_source_geometry_data_async(nm, src, func() -> void:
		if is_instance_valid(region):
			region.navigation_mesh = nm
			ready_count += 1
			print("[nav] %s: parse %d ms, baked after %d ms, %d polygons" % [id, t1 - t0, Time.get_ticks_msec() - t0, nm.get_polygon_count()]))


## Nearest point on the walkable mesh (or `p` itself before baking finished).
static func snap(world: World3D, p: Vector3) -> Vector3:
	var map := world.navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return p
	return NavigationServer3D.map_get_closest_point(map, p)


## A walking path, or an empty array when there is no navmesh (yet).
static func path(world: World3D, from: Vector3, to: Vector3) -> PackedVector3Array:
	var map := world.navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(map, from, to, true)
