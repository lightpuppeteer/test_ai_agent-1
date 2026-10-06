"""
Explorer outfit for the heroine: tunic + belt & brass buckle, canvas trousers,
laced leather boots with rubber soles. Grown from the body in its bind pose
(see garments.py), so every piece inherits the body's skin weights.

All recipes are parameterised by the body itself (joint positions from the
game rig), so they adapt when the character's proportions change.
"""

import math

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

import garments as G

ARM = {"upperArmL", "upperArmR", "foreArmL", "foreArmR"}


def _remove(name):
    if name in bpy.data.objects:
        bpy.data.objects.remove(bpy.data.objects[name], do_unlink=True)


def _apply(o, mod):
    with bpy.context.temp_override(object=o, active_object=o, selected_objects=[o]):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def _joints(rig):
    return {b.name: b.head_local.copy() for b in rig.data.bones}


# -----------------------------------------------------------------------------
# Tunic (+ belt and buckle)
# -----------------------------------------------------------------------------
def build_tunic(body, rig, proxy):
    J = _joints(rig)
    belt_z = (J["pelvis"].z + J["spine"].z) / 2 + 0.045       # ≈ natural waist
    hem_z = J["pelvis"].z - 0.047
    cuff_z = J["foreArmL"].z - 0.122                           # ¾ sleeves
    neck_z = J["neck"].z + 0.005
    _remove("Tunic")
    t = G.duplicate_body(body, "Tunic")

    def neckline(c):
        return neck_z - 0.045 * G.smoothstep(0.0, -0.07, c.y)

    def pred(c, bones):
        if any(b in ("head", "handL", "handR") for b in bones):
            return False
        if all(b in ARM for b in bones):
            return c.z > cuff_z
        if any(b in ("shinL", "shinR", "footL", "footR") for b in bones):
            return False
        return hem_z < c.z < neckline(c)

    G.keep_faces(t, pred)
    dom = G.dominant_bones(t)
    arm_idx = {i for i, b in enumerate(dom) if b in ARM}
    torso = lambda v: v.index not in arm_idx
    shoulder_x = abs(J["upperArmL"].x) - 0.014

    def ease(c):
        if abs(c.x) > shoulder_x and c.z < J["upperArmL"].z:
            return 0.008 + 0.012 * G.smoothstep(cuff_z + 0.135, cuff_z + 0.005, c.z)
        neck = G.smoothstep(neck_z - 0.06, neck_z, c.z)
        return 0.012 + 0.022 * G.smoothstep(belt_z - 0.025, hem_z, c.z) - 0.004 * neck

    G.drape(t, proxy, ease, iterations=20, relax=0.5, clearance=lambda c: 0.007)
    G.hang(t, torso, z_top=belt_z + 0.265, z_bottom=belt_z + 0.005, taper=0.09)
    G.relax(t, iterations=8, factor=0.45, select=torso)
    G.cinch(t, proxy, z=belt_z, width=0.075, clearance=0.01, select=torso)
    G.relax(t, iterations=6, factor=0.35, select=torso, keep_boundary=False)
    G.push_out(t, proxy, lambda c: 0.007)
    G.push_out_smooth(t, body, lambda c: 0.004, dilate=4, blur=8)
    G.relax(t, iterations=2, factor=0.25)
    G.clean_boundaries(t, iterations=14, factor=0.5, level_z=lambda c: 0.85 if c.z < hem_z + 0.07 else 0.0)
    G.subdivide(t, 1)

    def folds(co, n):
        nz = G.noise(co, 18.0)
        th = math.atan2(co.y + 0.02, co.x)
        if abs(co.x) > shoulder_x and co.z < J["upperArmL"].z:
            S = "L" if co.x > 0 else "R"
            sh, wr = J[f"upperArm{S}"], J[f"hand{S}"]
            s = (co - sh).dot((wr - sh).normalized())
            elbow = (J[f"foreArm{S}"] - sh).length
            cuff = (sh.z - cuff_z) / max((sh - wr).normalized().z, 1e-3)
            d = 0.0028 * math.exp(-((s - elbow) / 0.06) ** 2) * math.sin(s * 140 + nz * 2.5 + th * 1.5)
            d += 0.006 * math.exp(-((s - (cuff - 0.012)) / 0.012) ** 2)
            return d + 0.0012 * math.sin(s * 60 + th * 3 + nz * 3)
        d = 0.007 * G.smoothstep(belt_z - 0.02, hem_z + 0.025, co.z) * (
            0.6 * math.sin(th * 11 + nz * 2.0) + 0.4 * math.sin(th * 23 + nz * 3.0)
        )
        bl = G.smoothstep(belt_z + 0.005, belt_z + 0.02, co.z) * (1 - G.smoothstep(belt_z + 0.035, belt_z + 0.115, co.z))
        d += 0.0035 * bl * math.sin(co.z * 160 + th * 2.0 + nz * 4.0)
        d += 0.0012 * math.sin(th * 7 + co.z * 40 + nz * 3) * G.smoothstep(belt_z + 0.055, belt_z + 0.2, co.z)
        return d

    G.displace(t, folds)
    G.relax(t, iterations=1, factor=0.2)
    G.push_out_smooth(t, body, lambda c: 0.003, dilate=2, blur=4)
    t["belt_z"] = belt_z
    return t


