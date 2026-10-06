"""
Garment toolkit for the heroine pipeline (Blender 4.5, run inside Blender).

Garments are grown from the body mesh in its bind pose, so they inherit its
topology, UV layout and — most importantly — its skin weights. Each garment:

  1. copies the body faces of a region (predicate on face centre + dominant bone)
  2. inflates them along the normals by an ease profile (loose vs. fitted cloth)
  3. relaxes the surface (Laplacian) while a body-clearance constraint keeps it
     outside the skin, so cloth bridges concavities instead of hugging anatomy
  4. gets real thickness (solidify), so hems and cuffs read as fabric edges

Coordinates are Blender's: Z up, front = -Y, character's left = +X.
"""

import math

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

GAME_BONES = [
    "pelvis", "spine", "chest", "neck", "head",
    "upperArmL", "foreArmL", "handL", "upperArmR", "foreArmR", "handR",
    "thighL", "shinL", "footL", "thighR", "shinR", "footR",
    "hair0", "hair1", "hair2", "hair3",
]


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0))) if e1 != e0 else float(x >= e0)
    return t * t * (3 - 2 * t)


def body_bvh(body):
    dg = bpy.context.evaluated_depsgraph_get()
    return BVHTree.FromObject(body, dg, deform=False)


def dominant_bones(obj):
    """Per-vertex dominant deform bone name."""
    names = {g.index: g.name for g in obj.vertex_groups}
    out = []
    for v in obj.data.vertices:
        best, bw = None, 0.0
        for g in v.groups:
            n = names[g.group]
            if n in GAME_BONES and g.weight > bw:
                best, bw = n, g.weight
        out.append(best)
    return out


def duplicate_body(body, name, collection=None):
    me = body.data.copy()
    me.name = name
    me.materials.clear()
    o = bpy.data.objects.new(name, me)
    (collection or body.users_collection[0]).objects.link(o)
    o.parent = body.parent
    o.matrix_world = body.matrix_world.copy()
    for g in list(o.vertex_groups):
        if g.name not in GAME_BONES:
            o.vertex_groups.remove(g)
    mod = o.modifiers.new("Armature", "ARMATURE")
    mod.object = body.parent
    return o