def build_belt(tunic, rig):
    belt_z = tunic["belt_z"]
    _remove("Belt")
    _remove("Buckle")
    dom = G.dominant_bones(tunic)
    me = tunic.data.copy()
    me.name = "Belt"
    belt = bpy.data.objects.new("Belt", me)
    tunic.users_collection[0].objects.link(belt)
    belt.parent = rig
    belt.matrix_world = tunic.matrix_world.copy()
    belt.modifiers.clear()
    belt.modifiers.new("Armature", "ARMATURE").object = rig
    bm = bmesh.new()
    bm.from_mesh(me)
    kill = [
        f for f in bm.faces
        if abs(f.calc_center_median().z - belt_z) > 0.019 or any(dom[v.index] in ARM | {"handL", "handR"} for v in f.verts)
    ]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.normal_update()
    for v in bm.verts:
        v.co = v.co + v.normal * 0.003
    bm.to_mesh(me)
    bm.free()
    G.clean_boundaries(belt, iterations=20, factor=0.5, level_z=lambda c: 1.0)
    G.relax(belt, iterations=6, factor=0.5)
    G.push_out_smooth(belt, tunic, lambda c: 0.0025, dilate=2, blur=4)
    G.thicken(belt, thickness=0.004, rim=True)
    # Brass buckle: a bevelled frame on the front of the belt.
    front = min((v.co for v in belt.data.vertices if abs(v.co.x) < 0.01), key=lambda c: c.y)
    bme = bpy.data.meshes.new("Buckle")
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= 0.048
        v.co.y *= 0.007
        v.co.z *= 0.036
    fr = [f for f in bm.faces if abs(f.normal.y) > 0.9]
    bmesh.ops.inset_individual(bm, faces=fr, thickness=0.009, depth=0.0, use_even_offset=True)
    bmesh.ops.delete(bm, geom=fr, context="FACES")
    bmesh.ops.bridge_loops(bm, edges=[e for e in bm.edges if e.is_boundary])
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=0.001, segments=2, affect="EDGES", clamp_overlap=True)
    bmesh.ops.translate(bm, verts=bm.verts, vec=Vector((0, front.y - 0.0035, belt_z)))
    bm.to_mesh(bme)
    bm.free()
    bk = bpy.data.objects.new("Buckle", bme)
    belt.users_collection[0].objects.link(bk)
    bk.parent = rig
    for n in ("spine", "pelvis"):
        bk.vertex_groups.new(name=n).add(list(range(len(bme.vertices))), 0.5, "REPLACE")
    bk.modifiers.new("Armature", "ARMATURE").object = rig
    for p in bme.polygons:
        p.use_smooth = True
    return belt, bk