def keep_faces(obj, pred):
    """Keeps the faces for which pred(centre, bone_names_of_face_verts) is True."""
    dom = dominant_bones(obj)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    kill = []
    for f in bm.faces:
        c = f.calc_center_median()
        bones = [dom[v.index] for v in f.verts]
        if not pred(c, bones):
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def drape(obj, body, ease, *, iterations=24, relax=0.55, clearance=None, boundary_relax=0.25, pin=None):
    """
    Inflate + relax. `ease(co) -> metres` is the target distance from the skin.
    `clearance(co) -> metres` is the hard minimum (defaults to 0.6·ease).
    `pin(co) -> bool` keeps chosen vertices from relaxing (e.g. a waistband).
    """
    clearance = clearance or (lambda co: 0.6 * ease(co))
    bvh = body_bvh(body)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    bm.normal_update()
    rest = [v.co.copy() for v in bm.verts]
    # Initial inflation along the body's own normal at the closest point.
    for v in bm.verts:
        loc, nrm, _i, _d = bvh.find_nearest(v.co)
        n = nrm if nrm is not None else v.normal
        v.co = (loc if loc is not None else v.co) + n * ease(rest[v.index])
    boundary = {v.index for v in bm.verts if v.is_boundary}
    pinned = {v.index for v in bm.verts if pin and pin(rest[v.index])}
    for _ in range(iterations):
        new = {}
        for v in bm.verts:
            if v.index in pinned:
                continue
            nbrs = [e.other_vert(v) for e in v.link_edges]
            if v.index in boundary:
                nbrs = [u for u in nbrs if u.index in boundary]
                k = boundary_relax
            else:
                k = relax
            if not nbrs:
                continue
            avg = sum((u.co for u in nbrs), Vector()) / len(nbrs)
            new[v.index] = v.co.lerp(avg, k)
        for i, co in new.items():
            bm.verts[i].co = co
        # Hard clearance + soft pull back towards the ease surface.
        for v in bm.verts:
            loc, nrm, _i, _d = bvh.find_nearest(v.co)
            if loc is None:
                continue
            d = (v.co - loc).dot(nrm)
            target = ease(rest[v.index])
            cmin = clearance(rest[v.index])
            if d < cmin:
                v.co = v.co + nrm * (cmin - d)
            elif d > target * 1.6 + 0.01:
                v.co = v.co - nrm * (d - (target * 1.6 + 0.01)) * 0.5
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def thicken(obj, thickness=0.0025, rim=True):
    mod = obj.modifiers.new("Thickness", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = -1.0
    mod.use_rim = rim
    mod.use_even_offset = True
    mod.use_quality_normals = True
    # Solidify must run before the armature.
    obj.modifiers.move(obj.modifiers.find(mod.name), 0)
    with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj]):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def subdivide(obj, levels=1):
    mod = obj.modifiers.new("Subd", "SUBSURF")
    mod.levels = levels
    mod.render_levels = levels
    mod.quality = 3
    obj.modifiers.move(obj.modifiers.find(mod.name), 0)
    with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj]):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def smooth_weights(obj, iterations=4, factor=0.5):
    """Laplacian smoothing of the bone weights (cloth shouldn't crease like skin)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    groups = {g.index: g.name for g in obj.vertex_groups if g.name in GAME_BONES}
    W = [{gi: 0.0 for gi in groups} for _ in bm.verts]
    for v in obj.data.vertices:
        for g in v.groups:
            if g.group in groups:
                W[v.index][g.group] = g.weight
    nb = [[e.other_vert(v).index for e in v.link_edges] for v in bm.verts]
    for _ in range(iterations):
        W2 = []
        for i, w in enumerate(W):
            if not nb[i]:
                W2.append(w)
                continue
            avg = {gi: sum(W[j][gi] for j in nb[i]) / len(nb[i]) for gi in groups}
            W2.append({gi: w[gi] + (avg[gi] - w[gi]) * factor for gi in groups})
        W = W2
    bm.free()
    for gi, name in groups.items():
        vg = obj.vertex_groups[name]
        for i, w in enumerate(W):
            top = sorted(w.items(), key=lambda x: -x[1])[:4]
            tot = sum(x for _, x in top) or 1.0
            keep = {g: x / tot for g, x in top}
            if keep.get(gi, 0.0) > 1e-4:
                vg.add([i], keep[gi], "REPLACE")
            else:
                vg.remove([i])


def set_material(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def principled(name, color, roughness=0.8, sheen=0.0, metallic=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = roughness
    b.inputs["Metallic"].default_value = metallic
    if "Sheen Weight" in b.inputs:
        b.inputs["Sheen Weight"].default_value = sheen
    return m


def srgb(h):
    """Hex sRGB → linear RGB tuple."""
    def lin(c):
        c /= 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin((h >> 16) & 255), lin((h >> 8) & 255), lin(h & 255))


def smoothed_proxy(body, repeat=12, factor=1.2, name="_BodyProxy", zones=("pelvis", "spine", "chest")):
    """A copy of the body with anatomical detail smoothed away on the torso
    (volume preserved). Garments measure clearance against this, so they bridge
    small concavities and never show nipples, navel, ribs or collarbones. Limbs
    are left untouched (smoothing would thin them)."""
    if name in bpy.data.objects:
        bpy.data.objects.remove(bpy.data.objects[name], do_unlink=True)
    me = body.data.copy()
    o = bpy.data.objects.new(name, me)
    body.users_collection[0].objects.link(o)
    o.matrix_world = body.matrix_world.copy()
    o.modifiers.clear()
    dom = dominant_bones(body)
    vg = o.vertex_groups.new(name="_smooth")
    for i, b in enumerate(dom):
        if b in zones:
            vg.add([i], 1.0, "REPLACE")
    m = o.modifiers.new("Lap", "LAPLACIANSMOOTH")
    m.iterations = repeat
    m.lambda_factor = factor
    m.lambda_border = 0.0
    m.use_volume_preserve = True
    m.use_normalized = True
    m.vertex_group = vg.name
    with bpy.context.temp_override(object=o, active_object=o, selected_objects=[o]):
        bpy.ops.object.modifier_apply(modifier=m.name)
    o.data.update()
    o.hide_viewport = True
    o.hide_render = True
    return o


def hang(obj, select, *, axis=(0.0, -0.02), z_top, z_bottom, taper=0.25, bins=96, belt=None):
    """
    Gravity drape for loose fabric on a roughly vertical body section.

    In each angular sector around the vertical `axis`, cloth below a supporting
    high point (bust, shoulder blades, hips) falls straight down instead of
    following the body inwards: the radius may only shrink by `taper` metres per
    metre of descent. `belt=(z, radius_offset, width)` then cinches it back.
    """
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    ax, ay = axis
    sectors = [[] for _ in range(bins)]
    for v in bm.verts:
        if not select(v):
            continue
        dx, dy = v.co.x - ax, v.co.y - ay
        th = math.atan2(dy, dx)
        sectors[int((th + math.pi) / (2 * math.pi) * bins) % bins].append(v)
    for verts in sectors:
        verts.sort(key=lambda v: -v.co.z)
        R, zprev = None, None
        for v in verts:
            dx, dy = v.co.x - ax, v.co.y - ay
            r = math.hypot(dx, dy)
            z = v.co.z
            if z > z_top or R is None:
                R, zprev = r, z
                continue
            if z < z_bottom:
                break
            R = max(r, R - taper * (zprev - z))
            zprev = z
            if r < R and r > 1e-5:
                s = R / r
                v.co.x, v.co.y = ax + dx * s, ay + dy * s
    if belt:
        bz, boff, bw = belt
        # The belt cinch is applied by the caller via clearance; nothing here.
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def relax(obj, iterations=6, factor=0.4, select=None, keep_boundary=True):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    for _ in range(iterations):
        new = {}
        for v in bm.verts:
            if select and not select(v):
                continue
            if keep_boundary and v.is_boundary:
                continue
            nb = [e.other_vert(v) for e in v.link_edges]
            if nb:
                new[v.index] = v.co.lerp(sum((u.co for u in nb), Vector()) / len(nb), factor)
        for i, co in new.items():
            bm.verts[i].co = co
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def cinch(obj, proxy, z, width, clearance, select=None):
    """Pulls fabric towards the body around height z (a belt or waistband),
    with a smooth falloff of `width` above and below."""
    bvh = body_bvh(proxy)
    for v in obj.data.vertices:
        if select and not select(v):
            continue
        w = 1.0 - smoothstep(0.0, width, abs(v.co.z - z))
        if w <= 0:
            continue
        loc, nrm, _i, _d = bvh.find_nearest(v.co)
        if loc is None:
            continue
        d = (v.co - loc).dot(nrm)
        if d > clearance:
            v.co = v.co - nrm * (d - clearance) * w
    obj.data.update()


def push_out(obj, proxy, clearance):
    """Hard constraint: every vertex at least `clearance(co)` outside the proxy."""
    bvh = body_bvh(proxy)
    for v in obj.data.vertices:
        loc, nrm, _i, _d = bvh.find_nearest(v.co)
        if loc is None:
            continue
        d = (v.co - loc).dot(nrm)
        c = clearance(v.co)
        if d < c:
            v.co = v.co + nrm * (c - d)
    obj.data.update()


def push_out_smooth(obj, body, clearance, dilate=3, blur=6):
    """
    Pushes fabric outside the real skin, but spreads each correction over the
    neighbourhood (dilate, then blur) so it becomes a broad, soft mound — cloth
    tenting over a high point — instead of a sharp anatomical bump.
    """
    bvh = body_bvh(body)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    bm.normal_update()
    nb = [[e.other_vert(v).index for e in v.link_edges] for v in bm.verts]
    need = []
    for v in bm.verts:
        loc, nrm, _i, _d = bvh.find_nearest(v.co)
        if loc is None:
            need.append(0.0)
            continue
        d = (v.co - loc).dot(nrm)
        need.append(max(0.0, clearance(v.co) - d))
    p = need[:]
    for _ in range(dilate):
        p = [max([p[i]] + [p[j] for j in nb[i]]) for i in range(len(p))]
    for _ in range(blur):
        p = [0.5 * p[i] + 0.5 * (sum(p[j] for j in nb[i]) / len(nb[i]) if nb[i] else p[i]) for i in range(len(p))]
    for v in bm.verts:
        push = max(p[v.index], need[v.index])
        if push > 0:
            v.co = v.co + v.normal * push
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def clean_boundaries(obj, iterations=12, factor=0.5, level_z=None):
    """
    Smooths every open edge loop (hems, cuffs, necklines) along itself, so cut
    lines are clean curves instead of following the body's polygon edges.
    `level_z(co) -> weight` optionally pulls loops towards their mean height
    (a level hem).
    """
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    bverts = [v for v in bm.verts if v.is_boundary]
    nb = {}
    for v in bverts:
        nb[v.index] = [e.other_vert(v) for e in v.link_edges if e.is_boundary]
    # loops → mean z
    seen, loops = set(), []
    for v in bverts:
        if v.index in seen:
            continue
        loop, stack = [], [v]
        while stack:
            u = stack.pop()
            if u.index in seen:
                continue
            seen.add(u.index)
            loop.append(u)
            stack.extend(nb.get(u.index, []))
        loops.append(loop)
    for _ in range(iterations):
        new = {}
        for v in bverts:
            n = nb[v.index]
            if len(n) == 2:
                new[v.index] = v.co.lerp((n[0].co + n[1].co) * 0.5, factor)
        for i, co in new.items():
            bm.verts[i].co = co
    if level_z:
        for loop in loops:
            mz = sum(u.co.z for u in loop) / len(loop)
            for u in loop:
                w = level_z(u.co)
                if w > 0:
                    u.co.z += (mz - u.co.z) * w
    # Pull the first interior ring along so the edge doesn't fold over.
    for v in bverts:
        for e in v.link_edges:
            u = e.other_vert(v)
            if not u.is_boundary:
                inner = [e2.other_vert(u) for e2 in u.link_edges]
                u.co = u.co.lerp(sum((w.co for w in inner), Vector()) / len(inner), 0.5)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def displace(obj, fn):
    """Moves each vertex along its normal by fn(co, normal) metres."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.normal_update()
    for v in bm.verts:
        d = fn(v.co, v.normal)
        if d:
            v.co = v.co + v.normal * d
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def noise(co, scale=1.0):
    from mathutils import noise as N
    return N.noise(co * scale)