# -----------------------------------------------------------------------------
# Trousers
# -----------------------------------------------------------------------------
def build_trousers(body, rig, proxy):
    J = _joints(rig)
    waist_z = (J["pelvis"].z + J["spine"].z) / 2 + 0.062
    hem_z = J["shinL"].z - 0.182                            # tucked into the boots
    knee_z = J["shinL"].z + 0.02
    crotch_z = J["thighL"].z - 0.07
    _remove("Trousers")
    tr = G.duplicate_body(body, "Trousers")
    excluded = {"handL", "handR", "foreArmL", "foreArmR", "upperArmL", "upperArmR", "footL", "footR", "chest"}
    G.keep_faces(tr, lambda c, bones: not any(b in excluded for b in bones) and hem_z < c.z < waist_z)

    def ease(c):
        z = c.z
        e = 0.006 + 0.004 * G.smoothstep(waist_z - 0.012, waist_z - 0.092, z)
        e += 0.010 * G.smoothstep(crotch_z + 0.06, crotch_z - 0.10, z)
        e += 0.004 * G.smoothstep(knee_z + 0.05, knee_z - 0.05, z)
        e -= 0.010 * G.smoothstep(hem_z + 0.12, hem_z + 0.02, z)
        return max(0.005, e)

    G.drape(tr, proxy, ease, iterations=18, relax=0.5, clearance=lambda c: 0.005)
    for sx in (1, -1):
        leg_x = abs(J["thighL"].x) * sx
        G.hang(
            tr,
            (lambda sx: (lambda v: v.co.x * sx > 0.01 and v.co.z < crotch_z))(sx),
            axis=(leg_x, J["thighL"].y - 0.003),
            z_top=crotch_z - 0.06,
            z_bottom=hem_z + 0.10,
            taper=0.07,
        )
    G.relax(tr, iterations=6, factor=0.4)
    G.clean_boundaries(tr, iterations=12, factor=0.5, level_z=lambda c: 1.0)
    G.push_out_smooth(tr, body, lambda c: 0.0035, dilate=3, blur=6)
    G.subdivide(tr, 1)

    def folds(co, n):
        nz = G.noise(co, 16.0)
        side = 1 if co.x > 0 else -1
        th = math.atan2(co.y + 0.02, co.x - side * abs(J["thighL"].x))
        st = G.smoothstep(hem_z + 0.01, hem_z + 0.04, co.z) * (1 - G.smoothstep(hem_z + 0.10, hem_z + 0.18, co.z))
        d = 0.0045 * st * math.sin(co.z * 210 + th * 2.0 + nz * 3.0)
        kn = math.exp(-((co.z - knee_z) / 0.05) ** 2)
        d += 0.0025 * kn * math.sin(co.z * 150 + th * 3 + nz * 2.5)
        d += 0.0016 * math.sin(th * 7 + nz * 2.0) * G.smoothstep(crotch_z + 0.05, crotch_z - 0.05, co.z) * G.smoothstep(hem_z + 0.05, hem_z + 0.15, co.z)
        d += 0.0012 * math.sin(th * 5 + co.z * 60 + nz * 3) * math.exp(-((co.z - crotch_z) / 0.05) ** 2)
        return d

    G.displace(tr, folds)
    G.push_out_smooth(tr, body, lambda c: 0.003, dilate=2, blur=3)
    tr["waist_z"] = waist_z
    return tr


# -----------------------------------------------------------------------------
# Boots + soles
# -----------------------------------------------------------------------------
def _hull_tree(body, sx, zmax=0.09):
    pts = [v.co.copy() for v in body.data.vertices if v.co.z < zmax and v.co.x * sx > 0 and v.co.y < 0.0]
    hb = bmesh.new()
    for p in pts:
        hb.verts.new(p)
    bmesh.ops.convex_hull(hb, input=list(hb.verts))
    bmesh.ops.delete(hb, geom=[v for v in hb.verts if not v.link_faces], context="VERTS")
    bmesh.ops.recalc_face_normals(hb, faces=hb.faces)
    hb.normal_update()
    tree = BVHTree.FromBMesh(hb)
    hb.free()
    return tree


def build_boots(body, rig, top_z=0.33):
    _remove("Boots")
    _remove("Soles")
    coll = body.users_collection[0]
    me = body.data.copy()
    me.name = "Boots"
    me.materials.clear()
    for a in [a.name for a in me.attributes if a.name.startswith("_")]:
        me.attributes.remove(me.attributes[a])
    bo = bpy.data.objects.new("Boots", me)
    coll.objects.link(bo)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().z > top_z + 0.03], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.normal_update()
    for v in bm.verts:
        v.co = v.co + v.normal * (0.0065 + 0.004 * G.smoothstep(top_z - 0.07, top_z + 0.01, v.co.z))
    bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
    bm.to_mesh(me)
    bm.free()
    bo.vertex_groups.clear()
    rm = bo.modifiers.new("Remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = 0.0065
    _apply(bo, rm)
    sm = bo.modifiers.new("Smooth", "LAPLACIANSMOOTH")
    sm.iterations, sm.lambda_factor, sm.use_volume_preserve = 6, 0.6, True
    _apply(bo, sm)
    for sx in (1, -1):  # toe box from the convex hull of the forefoot
        tree = _hull_tree(body, sx)
        bm = bmesh.new()
        bm.from_mesh(bo.data)
        for v in bm.verts:
            if v.co.x * sx <= 0 or v.co.z > 0.10 or v.co.y > 0.0:
                continue
            loc, nrm, _i, _d = tree.find_nearest(v.co)
            if loc is None:
                continue
            sd = (v.co - loc).dot(nrm)
            w = G.smoothstep(0.10, 0.07, v.co.z) * G.smoothstep(0.0, -0.03, v.co.y)
            if sd < 0.007:
                v.co = v.co + nrm * (0.007 - sd) * w
        bm.to_mesh(bo.data)
        bm.free()
    sm = bo.modifiers.new("Smooth", "LAPLACIANSMOOTH")
    sm.iterations, sm.lambda_factor, sm.use_volume_preserve = 8, 0.8, True
    _apply(bo, sm)
    bm = bmesh.new()
    bm.from_mesh(bo.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, top_z), plane_no=(0, 0, 1), clear_outer=True)
    bmesh.ops.dissolve_degenerate(bm, dist=0.0008, edges=bm.edges[:])
    for v in bm.verts:
        if v.co.z < 0.010:
            v.co.z = 0.004 + (v.co.z - 0.004) * 0.25
    bm.to_mesh(bo.data)
    bm.free()
    G.clean_boundaries(bo, iterations=8, factor=0.5, level_z=lambda c: 1.0)
    bo.parent = rig
    so = _soles_from(bo, rig)
    G.thicken(bo, thickness=0.003, rim=True)
    tri = bo.modifiers.new("Tri", "TRIANGULATE")
    bo.modifiers.move(bo.modifiers.find("Tri"), 0)
    _apply(bo, tri)
    for o in (bo, so):
        _transfer_weights(o, body, rig, ("footL", "footR", "shinL", "shinR"))
        for p in o.data.polygons:
            p.use_smooth = True
    return bo, so


def _soles_from(bo, rig):
    sm = bo.data.copy()
    so = bpy.data.objects.new("Soles", sm)
    bo.users_collection[0].objects.link(so)
    bm = bmesh.new()
    bm.from_mesh(sm)
    bm.normal_update()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if not (f.normal.z < -0.55 and f.calc_center_median().z < 0.03)], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    for sx in (1, -1):
        vs = [v for v in bm.verts if v.co.x * sx > 0]
        if not vs:
            continue
        c = sum((v.co for v in vs), Vector()) / len(vs)
        for v in vs:
            d = v.co - c
            v.co = Vector((c.x + d.x * 1.06, c.y + d.y * 1.035, -0.006))
    bm.to_mesh(sm)
    bm.free()
    G.clean_boundaries(so, iterations=12, factor=0.5)
    G.relax(so, iterations=3, factor=0.5)
    s = so.modifiers.new("S", "SOLIDIFY")
    s.thickness, s.offset, s.use_rim, s.use_even_offset = 0.016, 1.0, True, True
    _apply(so, s)
    bm = bmesh.new()
    bm.from_mesh(sm)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(sm)
    bm.free()
    so.parent = rig
    return so


def _transfer_weights(o, body, rig, groups):
    o.vertex_groups.clear()
    for g in groups:
        o.vertex_groups.new(name=g)
    dt = o.modifiers.new("DT", "DATA_TRANSFER")
    dt.object = body
    dt.use_vert_data = True
    dt.data_types_verts = {"VGROUP_WEIGHTS"}
    dt.vert_mapping = "POLYINTERP_NEAREST"
    dt.layers_vgroup_select_src = "ALL"
    dt.layers_vgroup_select_dst = "NAME"
    with bpy.context.temp_override(object=o, active_object=o, selected_objects=[o]):
        bpy.ops.object.datalayout_transfer(modifier=dt.name)
    _apply(o, dt)
    for g in list(o.vertex_groups):
        if g.name not in groups:
            o.vertex_groups.remove(g)
    o.modifiers.new("Armature", "ARMATURE").object = rig
    G.smooth_weights(o, iterations=3, factor=0.5)


# -----------------------------------------------------------------------------
# Whole outfit
# -----------------------------------------------------------------------------
def build(body, rig):
    """Builds every piece, layers them (trousers < tunic < belt) and gives them thickness."""
    torso_proxy = G.smoothed_proxy(body, repeat=10, factor=1.0)
    tunic = build_tunic(body, rig, torso_proxy)
    legs_proxy = G.smoothed_proxy(body, repeat=10, factor=1.0, zones=("pelvis", "spine", "chest", "thighL", "thighR"), name="_LegsProxy")
    trousers = build_trousers(body, rig, legs_proxy)
    G.push_out_smooth(tunic, trousers, lambda c: 0.004 if c.z < trousers["waist_z"] + 0.02 else -1.0, dilate=3, blur=6)
    belt, buckle = build_belt(tunic, rig)
    boots, soles = build_boots(body, rig)
    G.thicken(tunic, thickness=0.0025)
    G.thicken(trousers, thickness=0.002)
    for o in (tunic, trousers):
        G.smooth_weights(o, iterations=3, factor=0.5)
        for p in o.data.polygons:
            p.use_smooth = True
    for o in (torso_proxy, legs_proxy):
        bpy.data.objects.remove(o, do_unlink=True)
    return dict(Tunic=tunic, Belt=belt, Buckle=buckle, Trousers=trousers, Boots=boots, Soles=soles)
